param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
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

# 1) Remove any existing sentinel block: from sentinel line to next blank line (inclusive)
$out1 = New-Object System.Collections.Generic.List[string]
$skip = $false
$skipped = $false
for($i=0;$i -lt $lines.Count;$i++){
  $ln = $lines[$i]
  if(-not $skip -and $ln -eq $sentinel){
    $skip = $true
    $skipped = $true
    continue
  }
  if($skip){
    if($ln -eq ""){
      $skip = $false
    }
    continue
  }
  [void]$out1.Add($ln)
}

# 2) Find insertion anchor AFTER receipt variables exist
$ins = -1

# Prefer any ReceiptPath assignment
for($i=0;$i -lt $out1.Count;$i++){
  if($out1[$i] -match '^\s*\$ReceiptPath\s*='){
    $ins = $i + 1
    break
  }
}

# Fallback: after RcptDir assignment
if($ins -lt 0){
  for($i=0;$i -lt $out1.Count;$i++){
    if($out1[$i] -match '^\s*\$RcptDir\s*='){
      $ins = $i + 1
      break
    }
  }
}

if($ins -lt 0){
  Die "PATCH_FAIL_NO_RECEIPT_ANCHOR: no $ReceiptPath= or $RcptDir= line found"
}

# 3) Build block (assumes runner already defines Die/RequireFile/Sha256HexFile and $PSExe)
$blk = New-Object System.Collections.Generic.List[string]
[void]$blk.Add($sentinel)
[void]$blk.Add("# Resolve effective policy/schema sets and bind receipt hash into Tier-0 receipt.")
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

# 4) Insert block
$out2 = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $ins;$i++){ [void]$out2.Add($out1[$i]) }
foreach($b in @(@($blk.ToArray()))){ [void]$out2.Add($b) }
for($i=$ins;$i -lt $out1.Count;$i++){ [void]$out2.Add($out1[$i]) }

$fixed = (@($out2.ToArray()) -join "`n")
if(-not $fixed.EndsWith("`n")){ $fixed += "`n" }

$bkDir = Join-Path $Scratch ("backups\rewire_effective_sets_v6_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $bkDir | Out-Null
Copy-Item -LiteralPath $Runner -Destination (Join-Path $bkDir "_RUN_contract_registry_tier0_selftest_v1.ps1") -Force

WriteUtf8NoBomLf $Runner $fixed
ParseGateFile $Runner
Write-Host ("PATCH_OK_REWIRE_EFFECTIVE_SETS_V6: " + $Runner) -ForegroundColor Green
