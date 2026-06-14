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

function Add-Unique {
  param([array]$Items,[string]$Value)
  if([string]::IsNullOrWhiteSpace($Value)){ return @($Items) }
  return @($Items + $Value | Sort-Object -Unique)
}

function Add-AttestationRequirement {
  param(
    [System.Collections.Generic.List[object]]$List,
    [string]$Code,
    [string]$Scope,
    [string]$Severity,
    [string]$Message,
    [string]$Evidence
  )

  $Existing = $List | Where-Object { $_.code -eq $Code } | Select-Object -First 1
  if($Existing){
    $Existing.evidence = @($Existing.evidence + $Evidence | Sort-Object -Unique)
    return
  }

  $List.Add([pscustomobject]@{
    code = $Code
    scope = $Scope
    severity = $Severity
    message = $Message
    evidence = @($Evidence)
  }) | Out-Null
}

if(-not (Test-Path -LiteralPath $TargetRepo -PathType Container)){
  throw "TARGET_REPO_NOT_FOUND: $TargetRepo"
}

$ResolvedRepo = (Resolve-Path -LiteralPath $TargetRepo).Path
$RepoName = Split-Path -Leaf $ResolvedRepo
$ProfileRoot = Join-Path $ResolvedRepo ("runtime\shadow_profiles\" + $RepoName)

$PolicyAuthority = Read-JsonSafe -Path (Join-Path $ProfileRoot "policy_authority\policy_authority.json")
$Risk = Read-JsonSafe -Path (Join-Path $ProfileRoot "risk_topology\risk_topology.json")
$Authority = Read-JsonSafe -Path (Join-Path $ProfileRoot "dependency_authority\dependency_authority.json")
$Dependency = Read-JsonSafe -Path (Join-Path $ProfileRoot "dependencies\dependency_intelligence.json")

if($null -eq $PolicyAuthority){ throw "POLICY_AUTHORITY_NOT_FOUND_RUN_POLICY_AUTHORITY_FIRST" }
if($null -eq $Risk){ throw "RISK_TOPOLOGY_NOT_FOUND_RUN_PIPELINE_FIRST" }
if($null -eq $Authority){ throw "DEPENDENCY_AUTHORITY_NOT_FOUND_RUN_PIPELINE_FIRST" }

$Requirements = [System.Collections.Generic.List[object]]::new()
$TrustAnchors = @()
$RemoteScopes = @()

$TopologyRisk = [string](Get-Prop -Obj $Risk -Name "topology_risk" -Default "unknown")
$MaxRiskNode = [string](Get-Prop -Obj $Risk -Name "max_risk_node" -Default "")
$AuthorityScore = [int](Get-Prop -Obj $Authority -Name "authority_score" -Default 0)
$DependencyConcentration = [string](Get-Prop -Obj $Authority -Name "dependency_concentration" -Default "unknown")

$PrimaryAuthorities = @(Get-Prop -Obj $Authority -Name "primary_authorities" -Default @())
foreach($a in @($PrimaryAuthorities)){
  $Name = [string](Get-Prop -Obj $a -Name "name" -Default "")
  if($Name){
    $TrustAnchors = Add-Unique $TrustAnchors $Name
    Add-AttestationRequirement -List $Requirements -Code ("ATTEST_PRIMARY_AUTHORITY_" + $Name.ToUpperInvariant()) -Scope "dependency_authority" -Severity "HIGH" -Message ("Remote attestations must bind primary authority: " + $Name) -Evidence ("primary_authority=" + $Name)
  }
}

if($Dependency){
  foreach($p in @(Get-Prop -Obj $Dependency -Name "external_platforms" -Default @())){
    $RemoteScopes = Add-Unique $RemoteScopes ([string]$p)
  }

  foreach($t in @(Get-Prop -Obj $Dependency -Name "trust_surface" -Default @())){
    $RemoteScopes = Add-Unique $RemoteScopes ([string]$t)
  }
}

if($TopologyRisk -eq "high"){
  Add-AttestationRequirement -List $Requirements -Code "REMOTE_ATTESTATION_REQUIRED_FOR_HIGH_RISK_TOPOLOGY" -Scope "risk_topology" -Severity "HIGH" -Message "High risk topology requires remote attestation before trust promotion." -Evidence ("max_risk_node=" + $MaxRiskNode)
}

if($AuthorityScore -ge 90){
  Add-AttestationRequirement -List $Requirements -Code "REMOTE_ATTESTATION_REQUIRED_FOR_PRIMARY_AUTHORITY" -Scope "dependency_authority" -Severity "HIGH" -Message "High authority score requires signed remote authority attestation." -Evidence ("authority_score=" + $AuthorityScore)
}

if($DependencyConcentration -eq "medium" -or $DependencyConcentration -eq "high"){
  Add-AttestationRequirement -List $Requirements -Code "REMOTE_ATTESTATION_REQUIRED_FOR_DEPENDENCY_CONCENTRATION" -Scope "dependency_authority" -Severity "MEDIUM" -Message "Dependency concentration requires explicit remote policy attestation." -Evidence ("dependency_concentration=" + $DependencyConcentration)
}

Add-AttestationRequirement -List $Requirements -Code "MACHINE_IDENTITY_REQUIRED" -Scope "machine_policy" -Severity "HIGH" -Message "Remote machines must present stable machine identity." -Evidence "remote_attestation_policy.v1"
Add-AttestationRequirement -List $Requirements -Code "SIGNED_POLICY_SET_REQUIRED" -Scope "remote_attestation_policy" -Severity "HIGH" -Message "Remote machines must present signed policy set receipt." -Evidence "remote_attestation_policy.v1"
Add-AttestationRequirement -List $Requirements -Code "POLICY_RECEIPT_CHAIN_REQUIRED" -Scope "remote_attestation_policy" -Severity "HIGH" -Message "Remote compliance must include receipt chain proof." -Evidence "remote_attestation_policy.v1"
Add-AttestationRequirement -List $Requirements -Code "REMOTE_VERIFIER_DECISION_REQUIRED" -Scope "remote_attestation_policy" -Severity "MEDIUM" -Message "Remote machines must be evaluated by a deterministic verifier." -Evidence "remote_attestation_policy.v1"

$RemoteVerificationMode = "not_ready"
if(@($Requirements).Count -gt 0){
  $RemoteVerificationMode = "policy_required"
}
if(($TrustAnchors.Count -gt 0) -and ($RemoteScopes.Count -gt 0)){
  $RemoteVerificationMode = "attestation_ready"
}

$Out = [ordered]@{
  schema = "contract_registry.remote_attestation_policy.v1"
  generated_utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  target_repo = $ResolvedRepo
  remote_verification_mode = $RemoteVerificationMode
  trust_anchors = @($TrustAnchors | Sort-Object -Unique)
  remote_scopes = @($RemoteScopes | Sort-Object -Unique)
  requirement_count = @($Requirements).Count
  requirements = @($Requirements | Sort-Object severity, code)
}

$Root = Join-Path $ProfileRoot "remote_attestation_policy"
New-Item -ItemType Directory -Force -Path $Root | Out-Null

$OutPath = Join-Path $Root "remote_attestation_policy.json"
Write-Utf8NoBomLf -Path $OutPath -Text ($Out | ConvertTo-Json -Depth 30)

$Report = @()
$Report += "# Contract Registry Remote Attestation Policy"
$Report += ""
$Report += "Repo: $RepoName"
$Report += "Generated UTC: $($Out.generated_utc)"
$Report += ""
$Report += "## Summary"
$Report += "- Remote verification mode: $RemoteVerificationMode"
$Report += "- Requirement count: $(@($Requirements).Count)"
$Report += ""
$Report += "## Trust Anchors"
foreach($x in @($Out.trust_anchors)){ $Report += "- $x" }
if(@($Out.trust_anchors).Count -eq 0){ $Report += "- None" }
$Report += ""
$Report += "## Remote Scopes"
foreach($x in @($Out.remote_scopes)){ $Report += "- $x" }
if(@($Out.remote_scopes).Count -eq 0){ $Report += "- None" }
$Report += ""
$Report += "## Requirements"
foreach($r in @($Out.requirements)){
  $Report += "- $($r.severity) $($r.code): $($r.message)"
}

$ReportPath = Join-Path $Root "remote_attestation_policy_report.md"
Write-Utf8NoBomLf -Path $ReportPath -Text ($Report -join "`n")

$Receipt = [ordered]@{
  schema = "contract_registry.remote_attestation_policy_receipt.v1"
  utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  remote_attestation_policy = $OutPath
  report = $ReportPath
  remote_verification_mode = $RemoteVerificationMode
  requirement_count = @($Requirements).Count
  trust_anchor_count = @($Out.trust_anchors).Count
}

$ReceiptPath = Join-Path $Root "remote_attestation_policy_receipt.json"
Write-Utf8NoBomLf -Path $ReceiptPath -Text ($Receipt | ConvertTo-Json -Depth 20)

Write-Host "CR_REMOTE_ATTESTATION_POLICY_OK" -ForegroundColor Green
Write-Host ("REMOTE_ATTESTATION_POLICY: " + $OutPath)
Write-Host ("REPORT: " + $ReportPath)
Write-Host ("RECEIPT: " + $ReceiptPath)
Write-Host ("REMOTE_VERIFICATION_MODE: " + $RemoteVerificationMode)
Write-Host ("TRUST_ANCHORS: " + (@($Out.trust_anchors) -join ", "))
Write-Host ("REMOTE_SCOPES: " + (@($Out.remote_scopes) -join ", "))
Write-Host ("REQUIREMENT_COUNT: " + @($Requirements).Count)

foreach($r in @($Out.requirements | Select-Object -First 8)){
  Write-Host ("ATTESTATION_REQUIREMENT: " + $r.severity + " " + $r.code)
}