[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$FilePath,
  [Parameter(Mandatory=$true)][string]$Namespace,

  [string]$Principal,
  [string]$KeyId,

  [string]$AuthorityName, # used only for local key filename, not identity
  [string]$SignerKeyPath, # optional explicit override

  [string]$TrustBundlePath = "proofs/trust/trust_bundle.json",
  [string]$ReceiptsPath = "proofs/receipts/neverlost.ndjson"
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "_lib_neverlost_v1.ps1")

$root = Split-Path -Parent $PSScriptRoot
$tb = Join-Path $root $TrustBundlePath
$rc = Join-Path $root $ReceiptsPath

$tbObj = LoadTrustBundle -TrustBundlePath $tb
$tbHash = Sha256HexPath -Path $tb

if (-not $Principal) { $Principal = $tbObj.defaults.principal }
if (-not $KeyId)     { $KeyId     = $tbObj.defaults.key_id }
if (-not $AuthorityName) { $AuthorityName = $tbObj.authority_name }

AssertPrincipalFormat $Principal
AssertKeyIdFormat $KeyId
if ($Namespace.Trim().Length -lt 1) { throw "Namespace required" }

# trust check (principal+key_id exists)
$rec = $null
foreach ($r in $tbObj.records) {
  if ($r.principal -eq $Principal -and $r.key_id -eq $KeyId) { $rec = $r; break }
}
if (-not $rec) { throw "Trust bundle has no record for principal=$Principal key_id=$KeyId" }

# namespace must be allowed
$nsAllowed = $false
foreach ($n in $rec.namespaces) { if ($n -eq $Namespace) { $nsAllowed = $true; break } }
if (-not $nsAllowed) { throw "Namespace not allowed for this principal+key_id: $Namespace" }

if (-not $SignerKeyPath) {
  $SignerKeyPath = Join-Path $root ("proofs/keys/" + $AuthorityName + "_ed25519")
}

$sigPath = SshYSignFile -SignerKeyPath $SignerKeyPath -Namespace $Namespace -Principal $Principal -FilePath $FilePath

$fileHash = Sha256HexPath -Path $FilePath
$sigHash  = Sha256HexPath -Path $sigPath

$receipt = [ordered]@{
  ts_utc = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
  action = "sign_file.v1"
  ok = $true
  principal = $Principal
  key_id = $KeyId
  namespace = $Namespace
  file_path = (RelPathUnix $root (ResolveRealPath $FilePath))
  file_sha256 = $fileHash
  sig_path = (RelPathUnix $root (ResolveRealPath $sigPath))
  sig_sha256 = $sigHash
  signer_key_path = (RelPathUnix $root (ResolveRealPath $SignerKeyPath))
  trust_bundle_path = (RelPathUnix $root $tb)
  trust_bundle_sha256 = $tbHash
}
Write-NeverLostReceipt -ReceiptsPath $rc -ReceiptObject $receipt

Write-Host ("OK: sig=" + $sigPath)