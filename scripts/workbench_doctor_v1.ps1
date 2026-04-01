Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "_lib_workbench_v1.ps1")

$repoRoot = WB-GetRepoRoot
$runtimeRoot = WB-GetRuntimeRoot
$configPath = WB-GetConfigPath
$cfg = WB-LoadConfig

if(-not (Test-Path -LiteralPath $repoRoot -PathType Container)){ throw ("WB_DOCTOR_REPO_ROOT_MISSING: " + $repoRoot) }
if(-not (Test-Path -LiteralPath $runtimeRoot -PathType Container)){ throw ("WB_DOCTOR_RUNTIME_ROOT_MISSING: " + $runtimeRoot) }
if(-not (Test-Path -LiteralPath $configPath -PathType Leaf)){ throw ("WB_DOCTOR_CONFIG_MISSING: " + $configPath) }

Write-Host ("repo_root=" + $repoRoot)
Write-Host ("runtime_root=" + $runtimeRoot)
Write-Host ("config_path=" + $configPath)
Write-Host ("channel=" + [string]$cfg.channel)
Write-Host "WORKBENCH_DOCTOR_OK"