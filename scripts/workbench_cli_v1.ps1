param(
  [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$Command,
  [Parameter()][string]$ArtifactPath = "",
  [Parameter()][string]$ExpectedSha256 = "",
  [Parameter()][string]$ExpectedFileName = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Require-Leaf([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ throw "MISSING_PATH" }
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ throw ("MISSING_FILE: " + $Path) }
}

function Invoke-ChildPs1 {
  param(
    [Parameter(Mandatory=$true)][string]$ScriptPath,
    [Parameter()][string[]]$ArgumentList = @()
  )

  Require-Leaf $ScriptPath
  $PSExe = (Get-Command powershell.exe -CommandType Application -ErrorAction Stop).Source
  $p = Start-Process -FilePath $PSExe `
    -ArgumentList @("-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",$ScriptPath) + @($ArgumentList) `
    -NoNewWindow -Wait -PassThru
  return [int]$p.ExitCode
}

$ScriptsRoot = $PSScriptRoot

switch ($Command) {
  "help" {
    Write-Host "Commands:"
    Write-Host "  help"
    Write-Host "  doctor"
    Write-Host "  whoami"
    Write-Host "  verify-download -ArtifactPath <path> -ExpectedSha256 <sha256> -ExpectedFileName <name>"
    return
  }

  "doctor" {
    $code = Invoke-ChildPs1 -ScriptPath (Join-Path $ScriptsRoot "workbench_doctor_v1.ps1")
    if($code -ne 0){ throw ("WORKBENCH_DOCTOR_FAILED exit_code=" + $code) }
    return
  }

  "whoami" {
    . (Join-Path $ScriptsRoot "_lib_workbench_v1.ps1")
    $cfg = WB-LoadConfig
    Write-Host ("runtime_root=" + (WB-GetRuntimeRoot))
    Write-Host ("config_path=" + (WB-GetConfigPath))
    Write-Host ("channel=" + [string]$cfg.channel)
    return
  }

  "verify-download" {
    $args = @(
      "-ArtifactPath", $ArtifactPath,
      "-ExpectedSha256", $ExpectedSha256,
      "-ExpectedFileName", $ExpectedFileName
    )
    $code = Invoke-ChildPs1 -ScriptPath (Join-Path $ScriptsRoot "workbench_verify_download_v1.ps1") -ArgumentList $args
    if($code -ne 0){ throw ("WORKBENCH_VERIFY_DOWNLOAD_FAILED exit_code=" + $code) }
    return
  }

  default {
    throw ("WB_UNKNOWN_COMMAND: " + $Command)
  }
}