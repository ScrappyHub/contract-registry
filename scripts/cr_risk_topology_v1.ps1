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

function Add-RiskNode {
  param(
    [System.Collections.Generic.List[object]]$List,
    [string]$Name,
    [string]$Category,
    [int]$BaseScore,
    [string[]]$ReasonCodes
  )

  if([string]::IsNullOrWhiteSpace($Name)){ return }

  $Existing = $List | Where-Object { $_.name -eq $Name -and $_.category -eq $Category } | Select-Object -First 1

  if($Existing){
    $Existing.risk_score = [Math]::Min(100, [int]$Existing.risk_score + $BaseScore)
    $Existing.reason_codes = @($Existing.reason_codes + $ReasonCodes | Sort-Object -Unique)
    return
  }

  $Score = [Math]::Min(100, $BaseScore)
  $Blast = "low"
  if($Score -ge 85){ $Blast = "high" }
  elseif($Score -ge 60){ $Blast = "medium" }

  $List.Add([pscustomobject]@{
    name = $Name
    category = $Category
    risk_score = $Score
    blast_radius = $Blast
    reason_codes = @($ReasonCodes | Sort-Object -Unique)
  }) | Out-Null
}

if(-not (Test-Path -LiteralPath $TargetRepo -PathType Container)){
  throw "TARGET_REPO_NOT_FOUND: $TargetRepo"
}

