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

function Run-AlertsStep {
  param([string]$Script,[string]$Repo)

  Write-Host "PIPELINE_STEP_START: alerts" -ForegroundColor Cyan

  $Out = & powershell.exe `
    -NoProfile `
    -NonInteractive `
    -ExecutionPolicy Bypass `
    -File $Script `
    -TargetRepo $Repo 2>&1

  $Exit = $LASTEXITCODE

  foreach($Line in @($Out)){ Write-Host $Line }

  if($Exit -ne 0){
    throw "PIPELINE_STEP_FAIL: alerts"
  }

  Write-Host "PIPELINE_STEP_OK: alerts" -ForegroundColor Green

  return @($Out)
}

function Run-NotifyStep {
  param([string]$Script,[string]$Repo)

  Write-Host "PIPELINE_STEP_START: notify" -ForegroundColor Cyan

  $Out = & powershell.exe `
    -NoProfile `
    -NonInteractive `
    -ExecutionPolicy Bypass `
    -File $Script `
    -TargetRepo $Repo 2>&1

  $Exit = $LASTEXITCODE

  foreach($Line in @($Out)){ Write-Host $Line }

  if($Exit -ne 0){
    throw "PIPELINE_STEP_FAIL: notify"
  }

  Write-Host "PIPELINE_STEP_OK: notify" -ForegroundColor Green

  return @($Out)
}

function Run-BehaviorStep {
  param([string]$Script,[string]$Repo)

  Write-Host "PIPELINE_STEP_START: behavioral_drift" -ForegroundColor Cyan

  $Out = & powershell.exe `
    -NoProfile `
    -NonInteractive `
    -ExecutionPolicy Bypass `
    -File $Script `
    -TargetRepo $Repo 2>&1

  $Exit = $LASTEXITCODE

  foreach($Line in @($Out)){ Write-Host $Line }

  if($Exit -ne 0){
    throw "PIPELINE_STEP_FAIL: behavioral_drift"
  }

  Write-Host "PIPELINE_STEP_OK: behavioral_drift" -ForegroundColor Green

  return @($Out)
}

function Run-IdentityStep {
  param([string]$Script,[string]$Repo)

  Write-Host "PIPELINE_STEP_START: repo_identity" -ForegroundColor Cyan

  $Out = & powershell.exe `
    -NoProfile `
    -NonInteractive `
    -ExecutionPolicy Bypass `
    -File $Script `
    -TargetRepo $Repo 2>&1

  $Exit = $LASTEXITCODE

  foreach($Line in @($Out)){ Write-Host $Line }

  if($Exit -ne 0){
    throw "PIPELINE_STEP_FAIL: repo_identity"
  }

  Write-Host "PIPELINE_STEP_OK: repo_identity" -ForegroundColor Green

  return @($Out)
}

function Run-ClassStep {
  param([string]$Script,[string]$Repo)

  Write-Host "PIPELINE_STEP_START: software_classification" -ForegroundColor Cyan

  $Out = & powershell.exe `
    -NoProfile `
    -NonInteractive `
    -ExecutionPolicy Bypass `
    -File $Script `
    -TargetRepo $Repo 2>&1

  $Exit = $LASTEXITCODE
  foreach($Line in @($Out)){ Write-Host $Line }

  if($Exit -ne 0){
    throw "PIPELINE_STEP_FAIL: software_classification"
  }

  Write-Host "PIPELINE_STEP_OK: software_classification" -ForegroundColor Green
  return @($Out)
}

function Run-LineageStep {
  param([string]$Script,[string]$Repo)

  Write-Host "PIPELINE_STEP_START: lineage" -ForegroundColor Cyan

  $Out = & powershell.exe `
    -NoProfile `
    -NonInteractive `
    -ExecutionPolicy Bypass `
    -File $Script `
    -TargetRepo $Repo 2>&1

  $Exit = $LASTEXITCODE
  foreach($Line in @($Out)){ Write-Host $Line }

  if($Exit -ne 0){
    throw "PIPELINE_STEP_FAIL: lineage"
  }

  Write-Host "PIPELINE_STEP_OK: lineage" -ForegroundColor Green
  return @($Out)
}

