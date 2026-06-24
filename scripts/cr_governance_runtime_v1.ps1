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

function New-Decision {
  param(
    [string]$Scope,
    [string]$Decision,
    [string]$Reason
  )

  return [pscustomobject]@{
    scope = $Scope
    decision = $Decision
    reason = $Reason
  }
}

if(-not (Test-Path -LiteralPath $TargetRepo -PathType Container)){
  throw "TARGET_REPO_NOT_FOUND: $TargetRepo"
}

$ResolvedRepo = (Resolve-Path -LiteralPath $TargetRepo).Path
$RepoName = Split-Path -Leaf $ResolvedRepo
$ProfileRoot = Join-Path $ResolvedRepo ("runtime\shadow_profiles\" + $RepoName)

$TrustRegistry = Read-JsonSafe -Path (Join-Path $ProfileRoot "trust_registry\trust_registry.json")

$ClearanceRoot = Join-Path $ProfileRoot "conditional_clearance"
$LatestClearance = $null
$LatestClearancePath = ""

if(Test-Path -LiteralPath $ClearanceRoot -PathType Container){
  $LatestClearanceFile = Get-ChildItem -LiteralPath $ClearanceRoot -Filter "*.conditional_clearance.json" -File |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1

  if($LatestClearanceFile){
    $LatestClearancePath = $LatestClearanceFile.FullName
    $LatestClearance = Read-JsonSafe -Path $LatestClearancePath
  }
}

if($null -eq $TrustRegistry){ throw "TRUST_REGISTRY_NOT_FOUND_RUN_TRUST_REGISTRY_FIRST" }
if($null -eq $LatestClearance){ throw "CONDITIONAL_CLEARANCE_NOT_FOUND_RUN_CLEARANCE_FIRST" }

$RegistryState = [string](Get-Prop -Obj $TrustRegistry -Name "registry_state" -Default "unknown")
$ClearanceLevel = [string](Get-Prop -Obj $LatestClearance -Name "clearance" -Default "untrusted")
$PolicyDecision = [string](Get-Prop -Obj $LatestClearance -Name "policy_decision" -Default "untrusted")
$AllowedScopes = @(Get-Prop -Obj $LatestClearance -Name "allowed_scopes" -Default @())
$BlockedScopes = @(Get-Prop -Obj $LatestClearance -Name "blocked_scopes" -Default @())
$RequiredApprovals = @(Get-Prop -Obj $LatestClearance -Name "required_approvals" -Default @())

$CandidateScopes = @(
  "read",
  "policy_read",
  "evidence_submit",
  "runtime",
  "runtime_limited",
  "governance_read",
  "governance_write",
  "policy_modify",
  "authority_promote",
  "production_deploy",
  "secret_rotation",
  "constitutional_action"
)

$Decisions = @()

foreach($Scope in $CandidateScopes){
  if(@($BlockedScopes) -contains $Scope){
    $Decisions += New-Decision -Scope $Scope -Decision "deny" -Reason ("Blocked by clearance level: " + $ClearanceLevel)
    continue
  }

  if(@($AllowedScopes) -contains $Scope){
    if(@($RequiredApprovals).Count -gt 0 -and ($Scope -eq "runtime_limited" -or $Scope -eq "evidence_submit")){
      $Decisions += New-Decision -Scope $Scope -Decision "conditional_allow" -Reason ("Allowed with approvals: " + (@($RequiredApprovals) -join ", "))
    } else {
      $Decisions += New-Decision -Scope $Scope -Decision "allow" -Reason ("Allowed by clearance level: " + $ClearanceLevel)
    }
    continue
  }

  if($PolicyDecision -eq "allow"){
    $Decisions += New-Decision -Scope $Scope -Decision "allow" -Reason "Policy evaluator allowed full trust."
  } elseif($PolicyDecision -eq "conditional"){
    $Decisions += New-Decision -Scope $Scope -Decision "deny" -Reason "Conditional clearance does not include this scope."
  } else {
    $Decisions += New-Decision -Scope $Scope -Decision "deny" -Reason ("Policy decision is " + $PolicyDecision)
  }
}

$RuntimeMode = "blocked"
if(@($Decisions | Where-Object { $_.scope -eq "runtime_limited" -and ($_.decision -eq "allow" -or $_.decision -eq "conditional_allow") }).Count -gt 0){
  $RuntimeMode = "limited"
}
if(@($Decisions | Where-Object { $_.scope -eq "runtime" -and $_.decision -eq "allow" }).Count -gt 0){
  $RuntimeMode = "full"
}

$GovernanceMode = "blocked"
if(@($Decisions | Where-Object { $_.scope -eq "governance_read" -and $_.decision -eq "allow" }).Count -gt 0){
  $GovernanceMode = "read_only"
}
if(@($Decisions | Where-Object { $_.scope -eq "governance_write" -and $_.decision -eq "allow" }).Count -gt 0){
  $GovernanceMode = "write"
}

$Out = [ordered]@{
  schema = "contract_registry.governance_runtime.v1"
  generated_utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  target_repo = $ResolvedRepo
  registry_state = $RegistryState
  clearance_level = $ClearanceLevel
  policy_decision = $PolicyDecision
  runtime_mode = $RuntimeMode
  governance_mode = $GovernanceMode
  required_approvals = @($RequiredApprovals)
  decision_count = @($Decisions).Count
  decisions = @($Decisions)
}

$Root = Join-Path $ProfileRoot "governance_runtime"
New-Item -ItemType Directory -Force -Path $Root | Out-Null

$RuntimePath = Join-Path $Root "governance_runtime.json"
Write-Utf8NoBomLf -Path $RuntimePath -Text ($Out | ConvertTo-Json -Depth 40)

$Report = @()
$Report += "# Contract Registry Governance Runtime"
$Report += ""
$Report += "Repo: $RepoName"
$Report += "Generated UTC: $($Out.generated_utc)"
$Report += ""
$Report += "## Runtime"
$Report += "- Registry state: $RegistryState"
$Report += "- Clearance level: $ClearanceLevel"
$Report += "- Policy decision: $PolicyDecision"
$Report += "- Runtime mode: $RuntimeMode"
$Report += "- Governance mode: $GovernanceMode"
$Report += ""
$Report += "## Scope Decisions"
foreach($d in @($Decisions)){
  $Report += "- $($d.scope): $($d.decision) - $($d.reason)"
}

$ReportPath = Join-Path $Root "governance_runtime_report.md"
Write-Utf8NoBomLf -Path $ReportPath -Text ($Report -join "`n")

$Receipt = [ordered]@{
  schema = "contract_registry.governance_runtime_receipt.v1"
  utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  runtime = $RuntimePath
  report = $ReportPath
  registry_state = $RegistryState
  clearance_level = $ClearanceLevel
  policy_decision = $PolicyDecision
  runtime_mode = $RuntimeMode
  governance_mode = $GovernanceMode
  decision_count = @($Decisions).Count
}

$ReceiptPath = Join-Path $Root "governance_runtime_receipt.json"
Write-Utf8NoBomLf -Path $ReceiptPath -Text ($Receipt | ConvertTo-Json -Depth 20)

Write-Host "CR_GOVERNANCE_RUNTIME_OK" -ForegroundColor Green
Write-Host ("GOVERNANCE_RUNTIME: " + $RuntimePath)
Write-Host ("REPORT: " + $ReportPath)
Write-Host ("RECEIPT: " + $ReceiptPath)
Write-Host ("REGISTRY_STATE: " + $RegistryState)
Write-Host ("CLEARANCE_LEVEL: " + $ClearanceLevel)
Write-Host ("POLICY_DECISION: " + $PolicyDecision)
Write-Host ("RUNTIME_MODE: " + $RuntimeMode)
Write-Host ("GOVERNANCE_MODE: " + $GovernanceMode)

foreach($d in @($Decisions)){
  Write-Host ("SCOPE_DECISION: " + $d.scope + " " + $d.decision)
}