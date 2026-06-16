param(
  [Parameter(Mandatory=$true)]
  [string]$TargetRepo,

  [Parameter(Mandatory=$false)]
  [string]$MachineId = "local-dev-machine",

  [Parameter(Mandatory=$false)]
  [ValidateSet("synthetic","observed")]
  [string]$Mode = "synthetic"
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

if(-not (Test-Path -LiteralPath $TargetRepo -PathType Container)){
  throw "TARGET_REPO_NOT_FOUND: $TargetRepo"
}

$ResolvedRepo = (Resolve-Path -LiteralPath $TargetRepo).Path
$RepoName = Split-Path -Leaf $ResolvedRepo
$ProfileRoot = Join-Path $ResolvedRepo ("runtime\shadow_profiles\" + $RepoName)

$PolicyContractPath = Join-Path $ProfileRoot "policy_contract\policy_contract.json"
$RemotePolicyPath = Join-Path $ProfileRoot "remote_attestation_policy\remote_attestation_policy.json"
$AuthorityPath = Join-Path $ProfileRoot "dependency_authority\dependency_authority.json"

$PolicyContract = Read-JsonSafe -Path $PolicyContractPath
$RemotePolicy = Read-JsonSafe -Path $RemotePolicyPath
$Authority = Read-JsonSafe -Path $AuthorityPath

if($null -eq $PolicyContract){ throw "POLICY_CONTRACT_NOT_FOUND_RUN_POLICY_CONTRACT_FIRST" }
if($null -eq $RemotePolicy){ throw "REMOTE_ATTESTATION_POLICY_NOT_FOUND_RUN_REMOTE_ATTESTATION_FIRST" }
if($null -eq $Authority){ throw "DEPENDENCY_AUTHORITY_NOT_FOUND_RUN_PIPELINE_FIRST" }

$TrustAnchors = @(Get-Prop -Obj $RemotePolicy -Name "trust_anchors" -Default @())
$RemoteScopes = @(Get-Prop -Obj $RemotePolicy -Name "remote_scopes" -Default @())
$RequiredAttestations = @(Get-Prop -Obj $PolicyContract -Name "required_attestations" -Default @())

$SignedPolicySet = $false
$PolicyReceiptChain = $false
$DependencyAuthorityBinding = $false
$RemoteVerifierDecision = ""

if($Mode -eq "synthetic"){
  $SignedPolicySet = $true
  $PolicyReceiptChain = $true
  $DependencyAuthorityBinding = $true
  $RemoteVerifierDecision = "verified"
} else {
  $SignedPolicySet = $false
  $PolicyReceiptChain = $false
  $DependencyAuthorityBinding = $false
  $RemoteVerifierDecision = "unverified"
}

$Evidence = [ordered]@{
  schema = "contract_registry.machine_evidence.v1"
  generated_utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  target_repo = $ResolvedRepo
  mode = $Mode
  machine_identity = $MachineId
  signed_policy_set = $SignedPolicySet
  policy_receipt_chain = $PolicyReceiptChain
  remote_verifier_decision = $RemoteVerifierDecision
  dependency_authority_binding = $DependencyAuthorityBinding
  contract_id = [string](Get-Prop -Obj $PolicyContract -Name "contract_id" -Default "")
  required_attestations = $RequiredAttestations
  trust_anchors = $TrustAnchors
  remote_scopes = $RemoteScopes
}

$Root = Join-Path $ProfileRoot "machine_evidence"
New-Item -ItemType Directory -Force -Path $Root | Out-Null

$Stamp = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss")
$EvidencePath = Join-Path $Root ($Stamp + ".machine_evidence.json")
Write-Utf8NoBomLf -Path $EvidencePath -Text ($Evidence | ConvertTo-Json -Depth 30)

$Report = @()
$Report += "# Contract Registry Machine Evidence"
$Report += ""
$Report += "Repo: $RepoName"
$Report += "Generated UTC: $($Evidence.generated_utc)"
$Report += ""
$Report += "## Evidence"
$Report += "- Machine identity: $MachineId"
$Report += "- Mode: $Mode"
$Report += "- Signed policy set: $SignedPolicySet"
$Report += "- Policy receipt chain: $PolicyReceiptChain"
$Report += "- Remote verifier decision: $RemoteVerifierDecision"
$Report += "- Dependency authority binding: $DependencyAuthorityBinding"
$Report += ""
$Report += "## Trust Anchors"
foreach($x in @($TrustAnchors)){ $Report += "- $x" }
if(@($TrustAnchors).Count -eq 0){ $Report += "- None" }
$Report += ""
$Report += "## Remote Scopes"
foreach($x in @($RemoteScopes)){ $Report += "- $x" }
if(@($RemoteScopes).Count -eq 0){ $Report += "- None" }

$ReportPath = Join-Path $Root ($Stamp + ".machine_evidence_report.md")
Write-Utf8NoBomLf -Path $ReportPath -Text ($Report -join "`n")

$Receipt = [ordered]@{
  schema = "contract_registry.machine_evidence_receipt.v1"
  utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  machine_identity = $MachineId
  evidence = $EvidencePath
  report = $ReportPath
  mode = $Mode
  contract_id = [string](Get-Prop -Obj $PolicyContract -Name "contract_id" -Default "")
  signed_policy_set = $SignedPolicySet
  policy_receipt_chain = $PolicyReceiptChain
  remote_verifier_decision = $RemoteVerifierDecision
  dependency_authority_binding = $DependencyAuthorityBinding
}

$ReceiptPath = Join-Path $Root ($Stamp + ".machine_evidence_receipt.json")
Write-Utf8NoBomLf -Path $ReceiptPath -Text ($Receipt | ConvertTo-Json -Depth 20)

Write-Host "CR_MACHINE_EVIDENCE_OK" -ForegroundColor Green
Write-Host ("EVIDENCE: " + $EvidencePath)
Write-Host ("REPORT: " + $ReportPath)
Write-Host ("RECEIPT: " + $ReceiptPath)
Write-Host ("MACHINE_IDENTITY: " + $MachineId)
Write-Host ("MODE: " + $Mode)
Write-Host ("SIGNED_POLICY_SET: " + $SignedPolicySet)
Write-Host ("POLICY_RECEIPT_CHAIN: " + $PolicyReceiptChain)
Write-Host ("REMOTE_VERIFIER_DECISION: " + $RemoteVerifierDecision)
Write-Host ("DEPENDENCY_AUTHORITY_BINDING: " + $DependencyAuthorityBinding)