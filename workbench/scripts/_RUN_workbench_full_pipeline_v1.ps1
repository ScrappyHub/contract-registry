param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$Workspace
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Step {
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][string]$Script,
    [Parameter(Mandatory=$true)][hashtable]$StepArgs
  )

  Write-Host ("STEP_START: " + $Name)

  $argList = New-Object System.Collections.Generic.List[string]
  [void]$argList.Add("-NoProfile")
  [void]$argList.Add("-NonInteractive")
  [void]$argList.Add("-ExecutionPolicy")
  [void]$argList.Add("Bypass")
  [void]$argList.Add("-File")
  [void]$argList.Add($Script)

  foreach($k in ($StepArgs.Keys | Sort-Object)){
    [void]$argList.Add("-" + [string]$k)
    [void]$argList.Add([string]$StepArgs[$k])
  }

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "powershell.exe"
  $psi.Arguments = [string]::Join(' ', ($argList | ForEach-Object {
    if($_ -match '\s'){ '"' + $_.Replace('"','\"') + '"' } else { $_ }
  }))
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.UseShellExecute = $false

  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi

  [void]$p.Start()

  $stdout = $p.StandardOutput.ReadToEnd()
  $stderr = $p.StandardError.ReadToEnd()

  $p.WaitForExit()

  if($stdout){ $stdout | Out-Host }
  if($stderr){ $stderr | Out-Host }

  if($p.ExitCode -ne 0){
    throw ("STEP_FAILED: " + $Name)
  }

  Write-Host ("STEP_OK: " + $Name)
}

$ScriptsDir = Join-Path $RepoRoot "workbench\scripts"

$InspectScript = Join-Path $ScriptsDir "_RUN_workbench_contract_inspect_v1.ps1"
$BuildScript   = Join-Path $ScriptsDir "_RUN_workbench_release_build_v1.ps1"
$VerifyScript  = Join-Path $ScriptsDir "_RUN_workbench_release_verify_v1.ps1"
$ExportScript  = Join-Path $ScriptsDir "_RUN_workbench_evidence_export_v1.ps1"

foreach($p in @($InspectScript,$BuildScript,$VerifyScript,$ExportScript)){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){
    throw ("PIPELINE_SCRIPT_MISSING: " + $p)
  }
}

Invoke-Step -Name "inspect" -Script $InspectScript -StepArgs @{
  Workspace = $Workspace
}

Invoke-Step -Name "build" -Script $BuildScript -StepArgs @{
  Workspace = $Workspace
}

$ReleaseRoot = Join-Path $Workspace "output\releases"
if(-not (Test-Path -LiteralPath $ReleaseRoot -PathType Container)){
  throw "RELEASE_ROOT_NOT_FOUND"
}

$LatestRelease = Get-ChildItem -LiteralPath $ReleaseRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1
if(-not $LatestRelease){
  throw "RELEASE_DIR_NOT_FOUND"
}

$ReleaseDir = $LatestRelease.FullName
Write-Host ("LATEST_RELEASE: " + $ReleaseDir)

Invoke-Step -Name "verify" -Script $VerifyScript -StepArgs @{
  ReleaseDir = $ReleaseDir
}

$ExportRoot = Join-Path $Workspace "output\exports"

Invoke-Step -Name "export" -Script $ExportScript -StepArgs @{
  ReleaseDir = $ReleaseDir
  ExportRoot = $ExportRoot
}

Write-Host "WORKBENCH_FULL_PIPELINE_GREEN"