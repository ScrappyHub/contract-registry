param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function EnsureDir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ Die "ENSUREDIR_EMPTY" }
  if(-not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null }
}
function RequireFile([string]$p){ if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die ("MISSING_FILE: " + $p) } }
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
function Sha256HexFile([string]$p){
  RequireFile $p
  $fs=[IO.File]::OpenRead($p)
  $sha=[Security.Cryptography.SHA256]::Create()
  try{ $h=$sha.ComputeHash($fs) } finally { $sha.Dispose(); $fs.Dispose() }
  $sb=New-Object System.Text.StringBuilder
  for($i=0;$i -lt $h.Length;$i++){ [void]$sb.AppendFormat("{0:x2}", $h[$i]) }
  $sb.ToString()
}
function Sha256HexBytes([byte[]]$b){
  $sha=[Security.Cryptography.SHA256]::Create()
  try{ $h=$sha.ComputeHash($b) } finally { $sha.Dispose() }
  $sb=New-Object System.Text.StringBuilder
  for($i=0;$i -lt $h.Length;$i++){ [void]$sb.AppendFormat("{0:x2}", $h[$i]) }
  $sb.ToString()
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Scripts  = Join-Path $RepoRoot "scripts"
$Scratch  = Join-Path $Scripts "_scratch"
EnsureDir $Scratch

# dirs
$PolicyCanon  = Join-Path (Join-Path $RepoRoot "policy")  "canonical"
$PolicyOver   = Join-Path (Join-Path $RepoRoot "policy")  "overlay"
$SchemaCanon  = Join-Path (Join-Path $RepoRoot "schemas") "canonical"
$SchemaOver   = Join-Path (Join-Path $RepoRoot "schemas") "overlay"
EnsureDir $PolicyCanon; EnsureDir $PolicyOver; EnsureDir $SchemaCanon; EnsureDir $SchemaOver

# overwrite resolver directly
$Resolve = Join-Path $Scripts "contract_registry_resolve_effective_sets_v1.ps1"

$res = New-Object System.Collections.Generic.List[string]
[void]$res.Add("# CONTRACT_REGISTRY_EFFECTIVE_SETS_RESOLVER_V1")
[void]$res.Add('param([Parameter(Mandatory=$true)][string]$RepoRoot,[Parameter(Mandatory=$true)][string]$OutDir,[Parameter()][switch]$AllowOverrides)')
[void]$res.Add('$ErrorActionPreference="Stop"')
[void]$res.Add('Set-StrictMode -Version Latest')
[void]$res.Add('function Die([string]$m){ throw $m }')
[void]$res.Add('function EnsureDir([string]$p){ if([string]::IsNullOrWhiteSpace($p)){ Die "ENSUREDIR_EMPTY" }; if(-not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }')
[void]$res.Add('function WriteUtf8NoBomLf([string]$Path,[string]$Text){ $dir=Split-Path -Parent $Path; if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }; $lf=($Text -replace "`r`n","`n") -replace "`r","`n"; if(-not $lf.EndsWith("`n")){ $lf += "`n" }; [IO.File]::WriteAllText($Path,$lf,[Text.UTF8Encoding]::new($false)) }')
[void]$res.Add('function Sha256HexFile([string]$p){ $fs=[IO.File]::OpenRead($p); $sha=[Security.Cryptography.SHA256]::Create(); try{ $h=$sha.ComputeHash($fs) } finally { $sha.Dispose(); $fs.Dispose() }; $sb=New-Object System.Text.StringBuilder; for($i=0;$i -lt $h.Length;$i++){ [void]$sb.AppendFormat("{0:x2}", $h[$i]) }; $sb.ToString() }')
[void]$res.Add('function Sha256HexBytes([byte[]]$b){ $sha=[Security.Cryptography.SHA256]::Create(); try{ $h=$sha.ComputeHash($b) } finally { $sha.Dispose() }; $sb=New-Object System.Text.StringBuilder; for($i=0;$i -lt $h.Length;$i++){ [void]$sb.AppendFormat("{0:x2}", $h[$i]) }; $sb.ToString() }')
[void]$res.Add('$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path')
[void]$res.Add('EnsureDir $OutDir')
[void]$res.Add('$PolicyCanon = Join-Path (Join-Path $RepoRoot "policy") "canonical"')
[void]$res.Add('$PolicyOver  = Join-Path (Join-Path $RepoRoot "policy") "overlay"')
[void]$res.Add('$SchemaCanon = Join-Path (Join-Path $RepoRoot "schemas") "canonical"')
[void]$res.Add('$SchemaOver  = Join-Path (Join-Path $RepoRoot "schemas") "overlay"')
[void]$res.Add('EnsureDir $PolicyCanon; EnsureDir $PolicyOver; EnsureDir $SchemaCanon; EnsureDir $SchemaOver')
[void]$res.Add('function Rel([string]$base,[string]$full){ $b=(Resolve-Path -LiteralPath $base).Path.TrimEnd([char]92); $f=(Resolve-Path -LiteralPath $full).Path; if(-not $f.StartsWith($b,[StringComparison]::OrdinalIgnoreCase)){ Die ("REL_PATH_OUTSIDE_BASE: " + $full) }; $r=$f.Substring($b.Length).TrimStart([char]92); $r.Replace([char]92,[char]47) }')
[void]$res.Add('function BuildSet([string]$canonDir,[string]$overDir,[string]$label){ $canonFiles=@(); if(Test-Path -LiteralPath $canonDir -PathType Container){ $canonFiles=@(Get-ChildItem -LiteralPath $canonDir -Recurse -File -Force | Sort-Object FullName) }; $overFiles=@(); if(Test-Path -LiteralPath $overDir -PathType Container){ $overFiles=@(Get-ChildItem -LiteralPath $overDir -Recurse -File -Force | Sort-Object FullName) }; $canon=@{}; foreach($f in @(@($canonFiles))){ $r=Rel $canonDir $f.FullName; $canon[$r]=$f.FullName }; $over=@{}; foreach($f in @(@($overFiles))){ $r=Rel $overDir $f.FullName; $over[$r]=$f.FullName }; $conf=New-Object System.Collections.Generic.List[string]; foreach($k in $over.Keys){ if($canon.ContainsKey($k)){ [void]$conf.Add($k) } }; if($conf.Count -gt 0 -and -not $AllowOverrides){ Die (("{0}_OVERLAY_CONFLICT: {1}" -f $label, (@($conf.ToArray()) -join ", "))) }; $eff=@{}; foreach($k in $canon.Keys){ $eff[$k]=$canon[$k] }; foreach($k in $over.Keys){ $eff[$k]=$over[$k] }; $effList=New-Object System.Collections.Generic.List[string]; foreach($k in ($eff.Keys | Sort-Object)){ $h=Sha256HexFile $eff[$k]; [void]$effList.Add(($h + "  " + $k)) }; $effHash=Sha256HexBytes([Text.UTF8Encoding]::UTF8.GetBytes((@($effList.ToArray()) -join "`n") + "`n")); return @{ effective_hash=$effHash; conflicts=@($conf.ToArray()); eff_list=@($effList.ToArray()) } }')
[void]$res.Add('$p = BuildSet $PolicyCanon $PolicyOver "POLICY"')
[void]$res.Add('$s = BuildSet $SchemaCanon $SchemaOver "SCHEMA"')
[void]$res.Add('$rc = New-Object System.Collections.Generic.List[string]')
[void]$res.Add('[void]$rc.Add("schema: contract_registry_effective_sets_receipt.v1")')
[void]$res.Add('[void]$rc.Add("utc: " + [DateTime]::UtcNow.ToString("o"))')
[void]$res.Add('[void]$rc.Add("policy_effective_hash: " + $p.effective_hash)')
[void]$res.Add('[void]$rc.Add("schema_effective_hash: " + $s.effective_hash)')
[void]$res.Add('[void]$rc.Add("policy_conflicts: " + $p.conflicts.Count)')
[void]$res.Add('[void]$rc.Add("schema_conflicts: " + $s.conflicts.Count)')
[void]$res.Add('[void]$rc.Add("allow_overrides: " + $(if($AllowOverrides){"true"}else{"false"}))')
[void]$res.Add('[void]$rc.Add("# policy_effective_files")')
[void]$res.Add('foreach($x in @(@($p.eff_list))){ [void]$rc.Add($x) }')
[void]$res.Add('[void]$rc.Add("# schema_effective_files")')
[void]$res.Add('foreach($x in @(@($s.eff_list))){ [void]$rc.Add($x) }')
[void]$res.Add('$ReceiptPath = Join-Path $OutDir "receipt.txt"')
[void]$res.Add('WriteUtf8NoBomLf $ReceiptPath ((@($rc.ToArray()) -join "`n") + "`n")')
[void]$res.Add('Write-Host ("EFFECTIVE_SETS_OK: receipt=" + $ReceiptPath) -ForegroundColor Green')

WriteUtf8NoBomLf $Resolve ((@($res.ToArray()) -join "`n") + "`n")
ParseGateFile $Resolve
Write-Host ("WROTE+PARSE_OK: " + $Resolve) -ForegroundColor Green

# wire runner (idempotent)
$Runner = Join-Path $Scripts "_RUN_contract_registry_tier0_selftest_v1.ps1"
RequireFile $Runner
$runnerSentinel = "CONTRACT_REGISTRY_TIER0_EFFECTIVE_SETS_WIRED_V1"
$raw = [IO.File]::ReadAllText($Runner,[Text.UTF8Encoding]::new($false))
if($raw -like ("*" + $runnerSentinel + "*")){
  Write-Host ("OK: runner already wired: " + $Runner) -ForegroundColor DarkGray
} else {
  $lines = @($raw -split "`n", -1)
  $ix = -1
  for($i=0;$i -lt $lines.Count;$i++){ if($lines[$i] -match "TIER0_OK:"){ $ix=$i; break } }
  if($ix -lt 0){ Die "PATCH_FAIL_NO_TIER0_OK_ANCHOR" }

  $blk = New-Object System.Collections.Generic.List[string]
  [void]$blk.Add("# " + $runnerSentinel)
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

  $out = New-Object System.Collections.Generic.List[string]
  for($i=0;$i -lt $ix;$i++){ [void]$out.Add($lines[$i]) }
  foreach($b in @(@($blk.ToArray()))){ [void]$out.Add($b) }
  for($i=$ix;$i -lt $lines.Count;$i++){ [void]$out.Add($lines[$i]) }

  $fixed = (@($out.ToArray()) -join "`n")
  if(-not $fixed.EndsWith("`n")){ $fixed += "`n" }

  $bkDir = Join-Path $Scratch ("backups\wire_effective_sets_v5_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss"))
  New-Item -ItemType Directory -Force -Path $bkDir | Out-Null
  Copy-Item -LiteralPath $Runner -Destination (Join-Path $bkDir "_RUN_contract_registry_tier0_selftest_v1.ps1") -Force

  WriteUtf8NoBomLf $Runner $fixed
  ParseGateFile $Runner
  Write-Host ("PATCH_OK: wired effective sets into Tier-0 runner + parse_ok " + $Runner) -ForegroundColor Green
}

Write-Host "PATCH_ALL_OK_V5" -ForegroundColor Green
