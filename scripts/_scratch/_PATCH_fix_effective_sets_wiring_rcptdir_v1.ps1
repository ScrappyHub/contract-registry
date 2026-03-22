param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $lf = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $lf.EndsWith("`n")){ $lf += "`n" }
  [IO.File]::WriteAllText($Path,$lf,[Text.UTF8Encoding]::new($false))
}

function ParseGateFile([string]$Path){
  $t=$null
  $e=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$t,[ref]$e)
  if($e -and $e.Count -gt 0){
    $x=$e[0]
    throw ("PARSE_GATE_FAIL: {0}:{1}:{2}: {3}" -f $Path,$x.Extent.StartLineNumber,$x.Extent.StartColumnNumber,$x.Message)
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Scripts  = Join-Path $RepoRoot "scripts"
$Scratch  = Join-Path $Scripts "_scratch"
if(-not (Test-Path -LiteralPath $Scratch -PathType Container)){
  New-Item -ItemType Directory -Force -Path $Scratch | Out-Null
}

$Runner = Join-Path $Scripts "_RUN_contract_registry_tier0_selftest_v1.ps1"
if(-not (Test-Path -LiteralPath $Runner -PathType Leaf)){ Die ("MISSING_RUNNER: " + $Runner) }

$raw = [IO.File]::ReadAllText($Runner,[Text.UTF8Encoding]::new($false))
$lines = @($raw -split "`n", -1)

$sentinel = "# CONTRACT_REGISTRY_TIER0_EFFECTIVE_SETS_WIRED_V1"
$start = -1
for($i=0;$i -lt $lines.Count;$i++){
  if($lines[$i] -eq $sentinel){
    $start = $i
    break
  }
}
if($start -lt 0){ Die "PATCH_FAIL_NO_SENTINEL_LINE" }

$ix = -1
for($i=0;$i -lt $lines.Count;$i++){
  if($lines[$i] -match "TIER0_OK:"){
    $ix = $i
    break
  }
}
if($ix -lt 0){ Die "PATCH_FAIL_NO_TIER0_OK_ANCHOR" }
if($ix -le $start){ Die "PATCH_FAIL_BAD_RANGE_SENTINEL_AFTER_TIER0_OK" }

# Replace everything from sentinel line up to (but not including) the TIER0_OK line.
$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $start;$i++){
  [void]$out.Add($lines[$i])
}

# --- replacement block (RcptDir-safe) ---
[void]$out.Add($sentinel)
[void]$out.Add("# Resolve effective policy/schema sets and bind receipt hash into Tier-0 receipt.")
[void]$out.Add('$Resolve = Join-Path (Join-Path $RepoRoot "scripts") "contract_registry_resolve_effective_sets_v1.ps1"')
[void]$out.Add('if(-not (Test-Path -LiteralPath $Resolve -PathType Leaf)){ Die ("MISSING_EFFECTIVE_SETS_RESOLVER: " + $Resolve) }')
[void]$out.Add('')
[void]$out.Add('# Determine receipt directory without requiring $RcptDir to exist yet.')
[void]$out.Add('$RcptDirLocal = $null')
[void]$out.Add('if(Test-Path variable:RcptDir){ $RcptDirLocal = $RcptDir }')
[void]$out.Add('elseif(Test-Path variable:ReceiptPath){ $RcptDirLocal = Split-Path -Parent $ReceiptPath }')
[void]$out.Add('if([string]::IsNullOrWhiteSpace($RcptDirLocal)){ Die "EFFECTIVE_SETS_NO_RCPTDIR_OR_RECEIPTPATH" }')
[void]$out.Add('$ReceiptPathLocal = $null')
[void]$out.Add('if(Test-Path variable:ReceiptPath){ $ReceiptPathLocal = $ReceiptPath } else { $ReceiptPathLocal = Join-Path $RcptDirLocal "receipt.txt" }')
[void]$out.Add('RequireFile $ReceiptPathLocal')
[void]$out.Add('')
[void]$out.Add('$EffDir = Join-Path $RcptDirLocal "effective_sets"')
[void]$out.Add('if(Test-Path -LiteralPath $EffDir -PathType Container){ Remove-Item -LiteralPath $EffDir -Recurse -Force }')
[void]$out.Add('New-Item -ItemType Directory -Force -Path $EffDir | Out-Null')
[void]$out.Add('$pe = Start-Process -FilePath $PSExe -ArgumentList @("-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",$Resolve,"-RepoRoot",$RepoRoot,"-OutDir",$EffDir) -NoNewWindow -Wait -PassThru')
[void]$out.Add('if($pe.ExitCode -ne 0){ Die ("EFFECTIVE_SETS_FAILED exit_code=" + $pe.ExitCode) }')
[void]$out.Add('$EffReceipt = Join-Path $EffDir "receipt.txt"')
[void]$out.Add('RequireFile $EffReceipt')
[void]$out.Add('$effHash = Sha256HexFile $EffReceipt')
[void]$out.Add('$cur = [IO.File]::ReadAllText($ReceiptPathLocal,[Text.UTF8Encoding]::new($false))')
[void]$out.Add('$add = [IO.File]::ReadAllText($EffReceipt,[Text.UTF8Encoding]::new($false))')
[void]$out.Add('$m = (($cur -replace "`r`n","`n") -replace "`r","`n")')
[void]$out.Add('$a = (($add -replace "`r`n","`n") -replace "`r","`n")')
[void]$out.Add('$m = $m.TrimEnd("`n") + "`n"')
[void]$out.Add('$a = $a.TrimEnd("`n") + "`n"')
[void]$out.Add('$merged = $m + "effective_sets_receipt_sha256: " + $effHash + "`n" + "effective_sets_receipt_path: effective_sets/receipt.txt`n" + $a')
[void]$out.Add('[IO.File]::WriteAllText($ReceiptPathLocal,$merged,[Text.UTF8Encoding]::new($false))')
[void]$out.Add('Write-Host ("EFFECTIVE_SETS_WIRED_OK: sha256=" + $effHash) -ForegroundColor DarkGray')
[void]$out.Add('')

# Now append the remainder starting at the original TIER0_OK anchor line
for($i=$ix;$i -lt $lines.Count;$i++){
  [void]$out.Add($lines[$i])
}

$fixed = (@($out.ToArray()) -join "`n")
if(-not $fixed.EndsWith("`n")){ $fixed += "`n" }

$bkDir = Join-Path $Scratch ("backups\fix_rcptdir_wiring_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $bkDir | Out-Null
Copy-Item -LiteralPath $Runner -Destination (Join-Path $bkDir "_RUN_contract_registry_tier0_selftest_v1.ps1") -Force

WriteUtf8NoBomLf $Runner $fixed
ParseGateFile $Runner
Write-Host ("PATCH_OK_EFFECTIVE_SETS_WIRING_RCPTDIR_SAFE: " + $Runner) -ForegroundColor Green
