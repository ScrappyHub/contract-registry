param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function EnsureDir([string]$p){ if (-not (Test-Path -LiteralPath $p -PathType Container)) { New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function RequireFile([string]$p){ if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { Die ("MISSING_FILE: " + $p) } }
function WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $lf = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if (-not $lf.EndsWith("`n")) { $lf += "`n" }
  [IO.File]::WriteAllText($Path,$lf,[Text.UTF8Encoding]::new($false))
}

$ScriptsDir = Join-Path $RepoRoot "scripts"
$Builder = Join-Path $ScriptsDir "contract_registry_make_release_packet_v1.ps1"
$Verifier = Join-Path $ScriptsDir "contract_registry_verify_release_packet_v1.ps1"
RequireFile $Builder
RequireFile $Verifier

$Contract = Join-Path $RepoRoot "contracts\example.contract.v1.json"
RequireFile $Contract

$OutDir = Join-Path $RepoRoot "packets\outbox"
EnsureDir $OutDir

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source

# Build unsigned packet deterministically (signature optional; keep selftest minimal)
& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Builder `
  -RepoRoot $RepoRoot `
  -ContractJsonPath $Contract `
  -ContractRef "example.contract.v1" `
  -OutDir $OutDir `
  -NoSign | Out-Host

# Find newest contract_release_* packet directory
$dirs = @(@(Get-ChildItem -LiteralPath $OutDir -Directory | Where-Object { $_.Name -like "contract_release_*" } | Sort-Object LastWriteTime -Descending))
if (@(@($dirs)).Count -lt 1) { Die ("SELFTEST_NO_PACKETS_FOUND: " + $OutDir) }
$PacketRoot = $dirs[0].FullName

# Verify
& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Verifier -PacketRoot $PacketRoot -RepoRoot $RepoRoot | Out-Host

# Receipt (repo-local, proof-of-work)
$stamp = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss")
$Proofs = Join-Path $RepoRoot "proofs\receipts"
EnsureDir $Proofs
$ReceiptPath = Join-Path $Proofs ("contract_registry_selftest_release_v1_" + $stamp + ".txt")
$r = New-Object System.Collections.Generic.List[string]
[void]$r.Add("schema: contract_registry_selftest_release.v1")
[void]$r.Add("utc: " + [DateTime]::UtcNow.ToString("o"))
[void]$r.Add("repo_root: " + $RepoRoot)
[void]$r.Add("packet_root: " + $PacketRoot)
[void]$r.Add("contract: contracts/example.contract.v1.json")
WriteUtf8NoBomLf $ReceiptPath ((@($r.ToArray()) -join "`n") + "`n")

Write-Host ("SELFTEST_OK: packet=" + $PacketRoot) -ForegroundColor Green
Write-Host ("receipt=" + $ReceiptPath) -ForegroundColor Gray
