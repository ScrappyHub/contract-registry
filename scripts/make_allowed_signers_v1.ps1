[CmdletBinding()]
param(
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

WriteAllowedSignersFile -TrustBundleObject $tbObj -AllowedSignersPath $as
$asHash = Sha256HexPath -Path $as

$receipt = [ordered]@{
  ts_utc = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
  action = "make_allowed_signers.v1"
  ok = $true
  trust_bundle_path = (RelPathUnix $root $tb)
  trust_bundle_sha256 = $tbHash
  allowed_signers_path = (RelPathUnix $root $as)
  allowed_signers_sha256 = $asHash
}
Write-NeverLostReceipt -ReceiptsPath $rc -ReceiptObject $receipt

Write-Host ("OK: wrote " + $as)
Write-Host ("OK: allowed_signers_sha256=" + $asHash)