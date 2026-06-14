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

function Add-Rule {
  param(
    [System.Collections.Generic.List[object]]$List,
    [string]$Condition,
    [string]$Decision,
    [string]$Severity,
    [string]$Reason
  )

  $List.Add([pscustomobject]@{
    condition = $Condition
    decision = $Decision
    severity = $Severity
    reason = $Reason
  }) | Out-Null
}

if(-not (Test-Path -LiteralPath $TargetRepo -PathType Container)){
  throw "TARGET_REPO_NOT_FOUND: $TargetRepo"
}

$ResolvedRepo = (Resolve-Path -LiteralPath $TargetRepo).Path
$RepoName = Split-Path -Leaf $ResolvedRepo
$ProfileRoot = Join-Path $ResolvedRepo ("runtime\shadow_profiles\" + $RepoName)

$PolicyAuthority = Read-JsonSafe -Path (Join-Path $ProfileRoot "policy_authority\policy_authority.json")
$RemoteAttestation = Read-JsonSafe -Path (Join-Path $ProfileRoot "remote_attestation_policy\remote_attestation_policy.json")
$Risk = Read-JsonSafe -Path (Join-Path $ProfileRoot "risk_topology\risk_topology.json")
$Authority = Read-JsonSafe -Path (Join-Path $ProfileRoot "dependency_authority\dependency_authority.json")
$Identity = Read-JsonSafe -Path (Join-Path $ProfileRoot "identity\repo_identity.json")

if($null -eq $PolicyAuthority){ throw "POLICY_AUTHORITY_NOT_FOUND_RUN_POLICY_AUTHORITY_FIRST" }
if($null -eq $RemoteAttestation){ throw "REMOTE_ATTESTATION_POLICY_NOT_FOUND_RUN_REMOTE_ATTESTATION_FIRST" }
if($null -eq $Risk){ throw "RISK_TOPOLOGY_NOT_FOUND_RUN_PIPELINE_FIRST" }
if($null -eq $Authority){ throw "DEPENDENCY_AUTHORITY_NOT_FOUND_RUN_PIPELINE_FIRST" }

$RequiredPolicies = @(
  "constitutional_policy",
  "resource_policy",
  "runtime_policy",
  "machine_policy",
  "remote_attestation_policy",
  "dependency_authority_policy"
)

$RequiredAttestations = @(
  "machine_identity",
  "signed_policy_set",
  "policy_receipt_chain",
  "remote_verifier_decision",
  "dependency_authority_binding"
)

$DetectedPolicyLayers = @(Get-Prop -Obj $PolicyAuthority -Name "detected_policy_layers" -Default @())
$MissingPolicyLayers = @(Get-Prop -Obj $PolicyAuthority -Name "missing_policy_layers" -Default @())
$RemoteVerificationMode = [string](Get-Prop -Obj $RemoteAttestation -Name "remote_verification_mode" -Default "not_ready")
$TopologyRisk = [string](Get-Prop -Obj $Risk -Name "topology_risk" -Default "unknown")
$MaxRiskNode = [string](Get-Prop -Obj $Risk -Name "max_risk_node" -Default "")
$MaxRiskScore = [int](Get-Prop -Obj $Risk -Name "max_risk_score" -Default 0)
$AuthorityScore = [int](Get-Prop -Obj $Authority -Name "authority_score" -Default 0)
$DependencyConcentration = [string](Get-Prop -Obj $Authority -Name "dependency_concentration" -Default "unknown")
$Archetype = if($Identity){ [string](Get-Prop -Obj $Identity -Name "archetype" -Default "unknown") } else { "unknown" }
$SoftwareClass = if($Identity){ [string](Get-Prop -Obj $Identity -Name "software_class" -Default "unknown") } else { "unknown" }

$Rules = [System.Collections.Generic.List[object]]::new()

Add-Rule -List $Rules -Condition "machine_identity_missing" -Decision "deny" -Severity "HIGH" -Reason "Remote machines must present stable machine identity."
Add-Rule -List $Rules -Condition "signed_policy_set_missing" -Decision "deny" -Severity "HIGH" -Reason "Remote machines must present signed policy set evidence."
Add-Rule -List $Rules -Condition "policy_receipt_chain_missing" -Decision "deny" -Severity "HIGH" -Reason "Remote compliance requires receipt-chain proof."
Add-Rule -List $Rules -Condition "remote_verifier_decision_missing" -Decision "deny" -Severity "HIGH" -Reason "Remote trust requires deterministic verifier decision."
Add-Rule -List $Rules -Condition "dependency_authority_binding_missing" -Decision "deny" -Severity "HIGH" -Reason "Primary dependency authorities must be bound to policy evidence."

if($TopologyRisk -eq "high"){
  Add-Rule -List $Rules -Condition "topology_risk_high" -Decision "conditional" -Severity "HIGH" -Reason ("High topology risk requires elevated review; max_risk_node=" + $MaxRiskNode)
}

if($AuthorityScore -ge 90){
  Add-Rule -List $Rules -Condition "authority_score_high" -Decision "conditional" -Severity "HIGH" -Reason ("High authority score requires authority attestation; authority_score=" + $AuthorityScore)
}

if($DependencyConcentration -eq "high"){
  Add-Rule -List $Rules -Condition "dependency_concentration_high" -Decision "conditional" -Severity "MEDIUM" -Reason "High dependency concentration requires concentration policy."
}
elseif($DependencyConcentration -eq "medium"){
  Add-Rule -List $Rules -Condition "dependency_concentration_medium" -Decision "conditional" -Severity "MEDIUM" -Reason "Medium dependency concentration requires documented authority bindings."
}

foreach($Layer in @($RequiredPolicies)){
  if(-not (@($DetectedPolicyLayers) -contains $Layer)){
    Add-Rule -List $Rules -Condition ("policy_layer_missing_" + $Layer) -Decision "deny" -Severity "HIGH" -Reason ("Required policy layer missing: " + $Layer)
  }
}

$ContractIdSeed = ($RepoName + "|" + $Archetype + "|" + $SoftwareClass + "|" + $RemoteVerificationMode + "|" + $AuthorityScore)
$Sha = [Security.Cryptography.SHA256]::Create()
$Bytes = [Text.Encoding]::UTF8.GetBytes($ContractIdSeed)
$Hash = ([BitConverter]::ToString($Sha.ComputeHash($Bytes))).Replace("-","").ToLowerInvariant()
$ContractId = "policy_contract_" + $Hash.Substring(0,16)

$DefaultDecision = "untrusted"
if($RemoteVerificationMode -eq "attestation_ready" -and @($MissingPolicyLayers).Count -eq 0){
  $DefaultDecision = "conditional"
}

$Out = [ordered]@{
  schema = "contract_registry.policy_contract.v1"
  generated_utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  target_repo = $ResolvedRepo
  contract_id = $ContractId
  archetype = $Archetype
  software_class = $SoftwareClass
  default_decision = $DefaultDecision
  remote_verification_mode = $RemoteVerificationMode
  required_policies = $RequiredPolicies
  required_attestations = $RequiredAttestations
  detected_policy_layers = @($DetectedPolicyLayers | Sort-Object -Unique)
  missing_policy_layers = @($MissingPolicyLayers | Sort-Object -Unique)
  topology_risk = $TopologyRisk
  max_risk_node = $MaxRiskNode
  max_risk_score = $MaxRiskScore
  authority_score = $AuthorityScore
  dependency_concentration = $DependencyConcentration
  evaluation_rule_count = @($Rules).Count
  evaluation_rules = @($Rules)
}

$Root = Join-Path $ProfileRoot "policy_contract"
New-Item -ItemType Directory -Force -Path $Root | Out-Null

$OutPath = Join-Path $Root "policy_contract.json"
Write-Utf8NoBomLf -Path $OutPath -Text ($Out | ConvertTo-Json -Depth 30)

$Report = @()
$Report += "# Contract Registry Policy Contract"
$Report += ""
$Report += "Repo: $RepoName"
$Report += "Generated UTC: $($Out.generated_utc)"
$Report += ""
$Report += "## Contract"
$Report += "- Contract ID: $ContractId"
$Report += "- Default decision: $DefaultDecision"
$Report += "- Remote verification mode: $RemoteVerificationMode"
$Report += "- Topology risk: $TopologyRisk"
$Report += "- Max risk node: $MaxRiskNode"
$Report += "- Authority score: $AuthorityScore"
$Report += "- Dependency concentration: $DependencyConcentration"
$Report += ""
$Report += "## Required Policies"
foreach($x in @($RequiredPolicies)){ $Report += "- $x" }
$Report += ""
$Report += "## Required Attestations"
foreach($x in @($RequiredAttestations)){ $Report += "- $x" }
$Report += ""
$Report += "## Evaluation Rules"
foreach($r in @($Rules)){
  $Report += "- $($r.decision.ToUpperInvariant()) $($r.condition): $($r.reason)"
}

$ReportPath = Join-Path $Root "policy_contract_report.md"
Write-Utf8NoBomLf -Path $ReportPath -Text ($Report -join "`n")

$Receipt = [ordered]@{
  schema = "contract_registry.policy_contract_receipt.v1"
  utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  contract_id = $ContractId
  policy_contract = $OutPath
  report = $ReportPath
  default_decision = $DefaultDecision
  required_policy_count = @($RequiredPolicies).Count
  required_attestation_count = @($RequiredAttestations).Count
  evaluation_rule_count = @($Rules).Count
}

$ReceiptPath = Join-Path $Root "policy_contract_receipt.json"
Write-Utf8NoBomLf -Path $ReceiptPath -Text ($Receipt | ConvertTo-Json -Depth 20)

Write-Host "CR_POLICY_CONTRACT_OK" -ForegroundColor Green
Write-Host ("POLICY_CONTRACT: " + $OutPath)
Write-Host ("REPORT: " + $ReportPath)
Write-Host ("RECEIPT: " + $ReceiptPath)
Write-Host ("CONTRACT_ID: " + $ContractId)
Write-Host ("DEFAULT_DECISION: " + $DefaultDecision)
Write-Host ("EVALUATION_RULE_COUNT: " + @($Rules).Count)

foreach($r in @($Rules | Select-Object -First 8)){
  Write-Host ("POLICY_RULE: " + $r.decision.ToUpperInvariant() + " " + $r.condition)
}