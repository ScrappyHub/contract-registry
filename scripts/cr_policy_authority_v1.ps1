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

function Add-PolicySignal {
  param(
    [System.Collections.Generic.List[object]]$List,
    [string]$Code,
    [string]$Layer,
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
    layer = $Layer
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

$Identity = Read-JsonSafe -Path (Join-Path $ProfileRoot "identity\repo_identity.json")
$Capability = Read-JsonSafe -Path (Join-Path $ProfileRoot "capabilities\capability_graph.json")
$Risk = Read-JsonSafe -Path (Join-Path $ProfileRoot "risk_topology\risk_topology.json")
$Authority = Read-JsonSafe -Path (Join-Path $ProfileRoot "dependency_authority\dependency_authority.json")
$Dependency = Read-JsonSafe -Path (Join-Path $ProfileRoot "dependencies\dependency_intelligence.json")

if($null -eq $Identity){ throw "REPO_IDENTITY_NOT_FOUND_RUN_PIPELINE_FIRST" }
if($null -eq $Risk){ throw "RISK_TOPOLOGY_NOT_FOUND_RUN_PIPELINE_FIRST" }
if($null -eq $Authority){ throw "DEPENDENCY_AUTHORITY_NOT_FOUND_RUN_PIPELINE_FIRST" }

$Signals = [System.Collections.Generic.List[object]]::new()

$RequiredPolicyLayers = @(
  "constitutional_policy",
  "resource_policy",
  "runtime_policy",
  "machine_policy",
  "remote_attestation_policy",
  "dependency_authority_policy"
)

$DetectedPolicyLayers = @()

$Files = Get-ChildItem -LiteralPath $ResolvedRepo -Recurse -File -Force |
  Where-Object {
    $_.FullName -notmatch '\\\.git\\' -and
    $_.FullName -notmatch '\\runtime\\'
  }

foreach($f in @($Files)){
  $Rel = $f.FullName.Substring($ResolvedRepo.Length).TrimStart('\','/').Replace('\','/').ToLowerInvariant()
  $Name = $f.Name.ToLowerInvariant()

  if($Rel -match 'constitution|constitutional|governance|policy|policies|rls|resource|quota|limit|attestation|machine|device|remote|authority'){
    if($Rel -match 'constitution|constitutional'){
      $DetectedPolicyLayers = Add-Unique $DetectedPolicyLayers "constitutional_policy"
      Add-PolicySignal -List $Signals -Code "CONSTITUTIONAL_POLICY_SURFACE_PRESENT" -Layer "constitutional_policy" -Severity "INFO" -Message "Constitutional or higher-law policy surface detected." -Evidence $Rel
    }

    if($Rel -match 'resource|quota|limit|limits|budget|rate'){
      $DetectedPolicyLayers = Add-Unique $DetectedPolicyLayers "resource_policy"
      Add-PolicySignal -List $Signals -Code "RESOURCE_POLICY_SURFACE_PRESENT" -Layer "resource_policy" -Severity "INFO" -Message "Resource policy surface detected." -Evidence $Rel
    }

    if($Rel -match 'runtime|allow|deny|gate|enforce|rls|constraint'){
      $DetectedPolicyLayers = Add-Unique $DetectedPolicyLayers "runtime_policy"
      Add-PolicySignal -List $Signals -Code "RUNTIME_POLICY_SURFACE_PRESENT" -Layer "runtime_policy" -Severity "INFO" -Message "Runtime enforcement policy surface detected." -Evidence $Rel
    }

    if($Rel -match 'machine|device|host|workstation|node'){
      $DetectedPolicyLayers = Add-Unique $DetectedPolicyLayers "machine_policy"
      Add-PolicySignal -List $Signals -Code "MACHINE_POLICY_SURFACE_PRESENT" -Layer "machine_policy" -Severity "INFO" -Message "Machine/device policy surface detected." -Evidence $Rel
    }

    if($Rel -match 'attest|attestation|receipt|verify|verification|remote'){
      $DetectedPolicyLayers = Add-Unique $DetectedPolicyLayers "remote_attestation_policy"
      Add-PolicySignal -List $Signals -Code "ATTESTATION_POLICY_SURFACE_PRESENT" -Layer "remote_attestation_policy" -Severity "INFO" -Message "Attestation or remote verification surface detected." -Evidence $Rel
    }

    if($Rel -match 'authority|dependency|vendor|trust'){
      $DetectedPolicyLayers = Add-Unique $DetectedPolicyLayers "dependency_authority_policy"
      Add-PolicySignal -List $Signals -Code "DEPENDENCY_AUTHORITY_POLICY_SURFACE_PRESENT" -Layer "dependency_authority_policy" -Severity "INFO" -Message "Dependency authority policy surface detected." -Evidence $Rel
    }
  }
}

$Capabilities = @(Get-Prop -Obj $Capability -Name "capabilities" -Default @())
foreach($c in @($Capabilities)){
  $Name = [string](Get-Prop -Obj $c -Name "name" -Default "")
  if($Name -eq "database_or_schema_governance"){
    $DetectedPolicyLayers = Add-Unique $DetectedPolicyLayers "runtime_policy"
    Add-PolicySignal -List $Signals -Code "DATABASE_GOVERNANCE_POLICY_CAPABILITY" -Layer "runtime_policy" -Severity "INFO" -Message "Database/schema governance capability supports runtime policy enforcement." -Evidence "capability_graph.database_or_schema_governance"
  }
  if($Name -eq "governance_modeling"){
    $DetectedPolicyLayers = Add-Unique $DetectedPolicyLayers "constitutional_policy"
    Add-PolicySignal -List $Signals -Code "GOVERNANCE_MODELING_POLICY_CAPABILITY" -Layer "constitutional_policy" -Severity "INFO" -Message "Governance modeling capability supports policy authority behavior." -Evidence "capability_graph.governance_modeling"
  }
}

$TopologyRisk = [string](Get-Prop -Obj $Risk -Name "topology_risk" -Default "unknown")
$MaxRiskNode = [string](Get-Prop -Obj $Risk -Name "max_risk_node" -Default "")
$AuthorityScore = [int](Get-Prop -Obj $Authority -Name "authority_score" -Default 0)
$DependencyConcentration = [string](Get-Prop -Obj $Authority -Name "dependency_concentration" -Default "unknown")

if($TopologyRisk -eq "high"){
  Add-PolicySignal -List $Signals -Code "POLICY_ENGINE_REQUIRES_RISK_GATES" -Layer "runtime_policy" -Severity "HIGH" -Message "High risk topology requires policy gate coverage before remote trust." -Evidence ("max_risk_node=" + $MaxRiskNode)
}

if($AuthorityScore -ge 90){
  Add-PolicySignal -List $Signals -Code "PRIMARY_AUTHORITY_POLICY_REQUIRED" -Layer "dependency_authority_policy" -Severity "HIGH" -Message "Primary dependency authorities require explicit policy binding." -Evidence ("authority_score=" + $AuthorityScore)
}

if($DependencyConcentration -eq "medium" -or $DependencyConcentration -eq "high"){
  Add-PolicySignal -List $Signals -Code "DEPENDENCY_CONCENTRATION_POLICY_REQUIRED" -Layer "dependency_authority_policy" -Severity "MEDIUM" -Message "Dependency concentration requires governance policy coverage." -Evidence ("dependency_concentration=" + $DependencyConcentration)
}

$MissingPolicyLayers = @()
foreach($Layer in @($RequiredPolicyLayers)){
  if(-not (@($DetectedPolicyLayers) -contains $Layer)){
    $MissingPolicyLayers += $Layer
  }
}

$PolicyAuthorityReadiness = "partial"
if(@($MissingPolicyLayers).Count -eq 0){ $PolicyAuthorityReadiness = "complete" }
elseif(@($DetectedPolicyLayers).Count -le 2){ $PolicyAuthorityReadiness = "early" }

$RemoteVerificationReady = $false
if((@($DetectedPolicyLayers) -contains "remote_attestation_policy") -and (@($DetectedPolicyLayers) -contains "machine_policy")){
  $RemoteVerificationReady = $true
}

$Out = [ordered]@{
  schema = "contract_registry.policy_authority.v1"
  generated_utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  target_repo = $ResolvedRepo
  policy_authority_readiness = $PolicyAuthorityReadiness
  remote_verification_ready = $RemoteVerificationReady
  required_policy_layers = $RequiredPolicyLayers
  detected_policy_layers = @($DetectedPolicyLayers | Sort-Object -Unique)
  missing_policy_layers = @($MissingPolicyLayers | Sort-Object -Unique)
  policy_signal_count = @($Signals).Count
  topology_risk = $TopologyRisk
  max_risk_node = $MaxRiskNode
  authority_score = $AuthorityScore
  dependency_concentration = $DependencyConcentration
  policy_signals = @($Signals | Sort-Object severity, code)
}

$Root = Join-Path $ProfileRoot "policy_authority"
New-Item -ItemType Directory -Force -Path $Root | Out-Null

$OutPath = Join-Path $Root "policy_authority.json"
Write-Utf8NoBomLf -Path $OutPath -Text ($Out | ConvertTo-Json -Depth 30)

$Report = @()
$Report += "# Contract Registry Policy Authority"
$Report += ""
$Report += "Repo: $RepoName"
$Report += "Generated UTC: $($Out.generated_utc)"
$Report += ""
$Report += "## Summary"
$Report += "- Policy authority readiness: $PolicyAuthorityReadiness"
$Report += "- Remote verification ready: $RemoteVerificationReady"
$Report += "- Topology risk: $TopologyRisk"
$Report += "- Max risk node: $MaxRiskNode"
$Report += "- Authority score: $AuthorityScore"
$Report += "- Dependency concentration: $DependencyConcentration"
$Report += ""
$Report += "## Detected Policy Layers"
foreach($x in @($Out.detected_policy_layers)){ $Report += "- $x" }
$Report += ""
$Report += "## Missing Policy Layers"
foreach($x in @($Out.missing_policy_layers)){ $Report += "- $x" }
if(@($Out.missing_policy_layers).Count -eq 0){ $Report += "- None" }
$Report += ""
$Report += "## Policy Signals"
foreach($s in @($Out.policy_signals)){
  $Report += "- $($s.severity) $($s.code): $($s.message)"
}

$ReportPath = Join-Path $Root "policy_authority_report.md"
Write-Utf8NoBomLf -Path $ReportPath -Text ($Report -join "`n")

$Receipt = [ordered]@{
  schema = "contract_registry.policy_authority_receipt.v1"
  utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  policy_authority = $OutPath
  report = $ReportPath
  policy_authority_readiness = $PolicyAuthorityReadiness
  remote_verification_ready = $RemoteVerificationReady
  detected_policy_layer_count = @($Out.detected_policy_layers).Count
  missing_policy_layer_count = @($Out.missing_policy_layers).Count
}

$ReceiptPath = Join-Path $Root "policy_authority_receipt.json"
Write-Utf8NoBomLf -Path $ReceiptPath -Text ($Receipt | ConvertTo-Json -Depth 20)

Write-Host "CR_POLICY_AUTHORITY_OK" -ForegroundColor Green
Write-Host ("POLICY_AUTHORITY: " + $OutPath)
Write-Host ("REPORT: " + $ReportPath)
Write-Host ("RECEIPT: " + $ReceiptPath)
Write-Host ("POLICY_AUTHORITY_READINESS: " + $PolicyAuthorityReadiness)
Write-Host ("REMOTE_VERIFICATION_READY: " + $RemoteVerificationReady)
Write-Host ("DETECTED_POLICY_LAYERS: " + (@($Out.detected_policy_layers) -join ", "))
Write-Host ("MISSING_POLICY_LAYERS: " + (@($Out.missing_policy_layers) -join ", "))

foreach($s in @($Out.policy_signals | Select-Object -First 8)){
  Write-Host ("POLICY_SIGNAL: " + $s.severity + " " + $s.code)
}