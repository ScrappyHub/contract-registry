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
function ParseGatePs1([string]$Path){
  $t=$null; $e=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$t,[ref]$e)
  if($e -and $e.Count -gt 0){
    $x=$e[0]
    throw ("PARSE_GATE_FAIL: {0}:{1}:{2}: {3}" -f $Path,$x.Extent.StartLineNumber,$x.Extent.StartColumnNumber,$x.Message)
  }
}

$B = Join-Path (Join-Path $RepoRoot "scripts") "contract_registry_make_release_packet_v1.ps1"
RequireFile $B
$raw = ReadUtf8NoBom $B

# Replace sha256sums normalization block (known-good) between $ShaPath=... and "# 7) Receipt (packet-local)"
$pattern = "(?s)\$ShaPath\s*=\s*Join-Path\s+\$PacketRoot\s+""sha256sums\.txt""\s*\n# Normalize sha256sums lines.*?\n# 7\) Receipt \(packet-local\)"
$m = [System.Text.RegularExpressions.Regex]::Match($raw,$pattern)
if(-not $m.Success){ Die "PATCH_TARGET_NOT_FOUND: could not locate sha256sums block to replace" }

$replacement = @(
  '$ShaPath = Join-Path $PacketRoot "sha256sums.txt"'
  '# Normalize sha256sums lines to "<64hex><two spaces><relpath>" and fail fast if malformed.'
  '$fixed = New-Object System.Collections.Generic.List[string]'
  'foreach($ln in @(@($sumLines.ToArray()))){'
  '  if([string]::IsNullOrWhiteSpace($ln)){ continue }'
  '  $mm = [System.Text.RegularExpressions.Regex]::Match($ln,''^(?<h>[0-9a-f]{64})\s+(?<p>.+)$'' )'
  '  if(-not $mm.Success){ Die ("BAD_SHA256SUMS_LINE_FMT(gen): " + $ln) }'
  '  $h = $mm.Groups["h"].Value.ToLowerInvariant()'
  '  $p = $mm.Groups["p"].Value'
  '  if($p -ne $p.Trim()){ Die ("BAD_SHA256SUMS_LINE_WS(gen): " + $ln) }'
  '  [void]$fixed.Add(($h + "  " + $p))'
  '}'
  'WriteUtf8NoBomLf $ShaPath ((@($fixed.ToArray()) -join "``n") + "``n")'
  '# 7) Receipt (packet-local)'
) -join "`n"

$raw2 = [System.Text.RegularExpressions.Regex]::Replace($raw,$pattern,[System.Text.RegularExpressions.MatchEvaluator]{ param($x) $replacement },1)

# Backup then write
$bkDir = Join-Path (Join-Path (Join-Path $RepoRoot "scripts") "_scratch") ("backups\builder_v1_fix_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $bkDir | Out-Null
Copy-Item -LiteralPath $B -Destination (Join-Path $bkDir "contract_registry_make_release_packet_v1.ps1") -Force
WriteUtf8NoBomLf $B $raw2

ParseGatePs1 $B
Write-Host ("PATCH_OK: fixed sha256sums block + parse_ok " + $B) -ForegroundColor Green
