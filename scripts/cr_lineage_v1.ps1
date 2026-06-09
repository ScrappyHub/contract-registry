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

$IdentityPath = Join-Path $ProfileRoot "identity\repo_identity.json"
$ClassPath = Join-Path $ProfileRoot "classification\software_classification.json"
$BehaviorPath = Join-Path $ProfileRoot "behavioral_drift\behavioral_drift.json"
$SnapshotRoot = Join-Path $ProfileRoot "snapshots"

$Identity = Read-JsonSafe -Path $IdentityPath
$Class = Read-JsonSafe -Path $ClassPath
$Behavior = Read-JsonSafe -Path $BehaviorPath

if($null -eq $Identity){ throw "REPO_IDENTITY_NOT_FOUND_RUN_CR_RUN_FIRST" }
if($null -eq $Class){ throw "SOFTWARE_CLASSIFICATION_NOT_FOUND_RUN_CR_RUN_FIRST" }

$Snapshots = @()
if(Test-Path -LiteralPath $SnapshotRoot){
  $Snapshots = Get-ChildItem -LiteralPath $SnapshotRoot -Filter "*.snapshot.json" -File | Sort-Object Name
}

$CurrentShape = [string](Get-Prop -Obj $Identity -Name "shape" -Default "unknown")
$CurrentClass = [string](Get-Prop -Obj $Identity -Name "software_class" -Default ([string](Get-Prop -Obj $Class -Name "software_class" -Default "unknown")))
$CurrentArchetype = [string](Get-Prop -Obj $Identity -Name "archetype" -Default "unknown")
$CurrentConfidence = [int](Get-Prop -Obj $Identity -Name "software_class_confidence" -Default ([int](Get-Prop -Obj $Class -Name "confidence" -Default 0)))
$Capabilities = @(Get-Prop -Obj $Identity -Name "capabilities" -Default @())
$Surfaces = @(Get-Prop -Obj $Identity -Name "runtime_surfaces" -Default @())
$BehavioralChangeCount = [int](Get-Prop -Obj $Identity -Name "behavioral_change_count" -Default 0)

$FirstShape = "unknown"
$FirstClass = "unknown"
$EvolutionChain = @()

if(@($Snapshots).Count -gt 0){
  $FirstSnapshot = Read-JsonSafe -Path $Snapshots[0].FullName

  if($FirstSnapshot){
    $FirstSignals = Get-Prop -Obj $FirstSnapshot -Name "signals" -Default $null
    $FirstApi = 0
    $FirstSchema = 0
    $FirstSupabase = $false
    $FirstCi = $false

    if($FirstSignals){
      $FirstApi = @(Get-Prop -Obj $FirstSignals -Name "api_candidates" -Default @()).Count
      $FirstSchema = @(Get-Prop -Obj $FirstSignals -Name "schema_candidates" -Default @()).Count
      $FirstSupabase = [bool](Get-Prop -Obj $FirstSignals -Name "has_supabase" -Default $false)
      $FirstCi = [bool](Get-Prop -Obj $FirstSignals -Name "has_github_actions" -Default $false)
    }

    if($FirstSupabase -and $FirstApi -gt 0 -and $FirstSchema -gt 0){
      $FirstShape = "full_stack_or_service"
      $FirstClass = "governance_platform"
    }
    elseif($FirstApi -gt 0 -and $FirstSchema -gt 0){
      $FirstShape = "full_stack_or_service"
      $FirstClass = "service_application"
    }
    elseif($FirstSchema -gt 0){
      $FirstShape = "schema_or_database_repo"
      $FirstClass = "database_centric_application"
    }
    elseif($FirstCi){
      $FirstShape = "automation_repo"
      $FirstClass = "developer_tooling"
    }
    else {
      $FirstShape = "repository"
      $FirstClass = "unknown_software"
    }
  }
}

if($FirstClass -ne "unknown"){ $EvolutionChain += $FirstClass }

if($Capabilities -contains "api" -and $EvolutionChain -notcontains "service_application"){
  $EvolutionChain += "service_application"
}

if($Capabilities -contains "schema_or_database" -and $EvolutionChain -notcontains "database_centric_application"){
  $EvolutionChain += "database_centric_application"
}