$ResolvedRepo = (Resolve-Path -LiteralPath $TargetRepo).Path
$RepoName = Split-Path -Leaf $ResolvedRepo
$ProfileRoot = Join-Path $ResolvedRepo ("runtime\shadow_profiles\" + $RepoName)

$Dependency = Read-JsonSafe -Path (Join-Path $ProfileRoot "dependencies\dependency_intelligence.json")
$CapabilityGraph = Read-JsonSafe -Path (Join-Path $ProfileRoot "capabilities\capability_graph.json")
$Identity = Read-JsonSafe -Path (Join-Path $ProfileRoot "identity\repo_identity.json")
$Alerts = Read-JsonSafe -Path (Join-Path $ProfileRoot "alerts\alerts.json")

if($null -eq $Dependency){ throw "DEPENDENCY_INTELLIGENCE_NOT_FOUND_RUN_DEPENDENCY_INTELLIGENCE_FIRST" }

$Nodes = [System.Collections.Generic.List[object]]::new()

foreach($p in @(Get-Prop -Obj $Dependency -Name "external_platforms" -Default @())){
  switch([string]$p){
    "supabase" {
      Add-RiskNode -List $Nodes -Name "supabase" -Category "external_platform" -BaseScore 88 -ReasonCodes @("BACKEND_AUTHORITY","DATABASE_AUTHORITY","HOSTED_SERVICE_DEPENDENCY")
    }
    "github_actions" {
      Add-RiskNode -List $Nodes -Name "github_actions" -Category "external_platform" -BaseScore 62 -ReasonCodes @("CI_TRUST_SURFACE","AUTOMATION_AUTHORITY")
    }
    "stripe" {
      Add-RiskNode -List $Nodes -Name "stripe" -Category "external_platform" -BaseScore 85 -ReasonCodes @("PAYMENT_AUTHORITY","EXTERNAL_VENDOR_DEPENDENCY")
    }
    default {
      Add-RiskNode -List $Nodes -Name ([string]$p) -Category "external_platform" -BaseScore 45 -ReasonCodes @("EXTERNAL_PLATFORM")
    }
  }
}

foreach($d in @(Get-Prop -Obj $Dependency -Name "critical_dependencies" -Default @())){
  switch([string]$d){
    "postgres" {
      Add-RiskNode -List $Nodes -Name "postgres" -Category "critical_dependency" -BaseScore 84 -ReasonCodes @("SCHEMA_AUTHORITY","DATA_AUTHORITY")
    }
    "supabase" {
      Add-RiskNode -List $Nodes -Name "supabase" -Category "critical_dependency" -BaseScore 88 -ReasonCodes @("BACKEND_AUTHORITY","CRITICAL_RUNTIME_DEPENDENCY")
    }
    "stripe" {
      Add-RiskNode -List $Nodes -Name "stripe" -Category "critical_dependency" -BaseScore 85 -ReasonCodes @("PAYMENT_AUTHORITY","CRITICAL_VENDOR_DEPENDENCY")
    }
    default {
      Add-RiskNode -List $Nodes -Name ([string]$d) -Category "critical_dependency" -BaseScore 55 -ReasonCodes @("CRITICAL_DEPENDENCY")
    }
  }
}

foreach($t in @(Get-Prop -Obj $Dependency -Name "trust_surface" -Default @())){
  switch([string]$t){
    "database_schema" {
      Add-RiskNode -List $Nodes -Name "database_schema" -Category "trust_surface" -BaseScore 76 -ReasonCodes @("SCHEMA_TRUST_SURFACE","DATA_MODEL_AUTHORITY")
    }
    "api_surface" {
      Add-RiskNode -List $Nodes -Name "api_surface" -Category "trust_surface" -BaseScore 68 -ReasonCodes @("REMOTE_ENTRYPOINT","SERVER_TRUST_SURFACE")
    }
    "ci_workflows" {
      Add-RiskNode -List $Nodes -Name "ci_workflows" -Category "trust_surface" -BaseScore 61 -ReasonCodes @("BUILD_PIPELINE_AUTHORITY")
    }
    "payments" {
      Add-RiskNode -List $Nodes -Name "payments" -Category "trust_surface" -BaseScore 82 -ReasonCodes @("PAYMENT_TRUST_SURFACE")
    }
    default {
      Add-RiskNode -List $Nodes -Name ([string]$t) -Category "trust_surface" -BaseScore 45 -ReasonCodes @("TRUST_SURFACE")
    }
  }
}

if($CapabilityGraph){
  foreach($c in @(Get-Prop -Obj $CapabilityGraph -Name "capabilities" -Default @())){
    $Name = [string](Get-Prop -Obj $c -Name "name" -Default "")
    $Conf = [int](Get-Prop -Obj $c -Name "confidence" -Default 0)

    if($Conf -lt 94){ continue }

    switch($Name){
      "governed_platform_runtime" {
        Add-RiskNode -List $Nodes -Name $Name -Category "capability" -BaseScore 70 -ReasonCodes @("GOVERNED_RUNTIME_CAPABILITY")
      }
      "supabase_backend" {
        Add-RiskNode -List $Nodes -Name $Name -Category "capability" -BaseScore 78 -ReasonCodes @("BACKEND_CAPABILITY")
      }
      "database_or_schema_governance" {
        Add-RiskNode -List $Nodes -Name $Name -Category "capability" -BaseScore 74 -ReasonCodes @("DATABASE_GOVERNANCE_CAPABILITY")
      }
      "api_surface" {
        Add-RiskNode -List $Nodes -Name $Name -Category "capability" -BaseScore 66 -ReasonCodes @("API_CAPABILITY")
      }
      "governance_modeling" {
        Add-RiskNode -List $Nodes -Name $Name -Category "capability" -BaseScore 62 -ReasonCodes @("GOVERNANCE_MODELING_CAPABILITY")
      }
    }
  }
}

if($Identity){
  $RiskPosture = [string](Get-Prop -Obj $Identity -Name "risk_posture" -Default "none")
  if($RiskPosture -eq "medium"){
    Add-RiskNode -List $Nodes -Name "repository_risk_posture" -Category "aggregate" -BaseScore 60 -ReasonCodes @("MEDIUM_REPOSITORY_RISK_POSTURE")
  }
  elseif($RiskPosture -eq "high"){
    Add-RiskNode -List $Nodes -Name "repository_risk_posture" -Category "aggregate" -BaseScore 85 -ReasonCodes @("HIGH_REPOSITORY_RISK_POSTURE")
  }
}

$Ranked = @($Nodes | Sort-Object name | Sort-Object risk_score -Descending)

$Collapsed = @(
  $Ranked |
    Group-Object name |
    ForEach-Object {
      $Group = @($_.Group)
      $Top = $Group | Sort-Object risk_score -Descending | Select-Object -First 1
      $ReasonCodes = @()
      $Categories = @()

      foreach($g in $Group){
        $ReasonCodes += @($g.reason_codes)
        $Categories += [string]$g.category
      }

      $Score = [int]$Top.risk_score
      $Blast = "low"
      if($Score -ge 85){ $Blast = "high" }
      elseif($Score -ge 60){ $Blast = "medium" }

      [pscustomobject]@{
        name = [string]$Top.name
        categories = @($Categories | Sort-Object -Unique)
        risk_score = $Score
        blast_radius = $Blast
        reason_codes = @($ReasonCodes | Sort-Object -Unique)
        source_node_count = @($Group).Count
      }
    } |
    Sort-Object name |
    Sort-Object risk_score -Descending
)

foreach($n in @($Ranked)){
  if($n.risk_score -ge 85){ $n.blast_radius = "high" }
  elseif($n.risk_score -ge 60){ $n.blast_radius = "medium" }
  else { $n.blast_radius = "low" }
}

$HighCount = @($Collapsed | Where-Object { $_.blast_radius -eq "high" }).Count
$MediumCount = @($Collapsed | Where-Object { $_.blast_radius -eq "medium" }).Count
$LowCount = @($Collapsed | Where-Object { $_.blast_radius -eq "low" }).Count

$MaxNode = $Collapsed | Select-Object -First 1
$MaxRiskNode = if($MaxNode){ [string]$MaxNode.name } else { "" }
$MaxRiskScore = if($MaxNode){ [int]$MaxNode.risk_score } else { 0 }

$TopologyRisk = "low"
if($HighCount -gt 0){ $TopologyRisk = "high" }
elseif($MediumCount -gt 0){ $TopologyRisk = "medium" }

$Out = [ordered]@{
  schema = "contract_registry.risk_topology.v1"
  generated_utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  target_repo = $ResolvedRepo
  topology_risk = $TopologyRisk
  max_risk_node = $MaxRiskNode
  max_risk_score = $MaxRiskScore
  high_risk_count = $HighCount
  medium_risk_count = $MediumCount
  low_risk_count = $LowCount
  node_count = @($Ranked).Count
  collapsed_node_count = @($Collapsed).Count
  collapsed_risk_nodes = $Collapsed
  risk_nodes = $Ranked
}

$Root = Join-Path $ProfileRoot "risk_topology"
New-Item -ItemType Directory -Force -Path $Root | Out-Null

$TopologyPath = Join-Path $Root "risk_topology.json"
Write-Utf8NoBomLf -Path $TopologyPath -Text ($Out | ConvertTo-Json -Depth 30)

$Report = @()
$Report += "# Contract Registry Risk Topology"
$Report += ""
$Report += "Repo: $RepoName"
$Report += "Generated UTC: $($Out.generated_utc)"
$Report += ""
$Report += "## Summary"
$Report += "- Topology risk: $TopologyRisk"
$Report += "- Max risk node: $MaxRiskNode"
$Report += "- Max risk score: $MaxRiskScore"
$Report += "- High risk count: $HighCount"
$Report += "- Medium risk count: $MediumCount"
$Report += "- Low risk count: $LowCount"
$Report += ""
$Report += "## Highest Risk Nodes"
foreach($n in @($Collapsed | Select-Object -First 10)){
  $Report += "- $($n.blast_radius.ToUpperInvariant()) $($n.risk_score) $($n.name) [$(@($n.categories) -join ', ')]"
}

$ReportPath = Join-Path $Root "risk_topology_report.md"
Write-Utf8NoBomLf -Path $ReportPath -Text ($Report -join "`n")

$Receipt = [ordered]@{
  schema = "contract_registry.risk_topology_receipt.v1"
  utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  risk_topology = $TopologyPath
  report = $ReportPath
  node_count = @($Ranked).Count
  collapsed_node_count = @($Collapsed).Count
  max_risk_node = $MaxRiskNode
  max_risk_score = $MaxRiskScore
  topology_risk = $TopologyRisk
}

$ReceiptPath = Join-Path $Root "risk_topology_receipt.json"
Write-Utf8NoBomLf -Path $ReceiptPath -Text ($Receipt | ConvertTo-Json -Depth 20)

Write-Host "CR_RISK_TOPOLOGY_OK" -ForegroundColor Green
Write-Host ("RISK_TOPOLOGY: " + $TopologyPath)
Write-Host ("REPORT: " + $ReportPath)
Write-Host ("RECEIPT: " + $ReceiptPath)
Write-Host ("TOPOLOGY_RISK: " + $TopologyRisk)
Write-Host ("MAX_RISK_NODE: " + $MaxRiskNode)
Write-Host ("MAX_RISK_SCORE: " + $MaxRiskScore)

foreach($n in @($Collapsed | Select-Object -First 8)){
  Write-Host ("RISK_NODE: " + $n.blast_radius.ToUpperInvariant() + " " + $n.risk_score + " " + $n.name)
}
