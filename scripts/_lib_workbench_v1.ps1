Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function WB-GetRepoRoot {
  $root = Split-Path -Parent $PSScriptRoot
  if([string]::IsNullOrWhiteSpace($root)){ throw "WB_REPO_ROOT_EMPTY" }
  return $root
}

function WB-GetRuntimeRoot {
  $root = Join-Path (WB-GetRepoRoot) "_runtime_local\workbench"
  return $root
}

function WB-GetConfigPath {
  return (Join-Path (WB-GetRuntimeRoot) "config.json")
}

function WB-EnsureDir([string]$Path) {
  if([string]::IsNullOrWhiteSpace($Path)){ throw "WB_ENSUREDIR_EMPTY" }
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function WB-WriteUtf8NoBomLf([string]$Path,[string]$Text) {
  $dir = Split-Path -Parent $Path
  if(-not [string]::IsNullOrWhiteSpace($dir)){ WB-EnsureDir $dir }
  $lf = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $lf.EndsWith("`n")){ $lf += "`n" }
  [System.IO.File]::WriteAllText($Path,$lf,[System.Text.UTF8Encoding]::new($false))
}

function WB-ReadUtf8NoBom([string]$Path) {
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ throw ("WB_MISSING_FILE: " + $Path) }
  return [System.IO.File]::ReadAllText($Path,[System.Text.UTF8Encoding]::new($false))
}

function WB-ConvertToJsonDeterministic([object]$InputObject) {
  return ($InputObject | ConvertTo-Json -Depth 32 -Compress)
}

function WB-GetDefaultConfig {
  return [ordered]@{
    schema = "contract_registry.workbench.config.v1"
    channel = "stable"
  }
}

function WB-LoadConfig {
  $runtime = WB-GetRuntimeRoot
  WB-EnsureDir $runtime
  $cfgPath = WB-GetConfigPath

  if(-not (Test-Path -LiteralPath $cfgPath -PathType Leaf)){
    $json = WB-ConvertToJsonDeterministic (WB-GetDefaultConfig)
    WB-WriteUtf8NoBomLf $cfgPath $json
  }

  $raw = WB-ReadUtf8NoBom $cfgPath
  $cfg = $raw | ConvertFrom-Json
  if($null -eq $cfg){ throw "WB_CONFIG_PARSE_NULL" }
  if([string]::IsNullOrWhiteSpace([string]$cfg.channel)){ throw "WB_CONFIG_CHANNEL_EMPTY" }
  return $cfg
}

function WB-GetSha256HexFile([string]$Path) {
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ throw ("WB_MISSING_FILE: " + $Path) }
  $fs = [System.IO.File]::OpenRead($Path)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($fs)
  } finally {
    $sha.Dispose()
    $fs.Dispose()
  }
  $sb = New-Object System.Text.StringBuilder
  for($i=0; $i -lt $hash.Length; $i++){
    [void]$sb.AppendFormat("{0:x2}", $hash[$i])
  }
  return $sb.ToString()
}