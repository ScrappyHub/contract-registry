param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function EnsureDir([string]$p){ if(-not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function RequireFile([string]$p){ if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die ("MISSING_FILE: " + $p) } }
function ParseGateFile([string]$Path){
  $t=$null; $e=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$t,[ref]$e)
  if($e -and $e.Count -gt 0){
    $x=$e[0]
    throw ("PARSE_GATE_FAIL: {0}:{1}:{2}: {3}" -f $Path,$x.Extent.StartLineNumber,$x.Extent.StartColumnNumber,$x.Message)
  }
}
function Sha256HexFile([string]$p){
  RequireFile $p
  $fs=[IO.File]::OpenRead($p); $sha=[Security.Cryptography.SHA256]::Create()
  try{ $h=$sha.ComputeHash($fs) } finally { $sha.Dispose(); $fs.Dispose() }
  $sb=New-Object System.Text.StringBuilder
  for($i=0;$i -lt $h.Length;$i++){ [void]$sb.AppendFormat("{0:x2}", $h[$i]) }
  $sb.ToString()
}
function WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $dir=Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $lf = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $lf.EndsWith("`n")){ $lf += "`n" }
  [IO.File]::WriteAllText($Path,$lf,[Text.UTF8Encoding]::new($false))
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

# Run GOLDEN maker with frozen inputs
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

# Emit Tier-0 receipt bundle
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
# Determine receipt directory without requiring $RcptDir to exist yet.
$RcptDirLocal = $null
if(Test-Path variable:RcptDir){ $RcptDirLocal = $RcptDir }
elseif(Test-Path variable:ReceiptPath){ $RcptDirLocal = Split-Path -Parent $ReceiptPath }
$ReceiptPathLocal = $null
if(Test-Path variable:ReceiptPath){ $ReceiptPathLocal = $ReceiptPath } else { $ReceiptPathLocal = Join-Path $RcptDirLocal "receipt.txt" }
RequireFile $ReceiptPathLocal

# CONTRACT_REGISTRY_TIER0_EFFECTIVE_SETS_WIRED_V1
# Resolve effective policy/schema sets and bind receipt hash into Tier-0 receipt.
if([string]::IsNullOrWhiteSpace($Receipt)){ Die "EFFECTIVE_SETS_RECEIPT_VAR_EMPTY" }
$ReceiptPath = $Receipt
$RcptDir = Split-Path -Parent $ReceiptPath
if([string]::IsNullOrWhiteSpace($RcptDir)){ Die "EFFECTIVE_SETS_BAD_RECEIPT_PARENT" }
$Resolve = Join-Path (Join-Path $RepoRoot "scripts") "contract_registry_resolve_effective_sets_v1.ps1"
if(-not (Test-Path -LiteralPath $Resolve -PathType Leaf)){ Die ("MISSING_EFFECTIVE_SETS_RESOLVER: " + $Resolve) }
$EffDir = Join-Path $RcptDir "effective_sets"
if(Test-Path -LiteralPath $EffDir -PathType Container){ Remove-Item -LiteralPath $EffDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $EffDir | Out-Null
$pe = Start-Process -FilePath $PSExe -ArgumentList @("-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",$Resolve,"-RepoRoot",$RepoRoot,"-OutDir",$EffDir) -NoNewWindow -Wait -PassThru
if($pe.ExitCode -ne 0){ Die ("EFFECTIVE_SETS_FAILED exit_code=" + $pe.ExitCode) }
$EffReceipt = Join-Path $EffDir "receipt.txt"
RequireFile $EffReceipt
$effHash = Sha256HexFile $EffReceipt
$cur = [IO.File]::ReadAllText($ReceiptPath,[Text.UTF8Encoding]::new($false))
$add = [IO.File]::ReadAllText($EffReceipt,[Text.UTF8Encoding]::new($false))
$m = (($cur -replace "`r`n","`n") -replace "`r","`n")
$a = (($add -replace "`r`n","`n") -replace "`r","`n")
$m = $m.TrimEnd("`n") + "`n"
$a = $a.TrimEnd("`n") + "`n"
$merged = $m + "effective_sets_receipt_sha256: " + $effHash + "`n" + "effective_sets_receipt_path: effective_sets/receipt.txt`n" + $a
[IO.File]::WriteAllText($ReceiptPath,$merged,[Text.UTF8Encoding]::new($false))
Write-Host ("EFFECTIVE_SETS_WIRED_OK: sha256=" + $effHash) -ForegroundColor DarkGray

Write-Host ("TIER0_OK: receipt=" + $Receipt) -ForegroundColor Green
