param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$msg){ throw $msg }
function Ok([string]$msg){ Write-Host $msg -ForegroundColor Green }
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
    Die ("PARSE_GATE_FAIL: {0}:{1}:{2}: {3}" -f $Path,$x.Extent.StartLineNumber,$x.Extent.StartColumnNumber,$x.Message)
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$T = Join-Path (Join-Path $RepoRoot "scripts") "contract_registry_make_golden_vectors_v1.ps1"
RequireFile $T
$raw = ReadUtf8NoBom $T

$sentinel = "CONTRACT_REGISTRY_PATCH_ELIMINATE_PID_AUTOVAR_V4"
if($raw -like ("*" + $sentinel + "*")){ Ok "PATCH_ALREADY_PRESENT"; return }

# Replace ANY casing of $pid / ${pid} with literal $ChildPid (avoid automatic read-only PID variable).
$patched = $raw
$opt = [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
$rxVar = New-Object System.Text.RegularExpressions.Regex('(?<![A-Za-z0-9_])\$(?:\{)?pid(?:\})?(?![A-Za-z0-9_])', $opt)
$patched = $rxVar.Replace($patched, { param($m) '$ChildPid' })

# Replace bare identifier pid (rare, but safe) with ChildPid (whole-word, case-insensitive).
$rxTok = New-Object System.Text.RegularExpressions.Regex('(?<![A-Za-z0-9_])pid(?![A-Za-z0-9_])', $opt)
$patched = $rxTok.Replace($patched, { param($m) 'ChildPid' })

# Stamp sentinel at top
$patched = ("# " + $sentinel + "`n") + $patched

# Backup then write
$bkDir = Join-Path (Join-Path (Join-Path $RepoRoot "scripts") "_scratch") ("backups\pid_autovar_v4_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $bkDir | Out-Null
Copy-Item -LiteralPath $T -Destination (Join-Path $bkDir "contract_registry_make_golden_vectors_v1.ps1") -Force
WriteUtf8NoBomLf $T $patched
ParseGateFile $T
Ok "PATCH_OK_PID_AUTOVAR_V4"
