[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$FilePath,
  [Parameter(Mandatory=$true)][string]$SigPath,
  [Parameter(Mandatory=$true)][string]$Namespace,

  [string]$Principal,
  [string]$KeyId,

  [string]$TrustBundlePath = "proofs/trust/trust_bundle.json",
  [string]$AllowedSignersPath = "proofs/trust/allowed_signers",
  [string]$ReceiptsPath = "proofs/receipts/neverlost.ndjson"
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "_lib_neverlost_v1.ps1")

$root = Split-Path -Parent $PSScriptRoot
$tb = Join-Path $root $TrustBundlePath
$as = Join-Path $root $AllowedSignersPath
$rc = Join-Path $root $ReceiptsPath

$tbObj = LoadTrustBundle -TrustBundlePath $tb
$tbHash = Sha256HexPath -Path $tb

if (-not $Principal) { $Principal = $tbObj.defaults.principal }
if (-not $KeyId)     { $KeyId     = $tbObj.defaults.key_id }

AssertPrincipalFormat $Principal
AssertKeyIdFormat $KeyId
if ($Namespace.Trim().Length -lt 1) { throw "Namespace required" }

# trust check: principal+key_id exists
$rec = $null
foreach ($r in $tbObj.records) {
  if ($r.principal -eq $Principal -and $r.key_id -eq $KeyId) { $rec = $r; break }
}
if (-not $rec) { throw "Trust bundle has no record for principal=$Principal key_id=$KeyId" }

# namespace law: must be allowed by trust bundle record
$nsAllowed = $false
foreach ($n in $rec.namespaces) { if ($n -eq $Namespace) { $nsAllowed = $true; break } }
if (-not $nsAllowed) { throw "Namespace not allowed for this principal+key_id: $Namespace" }

# cryptographic verify (ssh-keygen -Y) enforces namespace too
$ok = $true
$reason = $null
try {
  SshYVerifyFile -AllowedSignersPath $as -Principal $Principal -Namespace $Namespace -SigPath $SigPath -FilePath $FilePath
} catch {
  $ok = $false
  $reason = $_.Exception.Message
}

$fileHash = Sha256HexPath -Path $FilePath
$sigHash  = Sha256HexPath -Path $SigPath
$asHash   = Sha256HexPath -Path $as

$receipt = [ordered]@{
  ts_utc = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
  action = "verify_sig.v1"
  ok = $ok
  fail_reason = $reason
  principal = $Principal
  key_id = $KeyId
  namespace = $Namespace
  file_path = (RelPathUnix $root (ResolveRealPath $FilePath))
  file_sha256 = $fileHash
  sig_path = (RelPathUnix $root (ResolveRealPath $SigPath))
  sig_sha256 = $sigHash
  trust_bundle_path = (RelPathUnix $root $tb)
  trust_bundle_sha256 = $tbHash
  allowed_signers_path = (RelPathUnix $root $as)
  allowed_signers_sha256 = $asHash
}
Write-NeverLostReceipt -ReceiptsPath $rc -ReceiptObject $receipt

if (-not $ok) { throw ("VERIFY_FAIL: " + $reason) }
Write-Host "OK: verified"