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
$lines = @($raw -split "`n", -1)

# 1) Enforce two-space delimiter when generating sumLines (optional but canonical)
for($i=0;$i -lt $lines.Count;$i++){
  $ln = $lines[$i]
  if($ln -like '*sumLines.Add((*' -and $ln -like '*"+ " " + $rel*'){
    $lines[$i] = ($ln -replace '"\s"\s*\+\s*\$rel','"  " + $rel')
  }
}

# 2) Replace sha256sums normalization block by line anchors
$start = -1; $end = -1
for($i=0;$i -lt $lines.Count;$i++){
  if($start -lt 0 -and $lines[$i] -match '^\s*\$ShaPath\s*=\s*Join-Path\s+\$PacketRoot\s+"sha256sums\.txt"\s*$'){ $start = $i; continue }
  if($start -ge 0 -and $end -lt 0 -and $lines[$i] -match '^\s*#\s*7\)\s*Receipt\s*\(packet-local\)\s*$'){ $end = $i; break }
}
if($start -lt 0){ Die "PATCH_FAIL: start marker not found ($ShaPath = Join-Path $PacketRoot ""sha256sums.txt"")" }
if($end   -lt 0){ Die "PATCH_FAIL: end marker not found (# 7) Receipt (packet-local))" }
if($end -le $start){ Die ("PATCH_FAIL: bad range start=" + $start + " end=" + $end) }

$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $start;$i++){ [void]$out.Add($lines[$i]) }

# --- BEGIN REPLACEMENT (sha256sums normalization + write) ---
[void]$out.Add('$ShaPath = Join-Path $PacketRoot "sha256sums.txt"')
[void]$out.Add('# Normalize sha256sums lines to "<64hex><two spaces><relpath>" and fail fast if malformed.' )
[void]$out.Add('$fixed = New-Object System.Collections.Generic.List[string]')
[void]$out.Add('foreach($ln in @(@($sumLines.ToArray()))){')
[void]$out.Add('  if([string]::IsNullOrWhiteSpace($ln)){ continue }')
[void]$out.Add('  $mm = [System.Text.RegularExpressions.Regex]::Match($ln,''^(?<h>[0-9a-f]{64})\s+(?<p>.+)$'' )')
[void]$out.Add('  if(-not $mm.Success){ Die ("BAD_SHA256SUMS_LINE_FMT(gen): " + $ln) }')
[void]$out.Add('  $h = $mm.Groups["h"].Value.ToLowerInvariant()')
[void]$out.Add('  $p = $mm.Groups["p"].Value')
[void]$out.Add('  if($p -ne $p.Trim()){ Die ("BAD_SHA256SUMS_LINE_WS(gen): " + $ln) }')
[void]$out.Add('  [void]$fixed.Add(($h + "  " + $p))')
[void]$out.Add('}')
[void]$out.Add('WriteUtf8NoBomLf $ShaPath ((@($fixed.ToArray()) -join "``n") + "``n")')
# --- END REPLACEMENT ---

# Re-add the receipt section marker line and the remainder of the file
for($i=$end; $i -lt $lines.Count; $i++){ [void]$out.Add($lines[$i]) }

$fixedText = (@($out.ToArray()) -join "`n")
if(-not $fixedText.EndsWith("`n")){ $fixedText += "`n" }

# Backup + write + parse-gate
$bkDir = Join-Path (Join-Path (Join-Path $RepoRoot "scripts") "_scratch") ("backups\builder_v1_fix_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $bkDir | Out-Null
Copy-Item -LiteralPath $B -Destination (Join-Path $bkDir "contract_registry_make_release_packet_v1.ps1") -Force
WriteUtf8NoBomLf $B $fixedText
ParseGatePs1 $B
Write-Host ("PATCH_OK: fixed builder v1 sha256sums block + parse_ok " + $B) -ForegroundColor Green
