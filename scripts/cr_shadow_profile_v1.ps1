param(
  [Parameter(Mandatory=$true)]
  [string]$TargetRepo,

  [Parameter(Mandatory=$false)]
  [string]$OutRoot = "runtime\shadow_profiles"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Utf8NoBomLf {
  param([string]$Path,[string]$Text)
  $Text = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $Text.EndsWith("`n")){ $Text += "`n" }
  $dir = Split-Path -Parent $Path
  if($dir){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  [IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))
}

function Sha256File {
  param([string]$Path)
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [IO.File]::ReadAllBytes($Path)
    return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-","").ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
}

function To-JsonStable {
  param($Obj)
  return ($Obj | ConvertTo-Json -Depth 20)
}

if(-not (Test-Path -LiteralPath $TargetRepo -PathType Container)){
  throw "TARGET_REPO_NOT_FOUND: $TargetRepo"
}

$RepoName = Split-Path -Leaf (Resolve-Path -LiteralPath $TargetRepo)
$Now = Get-Date -Format "yyyyMMdd_HHmmss"
$Utc = (Get-Date).ToUniversalTime().ToString("o")

$Root = Join-Path (Get-Location) $OutRoot
$ProfileRoot = Join-Path $Root $RepoName
$SnapshotRoot = Join-Path $ProfileRoot "snapshots"
$ReportRoot = Join-Path $ProfileRoot "reports"

New-Item -ItemType Directory -Force -Path $SnapshotRoot,$ReportRoot | Out-Null

$IgnoredParts = @(
  "\.git\",
  "\node_modules\",
  "\dist\",
  "\build\",
  "\.vite\",
  "\runtime\",
  "\workbench\workspace\output\",
  "\workbench\workspace\input\"
)

$Files = Get-ChildItem -LiteralPath $TargetRepo -Recurse -File -Force |
  Where-Object {
    $p = $_.FullName
    foreach($part in $IgnoredParts){
      if($p -like "*$part*"){ return $false }
    }
    return $true
  } |
  Sort-Object FullName

$Inventory = @()

