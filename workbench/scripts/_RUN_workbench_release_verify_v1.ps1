param(
  [Parameter(Mandatory=$true)][string]$ReleaseDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "..\engine\_lib_workbench_v1.ps1")

if(-not (Test-Path $ReleaseDir)){
  throw "RELEASE_DIR_NOT_FOUND"
}

$Manifest = Join-Path $ReleaseDir "manifest.json"
$Contract = Join-Path $ReleaseDir "contract.json"
$Version  = Join-Path $ReleaseDir "version.json"
$Overlay  = Join-Path $ReleaseDir "overlay_summary.txt"
$ShaPath  = Join-Path $ReleaseDir "sha256sums.txt"

foreach($p in @($Manifest,$Contract,$Version,$Overlay,$ShaPath)){
  if(-not (Test-Path $p)){
    throw ("RELEASE_VERIFY_MISSING_FILE: " + $p)
  }
}

$expected = @{}
$lines = Get-Content -LiteralPath $ShaPath
foreach($line in @($lines)){
  if([string]::IsNullOrWhiteSpace($line)){ continue }
  $parts = $line -split '\s+', 2
  if(@($parts).Count -ne 2){
    throw ("SHA256SUMS_BAD_LINE: " + $line)
  }
  $expected[$parts[1].Trim()] = $parts[0].Trim().ToLowerInvariant()
}

$targets = @(
  "manifest.json",
  "contract.json",
  "version.json",
  "overlay_summary.txt"
)

foreach($name in @($targets)){
  if(-not $expected.ContainsKey($name)){
    throw ("SHA256SUMS_MISSING_ENTRY: " + $name)
  }

  $full = Join-Path $ReleaseDir $name
  $actual = Get-Sha256HexFromFile -Path $full

  if($actual -ne $expected[$name]){
    throw ("SHA256_MISMATCH: " + $name)
  }

  Write-Host ("VERIFY_OK: " + $name + "  " + $actual)
}

Write-Host "WORKBENCH_RELEASE_VERIFY_OK"