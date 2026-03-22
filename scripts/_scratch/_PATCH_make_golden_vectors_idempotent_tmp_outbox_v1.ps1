param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function RequireFile([string]$p){ if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die ("MISSING_FILE: " + $p) } }
function ReadUtf8NoBom([string]$p){ RequireFile $p; [IO.File]::ReadAllText($p,[Text.UTF8Encoding]::new($false)) }
function WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $lf = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $lf.EndsWith("`n")){ $lf += "`n" }
  [IO.File]::WriteAllText($Path,$lf,[Text.UTF8Encoding]::new($false))
}
function ParseGateFile([string]$Path){
  $t=$null; $e=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$t,[ref]$e)
  if($e -and $e.Count -gt 0){
    $x=$e[0]
    throw ("PARSE_GATE_FAIL: {0}:{1}:{2}: {3}" -f $Path,$x.Extent.StartLineNumber,$x.Extent.StartColumnNumber,$x.Message)
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$T = Join-Path (Join-Path $RepoRoot "scripts") "contract_registry_make_golden_vectors_v1.ps1"
RequireFile $T
$raw = ReadUtf8NoBom $T
$lines = @($raw -split "`n", -1)

# Insert idempotent cleanup for golden\tmp_outbox (sandbox only)
$insertAt = -1
for($i=0;$i -lt $lines.Count;$i++){
  if($lines[$i] -match "Resolve-Path\s+-LiteralPath\s+\$RepoRoot"){ $insertAt = $i + 1; break }
  if($lines[$i] -match "^\s*\$RepoRoot\s*=\s*\(Resolve-Path"){ $insertAt = $i + 1; break }
}
if($insertAt -lt 0){
  # fallback: after StrictMode line if present
  for($i=0;$i -lt [Math]::Min($lines.Count,80);$i++){ if($lines[$i] -match "Set-StrictMode"){ $insertAt = $i + 1; break } }
}
if($insertAt -lt 0){ Die "PATCH_FAIL: could not determine insertion point" }

# Avoid double-insert if already patched
$sentinel = "CONTRACT_REGISTRY_GOLDEN_TMP_OUTBOX_IDEMPOTENT_V1"
foreach($ln in $lines){ if($ln -like ("*" + $sentinel + "*")){ Die "PATCH_ALREADY_APPLIED" } }

$blk = New-Object System.Collections.Generic.List[string]
[void]$blk.Add("# " + $sentinel)
[void]$blk.Add("# Sandbox-only: allow reruns by cleaning golden\tmp_outbox before building vectors")
[void]$blk.Add("$GoldenTmp = Join-Path (Join-Path $RepoRoot ""golden"") ""tmp_outbox""")
[void]$blk.Add("if(Test-Path -LiteralPath $GoldenTmp -PathType Container){ Remove-Item -LiteralPath $GoldenTmp -Recurse -Force }")
[void]$blk.Add("New-Item -ItemType Directory -Force -Path $GoldenTmp | Out-Null")

$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $insertAt;$i++){ [void]$out.Add($lines[$i]) }
foreach($b in @($blk.ToArray())){ [void]$out.Add($b) }
for($i=$insertAt;$i -lt $lines.Count;$i++){ [void]$out.Add($lines[$i]) }
$fixed = (@($out.ToArray()) -join "`n")
if(-not $fixed.EndsWith("`n")){ $fixed += "`n" }

# Backup + write + parse-gate
$bkDir = Join-Path (Join-Path (Join-Path $RepoRoot "scripts") "_scratch") ("backups\golden_vectors_fix_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $bkDir | Out-Null
Copy-Item -LiteralPath $T -Destination (Join-Path $bkDir "contract_registry_make_golden_vectors_v1.ps1") -Force
WriteUtf8NoBomLf $T $fixed
ParseGateFile $T
Write-Host ("PATCH_OK: golden vectors now idempotent (tmp_outbox cleaned) " + $T) -ForegroundColor Green