foreach($f in $Files){
  $rel = $f.FullName.Substring((Resolve-Path $TargetRepo).Path.Length).TrimStart("\","/")
  $Inventory += [pscustomobject]@{
    path = ($rel -replace "\\","/")
    size = $f.Length
    sha256 = Sha256File $f.FullName
    modified_utc = $f.LastWriteTimeUtc.ToString("o")
  }
}

$Ext = @{}
foreach($i in $Inventory){
  $e = [IO.Path]::GetExtension($i.path).ToLowerInvariant()
  if([string]::IsNullOrWhiteSpace($e)){ $e = "(none)" }
  if(-not $Ext.ContainsKey($e)){ $Ext[$e] = 0 }
  $Ext[$e]++
}

$Signals = [ordered]@{
  has_package_json = [bool]($Inventory.path -contains "package.json")
  has_docker = [bool]($Inventory.path -contains "Dockerfile" -or $Inventory.path -contains "docker-compose.yml")
  has_supabase = [bool](@($Inventory | Where-Object { $_.path -like "supabase/*" }).Count -gt 0)
  has_github_actions = [bool](@($Inventory | Where-Object { $_.path -like ".github/workflows/*" }).Count -gt 0)
  has_env_example = [bool](@($Inventory | Where-Object { $_.path.ToLowerInvariant() -like "*.env.example" -or $_.path.ToLowerInvariant() -eq ".env.example" }).Count -gt 0)
  has_license = [bool](@($Inventory | Where-Object { (Split-Path $_.path -Leaf).ToLowerInvariant() -in @("license","license.md","license.txt") }).Count -gt 0)
  api_candidates = @($Inventory | Where-Object { $_.path -match "/api/|/routes/|server\.(js|ts)$|controller|endpoint" } | Select-Object -First 50 -ExpandProperty path)
  schema_candidates = @($Inventory | Where-Object { $_.path -match "schema|schemas/|migration|\.sql$" } | Select-Object -First 50 -ExpandProperty path)
}

$Snapshot = [ordered]@{
  schema = "contract_registry.shadow_snapshot.v1"
  utc = $Utc
  repo_name = $RepoName
  target_repo = (Resolve-Path -LiteralPath $TargetRepo).Path
  file_count = $Inventory.Count
  extensions = $Ext
  signals = $Signals
  files = $Inventory
}

$SnapshotJson = To-JsonStable $Snapshot
$SnapshotPath = Join-Path $SnapshotRoot "$Now.snapshot.json"
Write-Utf8NoBomLf $SnapshotPath $SnapshotJson

$Previous = Get-ChildItem -LiteralPath $SnapshotRoot -Filter "*.snapshot.json" -File |
  Where-Object { $_.FullName -ne $SnapshotPath } |
  Sort-Object Name -Descending |
  Select-Object -First 1

$Diff = [ordered]@{
  schema = "contract_registry.shadow_diff.v2"
  utc = $Utc
  previous_snapshot = $null
  current_snapshot = $SnapshotPath
  added = @()
  deleted = @()
  changed = @()
  dependency_files_changed = @()
  critical_files_deleted = @()
  severity = "INFO"
  risk_score = 0
  file_count_delta = 0
  risk_notes = @()
}

if($Previous){
  $PrevObj = Get-Content -Raw -LiteralPath $Previous.FullName | ConvertFrom-Json
  $PrevMap = @{}
  foreach($p in $PrevObj.files){ $PrevMap[$p.path] = $p.sha256 }

  $CurMap = @{}
  foreach($c in $Inventory){ $CurMap[$c.path] = $c.sha256 }

  $Diff.previous_snapshot = $Previous.FullName
  $Diff.file_count_delta = $Inventory.Count - [int]$PrevObj.file_count

  foreach($p in $PrevMap.Keys){
    if(-not $CurMap.ContainsKey($p)){ $Diff.deleted += $p }
  }

  foreach($p in $CurMap.Keys){
    if(-not $PrevMap.ContainsKey($p)){ $Diff.added += $p }
    elseif($PrevMap[$p] -ne $CurMap[$p]){ $Diff.changed += $p }
  }
}

$CriticalNames = @("package.json","package-lock.json","pnpm-lock.yaml","yarn.lock","Dockerfile","docker-compose.yml",".env.example","LICENSE","LICENSE.md","README.md")
$DependencyNames = @("package.json","package-lock.json","pnpm-lock.yaml","yarn.lock","requirements.txt","pyproject.toml","Cargo.toml","Cargo.lock","go.mod","go.sum")

foreach($p in @($Diff.deleted)){
  $leaf = Split-Path $p -Leaf
  if($CriticalNames -contains $leaf){
    $Diff.critical_files_deleted += $p
  }
}

foreach($p in @($Diff.changed + $Diff.added + $Diff.deleted)){
  $leaf = Split-Path $p -Leaf
  if($DependencyNames -contains $leaf){
    $Diff.dependency_files_changed += $p
  }
}

if(-not $Signals.has_license){
  $Diff.risk_notes += "No license file detected."
  $Diff.risk_score += 10
}

if($Signals.has_env_example){
  $Diff.risk_notes += "Environment template detected; review secrets handling."
  $Diff.risk_score += 10
}

if(@($Signals.api_candidates).Count -gt 0){
  $Diff.risk_notes += "API/server candidates detected."
  $Diff.risk_score += 15
}

if(@($Signals.schema_candidates).Count -gt 0){
  $Diff.risk_notes += "Schema/database candidates detected."
  $Diff.risk_score += 15
}

if(@($Diff.dependency_files_changed).Count -gt 0){
  $Diff.risk_notes += "Dependency or package manager files changed."
  $Diff.risk_score += 20
}

if(@($Diff.critical_files_deleted).Count -gt 0){
  $Diff.risk_notes += "Critical project/governance files were deleted."
  $Diff.risk_score += 30
}

if($Diff.risk_score -ge 60){
  $Diff.severity = "HIGH"
} elseif($Diff.risk_score -ge 30){
  $Diff.severity = "MEDIUM"
} elseif($Diff.risk_score -gt 0){
  $Diff.severity = "LOW"
} else {
  $Diff.severity = "INFO"
}

$DiffPath = Join-Path $SnapshotRoot "$Now.diff.json"
Write-Utf8NoBomLf $DiffPath (To-JsonStable $Diff)

$Report = @()
$Report += "# Contract Registry Shadow Report"
$Report += ""
$Report += "Repo: $RepoName"
$Report += "UTC: $Utc"
$Report += "Snapshot: $SnapshotPath"
$Report += ""
$Report += "## Summary"
$Report += "- Files scanned: $($Inventory.Count)"
$Report += "- File count delta: $($Diff.file_count_delta)"
$Report += "- Added: $(@($Diff.added).Count)"
$Report += "- Deleted: $(@($Diff.deleted).Count)"
$Report += "- Changed: $(@($Diff.changed).Count)"
$Report += "- Severity: $($Diff.severity)"
$Report += "- Risk score: $($Diff.risk_score)"
$Report += "- Dependency file changes: $(@($Diff.dependency_files_changed).Count)"
$Report += "- Critical files deleted: $(@($Diff.critical_files_deleted).Count)"
$Report += ""
$Report += "## Signals"
foreach($k in $Signals.Keys){
  if($Signals[$k] -is [array]){
    $Report += "- ${k}: $(@($Signals[$k]).Count)"
  } else {
    $Report += "- ${k}: $($Signals[$k])"
  }
}
$Report += ""
$Report += "## Risk Notes"
if(@($Diff.risk_notes).Count -eq 0){
  $Report += "- None"
} else {
  foreach($r in $Diff.risk_notes){ $Report += "- $r" }
}
$Report += ""
$Report += "## Dependency File Changes"
foreach($x in @($Diff.dependency_files_changed | Select-Object -First 30)){ $Report += "- $x" }
$Report += ""
$Report += "## Critical Files Deleted"
foreach($x in @($Diff.critical_files_deleted | Select-Object -First 30)){ $Report += "- $x" }
$Report += ""
$Report += "## Added Files"
foreach($x in @($Diff.added | Select-Object -First 30)){ $Report += "- $x" }
$Report += ""
$Report += "## Deleted Files"
foreach($x in @($Diff.deleted | Select-Object -First 30)){ $Report += "- $x" }
$Report += ""
$Report += "## Changed Files"
foreach($x in @($Diff.changed | Select-Object -First 30)){ $Report += "- $x" }

$ReportPath = Join-Path $ReportRoot "$Now.shadow_report.md"
Write-Utf8NoBomLf $ReportPath ($Report -join "`n")

Write-Host "CR_SHADOW_PROFILE_OK" -ForegroundColor Green
Write-Host ("SNAPSHOT: " + $SnapshotPath)
Write-Host ("DIFF: " + $DiffPath)
$ReceiptRoot = Join-Path $ProfileRoot "receipts"
New-Item -ItemType Directory -Force -Path $ReceiptRoot | Out-Null
$ReceiptPath = Join-Path $ReceiptRoot "shadow_profile.ndjson"

$Receipt = [ordered]@{
  schema = "contract_registry.shadow_receipt.v1"
  utc = $Utc
  repo_name = $RepoName
  snapshot = $SnapshotPath
  diff = $DiffPath
  report = $ReportPath
  severity = $Diff.severity
  risk_score = $Diff.risk_score
  file_count = $Inventory.Count
}

$ReceiptLine = To-JsonStable $Receipt
Add-Content -LiteralPath $ReceiptPath -Value $ReceiptLine -Encoding UTF8

Write-Host ("REPORT: " + $ReportPath)
Write-Host ("RECEIPT: " + $ReceiptPath)
