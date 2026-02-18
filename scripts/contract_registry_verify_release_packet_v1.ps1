param(
  [Parameter(Mandatory=$true)][string]$PacketRoot,
  [Parameter()][string]$RepoRoot = "",
  [Parameter()][string]$Namespace = "contract-registry",
  [Parameter()][string]$Principal = "",
  [Parameter()][string]$AllowedSignersPath = "",
  [Parameter()][int]$SigVerifyTimeoutSec = 20
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function RequireDir([string]$p){ if (-not (Test-Path -LiteralPath $p -PathType Container)) { Die ("MISSING_DIR: " + $p) } }
function RequireFile([string]$p){ if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { Die ("MISSING_FILE: " + $p) } }
function ReadUtf8([string]$p){ return [IO.File]::ReadAllText($p,[Text.UTF8Encoding]::new($false)) }
function ReadAllBytes([string]$p){ return [IO.File]::ReadAllBytes($p) }
function Sha256HexBytes([byte[]]$b){
  if ($null -eq $b) { $b = @() }
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $h = $sha.ComputeHash($b) } finally { $sha.Dispose() }
  $sb = New-Object System.Text.StringBuilder
  for($i=0;$i -lt $h.Length;$i++){ [void]$sb.AppendFormat("{0:x2}", $h[$i]) }
  return $sb.ToString()
}
function Sha256HexFile([string]$p){
  RequireFile $p
  $fs = [IO.File]::OpenRead($p)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $h = $sha.ComputeHash($fs) } finally { $sha.Dispose(); $fs.Dispose() }
  $sb = New-Object System.Text.StringBuilder
  for($i=0;$i -lt $h.Length;$i++){ [void]$sb.AppendFormat("{0:x2}", $h[$i]) }
  return $sb.ToString()
}

RequireDir $PacketRoot
$ManifestPath = Join-Path $PacketRoot "manifest.json"
$PacketIdPath = Join-Path $PacketRoot "packet_id.txt"
$ShaPath      = Join-Path $PacketRoot "sha256sums.txt"
RequireFile $ManifestPath
RequireFile $PacketIdPath
RequireFile $ShaPath

# (A) Verify PacketId == SHA256(canonical bytes(manifest-without-id))
$mBytes = ReadAllBytes $ManifestPath
$recalcPacketId = Sha256HexBytes $mBytes
$decl = (ReadUtf8 $PacketIdPath).Trim()
if ($decl -ne $recalcPacketId) { Die ("PACKET_ID_MISMATCH: declared=" + $decl + " recomputed=" + $recalcPacketId) }

# (B) Verify sha256sums.txt against on-disk bytes (non-mutating)
$lines = @(@((ReadUtf8 $ShaPath) -split "`n")) | Where-Object { $_ -and $_.Trim().Length -gt 0 }
if (@(@($lines)).Count -lt 1) { Die "BAD_SHA256SUMS: empty" }
foreach($ln in @(@($lines))){
  $t = $ln.Trim()
  $m = [Text.RegularExpressions.Regex]::Match($t, "^(?<h>[0-9a-f]{64})\s{2}(?<p>.+)$")
  if (-not $m.Success) { Die ("BAD_SHA256SUMS_LINE_FMT: " + $ln) }
  $h = $m.Groups["h"].Value
  $rel = $m.Groups["p"].Value
  if ($rel -match "^\.\.") { Die ("BAD_SHA256SUMS_PATH: " + $rel) }
  $abs = Join-Path $PacketRoot $rel
  RequireFile $abs
  $calc = Sha256HexFile $abs
  if ($calc -ne $h) { Die ("HASH_MISMATCH: " + $rel + " expected=" + $h + " got=" + $calc) }
}

# (C) Optional sshsig verify if signature exists AND allowed_signers is available.
#     IMPORTANT: this verifier does NOT mutate the packet. It writes temp stdout/stderr under RepoRoot\proofs\_tmp when RepoRoot is provided.
$SigFile = Join-Path (Join-Path $PacketRoot "signatures") "packet_id.sig"
if (Test-Path -LiteralPath $SigFile -PathType Leaf) {
  $as = $AllowedSignersPath
  if (-not $as -and $RepoRoot) {
    $cand = @( (Join-Path $RepoRoot "proofs\trust\allowed_signers"), (Join-Path $RepoRoot "keys\allowed_signers") )
    foreach($c in @(@($cand))){ if (Test-Path -LiteralPath $c -PathType Leaf) { $as = $c; break } }
  }
  if (-not $as) {
    Write-Host "SIG_PRESENT_BUT_SKIPPED: signatures/packet_id.sig (no allowed_signers found/provided)" -ForegroundColor Yellow
  } else {
    $ssh = (Get-Command ssh-keygen.exe -ErrorAction Stop).Source
    $id = $Principal
    if (-not $id) { $id = "contract-registry" }
    $tmpRoot = $env:TEMP
    if ($RepoRoot) {
      $candTmp = Join-Path $RepoRoot "proofs\_tmp"
      if (Test-Path -LiteralPath $candTmp -PathType Container) { $tmpRoot = $candTmp }
    }
    if ($RepoRoot) { EnsureDir $tmpRoot }
    $outPath = Join-Path $tmpRoot ("sshsig_verify_out_" + ([DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss")) + ".txt")
    $errPath = Join-Path $tmpRoot ("sshsig_verify_err_" + ([DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss")) + ".txt")

    $proc = Start-Process -FilePath $ssh -ArgumentList @(
      "-Y","verify","-f",$as,"-I",$id,"-n",$Namespace,"-s",$SigFile
    ) -NoNewWindow -PassThru -RedirectStandardInput $PacketIdPath -RedirectStandardOutput $outPath -RedirectStandardError $errPath

    $done = $proc.WaitForExit($SigVerifyTimeoutSec * 1000)
    if (-not $done) {
      try { $proc.Kill() } catch {}
      Die ("SIG_VERIFY_TIMEOUT: seconds=" + $SigVerifyTimeoutSec)
    }
    if ($proc.ExitCode -ne 0) {
      $e = ""
      if (Test-Path -LiteralPath $errPath -PathType Leaf) { $e = ([IO.File]::ReadAllText($errPath,[Text.UTF8Encoding]::new($false))).Trim() }
      Die ("SIG_VERIFY_FAILED exit_code=" + $proc.ExitCode + $(if($e){": " + $e}else{""}))
    }
    Write-Host "SIG_VERIFY_OK: signatures/packet_id.sig" -ForegroundColor Green
  }
}

Write-Host ("VERIFY_OK: " + $PacketRoot) -ForegroundColor Green
Write-Host ("packet_id=" + $decl) -ForegroundColor Gray
