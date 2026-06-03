param(
  [Parameter(Mandatory=$true)]
  [string]$TargetRepo,

  [Parameter(Mandatory=$false)]
  [string]$Date = (Get-Date).ToString("yyyy-MM-dd")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Utf8NoBomLf {
  param([string]$Path,[string]$Text)

  $Text = ($Text -replace "`r`n","`n") -replace "`r","`n"

  if(-not $Text.EndsWith("`n")){
    $Text += "`n"
  }

  $Parent = Split-Path -Parent $Path

  if($Parent){
    New-Item -ItemType Directory -Force -Path $Parent | Out-Null
  }

  [System.IO.File]::WriteAllText(
    $Path,
    $Text,
    [System.Text.UTF8Encoding]::new($false)
  )
}

function Read-NdjsonSafe {
  param([string]$Path)

  $Items = @()

  if(-not (Test-Path -LiteralPath $Path)){
    return $Items
  }

  $Lines = Get-Content -LiteralPath $Path

  foreach($LineRaw in @($Lines)){
    $Line = ([string]$LineRaw).Trim()

    if([string]::IsNullOrWhiteSpace($Line)){
      continue
    }

    if(-not $Line.StartsWith("{")){
      continue
    }

    try {
      $Items += ($Line | ConvertFrom-Json)
    } catch {
      continue
    }
  }

  return $Items
}

if(-not (Test-Path -LiteralPath $TargetRepo -PathType Container)){
  throw "TARGET_REPO_NOT_FOUND: $TargetRepo"
}

$RepoName = Split-Path -Leaf (Resolve-Path -LiteralPath $TargetRepo)
$ProfileRoot = Join-Path $TargetRepo ("runtime\shadow_profiles\" + $RepoName)
$ReceiptPath = Join-Path $ProfileRoot "receipts\shadow_profile.ndjson"
$TimelinePath = Join-Path $TargetRepo "runtime\watch\timeline\watch_timeline.ndjson"
$DailyRoot = Join-Path $ProfileRoot "daily_reports"

New-Item -ItemType Directory -Force -Path $DailyRoot | Out-Null

$Receipts = Read-NdjsonSafe -Path $ReceiptPath
$Events = Read-NdjsonSafe -Path $TimelinePath

$DayReceipts = @(
  $Receipts | Where-Object {
    ([string]$_.utc).StartsWith($Date)
  }
)

$DayEvents = @(
  $Events | Where-Object {
    ([string]$_.utc).StartsWith($Date)
  }
)

$SeverityOrder = @{
  "INFO" = 0
  "LOW" = 1
  "MEDIUM" = 2
  "HIGH" = 3
  "CRITICAL" = 4
}

$MaxSeverity = "INFO"
$MaxRisk = 0

foreach($r in @($DayReceipts)){
  $sev = [string]$r.severity

  if($SeverityOrder.ContainsKey($sev) -and $SeverityOrder[$sev] -gt $SeverityOrder[$MaxSeverity]){
    $MaxSeverity = $sev
  }

  if([int]$r.risk_score -gt $MaxRisk){
    $MaxRisk = [int]$r.risk_score
  }
}

$ChangeEvents = @($DayEvents | Where-Object { $_.changed -eq $true })
$NoChangeEvents = @($DayEvents | Where-Object { $_.changed -eq $false })

$LatestReceipt = $null
if(@($DayReceipts).Count -gt 0){
  $LatestReceipt = @($DayReceipts)[@($DayReceipts).Count - 1]
}

$Report = @()
$Report += "# Contract Registry Daily Shadow Report"
$Report += ""
$Report += "Repo: $RepoName"
$Report += "Date: $Date"
$Report += "Generated UTC: $([DateTime]::UtcNow.ToString("o"))"
$Report += ""
$Report += "## Executive Summary"
$Report += "- Shadow snapshots today: $(@($DayReceipts).Count)"
$Report += "- Watch ticks today: $(@($DayEvents).Count)"
$Report += "- Change ticks: $(@($ChangeEvents).Count)"
$Report += "- Stable ticks: $(@($NoChangeEvents).Count)"
$Report += "- Max severity: $MaxSeverity"
$Report += "- Max risk score: $MaxRisk"
$Report += ""

if($LatestReceipt){
  $Report += "## Latest State"
  $Report += "- Severity: $($LatestReceipt.severity)"
  $Report += "- Risk score: $($LatestReceipt.risk_score)"
  $Report += "- File count: $($LatestReceipt.file_count)"
  $Report += "- Snapshot: $($LatestReceipt.snapshot)"
  $Report += "- Diff: $($LatestReceipt.diff)"
  $Report += "- Report: $($LatestReceipt.report)"
  $Report += ""
}

$Report += "## Watch Timeline"
foreach($e in @($DayEvents | Select-Object -Last 30)){
  $State = "stable"
  if($e.changed -eq $true){ $State = "changed" }

  $Report += "- $($e.utc) :: $State :: severity=$($e.severity) risk=$($e.risk_score) files=$($e.file_count)"
}

if(@($DayEvents).Count -eq 0){
  $Report += "- No watch events recorded for this date."
}

$Report += ""
$Report += "## Operational Notes"

if(@($ChangeEvents).Count -gt 0){
  $Report += "- Change activity detected today."
} else {
  $Report += "- No semantic change activity detected today."
}

if($MaxRisk -ge 60){
  $Report += "- High risk posture. Review before release."
} elseif($MaxRisk -ge 30){
  $Report += "- Medium risk posture. Review important drift before release."
} elseif($MaxRisk -gt 0){
  $Report += "- Low risk posture. Continue monitoring."
} else {
  $Report += "- No risk notes detected."
}

$ReportPath = Join-Path $DailyRoot ($Date + ".daily_shadow_report.md")

Write-Utf8NoBomLf -Path $ReportPath -Text ($Report -join "`n")

$Receipt = [ordered]@{
  schema = "contract_registry.daily_report_receipt.v1"
  utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  date = $Date
  report = $ReportPath
  shadow_snapshot_count = @($DayReceipts).Count
  watch_tick_count = @($DayEvents).Count
  change_tick_count = @($ChangeEvents).Count
  stable_tick_count = @($NoChangeEvents).Count
  max_severity = $MaxSeverity
  max_risk_score = $MaxRisk
}

$ReceiptPathOut = Join-Path $DailyRoot ($Date + ".daily_report_receipt.json")
Write-Utf8NoBomLf -Path $ReceiptPathOut -Text ($Receipt | ConvertTo-Json -Depth 20)

Write-Host "CR_DAILY_REPORT_OK" -ForegroundColor Green
Write-Host ("REPORT: " + $ReportPath)
Write-Host ("RECEIPT: " + $ReceiptPathOut)