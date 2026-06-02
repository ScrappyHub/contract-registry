param(
  [Parameter(Mandatory=$true)]
  [string]$TargetRepo,

  [int]$IntervalSeconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function To-JsonStable {
  param($InputObject)

  return ($InputObject | ConvertTo-Json -Depth 100)
}

function Sha256File {
  param([string]$Path)

  return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Run-ShadowProfile {
  param([string]$Repo)

  $Script = Join-Path $PSScriptRoot "cr_shadow_profile_v1.ps1"

  $Output = & powershell.exe `
    -NoProfile `
    -NonInteractive `
    -ExecutionPolicy Bypass `
    -File $Script `
    -TargetRepo $Repo 2>&1

  return @{
    exit_code = $LASTEXITCODE
    output = @($Output)
  }
}

function Read-LatestReceipt {
  param([string]$RepoRoot)

  $RepoName = Split-Path $RepoRoot -Leaf

  $ReceiptPath = Join-Path `
    $RepoRoot `
    ("runtime\shadow_profiles\" + $RepoName + "\receipts\shadow_profile.ndjson")

  if(-not (Test-Path -LiteralPath $ReceiptPath)){
    return $null
  }

  $Lines = Get-Content -LiteralPath $ReceiptPath

  if(@($Lines).Count -lt 1){
    return $null
  }

  for($i = @($Lines).Count - 1; $i -ge 0; $i--){
    $Line = [string]$Lines[$i]

    if([string]::IsNullOrWhiteSpace($Line)){
      continue
    }

    $Trimmed = $Line.Trim()

    if(-not $Trimmed.StartsWith("{")){
      continue
    }

    try {
      return ($Trimmed | ConvertFrom-Json)
    } catch {
      continue
    }
  }

  return $null
}

$WatchRoot = Join-Path $TargetRepo "runtime\watch"
$TimelineRoot = Join-Path $WatchRoot "timeline"

New-Item -ItemType Directory -Force -Path $TimelineRoot | Out-Null

$TimelinePath = Join-Path $TimelineRoot "watch_timeline.ndjson"

Write-Host "CR_WATCH_STARTING" -ForegroundColor Cyan
Write-Host ("TARGET: " + $TargetRepo)
Write-Host ("INTERVAL_SECONDS: " + $IntervalSeconds)

$LastReceiptHash = ""

while($true){

  $Utc = [DateTime]::UtcNow.ToString("o")

  Write-Host ""
  Write-Host ("WATCH_TICK: " + $Utc) -ForegroundColor DarkCyan

  $Run = Run-ShadowProfile -Repo $TargetRepo

    $ReceiptPathFromOutput = $null

  foreach($Line in @($Run.output)){
    $S = [string]$Line
    if($S.StartsWith("RECEIPT:")){
      $ReceiptPathFromOutput = $S.Substring("RECEIPT:".Length).Trim()
    }
  }

  $Receipt = $null

  if($ReceiptPathFromOutput -and (Test-Path -LiteralPath $ReceiptPathFromOutput)){
    $ReceiptLines = Get-Content -LiteralPath $ReceiptPathFromOutput

    for($ri = @($ReceiptLines).Count - 1; $ri -ge 0; $ri--){
      $Candidate = ([string]$ReceiptLines[$ri]).Trim()

      if([string]::IsNullOrWhiteSpace($Candidate)){
        continue
      }

      if(-not $Candidate.StartsWith("{")){
        continue
      }

      try {
        $Receipt = ($Candidate | ConvertFrom-Json)
        break
      } catch {
        continue
      }
    }
  }

  if(-not $Receipt){
    $Receipt = Read-LatestReceipt -RepoRoot $TargetRepo
  }

  if($Receipt){

    $ReceiptJson = To-JsonStable $Receipt

    $Temp = Join-Path $env:TEMP "cr_watch_receipt.json"

    [System.IO.File]::WriteAllText(
      $Temp,
      $ReceiptJson,
      [System.Text.UTF8Encoding]::new($false)
    )

    $ReceiptHash = Sha256File $Temp

    Remove-Item $Temp -Force -ErrorAction SilentlyContinue

    $Changed = $ReceiptHash -ne $LastReceiptHash

    $Event = [ordered]@{
      schema = "contract_registry.watch_event.v1"
      utc = $Utc
      repo = $TargetRepo
      changed = $Changed
      receipt_hash = $ReceiptHash
      severity = $Receipt.severity
      risk_score = $Receipt.risk_score
      file_count = $Receipt.file_count
      exit_code = $Run.exit_code
    }

    $Line = To-JsonStable $Event

    Add-Content `
      -LiteralPath $TimelinePath `
      -Value $Line `
      -Encoding UTF8

    if($Changed){
      Write-Host "WATCH_CHANGE_DETECTED" -ForegroundColor Yellow
      Write-Host ("SEVERITY: " + $Receipt.severity)
      Write-Host ("RISK_SCORE: " + $Receipt.risk_score)
    }
    else{
      Write-Host "WATCH_NO_CHANGE" -ForegroundColor DarkGreen
    }

    $LastReceiptHash = $ReceiptHash
  }
  else{
    Write-Host "WATCH_NO_RECEIPT" -ForegroundColor Red
  }

  Start-Sleep -Seconds $IntervalSeconds
}