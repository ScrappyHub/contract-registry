param(
  [Parameter(Mandatory=$true)]
  [string]$TargetRepo,

  [Parameter(Mandatory=$true)]
  [string]$EvidencePath,

  [Parameter(Mandatory=$false)]
  [string]$VerifierIdentity = "cr-verifier-001"
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

function Sha256-FileHex {
  param([string]$Path)
  $Hash = Get-FileHash -LiteralPath $Path -Algorithm SHA256
  return $Hash.Hash.ToLowerInvariant()
}

if(-not (Test-Path -LiteralPath $TargetRepo -PathType Container)){
  throw "TARGET_REPO_NOT_FOUND: $TargetRepo"
}

if(-not (Test-Path -LiteralPath $EvidencePath -PathType Leaf)){
  throw "EVIDENCE_NOT_FOUND: $EvidencePath"
}

$ResolvedRepo = (Resolve-Path -LiteralPath $TargetRepo).Path
$ResolvedEvidence = (Resolve-Path -LiteralPath $EvidencePath).Path
$RepoName = Split-Path -Leaf $ResolvedRepo
$ProfileRoot = Join-Path $ResolvedRepo ("runtime\shadow_profiles\" + $RepoName)

$Evidence = Read-JsonSafe -Path $ResolvedEvidence
$PolicyContract = Read-JsonSafe -Path (Join-Path $ProfileRoot "policy_contract\policy_contract.json")
$RemotePolicy = Read-JsonSafe -Path (Join-Path $ProfileRoot "remote_attestation_policy\remote_attestation_policy.json")

if($null -eq $Evidence){ throw "EVIDENCE_INVALID_JSON: $ResolvedEvidence" }
if($null -eq $PolicyContract){ throw "POLICY_CONTRACT_NOT_FOUND_RUN_POLICY_CONTRACT_FIRST" }
if($null -eq $RemotePolicy){ throw "REMOTE_ATTESTATION_POLICY_NOT_FOUND_RUN_REMOTE_ATTESTATION_FIRST" }

$MachineIdentity = [string](Get-Prop -Obj $Evidence -Name "machine_identity" -Default "")
$SignedPolicySet = [bool](Get-Prop -Obj $Evidence -Name "signed_policy_set" -Default $false)
$PolicyReceiptChain = [bool](Get-Prop -Obj $Evidence -Name "policy_receipt_chain" -Default $false)
$RemoteVerifierDecision = [string](Get-Prop -Obj $Evidence -Name "remote_verifier_decision" -Default "")
$DependencyAuthorityBinding = [bool](Get-Prop -Obj $Evidence -Name "dependency_authority_binding" -Default $false)
$EvidenceContractId = [string](Get-Prop -Obj $Evidence -Name "contract_id" -Default "")
$ContractId = [string](Get-Prop -Obj $PolicyContract -Name "contract_id" -Default "")

$Failures = @()

if([string]::IsNullOrWhiteSpace($MachineIdentity)){ $Failures += "MACHINE_IDENTITY_MISSING" }
if(-not $SignedPolicySet){ $Failures += "SIGNED_POLICY_SET_MISSING" }
if(-not $PolicyReceiptChain){ $Failures += "POLICY_RECEIPT_CHAIN_MISSING" }
if($RemoteVerifierDecision -ne "verified"){ $Failures += "REMOTE_VERIFIER_DECISION_NOT_VERIFIED" }
if(-not $DependencyAuthorityBinding){ $Failures += "DEPENDENCY_AUTHORITY_BINDING_MISSING" }
if([string]::IsNullOrWhiteSpace($EvidenceContractId)){ $Failures += "EVIDENCE_CONTRACT_ID_MISSING" }
elseif($EvidenceContractId -ne $ContractId){ $Failures += "EVIDENCE_CONTRACT_ID_MISMATCH" }

$Decision = "verified"
if(@($Failures).Count -gt 0){
  $Decision = "failed"
}

$EvidenceHash = Sha256-FileHex -Path $ResolvedEvidence

$Out = [ordered]@{
  schema = "contract_registry.remote_attestation_verification.v1"
  generated_utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  target_repo = $ResolvedRepo
  machine_identity = $MachineIdentity
  verifier_identity = $VerifierIdentity
  decision = $Decision
  policy_contract = $ContractId
  evidence_path = $ResolvedEvidence
  evidence_sha256 = $EvidenceHash
  failure_count = @($Failures).Count
  failures = @($Failures)
  verified_fields = [ordered]@{
    machine_identity = (-not [string]::IsNullOrWhiteSpace($MachineIdentity))
    signed_policy_set = $SignedPolicySet
    policy_receipt_chain = $PolicyReceiptChain
    remote_verifier_decision = ($RemoteVerifierDecision -eq "verified")
    dependency_authority_binding = $DependencyAuthorityBinding
    contract_id_matches = ($EvidenceContractId -eq $ContractId)
  }
}

$Root = Join-Path $ProfileRoot "remote_attestation_verification"
New-Item -ItemType Directory -Force -Path $Root | Out-Null

$Stamp = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss")
$OutPath = Join-Path $Root ($Stamp + ".remote_attestation_verification.json")
Write-Utf8NoBomLf -Path $OutPath -Text ($Out | ConvertTo-Json -Depth 30)

$Report = @()
$Report += "# Contract Registry Remote Attestation Verification"
$Report += ""
$Report += "Repo: $RepoName"
$Report += "Generated UTC: $($Out.generated_utc)"
$Report += ""
$Report += "## Verification"
$Report += "- Machine identity: $MachineIdentity"
$Report += "- Verifier identity: $VerifierIdentity"
$Report += "- Decision: $Decision"
$Report += "- Policy contract: $ContractId"
$Report += "- Evidence SHA256: $EvidenceHash"
$Report += ""
$Report += "## Failures"
foreach($f in @($Failures)){ $Report += "- $f" }
if(@($Failures).Count -eq 0){ $Report += "- None" }

$ReportPath = Join-Path $Root ($Stamp + ".remote_attestation_verification_report.md")
Write-Utf8NoBomLf -Path $ReportPath -Text ($Report -join "`n")

$Receipt = [ordered]@{
  schema = "contract_registry.remote_attestation_verification_receipt.v1"
  utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  machine_identity = $MachineIdentity
  verifier_identity = $VerifierIdentity
  decision = $Decision
  verification = $OutPath
  report = $ReportPath
  policy_contract = $ContractId
  evidence = $ResolvedEvidence
  evidence_sha256 = $EvidenceHash
  failure_count = @($Failures).Count
}

$ReceiptPath = Join-Path $Root ($Stamp + ".remote_attestation_verification_receipt.json")
Write-Utf8NoBomLf -Path $ReceiptPath -Text ($Receipt | ConvertTo-Json -Depth 20)

Write-Host "CR_REMOTE_ATTESTATION_VERIFIER_OK" -ForegroundColor Green
Write-Host ("VERIFICATION: " + $OutPath)
Write-Host ("REPORT: " + $ReportPath)
Write-Host ("RECEIPT: " + $ReceiptPath)
Write-Host ("MACHINE_IDENTITY: " + $MachineIdentity)
Write-Host ("VERIFIER_IDENTITY: " + $VerifierIdentity)
Write-Host ("DECISION: " + $Decision)
Write-Host ("EVIDENCE_SHA256: " + $EvidenceHash)
Write-Host ("FAILURE_COUNT: " + @($Failures).Count)

foreach($f in @($Failures)){
  Write-Host ("FAILURE: " + $f)
}