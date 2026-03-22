param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function EnsureDir([string]$p){ if(-not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function RequireFile([string]$p){ if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die ("MISSING_FILE: " + $p) } }
function WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $lf = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $lf.EndsWith("`n")){ $lf += "`n" }
  [IO.File]::WriteAllText($Path,$lf,[Text.UTF8Encoding]::new($false))
}
function ParseGateFile([string]$Path){ $t=$null; $e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$t,[ref]$e); if($e -and $e.Count -gt 0){ $x=$e[0]; throw ("PARSE_GATE_FAIL: {0}:{1}:{2}: {3}" -f $Path,$x.Extent.StartLineNumber,$x.Extent.StartColumnNumber,$x.Message) } }
function Sha256HexFile([string]$p){ RequireFile $p; $fs=[IO.File]::OpenRead($p); $sha=[Security.Cryptography.SHA256]::Create(); try{ $h=$sha.ComputeHash($fs) } finally { $sha.Dispose(); $fs.Dispose() }; $sb=New-Object System.Text.StringBuilder; for($i=0;$i -lt $h.Length;$i++){ [void]$sb.AppendFormat("{0:x2}", $h[$i]) }; return $sb.ToString() }
function Sha256HexBytes([byte[]]$b){ $sha=[Security.Cryptography.SHA256]::Create(); try{ $h=$sha.ComputeHash($b) } finally { $sha.Dispose() }; $sb=New-Object System.Text.StringBuilder; for($i=0;$i -lt $h.Length;$i++){ [void]$sb.AppendFormat("{0:x2}", $h[$i]) }; return $sb.ToString() }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Scripts = Join-Path $RepoRoot "scripts"
$Scratch = Join-Path $Scripts "_scratch"
EnsureDir $Scratch

# ---------------------------------------------------------
# 1) Ensure canonical/overlay dirs exist
# ---------------------------------------------------------
$PolicyCanon  = Join-Path (Join-Path $RepoRoot "policy")  "canonical"
$PolicyOver   = Join-Path (Join-Path $RepoRoot "policy")  "overlay"
$SchemaCanon  = Join-Path (Join-Path $RepoRoot "schemas") "canonical"
$SchemaOver   = Join-Path (Join-Path $RepoRoot "schemas") "overlay"
EnsureDir $PolicyCanon; EnsureDir $PolicyOver; EnsureDir $SchemaCanon; EnsureDir $SchemaOver

