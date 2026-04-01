param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$ArtifactPath,
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$ExpectedSha256,
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$ExpectedFileName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "_lib_workbench_v1.ps1")

if(-not (Test-Path -LiteralPath $ArtifactPath -PathType Leaf)){
  throw ("WB_ARTIFACT_MISSING: " + $ArtifactPath)
}

$actualName = [System.IO.Path]::GetFileName($ArtifactPath)
if($actualName -ne $ExpectedFileName){
  throw ("WB_FILENAME_MISMATCH expected=" + $ExpectedFileName + " actual=" + $actualName)
}

$actualSha = WB-GetSha256HexFile $ArtifactPath
if($actualSha -ne $ExpectedSha256.ToLowerInvariant()){
  throw ("WB_SHA256_MISMATCH expected=" + $ExpectedSha256.ToLowerInvariant() + " actual=" + $actualSha)
}

Write-Host ("artifact_path=" + $ArtifactPath)
Write-Host ("file_name=" + $actualName)
Write-Host ("sha256=" + $actualSha)
Write-Host "WORKBENCH_VERIFY_DOWNLOAD_OK"