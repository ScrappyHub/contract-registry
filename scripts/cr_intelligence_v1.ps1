param(
  [Parameter(Mandatory=$true)]
  [string]$TargetRepo,

  [int]$Days = 7
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

function Read-JsonFileSafe {
  param([string]$Path)
  if(-not (Test-Path -LiteralPath $Path)){ return $null }
  try { return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json) } catch { return $null }
}

function Read-NdjsonSafe {
  param([string]$Path)
  $Items = @()
  if(-not (Test-Path -LiteralPath $Path)){ return $Items }

  foreach($LineRaw in @(Get-Content -LiteralPath $Path)){
    $Line = ([string]$LineRaw).Trim()
    if([string]::IsNullOrWhiteSpace($Line)){ continue }
    if(-not $Line.StartsWith("{")){ continue }

    try { $Items += ($Line | ConvertFrom-Json) } catch { continue }
  }

  return $Items
}

function Get-PropArray {
  param($Obj,[string]$Name)

  if($null -eq $Obj){ return @() }

  $Prop = $Obj.PSObject.Properties[$Name]

  if($null -eq $Prop){ return @() }

  return @($Prop.Value)
}

function Count-ByValue {
  param([object[]]$Values)

  $Map = @{}
  foreach($v in @($Values)){
    $s = [string]$v
    if([string]::IsNullOrWhiteSpace($s)){ continue }
    if(-not $Map.ContainsKey($s)){ $Map[$s] = 0 }
    $Map[$s]++
  }

  return $Map.GetEnumerator() |
    Sort-Object Value -Descending |
    ForEach-Object {
      [pscustomobject]@{
        value = $_.Key
        count = $_.Value
      }
    }
}

if(-not (Test-Path -LiteralPath $TargetRepo -PathType Container)){
  throw "TARGET_REPO_NOT_FOUND: $TargetRepo"
}

