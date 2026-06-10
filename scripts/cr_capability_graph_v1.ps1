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
  if(-not (Test-Path -LiteralPath $Path)){ return $null }
  try { return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json) } catch { return $null }
}

function Get-Prop {
  param($Obj,[string]$Name,$Default=$null)
  if($null -eq $Obj){ return $Default }
  $Prop = $Obj.PSObject.Properties[$Name]
  if($null -eq $Prop){ return $Default }
  return $Prop.Value
}

function Add-Capability {
  param(
    [System.Collections.Generic.List[object]]$List,
    [string]$Name,
    [int]$Confidence,
    [string]$Evidence,
    [string]$Source
  )

  $Existing = $List | Where-Object { $_.name -eq $Name } | Select-Object -First 1

  if($Existing){
    if($Confidence -gt $Existing.confidence){ $Existing.confidence = $Confidence }
    $Existing.evidence += $Evidence
    $Existing.sources += $Source
    $Existing.evidence = @($Existing.evidence | Sort-Object -Unique)
    $Existing.sources = @($Existing.sources | Sort-Object -Unique)
    return
  }

  $List.Add([pscustomobject]@{
    name = $Name
    confidence = $Confidence
    evidence = @($Evidence)
    sources = @($Source)
  }) | Out-Null
}

if(-not (Test-Path -LiteralPath $TargetRepo -PathType Container)){
  throw "TARGET_REPO_NOT_FOUND: $TargetRepo"
}