# ---------------------------------------------------------
# 2) OVERWRITE resolver script with known-good content
# ---------------------------------------------------------
$Resolve = Join-Path $Scripts "contract_registry_resolve_effective_sets_v1.ps1"
$Sent = "CONTRACT_REGISTRY_EFFECTIVE_SETS_RESOLVER_V1"
$R = New-Object System.Collections.Generic.List[string]
[void]$R.Add("# " + $Sent)
[void]$R.Add("param(")
[void]$R.Add("  [Parameter(Mandatory=$true)][string]$RepoRoot,")
[void]$R.Add("  [Parameter(Mandatory=$true)][string]$OutDir,")
[void]$R.Add("  [Parameter()][switch]$AllowOverrides")
[void]$R.Add(")")
[void]$R.Add("")
[void]$R.Add("$ErrorActionPreference=""Stop""")
[void]$R.Add("Set-StrictMode -Version Latest")
[void]$R.Add("")
[void]$R.Add("function Die([string]$m){ throw $m }")
[void]$R.Add("function EnsureDir([string]$p){ if(-not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }")
[void]$R.Add("function WriteUtf8NoBomLf([string]$Path,[string]$Text){ $dir=Split-Path -Parent $Path; if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }; $lf=($Text -replace ""`r`n"",""`n"") -replace ""`r"",""`n""; if(-not $lf.EndsWith(""`n"")){ $lf += ""`n"" }; [IO.File]::WriteAllText($Path,$lf,[Text.UTF8Encoding]::new($false)) }")
[void]$R.Add("function Sha256HexFile([string]$p){ $fs=[IO.File]::OpenRead($p); $sha=[Security.Cryptography.SHA256]::Create(); try{ $h=$sha.ComputeHash($fs) } finally { $sha.Dispose(); $fs.Dispose() }; $sb=New-Object System.Text.StringBuilder; for($i=0;$i -lt $h.Length;$i++){ [void]$sb.AppendFormat(""{{0:x2}}"",$h[$i]) }; return $sb.ToString() }")
[void]$R.Add("function Sha256HexBytes([byte[]]$b){ $sha=[Security.Cryptography.SHA256]::Create(); try{ $h=$sha.ComputeHash($b) } finally { $sha.Dispose() }; $sb=New-Object System.Text.StringBuilder; for($i=0;$i -lt $h.Length;$i++){ [void]$sb.AppendFormat(""{{0:x2}}"",$h[$i]) }; return $sb.ToString() }")
[void]$R.Add("")
[void]$R.Add('$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path')
[void]$R.Add('EnsureDir $OutDir')
[void]$R.Add('$PolicyCanon = Join-Path (Join-Path $RepoRoot "policy") "canonical"')
[void]$R.Add('$PolicyOver  = Join-Path (Join-Path $RepoRoot "policy") "overlay"')
[void]$R.Add('$SchemaCanon = Join-Path (Join-Path $RepoRoot "schemas") "canonical"')
[void]$R.Add('$SchemaOver  = Join-Path (Join-Path $RepoRoot "schemas") "overlay"')
[void]$R.Add('EnsureDir $PolicyCanon; EnsureDir $PolicyOver; EnsureDir $SchemaCanon; EnsureDir $SchemaOver')
[void]$R.Add('')
[void]$R.Add('function Rel([string]$base,[string]$full){ $b=(Resolve-Path -LiteralPath $base).Path.TrimEnd('\'); $f=(Resolve-Path -LiteralPath $full).Path; if(-not $f.StartsWith($b,[StringComparison]::OrdinalIgnoreCase)){ Die ("REL_PATH_OUTSIDE_BASE: " + $full) }; $r=$f.Substring($b.Length).TrimStart('\'); return ($r -replace '\','/') }')
[void]$R.Add('')
[void]$R.Add('function BuildSet([string]$canonDir,[string]$overDir,[string]$label){')
[void]$R.Add('  $canonFiles=@(); if(Test-Path -LiteralPath $canonDir -PathType Container){ $canonFiles=@(Get-ChildItem -LiteralPath $canonDir -Recurse -File -Force | Sort-Object FullName) }')
[void]$R.Add('  $overFiles=@();  if(Test-Path -LiteralPath $overDir  -PathType Container){ $overFiles=@(Get-ChildItem -LiteralPath $overDir  -Recurse -File -Force | Sort-Object FullName) }')
[void]$R.Add('  $canon=@{}; foreach($f in @(@($canonFiles))){ $r=Rel $canonDir $f.FullName; $canon[$r]=$f.FullName }')
[void]$R.Add('  $over=@{};  foreach($f in @(@($overFiles))){  $r=Rel $overDir  $f.FullName; $over[$r]=$f.FullName }')
[void]$R.Add('  $conf=New-Object System.Collections.Generic.List[string]; foreach($k in $over.Keys){ if($canon.ContainsKey($k)){ [void]$conf.Add($k) } }')
[void]$R.Add('  if($conf.Count -gt 0 -and -not $AllowOverrides){ Die ("{0}_OVERLAY_CONFLICT: {1}" -f $label, (@($conf.ToArray()) -join ", ")) }')
[void]$R.Add('  $eff=@{}; foreach($k in $canon.Keys){ $eff[$k]=$canon[$k] }; foreach($k in $over.Keys){ $eff[$k]=$over[$k] }')
[void]$R.Add('  $effList=New-Object System.Collections.Generic.List[string]; foreach($k in ($eff.Keys | Sort-Object)){ $h=Sha256HexFile $eff[$k]; [void]$effList.Add(($h + "  " + $k)) }')
[void]$R.Add('  $canonHash=Sha256HexBytes([Text.UTF8Encoding]::UTF8.GetBytes((@($effList.ToArray()) -join "`n") + "`n")) # canon hash is derived from effective list when no conflicts')
[void]$R.Add('  $overHash =$canonHash # overlay hash is carried separately by file lists; keep stable minimal for Tier-0')
[void]$R.Add('  $effHash  =$canonHash')
[void]$R.Add('  return @{ canon_hash=$canonHash; over_hash=$overHash; effective_hash=$effHash; conflicts=@($conf.ToArray()); eff_list=@($effList.ToArray()) }')
[void]$R.Add('}')
[void]$R.Add('')
[void]$R.Add('$p = BuildSet $PolicyCanon $PolicyOver "POLICY"')
[void]$R.Add('$s = BuildSet $SchemaCanon $SchemaOver "SCHEMA"')
[void]$R.Add('$rc = New-Object System.Collections.Generic.List[string]')
[void]$R.Add('[void]$rc.Add("schema: contract_registry_effective_sets_receipt.v1")')
[void]$R.Add('[void]$rc.Add("utc: " + [DateTime]::UtcNow.ToString("o"))')
[void]$R.Add('[void]$rc.Add("policy_effective_hash: " + $p.effective_hash)')
[void]$R.Add('[void]$rc.Add("schema_effective_hash: " + $s.effective_hash)')
[void]$R.Add('[void]$rc.Add("policy_conflicts: " + $p.conflicts.Count)')
[void]$R.Add('[void]$rc.Add("schema_conflicts: " + $s.conflicts.Count)')
[void]$R.Add('[void]$rc.Add("allow_overrides: " + $(if($AllowOverrides){"true"}else{"false"}))')
[void]$R.Add('[void]$rc.Add("# policy_effective_files")')
[void]$R.Add('foreach($x in @(@($p.eff_list))){ [void]$rc.Add($x) }')
[void]$R.Add('[void]$rc.Add("# schema_effective_files")')
[void]$R.Add('foreach($x in @(@($s.eff_list))){ [void]$rc.Add($x) }')
[void]$R.Add('$ReceiptPath = Join-Path $OutDir "receipt.txt"')
[void]$R.Add('WriteUtf8NoBomLf $ReceiptPath ((@($rc.ToArray()) -join "`n") + "`n")')
[void]$R.Add('Write-Host ("EFFECTIVE_SETS_OK: receipt=" + $ReceiptPath) -ForegroundColor Green')
$resolveText = (@($R.ToArray()) -join "`n") + "`n"
WriteUtf8NoBomLf $Resolve $resolveText
ParseGateFile $Resolve
Write-Host ("WROTE+PARSE_OK: " + $Resolve) -ForegroundColor Green

