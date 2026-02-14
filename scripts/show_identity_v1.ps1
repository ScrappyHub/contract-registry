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

$principal = $tbObj.defaults.principal
$keyId     = $tbObj.defaults.key_id

AssertPrincipalFormat $principal
AssertKeyIdFormat $keyId

# find trust record
$rec = $null
foreach ($r in $tbObj.records) {
  if ($r.principal -eq $principal -and $r.key_id -eq $keyId) { $rec = $r; break }
}
if (-not $rec) { throw "No trust record matches defaults principal+key_id" }

$allowedHash = $null; if (Test-Path -LiteralPath $as) { $allowedHash = Sha256HexPath -Path $as }

Write-Host ("principal=" + $principal)
Write-Host ("key_id=" + $keyId)
Write-Host ("pubkey_sha256=" + $rec.pubkey_sha256)
Write-Host ("trust_bundle_id=" + $tbObj.trust_bundle_id)
Write-Host ("trust_bundle_sha256=" + $tbHash)
if ($null -eq $allowedHash) { Write-Host "allowed_signers_sha256=missing" } else { Write-Host ("allowed_signers_sha256=" + $allowedHash) }
Write-Host ("repo_root=" + $root)

$receipt = [ordered]@{
  ts_utc = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
  action = "show_identity.v1"
  ok = $true
  principal = $principal
  key_id = $keyId
  pubkey_sha256 = $rec.pubkey_sha256
  trust_bundle_path = (RelPathUnix $root $tb)
  trust_bundle_sha256 = $tbHash
  allowed_signers_path = (RelPathUnix $root $as)
  allowed_signers_sha256 = $allowedHash
}
Write-NeverLostReceipt -ReceiptsPath $rc -ReceiptObject $receipt
