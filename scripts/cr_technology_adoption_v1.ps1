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

function Add-TechSignal {
  param(
    [System.Collections.Generic.List[object]]$List,
    [string]$Name,
    [string]$Category,
    [int]$Confidence,
    [string]$Evidence
  )

  $Existing = $List | Where-Object { $_.name -eq $Name -and $_.category -eq $Category } | Select-Object -First 1

  if($Existing){
    if($Confidence -gt [int]$Existing.confidence){ $Existing.confidence = $Confidence }
    $Existing.evidence = @($Existing.evidence + $Evidence | Sort-Object -Unique)
    return
  }

  $List.Add([pscustomobject]@{
    name = $Name
    category = $Category
    confidence = $Confidence
    evidence = @($Evidence)
  }) | Out-Null
}

if(-not (Test-Path -LiteralPath $TargetRepo -PathType Container)){
  throw "TARGET_REPO_NOT_FOUND: $TargetRepo"
}

$ResolvedRepo = (Resolve-Path -LiteralPath $TargetRepo).Path
$RepoName = Split-Path -Leaf $ResolvedRepo
$ProfileRoot = Join-Path $ResolvedRepo ("runtime\shadow_profiles\" + $RepoName)

$DependencyPath = Join-Path $ProfileRoot "dependencies\dependency_intelligence.json"
$CapabilityPath = Join-Path $ProfileRoot "capabilities\capability_graph.json"
$AuthorityPath = Join-Path $ProfileRoot "dependency_authority\dependency_authority.json"
$IdentityPath = Join-Path $ProfileRoot "identity\repo_identity.json"
$RiskPath = Join-Path $ProfileRoot "risk_topology\risk_topology.json"

$Dependency = Read-JsonSafe -Path $DependencyPath
$CapabilityGraph = Read-JsonSafe -Path $CapabilityPath
$Authority = Read-JsonSafe -Path $AuthorityPath
$Identity = Read-JsonSafe -Path $IdentityPath
$RiskTopology = Read-JsonSafe -Path $RiskPath

if($null -eq $Dependency){ throw "DEPENDENCY_INTELLIGENCE_NOT_FOUND_RUN_PIPELINE_FIRST" }
if($null -eq $Authority){ throw "DEPENDENCY_AUTHORITY_NOT_FOUND_RUN_PIPELINE_FIRST" }

$Signals = [System.Collections.Generic.List[object]]::new()
$Languages = @(Get-Prop -Obj $Dependency -Name "languages" -Default @())
$PackageManagers = @(Get-Prop -Obj $Dependency -Name "package_managers" -Default @())
$ExternalPlatforms = @(Get-Prop -Obj $Dependency -Name "external_platforms" -Default @())
$RuntimeDependencies = @(Get-Prop -Obj $Dependency -Name "runtime_dependencies" -Default @())
$CriticalDependencies = @(Get-Prop -Obj $Dependency -Name "critical_dependencies" -Default @())

foreach($x in @($Languages)){
  switch([string]$x){
    "powershell" { Add-TechSignal -List $Signals -Name "powershell" -Category "language" -Confidence 94 -Evidence "dependency.languages.powershell" }
    "sql" { Add-TechSignal -List $Signals -Name "sql" -Category "language" -Confidence 93 -Evidence "dependency.languages.sql" }
    "typescript" { Add-TechSignal -List $Signals -Name "typescript" -Category "language" -Confidence 88 -Evidence "dependency.languages.typescript" }
    "javascript" { Add-TechSignal -List $Signals -Name "javascript" -Category "language" -Confidence 84 -Evidence "dependency.languages.javascript" }
    "yaml" { Add-TechSignal -List $Signals -Name "yaml" -Category "configuration" -Confidence 80 -Evidence "dependency.languages.yaml" }
    default { Add-TechSignal -List $Signals -Name ([string]$x) -Category "language" -Confidence 60 -Evidence ("dependency.languages." + [string]$x) }
  }
}

foreach($x in @($PackageManagers)){
  switch([string]$x){
    "npm" { Add-TechSignal -List $Signals -Name "npm" -Category "package_manager" -Confidence 85 -Evidence "dependency.package_managers.npm" }
    "pnpm" { Add-TechSignal -List $Signals -Name "pnpm" -Category "package_manager" -Confidence 88 -Evidence "dependency.package_managers.pnpm" }
    "yarn" { Add-TechSignal -List $Signals -Name "yarn" -Category "package_manager" -Confidence 80 -Evidence "dependency.package_managers.yarn" }
    default { Add-TechSignal -List $Signals -Name ([string]$x) -Category "package_manager" -Confidence 65 -Evidence ("dependency.package_managers." + [string]$x) }
  }
}

foreach($x in @($ExternalPlatforms)){
  switch([string]$x){
    "supabase" { Add-TechSignal -List $Signals -Name "supabase" -Category "platform" -Confidence 97 -Evidence "dependency.external_platforms.supabase" }
    "github_actions" { Add-TechSignal -List $Signals -Name "github_actions" -Category "ci" -Confidence 90 -Evidence "dependency.external_platforms.github_actions" }
    "stripe" { Add-TechSignal -List $Signals -Name "stripe" -Category "payments" -Confidence 92 -Evidence "dependency.external_platforms.stripe" }
    default { Add-TechSignal -List $Signals -Name ([string]$x) -Category "platform" -Confidence 70 -Evidence ("dependency.external_platforms." + [string]$x) }
  }
}

foreach($x in @($RuntimeDependencies + $CriticalDependencies)){
  switch([string]$x){
    "postgres" { Add-TechSignal -List $Signals -Name "postgres" -Category "database" -Confidence 96 -Evidence "dependency.postgres" }
    "supabase" { Add-TechSignal -List $Signals -Name "supabase" -Category "platform" -Confidence 97 -Evidence "dependency.supabase" }
    "nodejs" { Add-TechSignal -List $Signals -Name "nodejs" -Category "runtime" -Confidence 85 -Evidence "dependency.nodejs" }
    "server_runtime" { Add-TechSignal -List $Signals -Name "server_runtime" -Category "runtime" -Confidence 82 -Evidence "dependency.server_runtime" }
    default { Add-TechSignal -List $Signals -Name ([string]$x) -Category "runtime" -Confidence 60 -Evidence ("dependency.runtime." + [string]$x) }
  }
}

if($CapabilityGraph){
  foreach($c in @(Get-Prop -Obj $CapabilityGraph -Name "capabilities" -Default @())){
    $Name = [string](Get-Prop -Obj $c -Name "name" -Default "")
    $Confidence = [int](Get-Prop -Obj $c -Name "confidence" -Default 0)

    if($Name -eq "database_or_schema_governance"){
      Add-TechSignal -List $Signals -Name "schema_governance" -Category "architecture_pattern" -Confidence $Confidence -Evidence "capability.database_or_schema_governance"
    }
    if($Name -eq "supabase_backend"){
      Add-TechSignal -List $Signals -Name "supabase_backend" -Category "architecture_pattern" -Confidence $Confidence -Evidence "capability.supabase_backend"
    }
    if($Name -eq "powershell_automation_tooling"){
      Add-TechSignal -List $Signals -Name "powershell_automation" -Category "automation_pattern" -Confidence $Confidence -Evidence "capability.powershell_automation_tooling"
    }
  }
}

if($Identity){
  $Archetype = [string](Get-Prop -Obj $Identity -Name "archetype" -Default "")
  $SoftwareClass = [string](Get-Prop -Obj $Identity -Name "software_class" -Default "")

  if($Archetype){
    Add-TechSignal -List $Signals -Name $Archetype -Category "repo_archetype" -Confidence 92 -Evidence "identity.archetype"
  }

  if($SoftwareClass){
    Add-TechSignal -List $Signals -Name $SoftwareClass -Category "software_class" -Confidence 99 -Evidence "identity.software_class"
  }
}

$Ranked = @($Signals | Sort-Object name | Sort-Object confidence -Descending)

$PrimaryAuthorities = @(Get-Prop -Obj $Authority -Name "primary_authorities" -Default @())
$SecondaryAuthorities = @(Get-Prop -Obj $Authority -Name "secondary_authorities" -Default @())
$AuthorityNames = @()
foreach($a in @($PrimaryAuthorities + $SecondaryAuthorities)){
  $AuthorityNames += [string](Get-Prop -Obj $a -Name "name" -Default "")
}
$AuthorityNames = @($AuthorityNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)

$EcosystemConcentration = "low"
if(@($PrimaryAuthorities).Count -ge 2){ $EcosystemConcentration = "medium" }
if((@($PrimaryAuthorities).Count -eq 1) -and (@($SecondaryAuthorities).Count -le 1)){ $EcosystemConcentration = "high" }

$AdoptionMaturity = "emerging"
$HighSignals = @($Ranked | Where-Object { [int]$_.confidence -ge 90 }).Count
if($HighSignals -ge 6){ $AdoptionMaturity = "established" }
elseif($HighSignals -ge 3){ $AdoptionMaturity = "developing" }

$LockInSignals = @()
if($AuthorityNames -contains "supabase"){ $LockInSignals = Add-Unique $LockInSignals "supabase_platform_lock_in" }
if($AuthorityNames -contains "postgres"){ $LockInSignals = Add-Unique $LockInSignals "postgres_data_model_lock_in" }
if($AuthorityNames -contains "github_actions"){ $LockInSignals = Add-Unique $LockInSignals "github_actions_ci_lock_in" }

$Out = [ordered]@{
  schema = "contract_registry.technology_adoption.v1"
  generated_utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  target_repo = $ResolvedRepo
  adoption_maturity = $AdoptionMaturity
  ecosystem_concentration = $EcosystemConcentration
  high_confidence_signal_count = $HighSignals
  technology_signal_count = @($Ranked).Count
  authority_names = $AuthorityNames
  lock_in_signals = $LockInSignals
  technology_signals = $Ranked
}

$Root = Join-Path $ProfileRoot "technology_adoption"
New-Item -ItemType Directory -Force -Path $Root | Out-Null

$OutPath = Join-Path $Root "technology_adoption.json"
Write-Utf8NoBomLf -Path $OutPath -Text ($Out | ConvertTo-Json -Depth 30)

$Report = @()
$Report += "# Contract Registry Technology Adoption"
$Report += ""
$Report += "Repo: $RepoName"
$Report += "Generated UTC: $($Out.generated_utc)"
$Report += ""
$Report += "## Summary"
$Report += "- Adoption maturity: $AdoptionMaturity"
$Report += "- Ecosystem concentration: $EcosystemConcentration"
$Report += "- High confidence signals: $HighSignals"
$Report += ""
$Report += "## Lock-In Signals"
foreach($x in @($LockInSignals)){ $Report += "- $x" }
if(@($LockInSignals).Count -eq 0){ $Report += "- None" }
$Report += ""
$Report += "## Top Technology Signals"
foreach($s in @($Ranked | Select-Object -First 12)){
  $Report += "- $($s.confidence) $($s.name) [$($s.category)]"
}

$ReportPath = Join-Path $Root "technology_adoption_report.md"
Write-Utf8NoBomLf -Path $ReportPath -Text ($Report -join "`n")

$Receipt = [ordered]@{
  schema = "contract_registry.technology_adoption_receipt.v1"
  utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  technology_adoption = $OutPath
  report = $ReportPath
  adoption_maturity = $AdoptionMaturity
  ecosystem_concentration = $EcosystemConcentration
  technology_signal_count = @($Ranked).Count
}

$ReceiptPath = Join-Path $Root "technology_adoption_receipt.json"
Write-Utf8NoBomLf -Path $ReceiptPath -Text ($Receipt | ConvertTo-Json -Depth 20)

Write-Host "CR_TECHNOLOGY_ADOPTION_OK" -ForegroundColor Green
Write-Host ("TECHNOLOGY_ADOPTION: " + $OutPath)
Write-Host ("REPORT: " + $ReportPath)
Write-Host ("RECEIPT: " + $ReceiptPath)
Write-Host ("ADOPTION_MATURITY: " + $AdoptionMaturity)
Write-Host ("ECOSYSTEM_CONCENTRATION: " + $EcosystemConcentration)
Write-Host ("TECHNOLOGY_SIGNAL_COUNT: " + @($Ranked).Count)

foreach($s in @($Ranked | Select-Object -First 8)){
  Write-Host ("TECH_SIGNAL: " + $s.confidence + " " + $s.name + " [" + $s.category + "]")
}