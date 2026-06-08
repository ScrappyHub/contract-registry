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
$BehaviorPath = Join-Path $ProfileRoot "behavioral_drift\behavioral_drift.json"
$AlertsPath = Join-Path $ProfileRoot "alerts\alerts.json"
$ConfigPath = Join-Path $ProfileRoot "shadow_config.json"

$Intel = Read-JsonSafe -Path $IntelPath
$Behavior = Read-JsonSafe -Path $BehaviorPath
$Alerts = Read-JsonSafe -Path $AlertsPath
$Config = Read-JsonSafe -Path $ConfigPath

if($null -eq $Intel){ throw "INTELLIGENCE_NOT_FOUND_RUN_CR_RUN_FIRST" }
if($null -eq $Behavior){ throw "BEHAVIORAL_DRIFT_NOT_FOUND_RUN_CR_RUN_FIRST" }

$LatestIdentity = Get-Prop -Obj $Behavior -Name "latest_identity" -Default $null

$Shape = "unknown"
$Surfaces = @()

if($LatestIdentity){
  $Shape = [string](Get-Prop -Obj $LatestIdentity -Name "shape" -Default "unknown")
  $Surfaces = @(Get-Prop -Obj $LatestIdentity -Name "runtime_surfaces" -Default @())
}

$MaxRisk = [int](Get-Prop -Obj $Intel -Name "max_risk_score" -Default 0)
$RiskPosture = "none"

if($MaxRisk -ge 60){ $RiskPosture = "high" }
elseif($MaxRisk -ge 30){ $RiskPosture = "medium" }
elseif($MaxRisk -gt 0){ $RiskPosture = "low" }

$AlertCodes = @()
if($Alerts){
  foreach($a in @($Alerts.alerts)){
    $AlertCodes += [string]$a.code
  }
}

$Capabilities = @()

foreach($s in @($Surfaces)){
  switch($s){
    "api_surface" { $Capabilities += "api" }
    "schema_surface" { $Capabilities += "schema_or_database" }
    "supabase_surface" { $Capabilities += "supabase" }
    "ci_surface" { $Capabilities += "ci" }
    "container_surface" { $Capabilities += "container" }
    "node_package_surface" { $Capabilities += "node_package" }
  }
}

$Capabilities = @($Capabilities | Sort-Object -Unique)

$Archetype = "unknown_repository"
$ClassificationConfidence = 40

if(
  $Surfaces -contains "supabase_surface" -and
  $Surfaces -contains "api_surface" -and
  $Surfaces -contains "schema_surface"
){
  $Archetype = "supabase_governed_platform"
  $ClassificationConfidence = 92
}
elseif(
  $Surfaces -contains "api_surface" -and
  $Surfaces -contains "schema_surface"
){
  $Archetype = "full_stack_service"
  $ClassificationConfidence = 86
}
elseif($Surfaces -contains "api_surface"){
  $Archetype = "api_service"
  $ClassificationConfidence = 78
}
elseif($Surfaces -contains "schema_surface"){
  $Archetype = "database_governance_system"
  $ClassificationConfidence = 74
}
elseif($Surfaces -contains "ci_surface"){
  $Archetype = "automation_or_ci_repo"
  $ClassificationConfidence = 65
}

$Ecosystems = @()

if($Surfaces -contains "supabase_surface"){ $Ecosystems += "supabase" }
if($Surfaces -contains "ci_surface"){ $Ecosystems += "github_actions_or_ci" }
if($Surfaces -contains "api_surface"){ $Ecosystems += "node_or_server_api" }
if($Surfaces -contains "schema_surface"){ $Ecosystems += "schema_governance" }

$Ecosystems = @($Ecosystems | Sort-Object -Unique)

