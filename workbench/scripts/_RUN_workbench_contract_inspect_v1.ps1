param(
  [Parameter(Mandatory=$true)][string]$Workspace
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "..\engine\_lib_workbench_v1.ps1")

Test-WorkbenchEnvironment -Workspace $Workspace

$BundleRoot = Join-Path $Workspace "input\contract"
if(-not (Test-Path $BundleRoot)){
  throw "CONTRACT_BUNDLE_ROOT_NOT_FOUND"
}

$Manifest = Join-Path $BundleRoot "manifest.json"
$Contract = Join-Path $BundleRoot "contract.json"
$Version  = Join-Path $BundleRoot "version.json"

foreach($p in @($Manifest,$Contract,$Version)){
  if(-not (Test-Path $p)){
    throw ("CONTRACT_BUNDLE_MISSING_FILE: " + $p)
  }
}

$files = Get-ChildItem -LiteralPath $BundleRoot -Recurse -File | Sort-Object FullName
if(@($files).Count -eq 0){
  throw "CONTRACT_BUNDLE_EMPTY"
}

Write-Host ("CONTRACT_BUNDLE_ROOT: " + $BundleRoot)

foreach($f in @($files)){
  $hash = Get-Sha256HexFromFile -Path $f.FullName
  Write-Host ($hash + "  " + $f.FullName)
}

Write-Host "WORKBENCH_CONTRACT_INSPECT_OK"