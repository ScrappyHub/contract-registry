param(
  [Parameter(Mandatory=$true)]
  [string]$TargetRepo
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Utf8NoBomLf {
  param([string]$Path,[string]$Text)
  $Text = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $Text.EndsWith("`n")){ $Text += "`n" }
  $Parent = Split-Path -Parent $Path
  if($Parent){ New-Item -ItemType Directory -Force -Path $Parent | Out-Null }
  [IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))
}

function Read-JsonSafe {
  param([string]$Path)
  if(-not (Test-Path -LiteralPath $Path)){ return $null }
  try { return (Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json) } catch { return $null }
}

function Sha256Text {
  param([string]$Text)
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
    return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-","").ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
}

if(-not (Test-Path -LiteralPath $TargetRepo -PathType Container)){
  throw "TARGET_REPO_NOT_FOUND: $TargetRepo"
}

$RepoName = Split-Path -Leaf (Resolve-Path -LiteralPath $TargetRepo)
$ProfileRoot = Join-Path $TargetRepo ("runtime\shadow_profiles\" + $RepoName)
$AlertsPath = Join-Path $ProfileRoot "alerts\alerts.json"

$NotifyRoot = Join-Path $ProfileRoot "notify"
New-Item -ItemType Directory -Force -Path $NotifyRoot | Out-Null

$NotificationsPath = Join-Path $NotifyRoot "notifications.ndjson"
$LatestPath = Join-Path $NotifyRoot "latest_notification.json"
$ReceiptPath = Join-Path $NotifyRoot "notify_receipt.json"

$Alerts = Read-JsonSafe -Path $AlertsPath
if($null -eq $Alerts){
  throw "ALERTS_NOT_FOUND_RUN_CR_RUN_FIRST"
}

$ExistingHashes = @{}
if(Test-Path -LiteralPath $NotificationsPath){
  foreach($LineRaw in @(Get-Content -LiteralPath $NotificationsPath)){
    $Line = ([string]$LineRaw).Trim()
    if([string]::IsNullOrWhiteSpace($Line)){ continue }
    if(-not $Line.StartsWith("{")){ continue }

    try {
      $Obj = $Line | ConvertFrom-Json
      if($Obj.signature){ $ExistingHashes[[string]$Obj.signature] = $true }
    } catch {}
  }
}

$Generated = @()

foreach($a in @($Alerts.alerts)){
  $SigPayload = [ordered]@{
    repo = $RepoName
    code = [string]$a.code
    severity = [string]$a.severity
    message = [string]$a.message
    evidence = [string]$a.evidence
  }

  $Sig = Sha256Text (($SigPayload | ConvertTo-Json -Depth 10 -Compress))

  if($ExistingHashes.ContainsKey($Sig)){
    continue
  }

  $N = [ordered]@{
    schema = "contract_registry.notification.v1"
    utc = [DateTime]::UtcNow.ToString("o")
    repo_name = $RepoName
    target_repo = (Resolve-Path -LiteralPath $TargetRepo).Path
    severity = [string]$a.severity
    code = [string]$a.code
    message = [string]$a.message
    evidence = [string]$a.evidence
    signature = $Sig
  }

  $Generated += $N

  Add-Content `
    -LiteralPath $NotificationsPath `
    -Value ($N | ConvertTo-Json -Depth 20 -Compress) `
    -Encoding UTF8

  Write-Utf8NoBomLf -Path $LatestPath -Text ($N | ConvertTo-Json -Depth 20)
}

$Receipt = [ordered]@{
  schema = "contract_registry.notify_receipt.v1"
  utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  alerts_source = $AlertsPath
  notifications = $NotificationsPath
  latest_notification = $LatestPath
  generated_count = @($Generated).Count
  total_alert_count = @($Alerts.alerts).Count
}

Write-Utf8NoBomLf -Path $ReceiptPath -Text ($Receipt | ConvertTo-Json -Depth 20)

Write-Host "CR_NOTIFY_OK" -ForegroundColor Green
Write-Host ("NOTIFICATIONS: " + $NotificationsPath)
Write-Host ("LATEST: " + $LatestPath)
Write-Host ("RECEIPT: " + $ReceiptPath)
Write-Host ("GENERATED: " + @($Generated).Count)

foreach($n in @($Generated)){
  Write-Host ("NOTIFY: " + $n.severity + " " + $n.code + " - " + $n.message)
}