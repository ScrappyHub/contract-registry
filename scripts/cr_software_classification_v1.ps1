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

function Add-Score {
  param(
    [hashtable]$Scores,
    [string]$Class,
    [int]$Points
  )

  if(-not $Scores.ContainsKey($Class)){ $Scores[$Class] = 0 }
  $Scores[$Class] += $Points
}

if(-not (Test-Path -LiteralPath $TargetRepo -PathType Container)){
  throw "TARGET_REPO_NOT_FOUND: $TargetRepo"
}

$RepoName = Split-Path -Leaf (Resolve-Path -LiteralPath $TargetRepo)
$ProfileRoot = Join-Path $TargetRepo ("runtime\shadow_profiles\" + $RepoName)

$IdentityPath = Join-Path $ProfileRoot "identity\repo_identity.json"
$IntelPath = Join-Path $ProfileRoot "intelligence\intelligence.json"

$Identity = Read-JsonSafe -Path $IdentityPath
$Intel = Read-JsonSafe -Path $IntelPath

if($null -eq $Identity){ throw "REPO_IDENTITY_NOT_FOUND_RUN_CR_RUN_FIRST" }
if($null -eq $Intel){ throw "INTELLIGENCE_NOT_FOUND_RUN_CR_RUN_FIRST" }

$Scores = @{}

$Archetype = [string](Get-Prop -Obj $Identity -Name "archetype" -Default "")
$Capabilities = @(Get-Prop -Obj $Identity -Name "capabilities" -Default @())
$Ecosystems = @(Get-Prop -Obj $Identity -Name "ecosystems" -Default @())
$Surfaces = @(Get-Prop -Obj $Identity -Name "runtime_surfaces" -Default @())
$Signals = Get-Prop -Obj $Intel -Name "latest_signals" -Default $null
$TopExtensions = @(Get-Prop -Obj $Intel -Name "top_extensions" -Default @())

if($Archetype -eq "supabase_governed_platform"){
  Add-Score -Scores $Scores -Class "governance_platform" -Points 45
  Add-Score -Scores $Scores -Class "database_centric_application" -Points 25
  Add-Score -Scores $Scores -Class "developer_tooling" -Points 15
}

if($Capabilities -contains "schema_or_database"){
  Add-Score -Scores $Scores -Class "database_centric_application" -Points 25
  Add-Score -Scores $Scores -Class "governance_platform" -Points 15
}

if($Capabilities -contains "api"){
  Add-Score -Scores $Scores -Class "service_application" -Points 20
  Add-Score -Scores $Scores -Class "governance_platform" -Points 10
}

if($Capabilities -contains "supabase"){
  Add-Score -Scores $Scores -Class "database_centric_application" -Points 20
  Add-Score -Scores $Scores -Class "governance_platform" -Points 15
}

if($Capabilities -contains "ci"){
  Add-Score -Scores $Scores -Class "developer_tooling" -Points 10
  Add-Score -Scores $Scores -Class "infrastructure_platform" -Points 10
}

if($Signals){
  $SchemaCandidates = @(Get-Prop -Obj $Signals -Name "schema_candidates" -Default @())
  $ApiCandidates = @(Get-Prop -Obj $Signals -Name "api_candidates" -Default @())

  if(@($SchemaCandidates).Count -gt 10){
    Add-Score -Scores $Scores -Class "governance_platform" -Points 15
    Add-Score -Scores $Scores -Class "protocol_or_contract_system" -Points 20
  }

  if(@($ApiCandidates).Count -gt 0){
    Add-Score -Scores $Scores -Class "service_application" -Points 15
  }
}

foreach($e in @($TopExtensions)){
  $Ext = [string](Get-Prop -Obj $e -Name "extension" -Default "")
  $Count = [int](Get-Prop -Obj $e -Name "count" -Default 0)

  if($Ext -eq ".ps1" -and $Count -gt 25){
    Add-Score -Scores $Scores -Class "developer_tooling" -Points 20
    Add-Score -Scores $Scores -Class "automation_system" -Points 20
  }

  if($Ext -eq ".sql" -and $Count -gt 5){
    Add-Score -Scores $Scores -Class "database_centric_application" -Points 15
  }

  if($Ext -eq ".sig" -and $Count -gt 5){
    Add-Score -Scores $Scores -Class "protocol_or_contract_system" -Points 15
  }
}

if($Scores.Count -eq 0){
  Add-Score -Scores $Scores -Class "unknown_software" -Points 10
}

$Ranked = @(
  $Scores.GetEnumerator() |
    Sort-Object Value -Descending |
    ForEach-Object {
      [pscustomobject]@{
        class = $_.Key
        score = $_.Value
      }
    }
)

$Top = $Ranked | Select-Object -First 1
$Class = [string]$Top.class
$Confidence = [Math]::Min(99, [int]$Top.score)

$Out = [ordered]@{
  schema = "contract_registry.software_classification.v1"
  generated_utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  target_repo = (Resolve-Path -LiteralPath $TargetRepo).Path
  software_class = $Class
  confidence = $Confidence
  candidates = $Ranked
  evidence = [ordered]@{
    archetype = $Archetype
    capabilities = $Capabilities
    ecosystems = $Ecosystems
    runtime_surfaces = $Surfaces
  }
}

$ClassRoot = Join-Path $ProfileRoot "classification"
New-Item -ItemType Directory -Force -Path $ClassRoot | Out-Null

$ClassPath = Join-Path $ClassRoot "software_classification.json"
Write-Utf8NoBomLf -Path $ClassPath -Text ($Out | ConvertTo-Json -Depth 30)

$Report = @()
$Report += "# Contract Registry Software Classification"
$Report += ""
$Report += "Repo: $RepoName"
$Report += "Generated UTC: $($Out.generated_utc)"
$Report += ""
$Report += "## Primary Classification"
$Report += "- Software class: $Class"
$Report += "- Confidence: $Confidence"
$Report += ""
$Report += "## Candidates"
foreach($c in @($Ranked)){
  $Report += "- $($c.class): $($c.score)"
}

$ReportPath = Join-Path $ClassRoot "software_classification_report.md"
Write-Utf8NoBomLf -Path $ReportPath -Text ($Report -join "`n")

$Receipt = [ordered]@{
  schema = "contract_registry.software_classification_receipt.v1"
  utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  classification = $ClassPath
  report = $ReportPath
  software_class = $Class
  confidence = $Confidence
}

$ReceiptPath = Join-Path $ClassRoot "software_classification_receipt.json"
Write-Utf8NoBomLf -Path $ReceiptPath -Text ($Receipt | ConvertTo-Json -Depth 20)

Write-Host "CR_SOFTWARE_CLASSIFICATION_OK" -ForegroundColor Green
Write-Host ("CLASSIFICATION: " + $ClassPath)
Write-Host ("REPORT: " + $ReportPath)
Write-Host ("RECEIPT: " + $ReceiptPath)
Write-Host ("SOFTWARE_CLASS: " + $Class)
Write-Host ("CONFIDENCE: " + $Confidence)