$RepoName = Split-Path -Leaf (Resolve-Path -LiteralPath $TargetRepo)
$ProfileRoot = Join-Path $TargetRepo ("runtime\shadow_profiles\" + $RepoName)
$SnapshotRoot = Join-Path $ProfileRoot "snapshots"
$ReceiptPath = Join-Path $ProfileRoot "receipts\shadow_profile.ndjson"
$TimelinePath = Join-Path $TargetRepo "runtime\watch\timeline\watch_timeline.ndjson"
$IntelRoot = Join-Path $ProfileRoot "intelligence"

New-Item -ItemType Directory -Force -Path $IntelRoot | Out-Null

$SinceUtc = [DateTime]::UtcNow.AddDays(-1 * $Days)

$Snapshots = @()
if(Test-Path -LiteralPath $SnapshotRoot){
  $Snapshots = Get-ChildItem -LiteralPath $SnapshotRoot -Filter "*.snapshot.json" -File |
    Sort-Object Name
}

$Diffs = @()
if(Test-Path -LiteralPath $SnapshotRoot){
  $Diffs = Get-ChildItem -LiteralPath $SnapshotRoot -Filter "*.diff.json" -File |
    Sort-Object Name
}

$ReceiptItems = Read-NdjsonSafe -Path $ReceiptPath
$TimelineItems = Read-NdjsonSafe -Path $TimelinePath

$RecentReceipts = @(
  $ReceiptItems | Where-Object {
    try { [DateTime]$_.utc -ge $SinceUtc } catch { $false }
  }
)

$RecentEvents = @(
  $TimelineItems | Where-Object {
    try { [DateTime]$_.utc -ge $SinceUtc } catch { $false }
  }
)

$RecentDiffs = @()
foreach($d in @($Diffs)){
  $obj = Read-JsonFileSafe -Path $d.FullName
  if($null -eq $obj){ continue }
  try {
    if([DateTime]$obj.utc -ge $SinceUtc){
      $RecentDiffs += $obj
    }
  } catch {}
}

$LatestSnapshotFile = $Snapshots | Select-Object -Last 1
$LatestSnapshot = $null
if($LatestSnapshotFile){
  $LatestSnapshot = Read-JsonFileSafe -Path $LatestSnapshotFile.FullName
}

$RiskScores = @()
$Severities = @()
foreach($r in @($RecentReceipts)){
  $RiskScores += [int]$r.risk_score
  $Severities += [string]$r.severity
}

$MaxRisk = 0
$AvgRisk = 0
if(@($RiskScores).Count -gt 0){
  $MaxRisk = ($RiskScores | Measure-Object -Maximum).Maximum
  $AvgRisk = [Math]::Round(($RiskScores | Measure-Object -Average).Average,2)
}

$TotalAdded = 0
$TotalDeleted = 0
$TotalChanged = 0
$TotalDependencyDrift = 0
$TotalCriticalDeleted = 0
$RiskNotes = @()

foreach($d in @($RecentDiffs)){
  $TotalAdded += @(Get-PropArray -Obj $d -Name "added").Count
  $TotalDeleted += @(Get-PropArray -Obj $d -Name "deleted").Count
  $TotalChanged += @(Get-PropArray -Obj $d -Name "changed").Count
  $TotalDependencyDrift += @(Get-PropArray -Obj $d -Name "dependency_files_changed").Count
  $TotalCriticalDeleted += @(Get-PropArray -Obj $d -Name "critical_files_deleted").Count
  $RiskNotes += @(Get-PropArray -Obj $d -Name "risk_notes")
}

$SignalSnapshot = @{}
if($LatestSnapshot -and $LatestSnapshot.signals){
  foreach($p in $LatestSnapshot.signals.PSObject.Properties){
    $SignalSnapshot[$p.Name] = $p.Value
  }
}

$Extensions = @()
if($LatestSnapshot -and $LatestSnapshot.extensions){
  foreach($p in $LatestSnapshot.extensions.PSObject.Properties){
    $Extensions += [pscustomobject]@{
      extension = $p.Name
      count = $p.Value
    }
  }
  $Extensions = $Extensions | Sort-Object count -Descending
}

$ChangeEvents = @($RecentEvents | Where-Object { $_.changed -eq $true })
$StableEvents = @($RecentEvents | Where-Object { $_.changed -eq $false })

$ActivityLevel = "none"
$TotalActivity = $TotalAdded + $TotalDeleted + $TotalChanged
if($TotalActivity -gt 200){ $ActivityLevel = "high" }
elseif($TotalActivity -gt 30){ $ActivityLevel = "medium" }
elseif($TotalActivity -gt 0){ $ActivityLevel = "low" }

$RiskTrend = "stable"
if(@($RiskScores).Count -ge 2){
  $First = [int]$RiskScores[0]
  $Last = [int]$RiskScores[@($RiskScores).Count - 1]
  if($Last -gt $First){ $RiskTrend = "increasing" }
  elseif($Last -lt $First){ $RiskTrend = "decreasing" }
}

$Recommendations = @()
if($MaxRisk -ge 60){ $Recommendations += "High risk posture detected. Require admin review before release." }
elseif($MaxRisk -ge 30){ $Recommendations += "Medium risk posture detected. Review drift before release." }

if($TotalDependencyDrift -gt 0){ $Recommendations += "Dependency drift detected. Review package manager and lockfile changes." }
if($TotalCriticalDeleted -gt 0){ $Recommendations += "Critical project/governance file deletion detected. Review immediately." }
if($SignalSnapshot["api_candidates"] -and @($SignalSnapshot["api_candidates"]).Count -gt 0){ $Recommendations += "API/server candidates exist. Review exposed surfaces." }
if($SignalSnapshot["schema_candidates"] -and @($SignalSnapshot["schema_candidates"]).Count -gt 0){ $Recommendations += "Schema/database candidates exist. Review data model drift." }
if(@($Recommendations).Count -eq 0){ $Recommendations += "No elevated recommendations. Continue monitoring." }

$Intel = [ordered]@{
  schema = "contract_registry.shadow_intelligence.v1"
  generated_utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  target_repo = (Resolve-Path -LiteralPath $TargetRepo).Path
  window_days = $Days
  snapshot_count_total = @($Snapshots).Count
  diff_count_total = @($Diffs).Count
  recent_diff_count = @($RecentDiffs).Count
  watch_tick_count = @($RecentEvents).Count
  semantic_change_tick_count = @($ChangeEvents).Count
  stable_tick_count = @($StableEvents).Count
  latest_file_count = if($LatestSnapshot){ $LatestSnapshot.file_count } else { 0 }
  activity_level = $ActivityLevel
  total_added = $TotalAdded
  total_deleted = $TotalDeleted
  total_changed = $TotalChanged
  dependency_drift_count = $TotalDependencyDrift
  critical_deletion_count = $TotalCriticalDeleted
  max_risk_score = $MaxRisk
  avg_risk_score = $AvgRisk
  risk_trend = $RiskTrend
  severity_distribution = @(Count-ByValue -Values $Severities)
  top_extensions = @($Extensions | Select-Object -First 12)
  latest_signals = $SignalSnapshot
  top_risk_notes = @(Count-ByValue -Values $RiskNotes | Select-Object -First 10)
  recommendations = $Recommendations
}

$IntelPath = Join-Path $IntelRoot "intelligence.json"
Write-Utf8NoBomLf -Path $IntelPath -Text ($Intel | ConvertTo-Json -Depth 30)

$Report = @()
$Report += "# Contract Registry Shadow Intelligence Report"
$Report += ""
$Report += "Repo: $RepoName"
$Report += "Generated UTC: $($Intel.generated_utc)"
$Report += "Window: last $Days days"
$Report += ""
$Report += "## Executive Summary"
$Report += "- Activity level: $ActivityLevel"
$Report += "- Risk trend: $RiskTrend"
$Report += "- Max risk score: $MaxRisk"
$Report += "- Average risk score: $AvgRisk"
$Report += "- Semantic change ticks: $(@($ChangeEvents).Count)"
$Report += "- Stable ticks: $(@($StableEvents).Count)"
$Report += "- Latest file count: $($Intel.latest_file_count)"
$Report += ""
$Report += "## Change Volume"
$Report += "- Added files: $TotalAdded"
$Report += "- Deleted files: $TotalDeleted"
$Report += "- Changed files: $TotalChanged"
$Report += "- Dependency drift count: $TotalDependencyDrift"
$Report += "- Critical deletion count: $TotalCriticalDeleted"
$Report += ""
$Report += "## Top Extensions"
foreach($e in @($Extensions | Select-Object -First 12)){
  $Report += "- $($e.extension): $($e.count)"
}
$Report += ""
$Report += "## Risk Notes"
foreach($n in @($Intel.top_risk_notes)){
  $Report += "- $($n.value): $($n.count)"
}
if(@($Intel.top_risk_notes).Count -eq 0){ $Report += "- None" }
$Report += ""
$Report += "## Recommendations"
foreach($r in @($Recommendations)){ $Report += "- $r" }

$ReportPath = Join-Path $IntelRoot "weekly_intelligence_report.md"
Write-Utf8NoBomLf -Path $ReportPath -Text ($Report -join "`n")

$Receipt = [ordered]@{
  schema = "contract_registry.shadow_intelligence_receipt.v1"
  utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  intelligence = $IntelPath
  report = $ReportPath
  max_risk_score = $MaxRisk
  activity_level = $ActivityLevel
  risk_trend = $RiskTrend
}

$ReceiptPath = Join-Path $IntelRoot "intelligence_receipt.json"
Write-Utf8NoBomLf -Path $ReceiptPath -Text ($Receipt | ConvertTo-Json -Depth 20)

Write-Host "CR_INTELLIGENCE_OK" -ForegroundColor Green
Write-Host ("INTELLIGENCE: " + $IntelPath)
Write-Host ("REPORT: " + $ReportPath)
Write-Host ("RECEIPT: " + $ReceiptPath)