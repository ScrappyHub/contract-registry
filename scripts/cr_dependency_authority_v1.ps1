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

function New-Authority {
  param(
    [string]$Name,
    [string]$AuthorityType,
    [int]$AuthorityScore,
    [string[]]$ReasonCodes
  )

  return [pscustomobject]@{
    name = $Name
    authority_type = $AuthorityType
    authority_score = $AuthorityScore
    reason_codes = @($ReasonCodes | Sort-Object -Unique)
  }
}

if(-not (Test-Path -LiteralPath $TargetRepo -PathType Container)){
  throw "TARGET_REPO_NOT_FOUND: $TargetRepo"
}

$ResolvedRepo = (Resolve-Path -LiteralPath $TargetRepo).Path
$RepoName = Split-Path -Leaf $ResolvedRepo
$ProfileRoot = Join-Path $ResolvedRepo ("runtime\shadow_profiles\" + $RepoName)

$DependencyPath = Join-Path $ProfileRoot "dependencies\dependency_intelligence.json"
$RiskPath = Join-Path $ProfileRoot "risk_topology\risk_topology.json"
$CapabilityPath = Join-Path $ProfileRoot "capabilities\capability_graph.json"

$Dependency = Read-JsonSafe -Path $DependencyPath
$RiskTopology = Read-JsonSafe -Path $RiskPath
$CapabilityGraph = Read-JsonSafe -Path $CapabilityPath

if($null -eq $Dependency){ throw "DEPENDENCY_INTELLIGENCE_NOT_FOUND_RUN_DEPENDENCY_FIRST" }
if($null -eq $RiskTopology){ throw "RISK_TOPOLOGY_NOT_FOUND_RUN_RISK_FIRST" }

$Primary = @()
$Secondary = @()
$Operational = @()
$Peripheral = @()

$ExternalPlatforms = @(Get-Prop -Obj $Dependency -Name "external_platforms" -Default @())
$CriticalDependencies = @(Get-Prop -Obj $Dependency -Name "critical_dependencies" -Default @())
$RuntimeDependencies = @(Get-Prop -Obj $Dependency -Name "runtime_dependencies" -Default @())
$PackageManagers = @(Get-Prop -Obj $Dependency -Name "package_managers" -Default @())
$TrustSurface = @(Get-Prop -Obj $Dependency -Name "trust_surface" -Default @())

foreach($p in @($ExternalPlatforms)){
  switch([string]$p){
    "supabase" {
      $Primary += New-Authority -Name "supabase" -AuthorityType "primary" -AuthorityScore 95 -ReasonCodes @("BACKEND_AUTHORITY","HOSTED_PLATFORM_AUTHORITY","DATABASE_GATEWAY")
    }
    "stripe" {
      $Primary += New-Authority -Name "stripe" -AuthorityType "primary" -AuthorityScore 92 -ReasonCodes @("PAYMENT_AUTHORITY","EXTERNAL_VENDOR_AUTHORITY")
    }
    "github_actions" {
      $Secondary += New-Authority -Name "github_actions" -AuthorityType "secondary" -AuthorityScore 72 -ReasonCodes @("CI_AUTHORITY","AUTOMATION_AUTHORITY")
    }
    default {
      $Secondary += New-Authority -Name ([string]$p) -AuthorityType "secondary" -AuthorityScore 55 -ReasonCodes @("EXTERNAL_PLATFORM_AUTHORITY")
    }
  }
}

foreach($d in @($CriticalDependencies)){
  switch([string]$d){
    "postgres" {
      $Primary += New-Authority -Name "postgres" -AuthorityType "primary" -AuthorityScore 93 -ReasonCodes @("DATA_AUTHORITY","SCHEMA_AUTHORITY")
    }
    "supabase" {
      if(-not (@($Primary.name) -contains "supabase")){
        $Primary += New-Authority -Name "supabase" -AuthorityType "primary" -AuthorityScore 95 -ReasonCodes @("BACKEND_AUTHORITY","CRITICAL_DEPENDENCY")
      }
    }
    default {
      $Secondary += New-Authority -Name ([string]$d) -AuthorityType "secondary" -AuthorityScore 65 -ReasonCodes @("CRITICAL_DEPENDENCY_AUTHORITY")
    }
  }
}

foreach($r in @($RuntimeDependencies)){
  switch([string]$r){
    "nodejs" {
      $Secondary += New-Authority -Name "nodejs" -AuthorityType "secondary" -AuthorityScore 68 -ReasonCodes @("RUNTIME_AUTHORITY")
    }
    "server_runtime" {
      $Operational += New-Authority -Name "server_runtime" -AuthorityType "operational" -AuthorityScore 64 -ReasonCodes @("SERVICE_RUNTIME_AUTHORITY")
    }
    "supabase" {
      if(-not (@($Primary.name) -contains "supabase")){
        $Primary += New-Authority -Name "supabase" -AuthorityType "primary" -AuthorityScore 95 -ReasonCodes @("BACKEND_AUTHORITY","RUNTIME_DEPENDENCY")
      }
    }
    "postgres" {
      if(-not (@($Primary.name) -contains "postgres")){
        $Primary += New-Authority -Name "postgres" -AuthorityType "primary" -AuthorityScore 93 -ReasonCodes @("DATA_AUTHORITY","RUNTIME_DEPENDENCY")
      }
    }
    default {
      $Operational += New-Authority -Name ([string]$r) -AuthorityType "operational" -AuthorityScore 50 -ReasonCodes @("RUNTIME_DEPENDENCY_AUTHORITY")
    }
  }
}

foreach($pm in @($PackageManagers)){
  switch([string]$pm){
    "npm" {
      $Secondary += New-Authority -Name "npm" -AuthorityType "secondary" -AuthorityScore 60 -ReasonCodes @("PACKAGE_MANAGER_AUTHORITY")
    }
    "pnpm" {
      $Secondary += New-Authority -Name "pnpm" -AuthorityType "secondary" -AuthorityScore 60 -ReasonCodes @("PACKAGE_MANAGER_AUTHORITY")
    }
    default {
      $Peripheral += New-Authority -Name ([string]$pm) -AuthorityType "peripheral" -AuthorityScore 35 -ReasonCodes @("PACKAGE_MANAGER")
    }
  }
}

foreach($t in @($TrustSurface)){
  switch([string]$t){
    "database_schema" {
      $Operational += New-Authority -Name "database_schema" -AuthorityType "operational" -AuthorityScore 78 -ReasonCodes @("SCHEMA_CONTROL_SURFACE")
    }
    "api_surface" {
      $Operational += New-Authority -Name "api_surface" -AuthorityType "operational" -AuthorityScore 70 -ReasonCodes @("REMOTE_ENTRYPOINT_SURFACE")
    }
    "ci_workflows" {
      $Operational += New-Authority -Name "ci_workflows" -AuthorityType "operational" -AuthorityScore 65 -ReasonCodes @("BUILD_PIPELINE_SURFACE")
    }
    default {
      $Peripheral += New-Authority -Name ([string]$t) -AuthorityType "peripheral" -AuthorityScore 35 -ReasonCodes @("TRUST_SURFACE")
    }
  }
}

function Collapse-Authorities {
  param([array]$Authorities)

  return @(
    $Authorities |
      Group-Object name |
      ForEach-Object {
        $Group = @($_.Group)
        $Top = $Group | Sort-Object authority_score -Descending | Select-Object -First 1
        $Reasons = @()
        foreach($g in $Group){ $Reasons += @($g.reason_codes) }

        [pscustomobject]@{
          name = [string]$Top.name
          authority_type = [string]$Top.authority_type
          authority_score = [int]$Top.authority_score
          reason_codes = @($Reasons | Sort-Object -Unique)
        }
      } |
      Sort-Object name | Sort-Object authority_score -Descending
  )
}

$Primary = Collapse-Authorities $Primary
$Secondary = Collapse-Authorities $Secondary
$Operational = Collapse-Authorities $Operational
$Peripheral = Collapse-Authorities $Peripheral

$AllAuthorities = @($Primary + $Secondary + $Operational + $Peripheral)
$MaxAuthority = $AllAuthorities | Sort-Object authority_score -Descending | Select-Object -First 1
$AuthorityScore = if($MaxAuthority){ [int]$MaxAuthority.authority_score } else { 0 }

$DependencyConcentration = "low"
if(@($Primary).Count -eq 1 -and $AuthorityScore -ge 90){ $DependencyConcentration = "high" }
elseif(@($Primary).Count -ge 2){ $DependencyConcentration = "medium" }

$Out = [ordered]@{
  schema = "contract_registry.dependency_authority.v1"
  generated_utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  target_repo = $ResolvedRepo
  authority_score = $AuthorityScore
  dependency_concentration = $DependencyConcentration
  primary_authorities = $Primary
  secondary_authorities = $Secondary
  operational_authorities = $Operational
  peripheral_dependencies = $Peripheral
}

$Root = Join-Path $ProfileRoot "dependency_authority"
New-Item -ItemType Directory -Force -Path $Root | Out-Null

$OutPath = Join-Path $Root "dependency_authority.json"
Write-Utf8NoBomLf -Path $OutPath -Text ($Out | ConvertTo-Json -Depth 30)

$Report = @()
$Report += "# Contract Registry Dependency Authority"
$Report += ""
$Report += "Repo: $RepoName"
$Report += "Generated UTC: $($Out.generated_utc)"
$Report += ""
$Report += "## Summary"
$Report += "- Authority score: $AuthorityScore"
$Report += "- Dependency concentration: $DependencyConcentration"
$Report += ""
$Report += "## Primary Authorities"
foreach($a in @($Primary)){ $Report += "- $($a.authority_score) $($a.name)" }
$Report += ""
$Report += "## Secondary Authorities"
foreach($a in @($Secondary)){ $Report += "- $($a.authority_score) $($a.name)" }
$Report += ""
$Report += "## Operational Authorities"
foreach($a in @($Operational)){ $Report += "- $($a.authority_score) $($a.name)" }

$ReportPath = Join-Path $Root "dependency_authority_report.md"
Write-Utf8NoBomLf -Path $ReportPath -Text ($Report -join "`n")

$Receipt = [ordered]@{
  schema = "contract_registry.dependency_authority_receipt.v1"
  utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  authority = $OutPath
  report = $ReportPath
  authority_score = $AuthorityScore
  dependency_concentration = $DependencyConcentration
  primary_authority_count = @($Primary).Count
}

$ReceiptPath = Join-Path $Root "dependency_authority_receipt.json"
Write-Utf8NoBomLf -Path $ReceiptPath -Text ($Receipt | ConvertTo-Json -Depth 20)

Write-Host "CR_DEPENDENCY_AUTHORITY_OK" -ForegroundColor Green
Write-Host ("AUTHORITY: " + $OutPath)
Write-Host ("REPORT: " + $ReportPath)
Write-Host ("RECEIPT: " + $ReceiptPath)
Write-Host ("AUTHORITY_SCORE: " + $AuthorityScore)
Write-Host ("DEPENDENCY_CONCENTRATION: " + $DependencyConcentration)

foreach($a in @($Primary)){
  Write-Host ("PRIMARY_AUTHORITY: " + $a.authority_score + " " + $a.name)
}