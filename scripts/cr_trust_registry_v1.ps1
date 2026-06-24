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

function Add-Entry {
  param(
    [System.Collections.Generic.List[object]]$List,
    [string]$Id,
    [string]$Kind,
    [string]$TrustState,
    [string]$Source,
    [string]$Reason
  )

  if([string]::IsNullOrWhiteSpace($Id)){ return }

  $Existing = $List | Where-Object { $_.id -eq $Id -and $_.kind -eq $Kind } | Select-Object -First 1
  if($Existing){
    $Existing.sources = @($Existing.sources + $Source | Sort-Object -Unique)
    $Existing.reasons = @($Existing.reasons + $Reason | Sort-Object -Unique)
    return
  }

  $List.Add([pscustomobject]@{
    id = $Id
    kind = $Kind
    trust_state = $TrustState
    sources = @($Source)
    reasons = @($Reason)
  }) | Out-Null
}

if(-not (Test-Path -LiteralPath $TargetRepo -PathType Container)){
  throw "TARGET_REPO_NOT_FOUND: $TargetRepo"
}

$ResolvedRepo = (Resolve-Path -LiteralPath $TargetRepo).Path
$RepoName = Split-Path -Leaf $ResolvedRepo
$ProfileRoot = Join-Path $ResolvedRepo ("runtime\shadow_profiles\" + $RepoName)

$PolicyBundle = Read-JsonSafe -Path (Join-Path $ProfileRoot "policy_bundle\policy_bundle.json")
$RemotePolicy = Read-JsonSafe -Path (Join-Path $ProfileRoot "remote_attestation_policy\remote_attestation_policy.json")
$Authority = Read-JsonSafe -Path (Join-Path $ProfileRoot "dependency_authority\dependency_authority.json")
$LatestClearance = $null

$ClearanceRoot = Join-Path $ProfileRoot "conditional_clearance"
if(Test-Path -LiteralPath $ClearanceRoot -PathType Container){
  $LatestClearanceFile = Get-ChildItem -LiteralPath $ClearanceRoot -Filter "*.conditional_clearance.json" -File |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
  if($LatestClearanceFile){ $LatestClearance = Read-JsonSafe -Path $LatestClearanceFile.FullName }
}

if($null -eq $PolicyBundle){ throw "POLICY_BUNDLE_NOT_FOUND_RUN_POLICY_BUNDLE_FIRST" }
if($null -eq $RemotePolicy){ throw "REMOTE_ATTESTATION_POLICY_NOT_FOUND" }
if($null -eq $Authority){ throw "DEPENDENCY_AUTHORITY_NOT_FOUND" }

$Entries = [System.Collections.Generic.List[object]]::new()

$BundleId = [string](Get-Prop -Obj $PolicyBundle -Name "bundle_id" -Default "")
$BundleHash = [string](Get-Prop -Obj $PolicyBundle -Name "bundle_hash" -Default "")
$ContractId = [string](Get-Prop -Obj (Get-Prop -Obj $PolicyBundle -Name "policy_contract" -Default $null) -Name "contract_id" -Default "")

Add-Entry -List $Entries -Id $RepoName -Kind "repository" -TrustState "registered" -Source "target_repo" -Reason "Repository is the trust registry target."
Add-Entry -List $Entries -Id $BundleId -Kind "policy_bundle" -TrustState "trusted" -Source "policy_bundle" -Reason ("Portable policy bundle hash: " + $BundleHash)
Add-Entry -List $Entries -Id $ContractId -Kind "policy_contract" -TrustState "trusted" -Source "policy_contract" -Reason "Policy contract is included in trusted bundle."

foreach($a in @(Get-Prop -Obj $RemotePolicy -Name "trust_anchors" -Default @())){
  Add-Entry -List $Entries -Id ([string]$a) -Kind "authority" -TrustState "trusted" -Source "remote_attestation_policy" -Reason "Remote attestation trust anchor."
}

foreach($a in @(Get-Prop -Obj $Authority -Name "primary_authorities" -Default @())){
  $Name = [string](Get-Prop -Obj $a -Name "name" -Default "")
  Add-Entry -List $Entries -Id $Name -Kind "primary_dependency_authority" -TrustState "trusted" -Source "dependency_authority" -Reason "Primary authority controls repo operation."
}

if($LatestClearance){
  $ClearanceLevel = [string](Get-Prop -Obj $LatestClearance -Name "clearance" -Default "unknown")
  $Decision = [string](Get-Prop -Obj $LatestClearance -Name "policy_decision" -Default "unknown")
  $State = "restricted"
  if($Decision -eq "allow"){ $State = "trusted" }
  elseif($Decision -eq "conditional"){ $State = "conditional" }
  elseif($Decision -eq "deny"){ $State = "denied" }
  elseif($Decision -eq "untrusted"){ $State = "untrusted" }

  Add-Entry -List $Entries -Id "local-dev-machine" -Kind "machine" -TrustState $State -Source "conditional_clearance" -Reason ("Latest clearance: " + $ClearanceLevel)
}

$TrustedCount = @($Entries | Where-Object { $_.trust_state -eq "trusted" }).Count
$ConditionalCount = @($Entries | Where-Object { $_.trust_state -eq "conditional" }).Count
$DeniedCount = @($Entries | Where-Object { $_.trust_state -eq "denied" -or $_.trust_state -eq "untrusted" }).Count

$RegistryState = "partial"
if($TrustedCount -ge 3 -and $DeniedCount -eq 0){ $RegistryState = "trusted_with_conditions" }
if($DeniedCount -gt 0){ $RegistryState = "restricted" }

$Out = [ordered]@{
  schema = "contract_registry.trust_registry.v1"
  generated_utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  target_repo = $ResolvedRepo
  registry_state = $RegistryState
  trusted_count = $TrustedCount
  conditional_count = $ConditionalCount
  denied_or_untrusted_count = $DeniedCount
  entries = @($Entries | Sort-Object kind, id)
}

$Root = Join-Path $ProfileRoot "trust_registry"
New-Item -ItemType Directory -Force -Path $Root | Out-Null

$RegistryPath = Join-Path $Root "trust_registry.json"
Write-Utf8NoBomLf -Path $RegistryPath -Text ($Out | ConvertTo-Json -Depth 40)

$Report = @()
$Report += "# Contract Registry Trust Registry"
$Report += ""
$Report += "Repo: $RepoName"
$Report += "Generated UTC: $($Out.generated_utc)"
$Report += ""
$Report += "## Registry"
$Report += "- Registry state: $RegistryState"
$Report += "- Trusted count: $TrustedCount"
$Report += "- Conditional count: $ConditionalCount"
$Report += "- Denied/untrusted count: $DeniedCount"
$Report += ""
$Report += "## Entries"
foreach($e in @($Out.entries)){
  $Report += "- $($e.trust_state) $($e.kind): $($e.id)"
}

$ReportPath = Join-Path $Root "trust_registry_report.md"
Write-Utf8NoBomLf -Path $ReportPath -Text ($Report -join "`n")

$Receipt = [ordered]@{
  schema = "contract_registry.trust_registry_receipt.v1"
  utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  registry = $RegistryPath
  report = $ReportPath
  registry_state = $RegistryState
  entry_count = @($Entries).Count
  trusted_count = $TrustedCount
  conditional_count = $ConditionalCount
  denied_or_untrusted_count = $DeniedCount
}

$ReceiptPath = Join-Path $Root "trust_registry_receipt.json"
Write-Utf8NoBomLf -Path $ReceiptPath -Text ($Receipt | ConvertTo-Json -Depth 20)

Write-Host "CR_TRUST_REGISTRY_OK" -ForegroundColor Green
Write-Host ("TRUST_REGISTRY: " + $RegistryPath)
Write-Host ("REPORT: " + $ReportPath)
Write-Host ("RECEIPT: " + $ReceiptPath)
Write-Host ("REGISTRY_STATE: " + $RegistryState)
Write-Host ("TRUSTED_COUNT: " + $TrustedCount)
Write-Host ("CONDITIONAL_COUNT: " + $ConditionalCount)
Write-Host ("DENIED_OR_UNTRUSTED_COUNT: " + $DeniedCount)

foreach($e in @($Out.entries | Select-Object -First 10)){
  Write-Host ("TRUST_ENTRY: " + $e.trust_state + " " + $e.kind + " " + $e.id)
}