function Run-CapabilityStep {
  param([string]$Script,[string]$Repo)

  Write-Host "PIPELINE_STEP_START: capability_graph" -ForegroundColor Cyan

  $Out = & powershell.exe `
    -NoProfile `
    -NonInteractive `
    -ExecutionPolicy Bypass `
    -File $Script `
    -TargetRepo $Repo 2>&1

  $Exit = $LASTEXITCODE
  foreach($Line in @($Out)){ Write-Host $Line }

  if($Exit -ne 0){
    throw "PIPELINE_STEP_FAIL: capability_graph"
  }

  Write-Host "PIPELINE_STEP_OK: capability_graph" -ForegroundColor Green
  return @($Out)
}

function Run-RiskTopologyStep {
  param([string]$Script,[string]$Repo)

  Write-Host "PIPELINE_STEP_START: risk_topology" -ForegroundColor Cyan

  $Out = & powershell.exe `
    -NoProfile `
    -NonInteractive `
    -ExecutionPolicy Bypass `
    -File $Script `
    -TargetRepo $Repo 2>&1

  $Exit = $LASTEXITCODE
  foreach($Line in @($Out)){ Write-Host $Line }

  if($Exit -ne 0){
    throw "PIPELINE_STEP_FAIL: risk_topology"
  }

  Write-Host "PIPELINE_STEP_OK: risk_topology" -ForegroundColor Green
  return @($Out)
}

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ShadowScript = Join-Path $PSScriptRoot "cr_shadow_profile_v1.ps1"
$DailyScript = Join-Path $PSScriptRoot "cr_daily_report_v1.ps1"
$IntelScript = Join-Path $PSScriptRoot "cr_intelligence_v1.ps1"
$BehaviorScript = Join-Path $PSScriptRoot "cr_behavioral_drift_v1.ps1"
$IdentityScript = Join-Path $PSScriptRoot "cr_repo_identity_v1.ps1"
$ClassScript = Join-Path $PSScriptRoot "cr_software_classification_v1.ps1"
$LineageScript = Join-Path $PSScriptRoot "cr_lineage_v1.ps1"
$CapabilityScript = Join-Path $PSScriptRoot "cr_capability_graph_v1.ps1"
$AlertsScript = Join-Path $PSScriptRoot "cr_alerts_v1.ps1"
$NotifyScript = Join-Path $PSScriptRoot "cr_notify_v1.ps1"

if(-not (Test-Path -LiteralPath $ShadowScript)){ throw "MISSING_SHADOW_SCRIPT" }
if(-not (Test-Path -LiteralPath $DailyScript)){ throw "MISSING_DAILY_SCRIPT" }
if(-not (Test-Path -LiteralPath $IntelScript)){ throw "MISSING_INTELLIGENCE_SCRIPT" }
if(-not (Test-Path -LiteralPath $BehaviorScript)){ throw "MISSING_BEHAVIORAL_DRIFT_SCRIPT" }
if(-not (Test-Path -LiteralPath $IdentityScript)){ throw "MISSING_REPO_IDENTITY_SCRIPT" }
if(-not (Test-Path -LiteralPath $ClassScript)){ throw "MISSING_SOFTWARE_CLASSIFICATION_SCRIPT" }
if(-not (Test-Path -LiteralPath $LineageScript)){ throw "MISSING_LINEAGE_SCRIPT" }
if(-not (Test-Path -LiteralPath $CapabilityScript)){ throw "MISSING_CAPABILITY_GRAPH_SCRIPT" }
if(-not (Test-Path -LiteralPath $AlertsScript)){ throw "MISSING_ALERTS_SCRIPT" }
if(-not (Test-Path -LiteralPath $NotifyScript)){ throw "MISSING_NOTIFY_SCRIPT" }

$ShadowOut = Run-ShadowStep -Script $ShadowScript -Repo $TargetRepo
$DailyOut = Run-DailyStep -Script $DailyScript -Repo $TargetRepo -ReportDate $Date
$IntelOut = Run-IntelStep -Script $IntelScript -Repo $TargetRepo
$BehaviorOut = Run-BehaviorStep -Script $BehaviorScript -Repo $TargetRepo
$IdentityOut = Run-IdentityStep -Script $IdentityScript -Repo $TargetRepo
$ClassOut = Run-ClassStep -Script $ClassScript -Repo $TargetRepo
$LineageOut = Run-LineageStep -Script $LineageScript -Repo $TargetRepo
$CapabilityOut = Run-CapabilityStep -Script $CapabilityScript -Repo $TargetRepo
$RiskTopologyOut = Run-RiskTopologyStep -Script $RiskTopologyScript -Repo $TargetRepo
$AlertsOut = Run-AlertsStep -Script $AlertsScript -Repo $TargetRepo
$NotifyOut = Run-NotifyStep -Script $NotifyScript -Repo $TargetRepo

$Snapshot = ""
$Diff = ""
$Report = ""
$Receipt = ""
$Intelligence = ""
$IntelReport = ""
$IntelReceipt = ""
$BehaviorDrift = ""
$BehaviorReport = ""
$BehaviorReceipt = ""
$Identity = ""
$IdentityReport = ""
$IdentityReceipt = ""
$Classification = ""
$ClassificationReport = ""
$ClassificationReceipt = ""
$Lineage = ""
$LineageReport = ""
$LineageReceipt = ""
$CapabilityGraph = ""
$CapabilityReport = ""
$CapabilityReceipt = ""
$RiskTopology = ""
$RiskTopologyReport = ""
$RiskTopologyReceipt = ""
$Alerts = ""
$AlertsReceipt = ""
$Notifications = ""
$LatestNotification = ""
$NotifyReceipt = ""

