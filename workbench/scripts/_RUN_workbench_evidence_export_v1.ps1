param(
  [Parameter(Mandatory=$true)][string]$ReleaseDir,
  [Parameter(Mandatory=$true)][string]$ExportRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "..\engine\_lib_workbench_v1.ps1")

if(-not (Test-Path $ReleaseDir)){
  throw "RELEASE_DIR_NOT_FOUND"
}

if(-not (Test-Path $ExportRoot)){
  New-Item -ItemType Directory -Force -Path $ExportRoot | Out-Null
}

$Manifest = Join-Path $ReleaseDir "manifest.json"
$Contract = Join-Path $ReleaseDir "contract.json"
$Version  = Join-Path $ReleaseDir "version.json"
$Overlay  = Join-Path $ReleaseDir "overlay_summary.txt"
$ShaPath  = Join-Path $ReleaseDir "sha256sums.txt"

foreach($p in @($Manifest,$Contract,$Version,$Overlay,$ShaPath)){
  if(-not (Test-Path $p)){
    throw ("EVIDENCE_EXPORT_MISSING_FILE: " + $p)
  }
}

$ExportId = Split-Path $ReleaseDir -Leaf
$OutDir = Join-Path $ExportRoot $ExportId

if(Test-Path $OutDir){
  Remove-Item -LiteralPath $OutDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

Copy-Item -LiteralPath $Manifest -Destination (Join-Path $OutDir "manifest.json")
Copy-Item -LiteralPath $Contract -Destination (Join-Path $OutDir "contract.json")
Copy-Item -LiteralPath $Version  -Destination (Join-Path $OutDir "version.json")
Copy-Item -LiteralPath $Overlay  -Destination (Join-Path $OutDir "overlay_summary.txt")
Copy-Item -LiteralPath $ShaPath  -Destination (Join-Path $OutDir "sha256sums.txt")

$ReceiptPath = Join-Path $OutDir "export_receipt.txt"

$files = Get-ChildItem -LiteralPath $OutDir -File | Sort-Object Name
$lines = New-Object System.Collections.Generic.List[string]
[void]$lines.Add("schema: contract_registry.workbench.export_receipt.v1")
[void]$lines.Add("utc: " + [DateTime]::UtcNow.ToString("o"))
[void]$lines.Add("export_id: " + $ExportId)
[void]$lines.Add("source_release_dir: " + $ReleaseDir)
[void]$lines.Add("# files")

foreach($f in @($files)){
  $h = Get-Sha256HexFromFile -Path $f.FullName
  [void]$lines.Add($h + "  " + $f.Name)
}

Write-Utf8NoBomLf -Path $ReceiptPath -Text ((@($lines.ToArray()) -join "`n") + "`n")

$ReceiptHash = Get-Sha256HexFromFile -Path $ReceiptPath

Write-Host ("EVIDENCE_EXPORT_DIR: " + $OutDir)
Write-Host ("EVIDENCE_EXPORT_RECEIPT: " + $ReceiptPath)
Write-Host ("EVIDENCE_EXPORT_RECEIPT_SHA256: " + $ReceiptHash)
Write-Host "WORKBENCH_EVIDENCE_EXPORT_OK"