# ---------------------------------------------------------
# 3) Wire Tier-0 runner (idempotent)
# ---------------------------------------------------------
$Runner = Join-Path $Scripts "_RUN_contract_registry_tier0_selftest_v1.ps1"
RequireFile $Runner
$runnerSentinel = "CONTRACT_REGISTRY_TIER0_EFFECTIVE_SETS_WIRED_V1"
$raw = [IO.File]::ReadAllText($Runner,[Text.UTF8Encoding]::new($false))
if($raw -like ("*" + $runnerSentinel + "*")){ Write-Host ("OK: runner already wired: " + $Runner) -ForegroundColor DarkGray } else {
  $lines = @($raw -split "`n", -1)
  $ix = -1; for($i=0;$i -lt $lines.Count;$i++){ if($lines[$i] -match "TIER0_OK:"){ $ix=$i; break } }
  if($ix -lt 0){ Die "PATCH_FAIL_NO_TIER0_OK_ANCHOR" }
  $blk = New-Object System.Collections.Generic.List[string]
  [void]$blk.Add("# " + $runnerSentinel)
  [void]$blk.Add("$Resolve = Join-Path (Join-Path $RepoRoot ""scripts"") ""contract_registry_resolve_effective_sets_v1.ps1""")
  [void]$blk.Add("if(-not (Test-Path -LiteralPath $Resolve -PathType Leaf)){ Die (""MISSING_EFFECTIVE_SETS_RESOLVER: "" + $Resolve) }")
  [void]$blk.Add("$EffDir = Join-Path $RcptDir ""effective_sets""")
  [void]$blk.Add("if(Test-Path -LiteralPath $EffDir -PathType Container){ Remove-Item -LiteralPath $EffDir -Recurse -Force }")
  [void]$blk.Add("New-Item -ItemType Directory -Force -Path $EffDir | Out-Null")
  [void]$blk.Add("$pe = Start-Process -FilePath $PSExe -ArgumentList @(")
  [void]$blk.Add("  ""-NoProfile"",""-NonInteractive"",""-ExecutionPolicy"",""Bypass"",""-File"",$Resolve,""-RepoRoot"",$RepoRoot,""-OutDir"",$EffDir")
  [void]$blk.Add(") -NoNewWindow -Wait -PassThru")
  [void]$blk.Add("if($pe.ExitCode -ne 0){ Die (""EFFECTIVE_SETS_FAILED exit_code="" + $pe.ExitCode) }")
  [void]$blk.Add("$EffReceipt = Join-Path $EffDir ""receipt.txt""")
  [void]$blk.Add("RequireFile $EffReceipt")
  [void]$blk.Add("$effHash = Sha256HexFile $EffReceipt")
  [void]$blk.Add("$cur = [IO.File]::ReadAllText($ReceiptPath,[Text.UTF8Encoding]::new($false))")
  [void]$blk.Add("$add = [IO.File]::ReadAllText($EffReceipt,[Text.UTF8Encoding]::new($false))")
  [void]$blk.Add("$m = (($cur -replace ""`r`n"",""`n"") -replace ""`r"",""`n"") )")
  [void]$blk.Add("$a = (($add -replace ""`r`n"",""`n"") -replace ""`r"",""`n"") )")
  [void]$blk.Add("$m = $m.TrimEnd(""`n"") + ""`n""")
  [void]$blk.Add("$a = $a.TrimEnd(""`n"") + ""`n""")
  [void]$blk.Add("$merged = $m + ""effective_sets_receipt_sha256: "" + $effHash + ""`n"" + ""effective_sets_receipt_path: effective_sets/receipt.txt`n"" + $a")
  [void]$blk.Add("[IO.File]::WriteAllText($ReceiptPath,$merged,[Text.UTF8Encoding]::new($false))")
  [void]$blk.Add("Write-Host (""EFFECTIVE_SETS_WIRED_OK: sha256="" + $effHash) -ForegroundColor DarkGray")

  $out = New-Object System.Collections.Generic.List[string]
  for($i=0;$i -lt $ix;$i++){ [void]$out.Add($lines[$i]) }
  foreach($b in @(@($blk.ToArray()))){ [void]$out.Add($b) }
  for($i=$ix;$i -lt $lines.Count;$i++){ [void]$out.Add($lines[$i]) }
  $fixed = (@($out.ToArray()) -join "`n"); if(-not $fixed.EndsWith("`n")){ $fixed += "`n" }
  $bkDir = Join-Path $Scratch ("backups\wire_effective_sets_v3_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss"))
  New-Item -ItemType Directory -Force -Path $bkDir | Out-Null
  Copy-Item -LiteralPath $Runner -Destination (Join-Path $bkDir "_RUN_contract_registry_tier0_selftest_v1.ps1") -Force
  WriteUtf8NoBomLf $Runner $fixed
  ParseGateFile $Runner
  Write-Host ("PATCH_OK: wired effective sets into Tier-0 runner + parse_ok " + $Runner) -ForegroundColor Green
}

Write-Host "PATCH_ALL_OK_V3" -ForegroundColor Green
