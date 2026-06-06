param(
  [Parameter(Mandatory=$true)]
  [string]$TargetRepo,

  [string]$Date = (Get-Date).ToString("yyyy-MM-dd")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Utf8NoBomLf {
  param([string]$Path,[string]$Text)
  $Text = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $Text.EndsWith("`n")){ $Text += "`n" }
  $Parent = Split-Path -Parent $Path
  if($Parent){ New-Item -ItemType Directory -Force -Path $Parent | Out-Null }
  [IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))
}

function Run-ShadowStep {
  param([string]$Script,[string]$Repo)

  Write-Host "PIPELINE_STEP_START: shadow_profile" -ForegroundColor Cyan

  $Out = & powershell.exe `
    -NoProfile `
    -NonInteractive `
    -ExecutionPolicy Bypass `
    -File $Script `
    -TargetRepo $Repo 2>&1

  $Exit = $LASTEXITCODE

  foreach($Line in @($Out)){ Write-Host $Line }

  if($Exit -ne 0){
    throw "PIPELINE_STEP_FAIL: shadow_profile"
  }

  Write-Host "PIPELINE_STEP_OK: shadow_profile" -ForegroundColor Green

  return @($Out)
}

function Run-DailyStep {
  param([string]$Script,[string]$Repo,[string]$ReportDate)

  Write-Host "PIPELINE_STEP_START: daily_report" -ForegroundColor Cyan

  $Out = & powershell.exe `
    -NoProfile `
    -NonInteractive `
    -ExecutionPolicy Bypass `
    -File $Script `
    -TargetRepo $Repo `
    -Date $ReportDate 2>&1

  $Exit = $LASTEXITCODE

  foreach($Line in @($Out)){ Write-Host $Line }

  if($Exit -ne 0){
    throw "PIPELINE_STEP_FAIL: daily_report"
  }

  Write-Host "PIPELINE_STEP_OK: daily_report" -ForegroundColor Green

  return @($Out)
}

function Run-IntelStep {
  param([string]$Script,[string]$Repo)

  Write-Host "PIPELINE_STEP_START: intelligence" -ForegroundColor Cyan

  $Out = & powershell.exe `
    -NoProfile `
    -NonInteractive `
    -ExecutionPolicy Bypass `
    -File $Script `
    -TargetRepo $Repo `
    -Days 7 2>&1

  $Exit = $LASTEXITCODE

  foreach($Line in @($Out)){ Write-Host $Line }

  if($Exit -ne 0){
    throw "PIPELINE_STEP_FAIL: intelligence"
  }

  Write-Host "PIPELINE_STEP_OK: intelligence" -ForegroundColor Green

  return @($Out)
}

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ShadowScript = Join-Path $PSScriptRoot "cr_shadow_profile_v1.ps1"
$DailyScript = Join-Path $PSScriptRoot "cr_daily_report_v1.ps1"
$IntelScript = Join-Path $PSScriptRoot "cr_intelligence_v1.ps1"

if(-not (Test-Path -LiteralPath $ShadowScript)){ throw "MISSING_SHADOW_SCRIPT" }
if(-not (Test-Path -LiteralPath $DailyScript)){ throw "MISSING_DAILY_SCRIPT" }
if(-not (Test-Path -LiteralPath $IntelScript)){ throw "MISSING_INTELLIGENCE_SCRIPT" }

$ShadowOut = Run-ShadowStep -Script $ShadowScript -Repo $TargetRepo
$DailyOut = Run-DailyStep -Script $DailyScript -Repo $TargetRepo -ReportDate $Date
$IntelOut = Run-IntelStep -Script $IntelScript -Repo $TargetRepo

$Snapshot = ""
$Diff = ""
$Report = ""
$Receipt = ""
$Intelligence = ""
$IntelReport = ""
$IntelReceipt = ""

foreach($Line in @($ShadowOut + $DailyOut + $IntelOut)){
  $S = [string]$Line
  if($S.StartsWith("SNAPSHOT:")){ $Snapshot = $S.Substring(9).Trim() }
  if($S.StartsWith("DIFF:")){ $Diff = $S.Substring(5).Trim() }
    if($S.StartsWith("REPORT:")){
    $ReportValue = $S.Substring(7).Trim()
    if($ReportValue -like "*weekly_intelligence_report.md"){
      $IntelReport = $ReportValue
    } else {
      $Report = $ReportValue
    }
  }
    if($S.StartsWith("RECEIPT:")){
    if([string]::IsNullOrWhiteSpace($Receipt)){ $Receipt = $S.Substring(8).Trim() }
    elseif([string]::IsNullOrWhiteSpace($IntelReceipt)){ $IntelReceipt = $S.Substring(8).Trim() }
  }
  if($S.StartsWith("INTELLIGENCE:")){ $Intelligence = $S.Substring(13).Trim() }
}

$Required = @($Snapshot,$Diff,$Report,$Receipt,$Intelligence,$IntelReport,$IntelReceipt)
foreach($Item in $Required){
  if([string]::IsNullOrWhiteSpace($Item)){ throw "PIPELINE_MISSING_OUTPUT_PATH" }
  if(-not (Test-Path -LiteralPath $Item)){ throw ("PIPELINE_OUTPUT_NOT_FOUND: " + $Item) }
}

$PipelineRoot = Join-Path $TargetRepo "runtime\pipeline"
New-Item -ItemType Directory -Force -Path $PipelineRoot | Out-Null

$PipelineReceipt = [ordered]@{
  schema = "contract_registry.pipeline_receipt.v1"
  utc = [DateTime]::UtcNow.ToString("o")
  target_repo = (Resolve-Path -LiteralPath $TargetRepo).Path
  date = $Date
  shadow_snapshot = $Snapshot
  shadow_diff = $Diff
  daily_report = $Report
  daily_receipt = $Receipt
  intelligence = $Intelligence
  intelligence_report = $IntelReport
  intelligence_receipt = $IntelReceipt
  status = "GREEN"
}

$ReceiptPath = Join-Path $PipelineRoot "cr_pipeline_receipts.ndjson"
Write-Utf8NoBomLf -Path $ReceiptPath -Text (($PipelineReceipt | ConvertTo-Json -Depth 20 -Compress))

Write-Host "CR_PIPELINE_OK" -ForegroundColor Green
Write-Host ("PIPELINE_RECEIPT: " + $ReceiptPath)