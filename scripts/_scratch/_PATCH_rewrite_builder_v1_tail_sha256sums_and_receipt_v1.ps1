param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function RequireFile([string]$p){ if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die ("MISSING_FILE: " + $p) } }
function EnsureDir([string]$p){ if(-not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
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

# Find start of tail: "# 6) sha256sums.txt" marker
$start = -1
for($i=0;$i -lt $lines.Count;$i++){
  if($lines[$i] -match '^\s*#\s*6\)\s*sha256sums\.txt'){ $start = $i; break }
}
if($start -lt 0){ Die "PATCH_FAIL: could not find tail marker (# 6) sha256sums.txt) to replace" }

$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $start;$i++){ [void]$out.Add($lines[$i]) }

# --- BEGIN KNOWN-GOOD TAIL (v1) ---
[void]$out.Add('# 6) sha256sums.txt LAST (final bytes on disk)')
[void]$out.Add('$ShaPath = Join-Path $PacketRoot "sha256sums.txt"')
[void]$out.Add('# Normalize sha256sums lines to "<64hex><two spaces><relpath>" and fail fast if malformed.' )
[void]$out.Add('if(-not (Get-Variable -Name sumLines -Scope Local -ErrorAction SilentlyContinue)){ Die "MISSING_SUM_LINES: expected $sumLines list before sha256sums write" }')
[void]$out.Add('$fixed = New-Object System.Collections.Generic.List[string]')
[void]$out.Add('foreach($ln in @(@($sumLines.ToArray()))){')
[void]$out.Add('  if([string]::IsNullOrWhiteSpace($ln)){ continue }')
[void]$out.Add('  $mm = [System.Text.RegularExpressions.Regex]::Match($ln,''^(?<h>[0-9a-f]{64})\s+(?<p>.+)$'' )')
[void]$out.Add('  if (-not $mm.Success) { Die ("BAD_SHA256SUMS_LINE_FMT(gen): " + $ln) }')
[void]$out.Add('  $h = $mm.Groups["h"].Value.ToLowerInvariant()')
[void]$out.Add('  $p = $mm.Groups["p"].Value')
[void]$out.Add('  if($p -ne $p.Trim()){ Die ("BAD_SHA256SUMS_LINE_WS(gen): " + $ln) }')
[void]$out.Add('  [void]$fixed.Add(($h + "  " + $p))')
[void]$out.Add('}')
[void]$out.Add('WriteUtf8NoBomLf $ShaPath ((@($fixed.ToArray()) -join "``n") + "``n")')

[void]$out.Add('# 7) Receipt (packet-local)')
[void]$out.Add('$rc = New-Object System.Collections.Generic.List[string]')
[void]$out.Add('[void]$rc.Add("schema: contract_registry_release_receipt.v1")')
[void]$out.Add('[void]$rc.Add("utc: " + [DateTime]::UtcNow.ToString("o"))')
[void]$out.Add('[void]$rc.Add("repo_root: " + $RepoRoot)')
[void]$out.Add('[void]$rc.Add("packet_root: " + $PacketRoot)')
[void]$out.Add('[void]$rc.Add("producer: " + $Producer)')
[void]$out.Add('[void]$rc.Add("namespace: " + $Namespace)')
[void]$out.Add('[void]$rc.Add("contract_ref: " + $ContractRef)')
[void]$out.Add('[void]$rc.Add("contract_sha256: " + $contract_sha256)')
[void]$out.Add('[void]$rc.Add("commit_hash: " + $commitHash)')
[void]$out.Add('[void]$rc.Add("packet_id: " + $PacketId)')
[void]$out.Add('[void]$rc.Add("signed: " + $(if($NoSign){"false"}else{"true"}))')
[void]$out.Add('if ($SigPath) { [void]$rc.Add("sig_path: signatures/packet_id.sig") }')
[void]$out.Add('[void]$rc.Add("sha256sums: sha256sums.txt")')
[void]$out.Add('$ReceiptDir = Join-Path $PacketRoot "receipts"' )
[void]$out.Add('EnsureDir $ReceiptDir' )
[void]$out.Add('$ReceiptPath = Join-Path $ReceiptDir "release_receipt.txt"' )
[void]$out.Add('WriteUtf8NoBomLf $ReceiptPath ((@($rc.ToArray()) -join "``n") + "``n")' )

[void]$out.Add('Write-Host ("RELEASE_PACKET_OK: " + $PacketRoot) -ForegroundColor Green')
[void]$out.Add('Write-Host ("packet_id=" + $PacketId) -ForegroundColor Gray')
[void]$out.Add('Write-Host ("receipt=" + $ReceiptPath) -ForegroundColor Gray')
# --- END KNOWN-GOOD TAIL ---

$fixedText = (@($out.ToArray()) -join "`n")
if(-not $fixedText.EndsWith("`n")){ $fixedText += "`n" }

# Backup + write + parse-gate
$bkDir = Join-Path (Join-Path (Join-Path $RepoRoot "scripts") "_scratch") ("backups\builder_v1_tail_fix_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $bkDir | Out-Null
Copy-Item -LiteralPath $B -Destination (Join-Path $bkDir "contract_registry_make_release_packet_v1.ps1") -Force
WriteUtf8NoBomLf $B $fixedText
ParseGatePs1 $B
Write-Host ("PATCH_OK: rewrote builder v1 tail + parse_ok " + $B) -ForegroundColor Green
