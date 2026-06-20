param(
  [Parameter(Mandatory=$true)]
  [string]$TargetRepo,

  [Parameter(Mandatory=$false)]
  [string]$EvidencePath = "",

  [Parameter(Mandatory=$false)]
  [string]$VerificationPath = ""
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

function Add-Finding {
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

$ContractPath = Join-Path $ProfileRoot "policy_contract\policy_contract.json"
$Contract = Read-JsonSafe -Path $ContractPath

if($null -eq $Contract){ throw "POLICY_CONTRACT_NOT_FOUND_RUN_POLICY_CONTRACT_FIRST" }

$Evidence = $null
$Verification = $null

if(-not [string]::IsNullOrWhiteSpace($VerificationPath)){
  $Verification = Read-JsonSafe -Path $VerificationPath
  if($null -eq $Verification){ throw "VERIFICATION_NOT_FOUND_OR_INVALID_JSON: $VerificationPath" }
}

if(-not [string]::IsNullOrWhiteSpace($EvidencePath)){
  $Evidence = Read-JsonSafe -Path $EvidencePath
  if($null -eq $Evidence){ throw "EVIDENCE_NOT_FOUND_OR_INVALID_JSON: $EvidencePath" }
}

$Findings = [System.Collections.Generic.List[object]]::new()

$MachineIdentity = if($Evidence){ [string](Get-Prop -Obj $Evidence -Name "machine_identity" -Default "") } else { "" }
$SignedPolicySet = if($Evidence){ [bool](Get-Prop -Obj $Evidence -Name "signed_policy_set" -Default $false) } else { $false }
$PolicyReceiptChain = if($Evidence){ [bool](Get-Prop -Obj $Evidence -Name "policy_receipt_chain" -Default $false) } else { $false }
$RemoteVerifierDecision = if($Evidence){ [string](Get-Prop -Obj $Evidence -Name "remote_verifier_decision" -Default "") } else { "" }
$DependencyAuthorityBinding = if($Evidence){ [bool](Get-Prop -Obj $Evidence -Name "dependency_authority_binding" -Default $false) } else { $false }
$RemoteAttestationVerified = $false

if($Verification){
  $RemoteAttestationVerified = ([string](Get-Prop -Obj $Verification -Name "decision" -Default "") -eq "verified")
}

foreach($Rule in @(Get-Prop -Obj $Contract -Name "evaluation_rules" -Default @())){
  $Condition = [string](Get-Prop -Obj $Rule -Name "condition" -Default "")
  $RuleDecision = [string](Get-Prop -Obj $Rule -Name "decision" -Default "deny")
  $Severity = [string](Get-Prop -Obj $Rule -Name "severity" -Default "HIGH")
  $Reason = [string](Get-Prop -Obj $Rule -Name "reason" -Default "")

  $Triggered = $false

  switch($Condition){
    "machine_identity_missing" {
      if([string]::IsNullOrWhiteSpace($MachineIdentity)){ $Triggered = $true }
    }
    "signed_policy_set_missing" {
      if(-not $SignedPolicySet){ $Triggered = $true }
    }
    "policy_receipt_chain_missing" {
      if(-not $PolicyReceiptChain){ $Triggered = $true }
    }
    "remote_verifier_decision_missing" {
      if([string]::IsNullOrWhiteSpace($RemoteVerifierDecision)){ $Triggered = $true }
    }
    "dependency_authority_binding_missing" {
      if(-not $DependencyAuthorityBinding){ $Triggered = $true }
    }
    "topology_risk_high" {
      if([string](Get-Prop -Obj $Contract -Name "topology_risk" -Default "") -eq "high"){ $Triggered = $true }
    }
    "authority_score_high" {
      if([int](Get-Prop -Obj $Contract -Name "authority_score" -Default 0) -ge 90){ $Triggered = $true }
    }
    "dependency_concentration_medium" {
      if([string](Get-Prop -Obj $Contract -Name "dependency_concentration" -Default "") -eq "medium"){ $Triggered = $true }
    }
    "dependency_concentration_high" {
      if([string](Get-Prop -Obj $Contract -Name "dependency_concentration" -Default "") -eq "high"){ $Triggered = $true }
    }
    default {
      if($Condition -like "policy_layer_missing_remote_attestation_policy"){
        if(-not $RemoteAttestationVerified){ $Triggered = $true }
      } elseif($Condition -like "policy_layer_missing_*"){
        $Triggered = $true
      }
    }
  }

  if($Triggered){
    Add-Finding -List $Findings -Condition $Condition -Decision $RuleDecision -Severity $Severity -Reason $Reason
  }
}

$FinalDecision = "allow"

if(@($Findings | Where-Object { $_.decision -eq "deny" }).Count -gt 0){
  $FinalDecision = "deny"
}
elseif(@($Findings | Where-Object { $_.decision -eq "conditional" }).Count -gt 0){
  $FinalDecision = "conditional"
}

if($null -eq $Evidence){
  $FinalDecision = "untrusted"
}

$Out = [ordered]@{
  schema = "contract_registry.policy_decision.v1"
  generated_utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  target_repo = $ResolvedRepo
  contract_id = [string](Get-Prop -Obj $Contract -Name "contract_id" -Default "")
  evidence_path = $EvidencePath
  verification_path = $VerificationPath
  remote_attestation_verified = $RemoteAttestationVerified
  final_decision = $FinalDecision
  finding_count = @($Findings).Count
  findings = @($Findings)
}

$Root = Join-Path $ProfileRoot "policy_decisions"
New-Item -ItemType Directory -Force -Path $Root | Out-Null

$Stamp = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss")
$OutPath = Join-Path $Root ($Stamp + ".policy_decision.json")
Write-Utf8NoBomLf -Path $OutPath -Text ($Out | ConvertTo-Json -Depth 30)

$Report = @()
$Report += "# Contract Registry Policy Decision"
$Report += ""
$Report += "Repo: $RepoName"
$Report += "Generated UTC: $($Out.generated_utc)"
$Report += ""
$Report += "## Decision"
$Report += "- Final decision: $FinalDecision"
$Report += "- Contract ID: $($Out.contract_id)"
$Report += "- Finding count: $($Out.finding_count)"
$Report += "- Remote attestation verified: $RemoteAttestationVerified"
$Report += ""
$Report += "## Findings"
foreach($f in @($Findings)){
  $Report += "- $($f.decision.ToUpperInvariant()) $($f.condition): $($f.reason)"
}
if(@($Findings).Count -eq 0){ $Report += "- None" }

$ReportPath = Join-Path $Root ($Stamp + ".policy_decision_report.md")
Write-Utf8NoBomLf -Path $ReportPath -Text ($Report -join "`n")

$Receipt = [ordered]@{
  schema = "contract_registry.policy_decision_receipt.v1"
  utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  contract_id = [string](Get-Prop -Obj $Contract -Name "contract_id" -Default "")
  decision = $OutPath
  report = $ReportPath
  final_decision = $FinalDecision
  remote_attestation_verified = $RemoteAttestationVerified
  finding_count = @($Findings).Count
}

$ReceiptPath = Join-Path $Root ($Stamp + ".policy_decision_receipt.json")
Write-Utf8NoBomLf -Path $ReceiptPath -Text ($Receipt | ConvertTo-Json -Depth 20)

Write-Host "CR_POLICY_EVALUATOR_OK" -ForegroundColor Green
Write-Host ("DECISION: " + $OutPath)
Write-Host ("REPORT: " + $ReportPath)
Write-Host ("RECEIPT: " + $ReceiptPath)
Write-Host ("FINAL_DECISION: " + $FinalDecision)
Write-Host ("FINDING_COUNT: " + @($Findings).Count)

foreach($f in @($Findings | Select-Object -First 8)){
  Write-Host ("FINDING: " + $f.decision.ToUpperInvariant() + " " + $f.condition)
}
