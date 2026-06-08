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

function Classify-Identity {
  param($Snapshot)

  $Signals = Get-Prop -Obj $Snapshot -Name "signals" -Default $null
  $Extensions = Get-Prop -Obj $Snapshot -Name "extensions" -Default $null

  $ApiCount = 0
  $SchemaCount = 0

  if($Signals){
    $ApiCount = @(Get-Prop -Obj $Signals -Name "api_candidates" -Default @()).Count
    $SchemaCount = @(Get-Prop -Obj $Signals -Name "schema_candidates" -Default @()).Count
  }

  $HasPackage = $false
  $HasDocker = $false
  $HasSupabase = $false
  $HasGithubActions = $false

  if($Signals){
    $HasPackage = [bool](Get-Prop -Obj $Signals -Name "has_package_json" -Default $false)
    $HasDocker = [bool](Get-Prop -Obj $Signals -Name "has_docker" -Default $false)
    $HasSupabase = [bool](Get-Prop -Obj $Signals -Name "has_supabase" -Default $false)
    $HasGithubActions = [bool](Get-Prop -Obj $Signals -Name "has_github_actions" -Default $false)
  }

  $Shape = "unknown"

  if($ApiCount -gt 0 -and $SchemaCount -gt 0){
    $Shape = "full_stack_or_service"
  } elseif($ApiCount -gt 0){
    $Shape = "api_or_service"
  } elseif($HasPackage){
    $Shape = "application_or_tooling"
  } else {
    $Shape = "repository"
  }

  $RuntimeSurface = @()
  if($HasPackage){ $RuntimeSurface += "node_package_surface" }
  if($HasDocker){ $RuntimeSurface += "container_surface" }
  if($HasSupabase){ $RuntimeSurface += "supabase_surface" }
  if($HasGithubActions){ $RuntimeSurface += "ci_surface" }
  if($ApiCount -gt 0){ $RuntimeSurface += "api_surface" }
  if($SchemaCount -gt 0){ $RuntimeSurface += "schema_surface" }

  return [ordered]@{
    shape = $Shape
    api_candidate_count = $ApiCount
    schema_candidate_count = $SchemaCount
    runtime_surfaces = $RuntimeSurface
  }
}

if(-not (Test-Path -LiteralPath $TargetRepo -PathType Container)){
  throw "TARGET_REPO_NOT_FOUND: $TargetRepo"
}

