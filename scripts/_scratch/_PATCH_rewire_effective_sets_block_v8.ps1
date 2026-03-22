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
  $t=$null; $e=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$t,[ref]$e)
  if($e -and $e.Count -gt 0){
    $x=$e[0]
    throw ("PARSE_GATE_FAIL: {0}:{1}:{2}: {3}" -f $Path,$x.Extent.StartLineNumber,$x.Extent.StartColumnNumber,$x.Message)
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Scripts  = Join-Path $RepoRoot "scripts"
$Scratch  = Join-Path $Scripts "_scratch"
if(-not (Test-Path -LiteralPath $Scratch -PathType Container)){ New-Item -ItemType Directory -Force -Path $Scratch | Out-Null }

$Runner = Join-Path $Scripts "_RUN_contract_registry_tier0_selftest_v1.ps1"
if(-not (Test-Path -LiteralPath $Runner -PathType Leaf)){ Die ("MISSING_RUNNER: " + $Runner) }

$raw = [IO.File]::ReadAllText($Runner,[Text.UTF8Encoding]::new($false))
$raw = ($raw -replace "`r`n","`n") -replace "`r","`n"
$lines = @($raw -split "`n", -1)

$sentinel = "# CONTRACT_REGISTRY_TIER0_EFFECTIVE_SETS_WIRED_V1"
$startMarker = 'contract_registry_resolve_effective_sets_v1.ps1'
$oldToken = 'EFFECTIVE_SETS_NO_RCPTDIR_OR_RECEIPTPATH'

# Pass 1: remove ANY old effective-sets blocks:
# - if we see the resolver marker anywhere, we skip until the next blank line
#   (this catches the legacy block we inserted earlier without requiring $RcptDir/$ReceiptPath to exist)
$outA = New-Object System.Collections.Generic.List[string]
$skipping = $false
for($i=0;$i -lt $lines.Count;$i++){
  $ln = $lines[$i]

  if(-not $skipping){
    if($ln -like ("*" + $startMarker + "*")){
      $skipping = $true
      continue
    }
    if($ln -like ("*" + $oldToken + "*")){
      # remove just the token line if it exists standalone
      continue
    }
    # also remove v7/v8 sentinel blocks (in case they existed already)
    if($ln -eq $sentinel){
      $skipping = $true
      continue
    }
    [void]$outA.Add($ln)
    continue
  }

  # skipping mode: stop at first blank line
  if($ln -eq ""){
    $skipping = $false
    continue
  }
}

# Find insertion point BEFORE TIER0_OK:
$ins = -1
for($i=0;$i -lt $outA.Count;$i++){
  if($outA[$i] -match 'TIER0_OK:'){
    $ins = $i
    break
  }
}
if($ins -lt 0){ Die "PATCH_FAIL_NO_TIER0_OK_LINE" }

# Block (StrictMode-safe) - does not assume $RcptDir/$ReceiptPath exist
$blk = New-Object System.Collections.Generic.List[string]
[void]$blk.Add($sentinel)
[void]$blk.Add("# Resolve effective policy/schema sets and bind receipt hash into Tier-0 receipt.")
[void]$blk.Add('$cand = @("ReceiptPath","Receipt","ReceiptFile","ReceiptTxt","OutReceipt","OutReceiptPath","Tier0Receipt","Tier0ReceiptPath")')
[void]$blk.Add('$rp = $null')
[void]$blk.Add('foreach($n in @(@($cand))){ $v = Get-Variable -Name $n -ErrorAction SilentlyContinue; if($v -and $v.Value){ $rp = [string]$v.Value; break } }')
[void]$blk.Add('if([string]::IsNullOrWhiteSpace($rp)){ Die "EFFECTIVE_SETS_NO_RECEIPT_VAR_FOUND" }')
[void]$blk.Add('$ReceiptPath = $rp')
[void]$blk.Add('$RcptDir = Split-Path -Parent $ReceiptPath')
[void]$blk.Add('if([string]::IsNullOrWhiteSpace($RcptDir)){ Die "EFFECTIVE_SETS_BAD_RECEIPT_PARENT" }')

[void]$blk.Add('$Resolve = Join-Path (Join-Path $RepoRoot "scripts") "contract_registry_resolve_effective_sets_v1.ps1"')
[void]$blk.Add('if(-not (Test-Path -LiteralPath $Resolve -PathType Leaf)){ Die ("MISSING_EFFECTIVE_SETS_RESOLVER: " + $Resolve) }')
[void]$blk.Add('$EffDir = Join-Path $RcptDir "effective_sets"')
[void]$blk.Add('if(Test-Path -LiteralPath $EffDir -PathType Container){ Remove-Item -LiteralPath $EffDir -Recurse -Force }')
[void]$blk.Add('New-Item -ItemType Directory -Force -Path $EffDir | Out-Null')
[void]$blk.Add('$pe = Start-Process -FilePath $PSExe -ArgumentList @("-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",$Resolve,"-RepoRoot",$RepoRoot,"-OutDir",$EffDir) -NoNewWindow -Wait -PassThru')
[void]$blk.Add('if($pe.ExitCode -ne 0){ Die ("EFFECTIVE_SETS_FAILED exit_code=" + $pe.ExitCode) }')
[void]$blk.Add('$EffReceipt = Join-Path $EffDir "receipt.txt"')
[void]$blk.Add('RequireFile $EffReceipt')
[void]$blk.Add('$effHash = Sha256HexFile $EffReceipt')
[void]$blk.Add('$cur = [IO.File]::ReadAllText($ReceiptPath,[Text.UTF8Encoding]::new($false))')
[void]$blk.Add('$add = [IO.File]::ReadAllText($EffReceipt,[Text.UTF8Encoding]::new($false))')
[void]$blk.Add('$m = (($cur -replace "`r`n","`n") -replace "`r","`n")')
[void]$blk.Add('$a = (($add -replace "`r`n","`n") -replace "`r","`n")')
[void]$blk.Add('$m = $m.TrimEnd("`n") + "`n"')
[void]$blk.Add('$a = $a.TrimEnd("`n") + "`n"')
[void]$blk.Add('$merged = $m + "effective_sets_receipt_sha256: " + $effHash + "`n" + "effective_sets_receipt_path: effective_sets/receipt.txt`n" + $a')
[void]$blk.Add('[IO.File]::WriteAllText($ReceiptPath,$merged,[Text.UTF8Encoding]::new($false))')
[void]$blk.Add('Write-Host ("EFFECTIVE_SETS_WIRED_OK: sha256=" + $effHash) -ForegroundColor DarkGray')
[void]$blk.Add("")

# Assemble final runner
$outB = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $ins;$i++){ [void]$outB.Add($outA[$i]) }
foreach($b in @(@($blk.ToArray()))){ [void]$outB.Add($b) }
for($i=$ins;$i -lt $outA.Count;$i++){ [void]$outB.Add($outA[$i]) }

$fixed = (@($outB.ToArray()) -join "`n")
if(-not $fixed.EndsWith("`n")){ $fixed += "`n" }

$bkDir = Join-Path $Scratch ("backups\rewire_effective_sets_v8_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $bkDir | Out-Null
Copy-Item -LiteralPath $Runner -Destination (Join-Path $bkDir "_RUN_contract_registry_tier0_selftest_v1.ps1") -Force

WriteUtf8NoBomLf $Runner $fixed
ParseGateFile $Runner
Write-Host ("PATCH_OK_REWIRE_EFFECTIVE_SETS_V8: " + $Runner) -ForegroundColor Green