$Identity = [ordered]@{
  schema = "contract_registry.repo_identity.v1"
  generated_utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  target_repo = (Resolve-Path -LiteralPath $TargetRepo).Path
  intent = if($Config){ [string](Get-Prop -Obj $Config -Name "intent" -Default "shadow") } else { "shadow" }
  shape = $Shape
  archetype = $Archetype
  classification_confidence = $ClassificationConfidence
  runtime_surfaces = $Surfaces
  capabilities = $Capabilities
  ecosystems = $Ecosystems
  risk_posture = $RiskPosture
  max_risk_score = $MaxRisk
  activity_level = [string](Get-Prop -Obj $Intel -Name "activity_level" -Default "unknown")
  risk_trend = [string](Get-Prop -Obj $Intel -Name "risk_trend" -Default "unknown")
  latest_file_count = [int](Get-Prop -Obj $Intel -Name "latest_file_count" -Default 0)
  behavioral_change_count = [int](Get-Prop -Obj $Behavior -Name "change_count" -Default 0)
  active_alert_count = if($Alerts){ [int](Get-Prop -Obj $Alerts -Name "alert_count" -Default 0) } else { 0 }
  active_alert_codes = @($AlertCodes | Sort-Object -Unique)
}

$IdentityRoot = Join-Path $ProfileRoot "identity"
New-Item -ItemType Directory -Force -Path $IdentityRoot | Out-Null

$IdentityPath = Join-Path $IdentityRoot "repo_identity.json"
Write-Utf8NoBomLf -Path $IdentityPath -Text ($Identity | ConvertTo-Json -Depth 30)

$Report = @()
$Report += "# Contract Registry Repo Identity"
$Report += ""
$Report += "Repo: $RepoName"
$Report += "Generated UTC: $($Identity.generated_utc)"
$Report += ""
$Report += "## Identity"
$Report += "- Shape: $Shape"
$Report += "- Archetype: $Archetype"
$Report += "- Classification confidence: $ClassificationConfidence"
$Report += "- Intent: $($Identity.intent)"
$Report += "- Risk posture: $RiskPosture"
$Report += "- Max risk score: $MaxRisk"
$Report += "- Activity level: $($Identity.activity_level)"
$Report += "- Risk trend: $($Identity.risk_trend)"
$Report += "- Latest file count: $($Identity.latest_file_count)"
$Report += ""
$Report += "## Runtime Surfaces"
foreach($s in @($Surfaces)){ $Report += "- $s" }
if(@($Surfaces).Count -eq 0){ $Report += "- None" }
$Report += ""
$Report += "## Ecosystems"
foreach($e in @($Ecosystems)){ $Report += "- $e" }
if(@($Ecosystems).Count -eq 0){ $Report += "- None" }
$Report += ""
$Report += "## Capabilities"
foreach($c in @($Capabilities)){ $Report += "- $c" }
if(@($Capabilities).Count -eq 0){ $Report += "- None" }
$Report += ""
$Report += "## Active Alert Codes"
foreach($a in @($Identity.active_alert_codes)){ $Report += "- $a" }
if(@($Identity.active_alert_codes).Count -eq 0){ $Report += "- None" }

$ReportPath = Join-Path $IdentityRoot "repo_identity_report.md"
Write-Utf8NoBomLf -Path $ReportPath -Text ($Report -join "`n")

$Receipt = [ordered]@{
  schema = "contract_registry.repo_identity_receipt.v1"
  utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  identity = $IdentityPath
  report = $ReportPath
  shape = $Shape
  archetype = $Archetype
  classification_confidence = $ClassificationConfidence
  risk_posture = $RiskPosture
  capability_count = @($Capabilities).Count
}

$ReceiptPath = Join-Path $IdentityRoot "repo_identity_receipt.json"
Write-Utf8NoBomLf -Path $ReceiptPath -Text ($Receipt | ConvertTo-Json -Depth 20)

Write-Host "CR_REPO_IDENTITY_OK" -ForegroundColor Green
Write-Host ("IDENTITY: " + $IdentityPath)
Write-Host ("REPORT: " + $ReportPath)
Write-Host ("RECEIPT: " + $ReceiptPath)
Write-Host ("SHAPE: " + $Shape)
Write-Host ("ARCHETYPE: " + $Archetype)
Write-Host ("CONFIDENCE: " + $ClassificationConfidence)
Write-Host ("RISK_POSTURE: " + $RiskPosture)