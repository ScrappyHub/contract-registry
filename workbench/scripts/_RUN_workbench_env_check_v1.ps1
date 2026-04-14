param(
  [Parameter(Mandatory=$true)][string]$Workspace
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "..\engine\_lib_workbench_v1.ps1")

Test-WorkbenchEnvironment -Workspace $Workspace

Write-Host "WORKBENCH_ENV_CHECK_OK"