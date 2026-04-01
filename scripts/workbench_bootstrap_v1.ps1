param(
  [Parameter()][string]$RuntimeRoot = "C:\ProgramData\ContractRegistryWorkbench"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "_lib_workbench_v1.ps1")

$ConfigDir    = Join-Path $RuntimeRoot "config"
$CacheDir     = Join-Path $RuntimeRoot "cache"
$DownloadsDir = Join-Path $RuntimeRoot "downloads"
$ReceiptsDir  = Join-Path $RuntimeRoot "receipts"
$StateDir     = Join-Path $RuntimeRoot "state"

WB-EnsureDir $RuntimeRoot
WB-EnsureDir $ConfigDir
WB-EnsureDir $CacheDir
WB-EnsureDir $DownloadsDir
WB-EnsureDir $ReceiptsDir
WB-EnsureDir $StateDir

$ConfigPath = Join-Path $ConfigDir "workbench.config.json"
if(-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)){
  $config = @{
    schema = "contract_registry.workbench.config.v1"
    channel = "stable"
    api_base_url = ""
    default_download_dir = $DownloadsDir
    receipts_dir = $ReceiptsDir
    state_dir = $StateDir
  }
  WB-WriteUtf8NoBomLf $ConfigPath (WB-ConvertToCanonicalJson $config)
}

WB-AppendReceipt @{
  schema = "contract_registry.workbench.receipt.v1"
  event_type = "workbench.bootstrap.completed"
  utc = [DateTime]::UtcNow.ToString("o")
  runtime_root = $RuntimeRoot
  config_path = $ConfigPath
}

Write-Host ("WORKBENCH_BOOTSTRAP_OK: " + $RuntimeRoot) -ForegroundColor Green