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
  Write-Host "  run  -TargetRepo <path> [-Date yyyy-MM-dd]"
  Write-Host "  watch -TargetRepo <path> [-IntervalSeconds 60]"
  Write-Host ""
}

function Ensure-Dir {
  param([string]$Path)
  New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Scripts = Join-Path $Root "scripts"

$PipelineScript = Join-Path $Scripts "cr_pipeline_v1.ps1"
$WatchScript = Join-Path $Scripts "cr_watch_v1.ps1"

switch($Command.ToLowerInvariant()){
  "help" {
    Show-Help
    exit 0
  }

  "init" {
    if($Intent.ToLowerInvariant() -ne "shadow"){
      throw "SUPPORTED_INTENT_REQUIRED: shadow"
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
      intent = "shadow"
      target_repo = (Resolve-Path -LiteralPath $TargetRepo).Path
      profile_root = $ProfileRoot
      pipeline = $PipelineScript
      watch = $WatchScript
    }

    $ConfigPath = Join-Path $ProfileRoot "shadow_config.json"

    [System.IO.File]::WriteAllText(
      $ConfigPath,
      ($Config | ConvertTo-Json -Depth 20),
      [System.Text.UTF8Encoding]::new($false)
    )

    Write-Host "CR_INIT_SHADOW_OK" -ForegroundColor Green
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