$RepoName = Split-Path -Leaf (Resolve-Path -LiteralPath $TargetRepo)
$ProfileRoot = Join-Path $TargetRepo ("runtime\shadow_profiles\" + $RepoName)
$SnapshotRoot = Join-Path $ProfileRoot "snapshots"
$DriftRoot = Join-Path $ProfileRoot "behavioral_drift"

New-Item -ItemType Directory -Force -Path $DriftRoot | Out-Null

$Snapshots = @()
if(Test-Path -LiteralPath $SnapshotRoot){
  $Snapshots = Get-ChildItem -LiteralPath $SnapshotRoot -Filter "*.snapshot.json" -File | Sort-Object Name
}

if(@($Snapshots).Count -lt 1){
  throw "NO_SNAPSHOTS_FOUND_RUN_CR_RUN_FIRST"
}

$FirstSnapshotPath = $Snapshots[0].FullName
$LatestSnapshotPath = $Snapshots[@($Snapshots).Count - 1].FullName

$First = Read-JsonSafe -Path $FirstSnapshotPath
$Latest = Read-JsonSafe -Path $LatestSnapshotPath

if($null -eq $First -or $null -eq $Latest){
  throw "SNAPSHOT_PARSE_FAILED"
}

$FirstIdentity = Classify-Identity -Snapshot $First
$LatestIdentity = Classify-Identity -Snapshot $Latest

$Changes = @()
$DisplayChanges = @()

if($FirstIdentity.shape -ne $LatestIdentity.shape){
  $Changes += [ordered]@{
    code = "REPO_SHAPE_CHANGED"
    from = $FirstIdentity.shape
    to = $LatestIdentity.shape
    severity = "MEDIUM"
  }
}

foreach($s in @($LatestIdentity.runtime_surfaces)){
  if(@($FirstIdentity.runtime_surfaces) -notcontains $s){
    $Changes += [ordered]@{
      code = "RUNTIME_SURFACE_ADDED"
      surface = $s
      severity = "MEDIUM"
    }
  }
}

foreach($s in @($FirstIdentity.runtime_surfaces)){
  if(@($LatestIdentity.runtime_surfaces) -notcontains $s){
    $Changes += [ordered]@{
      code = "RUNTIME_SURFACE_REMOVED"
      surface = $s
      severity = "LOW"
    }
  }
}

if([int]$LatestIdentity.api_candidate_count -gt [int]$FirstIdentity.api_candidate_count){
  $Changes += [ordered]@{
    code = "API_SURFACE_EXPANDED"
    from = $FirstIdentity.api_candidate_count
    to = $LatestIdentity.api_candidate_count
    severity = "MEDIUM"
  }
}

if([int]$LatestIdentity.schema_candidate_count -gt [int]$FirstIdentity.schema_candidate_count){
  $Changes += [ordered]@{
    code = "SCHEMA_SURFACE_EXPANDED"
    from = $FirstIdentity.schema_candidate_count
    to = $LatestIdentity.schema_candidate_count
    severity = "MEDIUM"
  }
}

$DisplayChanges = @($Changes)

if(@($Changes).Count -eq 0){
  $DisplayChanges += [ordered]@{
    code = "NO_BEHAVIORAL_DRIFT"
    severity = "INFO"
  }
}

$Out = [ordered]@{
  schema = "contract_registry.behavioral_drift.v1"
  generated_utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  first_snapshot = $FirstSnapshotPath
  latest_snapshot = $LatestSnapshotPath
  first_identity = $FirstIdentity
  latest_identity = $LatestIdentity
  change_count = @($Changes).Count
  display_count = @($DisplayChanges).Count
changes = $Changes
  display_changes = $DisplayChanges
}

$OutPath = Join-Path $DriftRoot "behavioral_drift.json"
Write-Utf8NoBomLf -Path $OutPath -Text ($Out | ConvertTo-Json -Depth 30)

$Report = @()
$Report += "# Contract Registry Behavioral Drift Report"
$Report += ""
$Report += "Repo: $RepoName"
$Report += "Generated UTC: $($Out.generated_utc)"
$Report += ""
$Report += "## Identity"
$Report += "- First shape: $($FirstIdentity.shape)"
$Report += "- Latest shape: $($LatestIdentity.shape)"
$Report += "- First surfaces: $(@($FirstIdentity.runtime_surfaces) -join ', ')"
$Report += "- Latest surfaces: $(@($LatestIdentity.runtime_surfaces) -join ', ')"
$Report += ""
$Report += "## Behavioral Changes"

foreach($c in @($DisplayChanges)){
  $Report += "- $($c.severity) $($c.code)"
}

$ReportPath = Join-Path $DriftRoot "behavioral_drift_report.md"
Write-Utf8NoBomLf -Path $ReportPath -Text ($Report -join "`n")

$Receipt = [ordered]@{
  schema = "contract_registry.behavioral_drift_receipt.v1"
  utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  drift = $OutPath
  report = $ReportPath
  change_count = @($Changes).Count
  display_count = @($DisplayChanges).Count
}

$ReceiptPath = Join-Path $DriftRoot "behavioral_drift_receipt.json"
Write-Utf8NoBomLf -Path $ReceiptPath -Text ($Receipt | ConvertTo-Json -Depth 20)

Write-Host "CR_BEHAVIORAL_DRIFT_OK" -ForegroundColor Green
Write-Host ("DRIFT: " + $OutPath)
Write-Host ("REPORT: " + $ReportPath)
Write-Host ("RECEIPT: " + $ReceiptPath)

foreach($c in @($DisplayChanges)){
  Write-Host ("DRIFT: " + $c.severity + " " + $c.code)
}