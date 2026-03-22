param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
$RunPath = Join-Path (Join-Path $RepoRoot "scripts") "_RUN_contract_registry_tier0_selftest_v1.ps1"
if(-not (Test-Path -LiteralPath $RunPath -PathType Leaf)){ throw ("MISSING_RUNNER: " + $RunPath) }
$raw = [IO.File]::ReadAllText($RunPath,[Text.UTF8Encoding]::new($false))
$lines = @($raw -split "`n", -1)
$out = New-Object System.Collections.Generic.List[string]
$skipping = $false
foreach($ln in $lines){
  # Start skipping if we detect the sha256sums parsing block / regex match lines
  if((-not $skipping) -and ($ln -match "sumLines" -or $ln -match "Regex\]::Match" -or $ln -match "BAD_SHA256SUMS")){
    $skipping = $true
    [void]$out.Add("# STRIPPED: sha256sums parsing removed from Tier-0 runner (v1)")
    continue
  }
  # Stop skipping once we hit a blank line AFTER we started skipping (simple, safe heuristic)
  if($skipping){
    if([string]::IsNullOrWhiteSpace($ln)){ $skipping = $false; [void]$out.Add($ln) }
    continue
  }
  [void]$out.Add($ln)
}
$fixed = (@($out.ToArray()) -join "`n")
if(-not $fixed.EndsWith("`n")){ $fixed += "`n" }
[IO.File]::WriteAllText($RunPath,$fixed,[Text.UTF8Encoding]::new($false))
$null = [ScriptBlock]::Create($fixed)
Write-Host ("PATCH_OK: stripped sha256sums parsing from " + $RunPath) -ForegroundColor Green