foreach($Line in @($ShadowOut + $DailyOut + $IntelOut + $BehaviorOut + $IdentityOut + $ClassOut + $LineageOut + $CapabilityOut + $AlertsOut + $NotifyOut)){
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
    elseif([string]::IsNullOrWhiteSpace($BehaviorReceipt)){ $BehaviorReceipt = $S.Substring(8).Trim() }
    elseif([string]::IsNullOrWhiteSpace($IdentityReceipt)){ $IdentityReceipt = $S.Substring(8).Trim() }
    elseif([string]::IsNullOrWhiteSpace($ClassificationReceipt)){ $ClassificationReceipt = $S.Substring(8).Trim() }
    elseif([string]::IsNullOrWhiteSpace($LineageReceipt)){ $LineageReceipt = $S.Substring(8).Trim() }
    elseif([string]::IsNullOrWhiteSpace($CapabilityReceipt)){ $CapabilityReceipt = $S.Substring(8).Trim() }
    elseif([string]::IsNullOrWhiteSpace($RiskTopologyReceipt)){ $RiskTopologyReceipt = $S.Substring(8).Trim() }
    elseif([string]::IsNullOrWhiteSpace($AlertsReceipt)){ $AlertsReceipt = $S.Substring(8).Trim() }
    elseif([string]::IsNullOrWhiteSpace($NotifyReceipt)){ $NotifyReceipt = $S.Substring(8).Trim() }
  }
    if($S.StartsWith("INTELLIGENCE:")){ $Intelligence = $S.Substring(13).Trim() }
      if($S.StartsWith("DRIFT:") -and $S -like "DRIFT: *behavioral_drift.json"){
    $BehaviorDrift = $S.Substring(6).Trim()
  }
  if($S.StartsWith("REPORT:") -and $S -like "*behavioral_drift_report.md"){
    $BehaviorReport = $S.Substring(7).Trim()
  }
    if($S.StartsWith("IDENTITY:")){ $Identity = $S.Substring(9).Trim() }
  if($S.StartsWith("REPORT:") -and $S -like "*repo_identity_report.md"){
    $IdentityReport = $S.Substring(7).Trim()
  }
    if($S.StartsWith("CLASSIFICATION:")){ $Classification = $S.Substring(15).Trim() }
  if($S.StartsWith("REPORT:") -and $S -like "*software_classification_report.md"){
    $ClassificationReport = $S.Substring(7).Trim()
  }
    if($S.StartsWith("LINEAGE:")){ $Lineage = $S.Substring(8).Trim() }
  if($S.StartsWith("REPORT:") -and $S -like "*lineage_report.md"){
    $LineageReport = $S.Substring(7).Trim()
  }
    if($S.StartsWith("GRAPH:")){ $CapabilityGraph = $S.Substring(6).Trim() }
  if($S.StartsWith("REPORT:") -and $S -like "*capability_graph_report.md"){
    $CapabilityReport = $S.Substring(7).Trim()
  }
    if($S.StartsWith("RISK_TOPOLOGY:")){ $RiskTopology = $S.Substring(14).Trim() }
  if($S.StartsWith("REPORT:") -and $S -like "*risk_topology_report.md"){
    $RiskTopologyReport = $S.Substring(7).Trim()
  }
  if($S.StartsWith("ALERTS:")){ $Alerts = $S.Substring(7).Trim() }
  if($S.StartsWith("NOTIFICATIONS:")){ $Notifications = $S.Substring(14).Trim() }
  if($S.StartsWith("LATEST:")){ $LatestNotification = $S.Substring(7).Trim() }
}

$Required = @($Snapshot,$Diff,$Report,$Receipt,$Intelligence,$IntelReport,$IntelReceipt,$BehaviorDrift,$BehaviorReport,$BehaviorReceipt,$Identity,$IdentityReport,$IdentityReceipt,$Classification,$ClassificationReport,$ClassificationReceipt,$Lineage,$LineageReport,$LineageReceipt,$CapabilityGraph,$CapabilityReport,$CapabilityReceipt,$Alerts,$AlertsReceipt,$Notifications,$LatestNotification,$NotifyReceipt)
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
  behavioral_drift = $BehaviorDrift
  behavioral_drift_report = $BehaviorReport
  behavioral_drift_receipt = $BehaviorReceipt
  repo_identity = $Identity
  repo_identity_report = $IdentityReport
  repo_identity_receipt = $IdentityReceipt
  software_classification = $Classification
  software_classification_report = $ClassificationReport
  software_classification_receipt = $ClassificationReceipt
  lineage = $Lineage
  lineage_report = $LineageReport
  lineage_receipt = $LineageReceipt
  capability_graph = $CapabilityGraph
  capability_graph_report = $CapabilityReport
  capability_graph_receipt = $CapabilityReceipt
  alerts = $Alerts
  alerts_receipt = $AlertsReceipt
  notifications = $Notifications
  latest_notification = $LatestNotification
  notify_receipt = $NotifyReceipt
  status = "GREEN"
}

$ReceiptPath = Join-Path $PipelineRoot "cr_pipeline_receipts.ndjson"
Write-Utf8NoBomLf -Path $ReceiptPath -Text (($PipelineReceipt | ConvertTo-Json -Depth 20 -Compress))

Write-Host "CR_PIPELINE_OK" -ForegroundColor Green
Write-Host ("PIPELINE_RECEIPT: " + $ReceiptPath)