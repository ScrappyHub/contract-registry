Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Utf8NoBomLf {
  param([string]$Path,[string]$Text)
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function Read-Utf8NoBom {
  param([string]$Path)
  $b = [System.IO.File]::ReadAllBytes($Path)
  $enc = New-Object System.Text.UTF8Encoding($false,$true)
  return $enc.GetString($b)
}

function Get-Sha256HexFromFile {
  param([string]$Path)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $fs = [System.IO.File]::OpenRead($Path)
  try {
    $hash = $sha.ComputeHash($fs)
  } finally {
    $fs.Dispose()
  }
  return ([BitConverter]::ToString($hash) -replace "-","").ToLowerInvariant()
}

function New-WorkbenchWorkspace {
  param([string]$Root)

  if(-not (Test-Path $Root)){
    New-Item -ItemType Directory -Path $Root | Out-Null
  }

  $paths = @(
    "input\contract",
    "input\overlays",
    "output\releases",
    "output\verification",
    "output\exports",
    "receipts",
    "logs",
    "cache"
  )

  foreach($p in $paths){
    $full = Join-Path $Root $p
    if(-not (Test-Path $full)){
      New-Item -ItemType Directory -Path $full -Force | Out-Null
    }
  }

  Write-Host ("WORKBENCH_WORKSPACE_READY: " + $Root)
}

function Test-WorkbenchEnvironment {
  param([string]$Workspace)

  if(-not (Test-Path $Workspace)){
    throw "WORKSPACE_NOT_FOUND"
  }

  $required = @(
    "input",
    "output",
    "receipts",
    "logs"
  )

  foreach($r in $required){
    $p = Join-Path $Workspace $r
    if(-not (Test-Path $p)){
      throw ("WORKSPACE_INVALID_MISSING_" + $r.ToUpper())
    }
  }

  Write-Host "WORKBENCH_ENV_OK"
}