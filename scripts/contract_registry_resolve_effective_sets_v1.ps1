# CONTRACT_REGISTRY_EFFECTIVE_SETS_RESOLVER_V1
param([Parameter(Mandatory=$true)][string]$RepoRoot,[Parameter(Mandatory=$true)][string]$OutDir,[Parameter()][switch]$AllowOverrides)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function EnsureDir([string]$p){ if([string]::IsNullOrWhiteSpace($p)){ Die "ENSUREDIR_EMPTY" }; if(-not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function WriteUtf8NoBomLf([string]$Path,[string]$Text){ $dir=Split-Path -Parent $Path; if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }; $lf=($Text -replace "`r`n","`n") -replace "`r","`n"; if(-not $lf.EndsWith("`n")){ $lf += "`n" }; [IO.File]::WriteAllText($Path,$lf,[Text.UTF8Encoding]::new($false)) }
function Sha256HexFile([string]$p){ $fs=[IO.File]::OpenRead($p); $sha=[Security.Cryptography.SHA256]::Create(); try{ $h=$sha.ComputeHash($fs) } finally { $sha.Dispose(); $fs.Dispose() }; $sb=New-Object System.Text.StringBuilder; for($i=0;$i -lt $h.Length;$i++){ [void]$sb.AppendFormat("{0:x2}", $h[$i]) }; $sb.ToString() }
function Sha256HexBytes([byte[]]$b){ $sha=[Security.Cryptography.SHA256]::Create(); try{ $h=$sha.ComputeHash($b) } finally { $sha.Dispose() }; $sb=New-Object System.Text.StringBuilder; for($i=0;$i -lt $h.Length;$i++){ [void]$sb.AppendFormat("{0:x2}", $h[$i]) }; $sb.ToString() }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
EnsureDir $OutDir
$PolicyCanon = Join-Path (Join-Path $RepoRoot "policy") "canonical"
$PolicyOver  = Join-Path (Join-Path $RepoRoot "policy") "overlay"
$SchemaCanon = Join-Path (Join-Path $RepoRoot "schemas") "canonical"
$SchemaOver  = Join-Path (Join-Path $RepoRoot "schemas") "overlay"
EnsureDir $PolicyCanon; EnsureDir $PolicyOver; EnsureDir $SchemaCanon; EnsureDir $SchemaOver
function Rel([string]$base,[string]$full){ $b=(Resolve-Path -LiteralPath $base).Path.TrimEnd([char]92); $f=(Resolve-Path -LiteralPath $full).Path; if(-not $f.StartsWith($b,[StringComparison]::OrdinalIgnoreCase)){ Die ("REL_PATH_OUTSIDE_BASE: " + $full) }; $r=$f.Substring($b.Length).TrimStart([char]92); $r.Replace([char]92,[char]47) }
function BuildSet([string]$canonDir,[string]$overDir,[string]$label){ $canonFiles=@(); if(Test-Path -LiteralPath $canonDir -PathType Container){ $canonFiles=@(Get-ChildItem -LiteralPath $canonDir -Recurse -File -Force | Sort-Object FullName) }; $overFiles=@(); if(Test-Path -LiteralPath $overDir -PathType Container){ $overFiles=@(Get-ChildItem -LiteralPath $overDir -Recurse -File -Force | Sort-Object FullName) }; $canon=@{}; foreach($f in @(@($canonFiles))){ $r=Rel $canonDir $f.FullName; $canon[$r]=$f.FullName }; $over=@{}; foreach($f in @(@($overFiles))){ $r=Rel $overDir $f.FullName; $over[$r]=$f.FullName }; $conf=New-Object System.Collections.Generic.List[string]; foreach($k in $over.Keys){ if($canon.ContainsKey($k)){ [void]$conf.Add($k) } }; if($conf.Count -gt 0 -and -not $AllowOverrides){ Die (("{0}_OVERLAY_CONFLICT: {1}" -f $label, (@($conf.ToArray()) -join ", "))) }; $eff=@{}; foreach($k in $canon.Keys){ $eff[$k]=$canon[$k] }; foreach($k in $over.Keys){ $eff[$k]=$over[$k] }; $effList=New-Object System.Collections.Generic.List[string]; foreach($k in ($eff.Keys | Sort-Object)){ $h=Sha256HexFile $eff[$k]; [void]$effList.Add(($h + "  " + $k)) }; $effHash=Sha256HexBytes([Text.UTF8Encoding]::UTF8.GetBytes((@($effList.ToArray()) -join "`n") + "`n")); return @{ effective_hash=$effHash; conflicts=@($conf.ToArray()); eff_list=@($effList.ToArray()) } }
$p = BuildSet $PolicyCanon $PolicyOver "POLICY"
$s = BuildSet $SchemaCanon $SchemaOver "SCHEMA"
$rc = New-Object System.Collections.Generic.List[string]
[void]$rc.Add("schema: contract_registry_effective_sets_receipt.v1")
[void]$rc.Add("utc: " + [DateTime]::UtcNow.ToString("o"))
[void]$rc.Add("policy_effective_hash: " + $p.effective_hash)
[void]$rc.Add("schema_effective_hash: " + $s.effective_hash)
[void]$rc.Add("policy_conflicts: " + $p.conflicts.Count)
[void]$rc.Add("schema_conflicts: " + $s.conflicts.Count)
[void]$rc.Add("allow_overrides: " + $(if($AllowOverrides){"true"}else{"false"}))
[void]$rc.Add("# policy_effective_files")
foreach($x in @(@($p.eff_list))){ [void]$rc.Add($x) }
[void]$rc.Add("# schema_effective_files")
foreach($x in @(@($s.eff_list))){ [void]$rc.Add($x) }
$ReceiptPath = Join-Path $OutDir "receipt.txt"
WriteUtf8NoBomLf $ReceiptPath ((@($rc.ToArray()) -join "`n") + "`n")
Write-Host ("EFFECTIVE_SETS_OK: receipt=" + $ReceiptPath) -ForegroundColor Green
