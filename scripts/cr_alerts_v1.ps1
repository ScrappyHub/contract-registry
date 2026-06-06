param(
  [Parameter(Mandatory=$true)]
  [string]$TargetRepo
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

function Read-JsonSafe {
  param([string]$Path)
  if(-not (Test-Path -LiteralPath $Path)){ return $null }
  try { return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json) } catch { return $null }
}

function Get-Prop {
  param($Obj,[string]$Name,$Default=$null)
  if($null -eq $Obj){ return $Default }
  $Prop = $Obj.PSObject.Properties[$Name]
  if($null -eq $Prop){ return $Default }
  return $Prop.Value
}

if(-not (Test-Path -LiteralPath $TargetRepo -PathType Container)){
  throw "TARGET_REPO_NOT_FOUND: $TargetRepo"
}

$RepoName = Split-Path -Leaf (Resolve-Path -LiteralPath $TargetRepo)
$ProfileRoot = Join-Path $TargetRepo ("runtime\shadow_profiles\" + $RepoName)
$IntelPath = Join-Path $ProfileRoot "intelligence\intelligence.json"
$AlertsRoot = Join-Path $ProfileRoot "alerts"
New-Item -ItemType Directory -Force -Path $AlertsRoot | Out-Null

$Intel = Read-JsonSafe -Path $IntelPath
if($null -eq $Intel){
  throw "INTELLIGENCE_NOT_FOUND_RUN_CR_RUN_FIRST"
}

$Alerts = @()

function Add-Alert {
  param(
    [string]$Code,
    [string]$Severity,
    [string]$Message,
    [string]$Evidence = ""
  )

  $script:Alerts += [ordered]@{
    code = $Code
    severity = $Severity
    message = $Message
    evidence = $Evidence
  }
}

$MaxRisk = [int](Get-Prop -Obj $Intel -Name "max_risk_score" -Default 0)
$Activity = [string](Get-Prop -Obj $Intel -Name "activity_level" -Default "none")
$RiskTrend = [string](Get-Prop -Obj $Intel -Name "risk_trend" -Default "stable")
$DependencyDrift = [int](Get-Prop -Obj $Intel -Name "dependency_drift_count" -Default 0)
$CriticalDeleted = [int](Get-Prop -Obj $Intel -Name "critical_deletion_count" -Default 0)
$Signals = Get-Prop -Obj $Intel -Name "latest_signals" -Default $null

if($MaxRisk -ge 60){
  Add-Alert -Code "HIGH_RISK_POSTURE" -Severity "HIGH" -Message "High repository risk posture detected." -Evidence "max_risk_score=$MaxRisk"
} elseif($MaxRisk -ge 30){
  Add-Alert -Code "MEDIUM_RISK_POSTURE" -Severity "MEDIUM" -Message "Medium repository risk posture detected." -Evidence "max_risk_score=$MaxRisk"
}

if($RiskTrend -eq "increasing"){
  Add-Alert -Code "RISK_TREND_INCREASING" -Severity "MEDIUM" -Message "Risk trend is increasing over the analysis window." -Evidence "risk_trend=$RiskTrend"
}

if($Activity -eq "high"){
  Add-Alert -Code "HIGH_ACTIVITY_REPO" -Severity "MEDIUM" -Message "High change activity detected." -Evidence "activity_level=$Activity"
}

if($DependencyDrift -gt 0){
  Add-Alert -Code "DEPENDENCY_DRIFT" -Severity "MEDIUM" -Message "Dependency/package manager drift detected." -Evidence "dependency_drift_count=$DependencyDrift"
}

if($CriticalDeleted -gt 0){
  Add-Alert -Code "CRITICAL_FILE_DELETION" -Severity "HIGH" -Message "Critical project or governance file deletion detected." -Evidence "critical_deletion_count=$CriticalDeleted"
}

if($Signals){
  $ApiCandidates = Get-Prop -Obj $Signals -Name "api_candidates" -Default @()
  $SchemaCandidates = Get-Prop -Obj $Signals -Name "schema_candidates" -Default @()

  if(@($ApiCandidates).Count -gt 0){
    Add-Alert -Code "API_SURFACE_PRESENT" -Severity "LOW" -Message "API/server candidates are present." -Evidence ("count=" + @($ApiCandidates).Count)
  }

  if(@($SchemaCandidates).Count -gt 0){
    Add-Alert -Code "SCHEMA_SURFACE_PRESENT" -Severity "LOW" -Message "Schema/database candidates are present." -Evidence ("count=" + @($SchemaCandidates).Count)
  }
}

if(@($Alerts).Count -eq 0){
  Add-Alert -Code "NO_ACTIVE_ALERTS" -Severity "INFO" -Message "No active alerts detected." -Evidence ""
}

$Out = [ordered]@{
  schema = "contract_registry.alerts.v1"
  generated_utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  target_repo = (Resolve-Path -LiteralPath $TargetRepo).Path
  alert_count = @($Alerts).Count
  alerts = $Alerts
}

$AlertsPath = Join-Path $AlertsRoot "alerts.json"
Write-Utf8NoBomLf -Path $AlertsPath -Text ($Out | ConvertTo-Json -Depth 20)

$Receipt = [ordered]@{
  schema = "contract_registry.alerts_receipt.v1"
  utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  alerts = $AlertsPath
  alert_count = @($Alerts).Count
}

$ReceiptPath = Join-Path $AlertsRoot "alerts_receipt.json"
Write-Utf8NoBomLf -Path $ReceiptPath -Text ($Receipt | ConvertTo-Json -Depth 20)

Write-Host "CR_ALERTS_OK" -ForegroundColor Green
Write-Host ("ALERTS: " + $AlertsPath)
Write-Host ("RECEIPT: " + $ReceiptPath)

foreach($a in @($Alerts)){
  Write-Host ("ALERT: " + $a.severity + " " + $a.code + " - " + $a.message)
}