if($CurrentClass -and $EvolutionChain -notcontains $CurrentClass){
  $EvolutionChain += $CurrentClass
}

if(@($EvolutionChain).Count -eq 0){
  $EvolutionChain = @($CurrentClass)
}

$Trajectory = "stable"

if($CurrentClass -eq "governance_platform" -and ($Capabilities -contains "api") -and ($Capabilities -contains "schema_or_database")){
  $Trajectory = "platformizing"
}
elseif($CurrentShape -ne $FirstShape -and $CurrentShape -eq "full_stack_or_service"){
  $Trajectory = "expanding"
}
elseif($BehavioralChangeCount -gt 2){
  $Trajectory = "expanding"
}
elseif($CurrentClass -eq $FirstClass){
  $Trajectory = "stable"
}

$Velocity = "low"
if(@($Snapshots).Count -gt 100){ $Velocity = "moderate" }
if(@($Snapshots).Count -gt 300){ $Velocity = "high" }

$ShapeChanged = $FirstShape -ne "unknown" -and $CurrentShape -ne $FirstShape
$ClassChanged = $FirstClass -ne "unknown" -and $CurrentClass -ne $FirstClass

$Confidence = $CurrentConfidence
if($Trajectory -eq "platformizing" -and $Confidence -lt 95){ $Confidence = 95 }
if($Confidence -gt 99){ $Confidence = 99 }

$Out = [ordered]@{
  schema = "contract_registry.lineage.v1"
  generated_utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  target_repo = (Resolve-Path -LiteralPath $TargetRepo).Path
  first_observed_shape = $FirstShape
  current_shape = $CurrentShape
  first_class = $FirstClass
  current_class = $CurrentClass
  current_archetype = $CurrentArchetype
  evolution_chain = $EvolutionChain
  trajectory = $Trajectory
  velocity = $Velocity
  shape_changed = $ShapeChanged
  classification_changed = $ClassChanged
  snapshot_count = @($Snapshots).Count
  confidence = $Confidence
}

$LineageRoot = Join-Path $ProfileRoot "lineage"
New-Item -ItemType Directory -Force -Path $LineageRoot | Out-Null

$LineagePath = Join-Path $LineageRoot "lineage.json"
Write-Utf8NoBomLf -Path $LineagePath -Text ($Out | ConvertTo-Json -Depth 30)

$Report = @()
$Report += "# Contract Registry Lineage"
$Report += ""
$Report += "Repo: $RepoName"
$Report += "Generated UTC: $($Out.generated_utc)"
$Report += ""
$Report += "## Current"
$Report += "- Current class: $CurrentClass"
$Report += "- Current archetype: $CurrentArchetype"
$Report += "- Current shape: $CurrentShape"
$Report += ""
$Report += "## Origin"
$Report += "- First observed class: $FirstClass"
$Report += "- First observed shape: $FirstShape"
$Report += ""
$Report += "## Trajectory"
$Report += "- Trajectory: $Trajectory"
$Report += "- Velocity: $Velocity"
$Report += "- Confidence: $Confidence"
$Report += ""
$Report += "## Evolution Chain"
foreach($e in @($EvolutionChain)){ $Report += "- $e" }

$ReportPath = Join-Path $LineageRoot "lineage_report.md"
Write-Utf8NoBomLf -Path $ReportPath -Text ($Report -join "`n")

$Receipt = [ordered]@{
  schema = "contract_registry.lineage_receipt.v1"
  utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  lineage = $LineagePath
  report = $ReportPath
  current_class = $CurrentClass
  trajectory = $Trajectory
  confidence = $Confidence
}

$ReceiptPath = Join-Path $LineageRoot "lineage_receipt.json"
Write-Utf8NoBomLf -Path $ReceiptPath -Text ($Receipt | ConvertTo-Json -Depth 20)

Write-Host "CR_LINEAGE_OK" -ForegroundColor Green
Write-Host ("LINEAGE: " + $LineagePath)
Write-Host ("REPORT: " + $ReportPath)
Write-Host ("RECEIPT: " + $ReceiptPath)
Write-Host ("CURRENT_CLASS: " + $CurrentClass)
Write-Host ("TRAJECTORY: " + $Trajectory)
Write-Host ("CONFIDENCE: " + $Confidence)