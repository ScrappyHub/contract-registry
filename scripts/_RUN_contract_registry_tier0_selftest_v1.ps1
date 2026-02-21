param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function RequireFile([string]$p){ if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die ("MISSING_FILE: " + $p) } }
function EnsureDir([string]$p){ if(-not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function ReadTextUtf8NoBom([string]$p){ RequireFile $p; [IO.File]::ReadAllText($p,[Text.UTF8Encoding]::new($false)) }
function WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $lf = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $lf.EndsWith("`n")){ $lf += "`n" }
  [IO.File]::WriteAllText($Path,$lf,[Text.UTF8Encoding]::new($false))
}
function ParseGateFile([string]$Path){ $raw = ReadTextUtf8NoBom $Path; $null = [ScriptBlock]::Create($raw) }
function Sha256HexFile([string]$p){
  RequireFile $p
  $fs=[IO.File]::OpenRead($p); $sha=[Security.Cryptography.SHA256]::Create()
  try{ $h=$sha.ComputeHash($fs) } finally { $sha.Dispose(); $fs.Dispose() }
  $sb=New-Object System.Text.StringBuilder
  for($i=0;$i -lt $h.Length;$i++){ [void]$sb.AppendFormat("{0:x2}", $h[$i]) }
  $sb.ToString()
}

$ScriptsDir = Join-Path $RepoRoot "scripts"
if(-not (Test-Path -LiteralPath $ScriptsDir -PathType Container)){ Die ("MISSING_SCRIPTS_DIR: " + $ScriptsDir) }

$Verifier = Join-Path $ScriptsDir "contract_registry_verify_release_packet_v1.ps1"
$Selftest = Join-Path $ScriptsDir "selftest_contract_registry_release_packet_v1.ps1"
$Golden   = Join-Path $ScriptsDir "contract_registry_make_golden_vectors_v1.ps1"
$Builder1 = Join-Path $ScriptsDir "contract_registry_make_release_packet_v1.ps1"
$Builder11= Join-Path $ScriptsDir "contract_registry_make_release_packet_v1_1.ps1"

RequireFile $Verifier
RequireFile $Selftest
RequireFile $Golden
if(Test-Path -LiteralPath $Builder1  -PathType Leaf){ RequireFile $Builder1 }
if(Test-Path -LiteralPath $Builder11 -PathType Leaf){ RequireFile $Builder11 }

ParseGateFile $Verifier
ParseGateFile $Selftest
ParseGateFile $Golden
if(Test-Path -LiteralPath $Builder1  -PathType Leaf){ ParseGateFile $Builder1 }
if(Test-Path -LiteralPath $Builder11 -PathType Leaf){ ParseGateFile $Builder11 }
Write-Host "PARSE_GATES_OK: contract-registry Tier-0 dependencies" -ForegroundColor Green

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source
$p = Start-Process -FilePath $PSExe -ArgumentList @(
  "-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",$Golden,
  "-RepoRoot",$RepoRoot,
  "-ContractRef","example.contract.v1",
  "-CreatedUtc","2026-01-01T00:00:00Z",
  "-Stamp","20260101_000000",
  "-NoSign"
) -NoNewWindow -Wait -PassThru
if($p.ExitCode -ne 0){ Die ("GOLDEN_MAKER_FAILED exit_code=" + $p.ExitCode) }
Write-Host "GOLDEN_MAKER_OK" -ForegroundColor Green

$run_id = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss")
$Base = Join-Path (Join-Path $RepoRoot "proofs\receipts") "contract_registry_tier0_selftest_v1"
EnsureDir $Base
$Out = Join-Path $Base $run_id
EnsureDir $Out
$Receipt = Join-Path $Out "receipt.txt"
$rc = New-Object System.Collections.Generic.List[string]
[void]$rc.Add("schema: contract_registry_tier0_selftest_receipt.v1")
[void]$rc.Add("utc: " + [DateTime]::UtcNow.ToString("o"))
[void]$rc.Add("repo_root: " + $RepoRoot)
[void]$rc.Add("golden_contract_ref: example.contract.v1")
[void]$rc.Add("golden_created_utc: 2026-01-01T00:00:00Z")
[void]$rc.Add("golden_stamp: 20260101_000000")
[void]$rc.Add("scripts/verifier_sha256: " + (Sha256HexFile $Verifier))
[void]$rc.Add("scripts/selftest_sha256: " + (Sha256HexFile $Selftest))
[void]$rc.Add("scripts/golden_maker_sha256: " + (Sha256HexFile $Golden))
if(Test-Path -LiteralPath $Builder1  -PathType Leaf){ [void]$rc.Add("scripts/builder_v1_sha256: " + (Sha256HexFile $Builder1)) }
if(Test-Path -LiteralPath $Builder11 -PathType Leaf){ [void]$rc.Add("scripts/builder_v1_1_sha256: " + (Sha256HexFile $Builder11)) }
WriteUtf8NoBomLf $Receipt ((@($rc.ToArray()) -join "`n") + "`n")
Write-Host ("TIER0_OK: receipt=" + $Receipt) -ForegroundColor Green
