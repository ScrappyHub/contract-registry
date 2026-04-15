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

$PolicyDir = Join-Path $BundleRoot "overlays\policy"
$SchemaDir = Join-Path $BundleRoot "overlays\schema"

if(-not (Test-Path $PolicyDir)){
  throw "POLICY_OVERLAY_DIR_NOT_FOUND"
}
if(-not (Test-Path $SchemaDir)){
  throw "SCHEMA_OVERLAY_DIR_NOT_FOUND"
}

$PolicyFiles = @(Get-ChildItem -LiteralPath $PolicyDir -File | Sort-Object FullName)
$SchemaFiles = @(Get-ChildItem -LiteralPath $SchemaDir -File | Sort-Object FullName)

$PolicyHashes = New-Object System.Collections.Generic.List[string]
$SchemaHashes = New-Object System.Collections.Generic.List[string]

foreach($f in @($PolicyFiles)){
  $h = Get-Sha256HexFromFile -Path $f.FullName
  [void]$PolicyHashes.Add($h + "  " + $f.FullName)
}

foreach($f in @($SchemaFiles)){
  $h = Get-Sha256HexFromFile -Path $f.FullName
  [void]$SchemaHashes.Add($h + "  " + $f.FullName)
}

$ResolvedRoot = Join-Path $Workspace "output\verification"
if(-not (Test-Path $ResolvedRoot)){
  New-Item -ItemType Directory -Force -Path $ResolvedRoot | Out-Null
}

$SummaryPath = Join-Path $ResolvedRoot "overlay_resolution_summary.txt"

$lines = New-Object System.Collections.Generic.List[string]
[void]$lines.Add("schema: contract_registry.workbench.overlay_resolution_summary.v1")
[void]$lines.Add("utc: " + [DateTime]::UtcNow.ToString("o"))
[void]$lines.Add("policy_overlay_count: " + @($PolicyFiles).Count)
[void]$lines.Add("schema_overlay_count: " + @($SchemaFiles).Count)
[void]$lines.Add("# policy_overlays")
foreach($x in @($PolicyHashes.ToArray())){ [void]$lines.Add($x) }
[void]$lines.Add("# schema_overlays")
foreach($x in @($SchemaHashes.ToArray())){ [void]$lines.Add($x) }

Write-Utf8NoBomLf -Path $SummaryPath -Text ((@($lines.ToArray()) -join "`n") + "`n")

$SummaryHash = Get-Sha256HexFromFile -Path $SummaryPath

Write-Host ("OVERLAY_SUMMARY_PATH: " + $SummaryPath)
Write-Host ("OVERLAY_SUMMARY_SHA256: " + $SummaryHash)
Write-Host "WORKBENCH_OVERLAYS_RESOLVE_OK"