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

function Add-Unique {
  param([array]$Items,[string]$Value)
  if([string]::IsNullOrWhiteSpace($Value)){ return @($Items) }
  return @($Items + $Value | Sort-Object -Unique)
}

if(-not (Test-Path -LiteralPath $TargetRepo -PathType Container)){
  throw "TARGET_REPO_NOT_FOUND: $TargetRepo"
}

$ResolvedRepo = (Resolve-Path -LiteralPath $TargetRepo).Path
$RepoName = Split-Path -Leaf $ResolvedRepo
$ProfileRoot = Join-Path $ResolvedRepo ("runtime\shadow_profiles\" + $RepoName)

$Identity = Read-JsonSafe -Path (Join-Path $ProfileRoot "identity\repo_identity.json")
$CapabilityGraph = Read-JsonSafe -Path (Join-Path $ProfileRoot "capabilities\capability_graph.json")
$Intelligence = Read-JsonSafe -Path (Join-Path $ProfileRoot "intelligence\intelligence.json")

$Languages = @()
$PackageManagers = @()
$ExternalPlatforms = @()
$RuntimeDependencies = @()
$CriticalDependencies = @()
$TrustSurface = @()

$Files = Get-ChildItem -LiteralPath $ResolvedRepo -Recurse -File -Force |
  Where-Object {
    $_.FullName -notmatch '\\\.git\\' -and
    $_.FullName -notmatch '\\runtime\\'
  }

foreach($f in @($Files)){
  $Rel = $f.FullName.Substring($ResolvedRepo.Length).TrimStart('\','/').Replace('\','/').ToLowerInvariant()
  $Name = $f.Name.ToLowerInvariant()
  $Ext = $f.Extension.ToLowerInvariant()

  switch($Ext){
    ".ps1" { $Languages = Add-Unique $Languages "powershell" }
    ".psm1" { $Languages = Add-Unique $Languages "powershell" }
    ".sql" { $Languages = Add-Unique $Languages "sql" }
    ".js" { $Languages = Add-Unique $Languages "javascript" }
    ".jsx" { $Languages = Add-Unique $Languages "javascript" }
    ".ts" { $Languages = Add-Unique $Languages "typescript" }
    ".tsx" { $Languages = Add-Unique $Languages "typescript" }
    ".json" { }
    ".yml" { $Languages = Add-Unique $Languages "yaml" }
    ".yaml" { $Languages = Add-Unique $Languages "yaml" }
  }

  switch($Name){
    "package.json" {
      $PackageManagers = Add-Unique $PackageManagers "npm"
      $RuntimeDependencies = Add-Unique $RuntimeDependencies "nodejs"
    }
    "pnpm-lock.yaml" { $PackageManagers = Add-Unique $PackageManagers "pnpm" }
    "yarn.lock" { $PackageManagers = Add-Unique $PackageManagers "yarn" }
    "package-lock.json" { $PackageManagers = Add-Unique $PackageManagers "npm" }
    "requirements.txt" {
      $PackageManagers = Add-Unique $PackageManagers "pip"
      $RuntimeDependencies = Add-Unique $RuntimeDependencies "python"
    }
    "pyproject.toml" {
      $PackageManagers = Add-Unique $PackageManagers "python"
      $RuntimeDependencies = Add-Unique $RuntimeDependencies "python"
    }
    "dockerfile" {
      $RuntimeDependencies = Add-Unique $RuntimeDependencies "container_runtime"
      $ExternalPlatforms = Add-Unique $ExternalPlatforms "docker"
    }
  }

  if($Rel -like ".github/workflows/*"){
    $ExternalPlatforms = Add-Unique $ExternalPlatforms "github_actions"
    $TrustSurface = Add-Unique $TrustSurface "ci_workflows"
  }

  if($Rel -like "supabase/*" -or $Rel -like "*supabase*"){
    $ExternalPlatforms = Add-Unique $ExternalPlatforms "supabase"
    $RuntimeDependencies = Add-Unique $RuntimeDependencies "postgres"
    $RuntimeDependencies = Add-Unique $RuntimeDependencies "supabase"
    $CriticalDependencies = Add-Unique $CriticalDependencies "supabase"
    $CriticalDependencies = Add-Unique $CriticalDependencies "postgres"
    $TrustSurface = Add-Unique $TrustSurface "database_schema"
  }

  if($Rel -like "*stripe*"){
    $ExternalPlatforms = Add-Unique $ExternalPlatforms "stripe"
    $CriticalDependencies = Add-Unique $CriticalDependencies "stripe"
    $TrustSurface = Add-Unique $TrustSurface "payments"
  }

  if($Rel -like "*server.js" -or $Rel -like "*api*"){
    $RuntimeDependencies = Add-Unique $RuntimeDependencies "server_runtime"
    $TrustSurface = Add-Unique $TrustSurface "api_surface"
  }
}

if($Identity){
  foreach($e in @(Get-Prop -Obj $Identity -Name "ecosystems" -Default @())){
    if($e -eq "supabase"){ $ExternalPlatforms = Add-Unique $ExternalPlatforms "supabase" }
    if($e -eq "github_actions_or_ci"){ $ExternalPlatforms = Add-Unique $ExternalPlatforms "github_actions" }
    if($e -eq "node_or_server_api"){ $RuntimeDependencies = Add-Unique $RuntimeDependencies "server_runtime" }
  }

  foreach($c in @(Get-Prop -Obj $Identity -Name "capabilities" -Default @())){
    if($c -eq "api"){ $TrustSurface = Add-Unique $TrustSurface "api_surface" }
    if($c -eq "schema_or_database"){ $TrustSurface = Add-Unique $TrustSurface "database_schema" }
  }
}

if($CapabilityGraph){
  foreach($c in @(Get-Prop -Obj $CapabilityGraph -Name "capabilities" -Default @())){
    $Name = [string](Get-Prop -Obj $c -Name "name" -Default "")
    if($Name -eq "signed_artifact_or_receipt_surface"){
      $TrustSurface = Add-Unique $TrustSurface "signed_artifacts"
    }
    if($Name -eq "workflow_automation"){
      $TrustSurface = Add-Unique $TrustSurface "ci_workflows"
    }
  }
}

$OfflinePosture = "mostly_local"
if($ExternalPlatforms -contains "supabase"){ $OfflinePosture = "external_backend_required" }
if(($ExternalPlatforms -contains "supabase") -and ($ExternalPlatforms -contains "stripe")){
  $OfflinePosture = "multiple_external_services_required"
}

$Out = [ordered]@{
  schema = "contract_registry.dependency_intelligence.v1"
  generated_utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  target_repo = $ResolvedRepo
  languages = $Languages
  package_managers = $PackageManagers
  external_platforms = $ExternalPlatforms
  runtime_dependencies = $RuntimeDependencies
  critical_dependencies = $CriticalDependencies
  trust_surface = $TrustSurface
  offline_posture = $OfflinePosture
}

$Root = Join-Path $ProfileRoot "dependencies"
New-Item -ItemType Directory -Force -Path $Root | Out-Null

$OutPath = Join-Path $Root "dependency_intelligence.json"
Write-Utf8NoBomLf -Path $OutPath -Text ($Out | ConvertTo-Json -Depth 30)

$Report = @()
$Report += "# Contract Registry Dependency Intelligence"
$Report += ""
$Report += "Repo: $RepoName"
$Report += "Generated UTC: $($Out.generated_utc)"
$Report += ""
$Report += "## Offline Posture"
$Report += "- $OfflinePosture"
$Report += ""
$Report += "## Languages"
foreach($x in @($Languages)){ $Report += "- $x" }
$Report += ""
$Report += "## Package Managers"
foreach($x in @($PackageManagers)){ $Report += "- $x" }
$Report += ""
$Report += "## External Platforms"
foreach($x in @($ExternalPlatforms)){ $Report += "- $x" }
$Report += ""
$Report += "## Critical Dependencies"
foreach($x in @($CriticalDependencies)){ $Report += "- $x" }
$Report += ""
$Report += "## Trust Surface"
foreach($x in @($TrustSurface)){ $Report += "- $x" }

$ReportPath = Join-Path $Root "dependency_intelligence_report.md"
Write-Utf8NoBomLf -Path $ReportPath -Text ($Report -join "`n")

$Receipt = [ordered]@{
  schema = "contract_registry.dependency_intelligence_receipt.v1"
  utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  dependency_intelligence = $OutPath
  report = $ReportPath
  external_platform_count = @($ExternalPlatforms).Count
  critical_dependency_count = @($CriticalDependencies).Count
  offline_posture = $OfflinePosture
}

$ReceiptPath = Join-Path $Root "dependency_intelligence_receipt.json"
Write-Utf8NoBomLf -Path $ReceiptPath -Text ($Receipt | ConvertTo-Json -Depth 20)

Write-Host "CR_DEPENDENCY_INTELLIGENCE_OK" -ForegroundColor Green
Write-Host ("DEPENDENCIES: " + $OutPath)
Write-Host ("REPORT: " + $ReportPath)
Write-Host ("RECEIPT: " + $ReceiptPath)
Write-Host ("OFFLINE_POSTURE: " + $OfflinePosture)
Write-Host ("EXTERNAL_PLATFORMS: " + (@($ExternalPlatforms) -join ", "))
Write-Host ("CRITICAL_DEPENDENCIES: " + (@($CriticalDependencies) -join ", "))