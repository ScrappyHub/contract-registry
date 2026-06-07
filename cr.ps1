param(
  [Parameter(Position=0)]
  [string]$Command = "help",

  [string]$Intent = "",

  [string]$TargetRepo = (Get-Location).Path,

  [string]$Date = (Get-Date).ToString("yyyy-MM-dd"),

  [int]$IntervalSeconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Show-Help {
  Write-Host "Contract Registry CLI"
  Write-Host ""
  Write-Host "Commands:"
  Write-Host "  help"
  Write-Host "  init -Intent shadow -TargetRepo <path>"
  Write-Host "  init -Intent notify -TargetRepo <path>"
  Write-Host "  run  -TargetRepo <path> [-Date yyyy-MM-dd]"
  Write-Host "  watch -TargetRepo <path> [-IntervalSeconds 60]"
  Write-Host "  status -TargetRepo <path>"
  Write-Host "  notify -TargetRepo <path>"
  Write-Host "  alerts -TargetRepo <path>"
  Write-Host ""
}

function Ensure-Dir {
  param([string]$Path)
  New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Read-JsonSafe {
  param([string]$Path)

  if(-not (Test-Path -LiteralPath $Path)){
    return $null
  }

  try {
    return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json)
  } catch {
    return $null
  }
}

function Read-LastNdjsonSafe {
  param([string]$Path)

  if(-not (Test-Path -LiteralPath $Path)){
    return $null
  }

  $Lines = Get-Content -LiteralPath $Path

  for($i = @($Lines).Count - 1; $i -ge 0; $i--){
    $Line = ([string]$Lines[$i]).Trim()

    if([string]::IsNullOrWhiteSpace($Line)){ continue }
    if(-not $Line.StartsWith("{")){ continue }

    try {
      return ($Line | ConvertFrom-Json)
    } catch {
      continue
    }
  }

  return $null
}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Scripts = Join-Path $Root "scripts"

$PipelineScript = Join-Path $Scripts "cr_pipeline_v1.ps1"
$WatchScript = Join-Path $Scripts "cr_watch_v1.ps1"
$NotifyScript = Join-Path $Scripts "cr_notify_v1.ps1"
$AlertsScript = Join-Path $Scripts "cr_alerts_v1.ps1"

switch($Command.ToLowerInvariant()){
  "help" {
    Show-Help
    exit 0
  }

  "init" {
    $IntentLower = $Intent.ToLowerInvariant()

    if($IntentLower -notin @("shadow","notify")){
      throw "SUPPORTED_INTENT_REQUIRED: shadow|notify"
    }

    if(-not (Test-Path -LiteralPath $TargetRepo -PathType Container)){
      throw "TARGET_REPO_NOT_FOUND: $TargetRepo"
    }

    $RepoName = Split-Path -Leaf (Resolve-Path -LiteralPath $TargetRepo)
    $ProfileRoot = Join-Path $TargetRepo ("runtime\shadow_profiles\" + $RepoName)

    Ensure-Dir (Join-Path $ProfileRoot "snapshots")
    Ensure-Dir (Join-Path $ProfileRoot "reports")
    Ensure-Dir (Join-Path $ProfileRoot "receipts")
    Ensure-Dir (Join-Path $ProfileRoot "daily_reports")
    Ensure-Dir (Join-Path $TargetRepo "runtime\watch\timeline")
    Ensure-Dir (Join-Path $TargetRepo "runtime\pipeline")

    $Config = [ordered]@{
      schema = "contract_registry.shadow_init.v1"
      utc = [DateTime]::UtcNow.ToString("o")
      intent = $IntentLower
      target_repo = (Resolve-Path -LiteralPath $TargetRepo).Path
      profile_root = $ProfileRoot
      pipeline = $PipelineScript
      watch = $WatchScript
      notify = $NotifyScript
    }

    $ConfigPath = Join-Path $ProfileRoot "shadow_config.json"

    [System.IO.File]::WriteAllText(
      $ConfigPath,
      ($Config | ConvertTo-Json -Depth 20),
      [System.Text.UTF8Encoding]::new($false)
    )

    if($IntentLower -eq "shadow"){
      Write-Host "CR_INIT_SHADOW_OK" -ForegroundColor Green
    } else {
      Ensure-Dir (Join-Path $ProfileRoot "alerts")
      Ensure-Dir (Join-Path $ProfileRoot "notify")
      Write-Host "CR_INIT_NOTIFY_OK" -ForegroundColor Green
    }
    Write-Host ("CONFIG: " + $ConfigPath)
    exit 0
  }

  "run" {
    if(-not (Test-Path -LiteralPath $PipelineScript -PathType Leaf)){
      throw "MISSING_PIPELINE_SCRIPT"
    }

    & powershell.exe `
      -NoProfile `
      -NonInteractive `
      -ExecutionPolicy Bypass `
      -File $PipelineScript `
      -TargetRepo $TargetRepo `
      -Date $Date

    exit $LASTEXITCODE
  }

  "status" {
    if(-not (Test-Path -LiteralPath $TargetRepo -PathType Container)){
      throw "TARGET_REPO_NOT_FOUND: $TargetRepo"
    }

    $RepoName = Split-Path -Leaf (Resolve-Path -LiteralPath $TargetRepo)
    $ProfileRoot = Join-Path $TargetRepo ("runtime\shadow_profiles\" + $RepoName)

    $IntelPath = Join-Path $ProfileRoot "intelligence\intelligence.json"
    $IntelReceiptPath = Join-Path $ProfileRoot "intelligence\intelligence_receipt.json"
    $ShadowReceiptPath = Join-Path $ProfileRoot "receipts\shadow_profile.ndjson"
    $PipelineReceiptPath = Join-Path $TargetRepo "runtime\pipeline\cr_pipeline_receipts.ndjson"
    $AlertsPath = Join-Path $ProfileRoot "alerts\alerts.json"
    $AlertsReceiptPath = Join-Path $ProfileRoot "alerts\alerts_receipt.json"

    $Intel = Read-JsonSafe -Path $IntelPath
    $IntelReceipt = Read-JsonSafe -Path $IntelReceiptPath
    $ShadowReceipt = Read-LastNdjsonSafe -Path $ShadowReceiptPath
    $PipelineReceipt = Read-LastNdjsonSafe -Path $PipelineReceiptPath
    $Alerts = Read-JsonSafe -Path $AlertsPath
    $AlertsReceipt = Read-JsonSafe -Path $AlertsReceiptPath

    Write-Host "Contract Registry Status" -ForegroundColor Cyan
    Write-Host ("Repo: " + $RepoName)
    Write-Host ("Target: " + (Resolve-Path -LiteralPath $TargetRepo).Path)
    Write-Host ""

    if($Intel){
      Write-Host "Intelligence" -ForegroundColor Green
      Write-Host ("  activity_level: " + $Intel.activity_level)
      Write-Host ("  risk_trend: " + $Intel.risk_trend)
      Write-Host ("  max_risk_score: " + $Intel.max_risk_score)
      Write-Host ("  avg_risk_score: " + $Intel.avg_risk_score)
      Write-Host ("  semantic_change_ticks: " + $Intel.semantic_change_tick_count)
      Write-Host ("  stable_ticks: " + $Intel.stable_tick_count)
      Write-Host ("  latest_file_count: " + $Intel.latest_file_count)
      Write-Host ""
    } else {
      Write-Host "Intelligence: missing. Run .\cr.ps1 run first." -ForegroundColor Yellow
      Write-Host ""
    }

    if($ShadowReceipt){
      Write-Host "Latest Shadow Receipt" -ForegroundColor Green
      Write-Host ("  severity: " + $ShadowReceipt.severity)
      Write-Host ("  risk_score: " + $ShadowReceipt.risk_score)
      Write-Host ("  file_count: " + $ShadowReceipt.file_count)
      Write-Host ("  report: " + $ShadowReceipt.report)
      Write-Host ""
    }

    if($IntelReceipt){
      Write-Host "Intelligence Report" -ForegroundColor Green
      Write-Host ("  report: " + $IntelReceipt.report)
      Write-Host ("  receipt: " + $IntelReceiptPath)
      Write-Host ""
    }

    if($Alerts){
      Write-Host "Active Alerts" -ForegroundColor Green
      Write-Host ("  count: " + $Alerts.alert_count)

      foreach($a in @($Alerts.alerts)){
        Write-Host ("  " + $a.severity + " " + $a.code + " :: " + $a.message)
      }

      if($AlertsReceipt){
        Write-Host ("  receipt: " + $AlertsReceiptPath)
      }

      Write-Host ""
    }

    if($PipelineReceipt){
      Write-Host "Pipeline" -ForegroundColor Green
      Write-Host ("  status: " + $PipelineReceipt.status)
      Write-Host ("  receipt: " + $PipelineReceiptPath)
      Write-Host ""
    }

    Write-Host "CR_STATUS_OK" -ForegroundColor Green
    exit 0
  }

  "alerts" {
    if(-not (Test-Path -LiteralPath $AlertsScript -PathType Leaf)){
      throw "MISSING_ALERTS_SCRIPT"
    }

    & powershell.exe `
      -NoProfile `
      -NonInteractive `
      -ExecutionPolicy Bypass `
      -File $AlertsScript `
      -TargetRepo $TargetRepo

    exit $LASTEXITCODE
  }

  "notify" {
    if(-not (Test-Path -LiteralPath $NotifyScript -PathType Leaf)){
      throw "MISSING_NOTIFY_SCRIPT"
    }

    & powershell.exe `
      -NoProfile `
      -NonInteractive `
      -ExecutionPolicy Bypass `
      -File $NotifyScript `
      -TargetRepo $TargetRepo

    exit $LASTEXITCODE
  }

  "watch" {
    if(-not (Test-Path -LiteralPath $WatchScript -PathType Leaf)){
      throw "MISSING_WATCH_SCRIPT"
    }

    & powershell.exe `
      -NoProfile `
      -NonInteractive `
      -ExecutionPolicy Bypass `
      -File $WatchScript `
      -TargetRepo $TargetRepo `
      -IntervalSeconds $IntervalSeconds

    exit $LASTEXITCODE
  }

  default {
    Show-Help
    throw ("UNKNOWN_COMMAND: " + $Command)
  }
}