param(
  [Parameter(Mandatory=$true)]
  [string]$TargetRepo,

  [Parameter(Mandatory=$false)]
  [string]$DecisionPath = ""
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
  if([string]::IsNullOrWhiteSpace($Path)){ return $null }
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ return $null }
  try { return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json) } catch { return $null }
}

function Get-Prop {
  param($Obj,[string]$Name,$Default=$null)
  if($null -eq $Obj){ return $Default }
  $Prop = $Obj.PSObject.Properties[$Name]
  if($null -eq $Prop){ return $Default }
  return $Prop.Value
}

function Add-Scope {
  param([array]$Items,[string]$Value)
  if([string]::IsNullOrWhiteSpace($Value)){ return @($Items) }
  return @($Items + $Value | Sort-Object -Unique)
}

function Add-Condition {
  param(
    [System.Collections.Generic.List[object]]$List,
    [string]$Code,
    [string]$Severity,
    [string]$Message
  )

  $List.Add([pscustomobject]@{
    code = $Code
    severity = $Severity
    message = $Message
  }) | Out-Null
}

if(-not (Test-Path -LiteralPath $TargetRepo -PathType Container)){
  throw "TARGET_REPO_NOT_FOUND: $TargetRepo"
}

$ResolvedRepo = (Resolve-Path -LiteralPath $TargetRepo).Path
$RepoName = Split-Path -Leaf $ResolvedRepo
$ProfileRoot = Join-Path $ResolvedRepo ("runtime\shadow_profiles\" + $RepoName)

if([string]::IsNullOrWhiteSpace($DecisionPath)){
  $DecisionRoot = Join-Path $ProfileRoot "policy_decisions"
  if(-not (Test-Path -LiteralPath $DecisionRoot -PathType Container)){
    throw "POLICY_DECISION_ROOT_NOT_FOUND_RUN_EVALUATOR_FIRST"
  }

  $Latest = Get-ChildItem -LiteralPath $DecisionRoot -Filter "*.policy_decision.json" -File |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1

  if($null -eq $Latest){ throw "POLICY_DECISION_NOT_FOUND_RUN_EVALUATOR_FIRST" }
  $DecisionPath = $Latest.FullName
}

$Decision = Read-JsonSafe -Path $DecisionPath
if($null -eq $Decision){ throw "POLICY_DECISION_INVALID_JSON: $DecisionPath" }

$Risk = Read-JsonSafe -Path (Join-Path $ProfileRoot "risk_topology\risk_topology.json")
$Authority = Read-JsonSafe -Path (Join-Path $ProfileRoot "dependency_authority\dependency_authority.json")
$Contract = Read-JsonSafe -Path (Join-Path $ProfileRoot "policy_contract\policy_contract.json")

$FinalDecision = [string](Get-Prop -Obj $Decision -Name "final_decision" -Default "untrusted")
$Findings = @(Get-Prop -Obj $Decision -Name "findings" -Default @())

$TopologyRisk = if($Risk){ [string](Get-Prop -Obj $Risk -Name "topology_risk" -Default "unknown") } else { "unknown" }
$MaxRiskNode = if($Risk){ [string](Get-Prop -Obj $Risk -Name "max_risk_node" -Default "") } else { "" }
$AuthorityScore = if($Authority){ [int](Get-Prop -Obj $Authority -Name "authority_score" -Default 0) } else { 0 }
$DependencyConcentration = if($Authority){ [string](Get-Prop -Obj $Authority -Name "dependency_concentration" -Default "unknown") } else { "unknown" }

$AllowedScopes = @()
$BlockedScopes = @()
$RequiredApprovals = @()
$Conditions = [System.Collections.Generic.List[object]]::new()

if($FinalDecision -eq "allow"){
  $AllowedScopes = Add-Scope $AllowedScopes "read"
  $AllowedScopes = Add-Scope $AllowedScopes "runtime"
  $AllowedScopes = Add-Scope $AllowedScopes "policy_read"
  $AllowedScopes = Add-Scope $AllowedScopes "governance_read"
}

elseif($FinalDecision -eq "conditional"){
  $AllowedScopes = Add-Scope $AllowedScopes "read"
  $AllowedScopes = Add-Scope $AllowedScopes "policy_read"
  $AllowedScopes = Add-Scope $AllowedScopes "evidence_submit"
  $AllowedScopes = Add-Scope $AllowedScopes "runtime_limited"

  $BlockedScopes = Add-Scope $BlockedScopes "governance_write"
  $BlockedScopes = Add-Scope $BlockedScopes "policy_modify"
  $BlockedScopes = Add-Scope $BlockedScopes "authority_promote"
  $BlockedScopes = Add-Scope $BlockedScopes "production_deploy"
  $BlockedScopes = Add-Scope $BlockedScopes "secret_rotation"
  $BlockedScopes = Add-Scope $BlockedScopes "constitutional_action"

  $RequiredApprovals = Add-Scope $RequiredApprovals "human_governance_review"
  $RequiredApprovals = Add-Scope $RequiredApprovals "authority_owner_review"

  foreach($f in @($Findings)){
    $Condition = [string](Get-Prop -Obj $f -Name "condition" -Default "")
    if($Condition -eq "topology_risk_high"){
      Add-Condition -List $Conditions -Code "HIGH_TOPOLOGY_RISK_LIMITS_RUNTIME" -Severity "HIGH" -Message ("Runtime is limited because topology risk is high; max risk node: " + $MaxRiskNode)
    }
    if($Condition -eq "authority_score_high"){
      Add-Condition -List $Conditions -Code "HIGH_AUTHORITY_SCORE_BLOCKS_PROMOTION" -Severity "HIGH" -Message ("Authority promotion blocked because authority score is " + $AuthorityScore)
    }
    if($Condition -eq "dependency_concentration_medium" -or $Condition -eq "dependency_concentration_high"){
      Add-Condition -List $Conditions -Code "DEPENDENCY_CONCENTRATION_REQUIRES_REVIEW" -Severity "MEDIUM" -Message ("Dependency concentration requires review: " + $DependencyConcentration)
    }
  }
}

elseif($FinalDecision -eq "deny"){
  $BlockedScopes = Add-Scope $BlockedScopes "read"
  $BlockedScopes = Add-Scope $BlockedScopes "runtime"
  $BlockedScopes = Add-Scope $BlockedScopes "policy_read"
  $BlockedScopes = Add-Scope $BlockedScopes "governance_read"
  $BlockedScopes = Add-Scope $BlockedScopes "governance_write"
  $BlockedScopes = Add-Scope $BlockedScopes "policy_modify"
  $BlockedScopes = Add-Scope $BlockedScopes "authority_promote"
  $BlockedScopes = Add-Scope $BlockedScopes "production_deploy"
  $BlockedScopes = Add-Scope $BlockedScopes "constitutional_action"

  Add-Condition -List $Conditions -Code "DENY_BLOCKS_ALL_OPERATIONAL_SCOPES" -Severity "HIGH" -Message "Policy evaluator returned deny."
}

else {
  $BlockedScopes = Add-Scope $BlockedScopes "read"
  $BlockedScopes = Add-Scope $BlockedScopes "runtime"
  $BlockedScopes = Add-Scope $BlockedScopes "policy_read"
  $BlockedScopes = Add-Scope $BlockedScopes "governance_read"
  $BlockedScopes = Add-Scope $BlockedScopes "governance_write"
  $BlockedScopes = Add-Scope $BlockedScopes "policy_modify"
  $BlockedScopes = Add-Scope $BlockedScopes "authority_promote"
  $BlockedScopes = Add-Scope $BlockedScopes "production_deploy"
  $BlockedScopes = Add-Scope $BlockedScopes "constitutional_action"

  Add-Condition -List $Conditions -Code "UNTRUSTED_BLOCKS_ALL_SCOPES" -Severity "HIGH" -Message "Policy evaluator returned untrusted."
}

$Clearance = "none"
if($FinalDecision -eq "allow"){ $Clearance = "allow_full" }
elseif($FinalDecision -eq "conditional"){ $Clearance = "conditional_limited_runtime" }
elseif($FinalDecision -eq "deny"){ $Clearance = "deny" }
else { $Clearance = "untrusted" }

$Out = [ordered]@{
  schema = "contract_registry.conditional_clearance.v1"
  generated_utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  target_repo = $ResolvedRepo
  decision_path = (Resolve-Path -LiteralPath $DecisionPath).Path
  contract_id = [string](Get-Prop -Obj $Decision -Name "contract_id" -Default "")
  policy_decision = $FinalDecision
  clearance = $Clearance
  topology_risk = $TopologyRisk
  max_risk_node = $MaxRiskNode
  authority_score = $AuthorityScore
  dependency_concentration = $DependencyConcentration
  allowed_scopes = @($AllowedScopes | Sort-Object -Unique)
  blocked_scopes = @($BlockedScopes | Sort-Object -Unique)
  required_approvals = @($RequiredApprovals | Sort-Object -Unique)
  condition_count = @($Conditions).Count
  conditions = @($Conditions)
}

$Root = Join-Path $ProfileRoot "conditional_clearance"
New-Item -ItemType Directory -Force -Path $Root | Out-Null

$Stamp = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss")
$OutPath = Join-Path $Root ($Stamp + ".conditional_clearance.json")
Write-Utf8NoBomLf -Path $OutPath -Text ($Out | ConvertTo-Json -Depth 30)

$Report = @()
$Report += "# Contract Registry Conditional Clearance"
$Report += ""
$Report += "Repo: $RepoName"
$Report += "Generated UTC: $($Out.generated_utc)"
$Report += ""
$Report += "## Clearance"
$Report += "- Policy decision: $FinalDecision"
$Report += "- Clearance: $Clearance"
$Report += "- Topology risk: $TopologyRisk"
$Report += "- Max risk node: $MaxRiskNode"
$Report += "- Authority score: $AuthorityScore"
$Report += "- Dependency concentration: $DependencyConcentration"
$Report += ""
$Report += "## Allowed Scopes"
foreach($x in @($Out.allowed_scopes)){ $Report += "- $x" }
if(@($Out.allowed_scopes).Count -eq 0){ $Report += "- None" }
$Report += ""
$Report += "## Blocked Scopes"
foreach($x in @($Out.blocked_scopes)){ $Report += "- $x" }
if(@($Out.blocked_scopes).Count -eq 0){ $Report += "- None" }
$Report += ""
$Report += "## Required Approvals"
foreach($x in @($Out.required_approvals)){ $Report += "- $x" }
if(@($Out.required_approvals).Count -eq 0){ $Report += "- None" }
$Report += ""
$Report += "## Conditions"
foreach($c in @($Out.conditions)){ $Report += "- $($c.severity) $($c.code): $($c.message)" }
if(@($Out.conditions).Count -eq 0){ $Report += "- None" }

$ReportPath = Join-Path $Root ($Stamp + ".conditional_clearance_report.md")
Write-Utf8NoBomLf -Path $ReportPath -Text ($Report -join "`n")

$Receipt = [ordered]@{
  schema = "contract_registry.conditional_clearance_receipt.v1"
  utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  contract_id = [string](Get-Prop -Obj $Decision -Name "contract_id" -Default "")
  clearance = $OutPath
  report = $ReportPath
  policy_decision = $FinalDecision
  clearance_level = $Clearance
  allowed_scope_count = @($Out.allowed_scopes).Count
  blocked_scope_count = @($Out.blocked_scopes).Count
  required_approval_count = @($Out.required_approvals).Count
}

$ReceiptPath = Join-Path $Root ($Stamp + ".conditional_clearance_receipt.json")
Write-Utf8NoBomLf -Path $ReceiptPath -Text ($Receipt | ConvertTo-Json -Depth 20)

Write-Host "CR_CONDITIONAL_CLEARANCE_OK" -ForegroundColor Green
Write-Host ("CLEARANCE: " + $OutPath)
Write-Host ("REPORT: " + $ReportPath)
Write-Host ("RECEIPT: " + $ReceiptPath)
Write-Host ("POLICY_DECISION: " + $FinalDecision)
Write-Host ("CLEARANCE_LEVEL: " + $Clearance)
Write-Host ("ALLOWED_SCOPES: " + (@($Out.allowed_scopes) -join ", "))
Write-Host ("BLOCKED_SCOPES: " + (@($Out.blocked_scopes) -join ", "))
Write-Host ("REQUIRED_APPROVALS: " + (@($Out.required_approvals) -join ", "))

foreach($c in @($Out.conditions | Select-Object -First 8)){
  Write-Host ("CLEARANCE_CONDITION: " + $c.severity + " " + $c.code)
}