$RepoName = Split-Path -Leaf (Resolve-Path -LiteralPath $TargetRepo)
$ProfileRoot = Join-Path $TargetRepo ("runtime\shadow_profiles\" + $RepoName)

$IdentityPath = Join-Path $ProfileRoot "identity\repo_identity.json"
$IntelPath = Join-Path $ProfileRoot "intelligence\intelligence.json"
$ClassPath = Join-Path $ProfileRoot "classification\software_classification.json"
$LineagePath = Join-Path $ProfileRoot "lineage\lineage.json"

$Identity = Read-JsonSafe -Path $IdentityPath
$Intel = Read-JsonSafe -Path $IntelPath
$Class = Read-JsonSafe -Path $ClassPath
$Lineage = Read-JsonSafe -Path $LineagePath

if($null -eq $Identity){ throw "REPO_IDENTITY_NOT_FOUND_RUN_CR_RUN_FIRST" }
if($null -eq $Intel){ throw "INTELLIGENCE_NOT_FOUND_RUN_CR_RUN_FIRST" }

$Caps = [System.Collections.Generic.List[object]]::new()

$Capabilities = @(Get-Prop -Obj $Identity -Name "capabilities" -Default @())
$Surfaces = @(Get-Prop -Obj $Identity -Name "runtime_surfaces" -Default @())
$Ecosystems = @(Get-Prop -Obj $Identity -Name "ecosystems" -Default @())
$SoftwareClass = [string](Get-Prop -Obj $Identity -Name "software_class" -Default "")
$Archetype = [string](Get-Prop -Obj $Identity -Name "archetype" -Default "")
$Signals = Get-Prop -Obj $Intel -Name "latest_signals" -Default $null
$TopExtensions = @(Get-Prop -Obj $Intel -Name "top_extensions" -Default @())

if($Capabilities -contains "api"){
  Add-Capability -List $Caps -Name "api_surface" -Confidence 95 -Evidence "identity.capabilities.api" -Source $IdentityPath
}

if($Capabilities -contains "schema_or_database"){
  Add-Capability -List $Caps -Name "database_or_schema_governance" -Confidence 97 -Evidence "identity.capabilities.schema_or_database" -Source $IdentityPath
}

if($Capabilities -contains "supabase"){
  Add-Capability -List $Caps -Name "supabase_backend" -Confidence 96 -Evidence "identity.capabilities.supabase" -Source $IdentityPath
}

if($Capabilities -contains "ci"){
  Add-Capability -List $Caps -Name "ci_or_automation" -Confidence 88 -Evidence "identity.capabilities.ci" -Source $IdentityPath
}

if($SoftwareClass -eq "governance_platform"){
  Add-Capability -List $Caps -Name "governance_modeling" -Confidence 96 -Evidence "identity.software_class.governance_platform" -Source $IdentityPath
}

if($Archetype -eq "supabase_governed_platform"){
  Add-Capability -List $Caps -Name "governed_platform_runtime" -Confidence 94 -Evidence "identity.archetype.supabase_governed_platform" -Source $IdentityPath
}

if($Signals){
  $SchemaCandidates = @(Get-Prop -Obj $Signals -Name "schema_candidates" -Default @())
  $ApiCandidates = @(Get-Prop -Obj $Signals -Name "api_candidates" -Default @())

  if(@($SchemaCandidates).Count -gt 0){
    Add-Capability -List $Caps -Name "contract_schema_inventory" -Confidence 92 -Evidence ("schema_candidates=" + @($SchemaCandidates).Count) -Source $IntelPath
  }

  if(@($ApiCandidates).Count -gt 0){
    Add-Capability -List $Caps -Name "server_runtime_surface" -Confidence 90 -Evidence ("api_candidates=" + @($ApiCandidates).Count) -Source $IntelPath
  }

  if([bool](Get-Prop -Obj $Signals -Name "has_github_actions" -Default $false)){
    Add-Capability -List $Caps -Name "workflow_automation" -Confidence 88 -Evidence "has_github_actions=true" -Source $IntelPath
  }
}

foreach($e in @($TopExtensions)){
  $Ext = [string](Get-Prop -Obj $e -Name "extension" -Default "")
  $Count = [int](Get-Prop -Obj $e -Name "count" -Default 0)

  if($Ext -eq ".ps1" -and $Count -gt 25){
    Add-Capability -List $Caps -Name "powershell_automation_tooling" -Confidence 91 -Evidence (".ps1_count=" + $Count) -Source $IntelPath
  }

  if($Ext -eq ".sql" -and $Count -gt 5){
    Add-Capability -List $Caps -Name "database_migration_surface" -Confidence 90 -Evidence (".sql_count=" + $Count) -Source $IntelPath
  }

  if($Ext -eq ".sig" -and $Count -gt 5){
    Add-Capability -List $Caps -Name "signed_artifact_or_receipt_surface" -Confidence 86 -Evidence (".sig_count=" + $Count) -Source $IntelPath
  }
}

$Ranked = @($Caps | Sort-Object confidence -Descending)

$Out = [ordered]@{
  schema = "contract_registry.capability_graph.v1"
  generated_utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  target_repo = (Resolve-Path -LiteralPath $TargetRepo).Path
  capability_count = @($Ranked).Count
  capabilities = $Ranked
}

$Root = Join-Path $ProfileRoot "capabilities"
New-Item -ItemType Directory -Force -Path $Root | Out-Null

$GraphPath = Join-Path $Root "capability_graph.json"
Write-Utf8NoBomLf -Path $GraphPath -Text ($Out | ConvertTo-Json -Depth 30)

$Report = @()
$Report += "# Contract Registry Capability Graph"
$Report += ""
$Report += "Repo: $RepoName"
$Report += "Generated UTC: $($Out.generated_utc)"
$Report += ""
$Report += "## Capabilities"
foreach($c in @($Ranked)){
  $Report += ("- " + $c.name + " - confidence " + $c.confidence)
}

$ReportPath = Join-Path $Root "capability_graph_report.md"
Write-Utf8NoBomLf -Path $ReportPath -Text ($Report -join "`n")

$Receipt = [ordered]@{
  schema = "contract_registry.capability_graph_receipt.v1"
  utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  graph = $GraphPath
  report = $ReportPath
  capability_count = @($Ranked).Count
}

$ReceiptPath = Join-Path $Root "capability_graph_receipt.json"
Write-Utf8NoBomLf -Path $ReceiptPath -Text ($Receipt | ConvertTo-Json -Depth 20)

Write-Host "CR_CAPABILITY_GRAPH_OK" -ForegroundColor Green
Write-Host ("GRAPH: " + $GraphPath)
Write-Host ("REPORT: " + $ReportPath)
Write-Host ("RECEIPT: " + $ReceiptPath)
Write-Host ("CAPABILITY_COUNT: " + @($Ranked).Count)

foreach($c in @($Ranked | Select-Object -First 8)){
  Write-Host ("CAPABILITY: " + $c.confidence + " " + $c.name)
}