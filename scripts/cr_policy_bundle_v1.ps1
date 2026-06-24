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

function Sha256-TextHex {
  param([string]$Text)
  $Sha = [Security.Cryptography.SHA256]::Create()
  $Bytes = [Text.Encoding]::UTF8.GetBytes($Text)
  return ([BitConverter]::ToString($Sha.ComputeHash($Bytes))).Replace("-","").ToLowerInvariant()
}

if(-not (Test-Path -LiteralPath $TargetRepo -PathType Container)){
  throw "TARGET_REPO_NOT_FOUND: $TargetRepo"
}

$ResolvedRepo = (Resolve-Path -LiteralPath $TargetRepo).Path
$RepoName = Split-Path -Leaf $ResolvedRepo
$ProfileRoot = Join-Path $ResolvedRepo ("runtime\shadow_profiles\" + $RepoName)

$PolicyAuthorityPath = Join-Path $ProfileRoot "policy_authority\policy_authority.json"
$RemoteAttestationPolicyPath = Join-Path $ProfileRoot "remote_attestation_policy\remote_attestation_policy.json"
$PolicyContractPath = Join-Path $ProfileRoot "policy_contract\policy_contract.json"
$ConditionalClearanceRoot = Join-Path $ProfileRoot "conditional_clearance"
$DependencyAuthorityPath = Join-Path $ProfileRoot "dependency_authority\dependency_authority.json"
$RiskTopologyPath = Join-Path $ProfileRoot "risk_topology\risk_topology.json"

$PolicyAuthority = Read-JsonSafe -Path $PolicyAuthorityPath
$RemoteAttestationPolicy = Read-JsonSafe -Path $RemoteAttestationPolicyPath
$PolicyContract = Read-JsonSafe -Path $PolicyContractPath
$DependencyAuthority = Read-JsonSafe -Path $DependencyAuthorityPath
$RiskTopology = Read-JsonSafe -Path $RiskTopologyPath

if($null -eq $PolicyAuthority){ throw "POLICY_AUTHORITY_NOT_FOUND" }
if($null -eq $RemoteAttestationPolicy){ throw "REMOTE_ATTESTATION_POLICY_NOT_FOUND" }
if($null -eq $PolicyContract){ throw "POLICY_CONTRACT_NOT_FOUND" }
if($null -eq $DependencyAuthority){ throw "DEPENDENCY_AUTHORITY_NOT_FOUND" }
if($null -eq $RiskTopology){ throw "RISK_TOPOLOGY_NOT_FOUND" }

$LatestClearance = $null
if(Test-Path -LiteralPath $ConditionalClearanceRoot -PathType Container){
  $LatestClearanceFile = Get-ChildItem -LiteralPath $ConditionalClearanceRoot -Filter "*.conditional_clearance.json" -File |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
  if($LatestClearanceFile){ $LatestClearance = Read-JsonSafe -Path $LatestClearanceFile.FullName }
}

$Bundle = [ordered]@{
  schema = "contract_registry.policy_bundle.v1"
  generated_utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  target_repo = $ResolvedRepo
  bundle_kind = "portable_policy_authority_bundle"
  policy_authority = $PolicyAuthority
  remote_attestation_policy = $RemoteAttestationPolicy
  policy_contract = $PolicyContract
  dependency_authority = $DependencyAuthority
  risk_topology = $RiskTopology
  latest_conditional_clearance = $LatestClearance
}

$Canonical = $Bundle | ConvertTo-Json -Depth 80
$BundleHash = Sha256-TextHex -Text $Canonical

$Bundle["bundle_hash"] = $BundleHash
$Bundle["bundle_id"] = "policy_bundle_" + $BundleHash.Substring(0,16)

$Root = Join-Path $ProfileRoot "policy_bundle"
New-Item -ItemType Directory -Force -Path $Root | Out-Null

$BundlePath = Join-Path $Root "policy_bundle.json"
Write-Utf8NoBomLf -Path $BundlePath -Text ($Bundle | ConvertTo-Json -Depth 80)

$Report = @()
$Report += "# Contract Registry Policy Bundle"
$Report += ""
$Report += "Repo: $RepoName"
$Report += "Generated UTC: $($Bundle.generated_utc)"
$Report += ""
$Report += "## Bundle"
$Report += "- Bundle ID: $($Bundle.bundle_id)"
$Report += "- Bundle hash: $BundleHash"
$Report += "- Bundle kind: portable_policy_authority_bundle"
$Report += ""
$Report += "## Included Authority Layers"
$Report += "- policy_authority"
$Report += "- remote_attestation_policy"
$Report += "- policy_contract"
$Report += "- dependency_authority"
$Report += "- risk_topology"
if($LatestClearance){ $Report += "- latest_conditional_clearance" }
$Report += ""
$Report += "## Policy Contract"
$ContractIdForReport = [string](Get-Prop -Obj $PolicyContract -Name "contract_id" -Default "")
$Report += "- Contract ID: $ContractIdForReport"
$DefaultDecisionForReport = [string](Get-Prop -Obj $PolicyContract -Name "default_decision" -Default "")
$Report += "- Default decision: $DefaultDecisionForReport"
$Report += ""
$Report += "## Remote Attestation"
$RemoteModeForReport = [string](Get-Prop -Obj $RemoteAttestationPolicy -Name "remote_verification_mode" -Default "")
$Report += "- Mode: $RemoteModeForReport"
$Report += "- Trust anchors: $(@(Get-Prop -Obj $RemoteAttestationPolicy -Name "trust_anchors" -Default @()) -join ', ')"

$ReportPath = Join-Path $Root "policy_bundle_report.md"
Write-Utf8NoBomLf -Path $ReportPath -Text ($Report -join "`n")

$Receipt = [ordered]@{
  schema = "contract_registry.policy_bundle_receipt.v1"
  utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  bundle = $BundlePath
  report = $ReportPath
  bundle_id = $Bundle["bundle_id"]
  bundle_hash = $BundleHash
  contract_id = [string](Get-Prop -Obj $PolicyContract -Name "contract_id" -Default "")
}

$ReceiptPath = Join-Path $Root "policy_bundle_receipt.json"
Write-Utf8NoBomLf -Path $ReceiptPath -Text ($Receipt | ConvertTo-Json -Depth 20)

Write-Host "CR_POLICY_BUNDLE_OK" -ForegroundColor Green
Write-Host ("BUNDLE: " + $BundlePath)
Write-Host ("REPORT: " + $ReportPath)
Write-Host ("RECEIPT: " + $ReceiptPath)
Write-Host ("BUNDLE_ID: " + $Bundle["bundle_id"])
Write-Host ("BUNDLE_HASH: " + $BundleHash)
Write-Host ("CONTRACT_ID: " + [string](Get-Prop -Obj $PolicyContract -Name "contract_id" -Default ""))