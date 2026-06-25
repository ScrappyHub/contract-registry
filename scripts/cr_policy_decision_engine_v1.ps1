param(
  [Parameter(Mandatory=$true)]
  [string]$TargetRepo,

  [Parameter(Mandatory=$false)]
  [string]$Operation = "status",

  [Parameter(Mandatory=$false)]
  [string]$Requester = "local-user",

  [Parameter(Mandatory=$false)]
  [string]$MachineId = "local-dev-machine"
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

function New-Finding {
  param([string]$Layer,[string]$Decision,[string]$Severity,[string]$Code,[string]$Reason)
  return [pscustomobject]@{
    layer = $Layer
    decision = $Decision
    severity = $Severity
    code = $Code
    reason = $Reason
  }
}

if(-not (Test-Path -LiteralPath $TargetRepo -PathType Container)){
  throw "TARGET_REPO_NOT_FOUND: $TargetRepo"
}

$ResolvedRepo = (Resolve-Path -LiteralPath $TargetRepo).Path
$RepoName = Split-Path -Leaf $ResolvedRepo
$ProfileRoot = Join-Path $ResolvedRepo ("runtime\shadow_profiles\" + $RepoName)

$Runtime = Read-JsonSafe -Path (Join-Path $ProfileRoot "governance_runtime\governance_runtime.json")
$Trust = Read-JsonSafe -Path (Join-Path $ProfileRoot "trust_registry\trust_registry.json")
$Bundle = Read-JsonSafe -Path (Join-Path $ProfileRoot "policy_bundle\policy_bundle.json")
$Risk = Read-JsonSafe -Path (Join-Path $ProfileRoot "risk_topology\risk_topology.json")

if($null -eq $Runtime){ throw "GOVERNANCE_RUNTIME_NOT_FOUND_RUN_VERIFIED_RUNTIME_FIRST" }
if($null -eq $Trust){ throw "TRUST_REGISTRY_NOT_FOUND_RUN_VERIFIED_RUNTIME_FIRST" }
if($null -eq $Bundle){ throw "POLICY_BUNDLE_NOT_FOUND_RUN_VERIFIED_RUNTIME_FIRST" }

$ScopeMap = @{
  "status" = "read"
  "read" = "read"
  "policy-read" = "policy_read"
  "submit-evidence" = "evidence_submit"
  "runtime" = "runtime"
  "runtime-limited" = "runtime_limited"
  "governance-read" = "governance_read"
  "governance-write" = "governance_write"
  "policy-modify" = "policy_modify"
  "authority-promote" = "authority_promote"
  "deploy" = "production_deploy"
  "production-deploy" = "production_deploy"
  "secret-rotation" = "secret_rotation"
  "constitutional-action" = "constitutional_action"
}

$OpKey = $Operation.ToLowerInvariant()
if(-not $ScopeMap.ContainsKey($OpKey)){
  throw ("UNKNOWN_OPERATION: " + $Operation)
}

$RequestedScope = [string]$ScopeMap[$OpKey]
$Findings = @()

$RegistryState = [string](Get-Prop -Obj $Trust -Name "registry_state" -Default "unknown")
$RuntimeMode = [string](Get-Prop -Obj $Runtime -Name "runtime_mode" -Default "blocked")
$GovernanceMode = [string](Get-Prop -Obj $Runtime -Name "governance_mode" -Default "blocked")
$PolicyDecision = [string](Get-Prop -Obj $Runtime -Name "policy_decision" -Default "untrusted")
$ClearanceLevel = [string](Get-Prop -Obj $Runtime -Name "clearance_level" -Default "untrusted")
$BundleId = [string](Get-Prop -Obj $Bundle -Name "bundle_id" -Default "")
$BundleHash = [string](Get-Prop -Obj $Bundle -Name "bundle_hash" -Default "")
$TopologyRisk = if($Risk){ [string](Get-Prop -Obj $Risk -Name "topology_risk" -Default "unknown") } else { "unknown" }

$ScopeDecision = $null
foreach($d in @(Get-Prop -Obj $Runtime -Name "decisions" -Default @())){
  if([string](Get-Prop -Obj $d -Name "scope" -Default "") -eq $RequestedScope){
    $ScopeDecision = $d
    break
  }
}

if($null -eq $ScopeDecision){
  $Findings += New-Finding -Layer "governance_runtime" -Decision "deny" -Severity "HIGH" -Code "SCOPE_NOT_DECLARED" -Reason ("Scope not declared by governance runtime: " + $RequestedScope)
} else {
  $DecisionValue = [string](Get-Prop -Obj $ScopeDecision -Name "decision" -Default "deny")
  $Reason = [string](Get-Prop -Obj $ScopeDecision -Name "reason" -Default "")

  if($DecisionValue -eq "allow"){
    $Findings += New-Finding -Layer "governance_runtime" -Decision "allow" -Severity "INFO" -Code "SCOPE_ALLOWED" -Reason $Reason
  } elseif($DecisionValue -eq "conditional_allow"){
    $Findings += New-Finding -Layer "governance_runtime" -Decision "conditional" -Severity "MEDIUM" -Code "SCOPE_CONDITIONAL_ALLOW" -Reason $Reason
  } else {
    $Findings += New-Finding -Layer "governance_runtime" -Decision "deny" -Severity "HIGH" -Code "SCOPE_DENIED" -Reason $Reason
  }
}

if($RegistryState -eq "restricted"){
  $Findings += New-Finding -Layer "trust_registry" -Decision "deny" -Severity "HIGH" -Code "TRUST_REGISTRY_RESTRICTED" -Reason "Trust registry is restricted."
} elseif($RegistryState -eq "trusted_with_conditions"){
  $Findings += New-Finding -Layer "trust_registry" -Decision "conditional" -Severity "MEDIUM" -Code "TRUST_REGISTRY_CONDITIONAL" -Reason "Trust registry is trusted with conditions."
}

if($TopologyRisk -eq "high" -and ($RequestedScope -in @("production_deploy","policy_modify","authority_promote","secret_rotation","constitutional_action"))){
  $Findings += New-Finding -Layer "risk_topology" -Decision "deny" -Severity "HIGH" -Code "HIGH_RISK_BLOCKS_SENSITIVE_SCOPE" -Reason ("High topology risk blocks sensitive scope: " + $RequestedScope)
}

$FinalDecision = "allow"
if(@($Findings | Where-Object { $_.decision -eq "deny" }).Count -gt 0){
  $FinalDecision = "deny"
} elseif(@($Findings | Where-Object { $_.decision -eq "conditional" }).Count -gt 0){
  $FinalDecision = "conditional"
}

$SessionSeed = $RepoName + "|" + $Operation + "|" + $Requester + "|" + $MachineId + "|" + [DateTime]::UtcNow.ToString("o")
$Sha = [Security.Cryptography.SHA256]::Create()
$SessionHash = ([BitConverter]::ToString($Sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($SessionSeed)))).Replace("-","").ToLowerInvariant()
$SessionId = "policy_session_" + $SessionHash.Substring(0,16)

$Out = [ordered]@{
  schema = "contract_registry.policy_decision_engine.v1"
  generated_utc = [DateTime]::UtcNow.ToString("o")
  session_id = $SessionId
  repo_name = $RepoName
  target_repo = $ResolvedRepo
  requester = $Requester
  machine_id = $MachineId
  operation = $Operation
  requested_scope = $RequestedScope
  final_decision = $FinalDecision
  registry_state = $RegistryState
  clearance_level = $ClearanceLevel
  policy_decision = $PolicyDecision
  runtime_mode = $RuntimeMode
  governance_mode = $GovernanceMode
  policy_bundle_id = $BundleId
  policy_bundle_hash = $BundleHash
  finding_count = @($Findings).Count
  findings = @($Findings)
}

$Root = Join-Path $ProfileRoot "policy_sessions"
New-Item -ItemType Directory -Force -Path $Root | Out-Null

$SessionPath = Join-Path $Root ($SessionId + ".policy_session.json")
Write-Utf8NoBomLf -Path $SessionPath -Text ($Out | ConvertTo-Json -Depth 40)

$Report = @()
$Report += "# Contract Registry Policy Decision Session"
$Report += ""
$Report += "Session: $SessionId"
$Report += "Repo: $RepoName"
$Report += "Operation: $Operation"
$Report += "Requested scope: $RequestedScope"
$Report += "Final decision: $FinalDecision"
$Report += ""
$Report += "## Findings"
foreach($f in @($Findings)){
  $Report += "- $($f.decision.ToUpperInvariant()) $($f.layer) $($f.code): $($f.reason)"
}

$ReportPath = Join-Path $Root ($SessionId + ".policy_session_report.md")
Write-Utf8NoBomLf -Path $ReportPath -Text ($Report -join "`n")

$Receipt = [ordered]@{
  schema = "contract_registry.policy_decision_engine_receipt.v1"
  utc = [DateTime]::UtcNow.ToString("o")
  session_id = $SessionId
  repo_name = $RepoName
  operation = $Operation
  requested_scope = $RequestedScope
  final_decision = $FinalDecision
  session = $SessionPath
  report = $ReportPath
  finding_count = @($Findings).Count
}

$ReceiptPath = Join-Path $Root ($SessionId + ".policy_session_receipt.json")
Write-Utf8NoBomLf -Path $ReceiptPath -Text ($Receipt | ConvertTo-Json -Depth 20)

Write-Host "CR_POLICY_DECISION_ENGINE_OK" -ForegroundColor Green
Write-Host ("SESSION: " + $SessionPath)
Write-Host ("REPORT: " + $ReportPath)
Write-Host ("RECEIPT: " + $ReceiptPath)
Write-Host ("SESSION_ID: " + $SessionId)
Write-Host ("OPERATION: " + $Operation)
Write-Host ("REQUESTED_SCOPE: " + $RequestedScope)
Write-Host ("FINAL_DECISION: " + $FinalDecision)

foreach($f in @($Findings)){
  Write-Host ("DECISION_FINDING: " + $f.decision.ToUpperInvariant() + " " + $f.layer + " " + $f.code)
}