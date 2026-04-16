param(
  [Parameter(Mandatory=$true)][string]$Workspace
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "..\engine\_lib_workbench_v1.ps1")

Test-WorkbenchEnvironment -Workspace $Workspace

$InputRoot = Join-Path $Workspace "input\contract"
$VerifyRoot = Join-Path $Workspace "output\verification"
$ReleaseRoot = Join-Path $Workspace "output\releases"

if(-not (Test-Path $InputRoot)){ throw "INPUT_CONTRACT_NOT_FOUND" }
if(-not (Test-Path $VerifyRoot)){ throw "VERIFY_ROOT_NOT_FOUND" }

if(-not (Test-Path $ReleaseRoot)){
  New-Item -ItemType Directory -Force -Path $ReleaseRoot | Out-Null
}

$RunId = (Get-Date -Format "yyyyMMdd_HHmmss")
$OutDir = Join-Path $ReleaseRoot $RunId

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$Manifest = Join-Path $InputRoot "manifest.json"
$Contract = Join-Path $InputRoot "contract.json"
$Version  = Join-Path $InputRoot "version.json"
$OverlaySummary = Join-Path $VerifyRoot "overlay_resolution_summary.txt"

foreach($p in @($Manifest,$Contract,$Version,$OverlaySummary)){
  if(-not (Test-Path $p)){
    throw ("REQUIRED_INPUT_MISSING: " + $p)
  }
}

Copy-Item -LiteralPath $Manifest -Destination (Join-Path $OutDir "manifest.json")
Copy-Item -LiteralPath $Contract -Destination (Join-Path $OutDir "contract.json")
Copy-Item -LiteralPath $Version  -Destination (Join-Path $OutDir "version.json")
Copy-Item -LiteralPath $OverlaySummary -Destination (Join-Path $OutDir "overlay_summary.txt")

$Files = Get-ChildItem -LiteralPath $OutDir -File | Sort-Object Name

$ShaPath = Join-Path $OutDir "sha256sums.txt"

$lines = New-Object System.Collections.Generic.List[string]

foreach($f in @($Files)){
  $h = Get-Sha256HexFromFile -Path $f.FullName
  [void]$lines.Add($h + "  " + $f.Name)
}

Write-Utf8NoBomLf -Path $ShaPath -Text ((@($lines.ToArray()) -join "`n") + "`n")

$FinalHash = Get-Sha256HexFromFile -Path $ShaPath

Write-Host ("RELEASE_OUTPUT: " + $OutDir)
Write-Host ("SHA256SUMS: " + $ShaPath)
Write-Host ("SHA256SUMS_HASH: " + $FinalHash)
Write-Host "WORKBENCH_RELEASE_BUILD_OK"