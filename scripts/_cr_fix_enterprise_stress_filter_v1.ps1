$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$Root="C:\dev\contract-registry"
if(-not(Test-Path -LiteralPath $Root)){ throw "Repo root not found: $Root" }
Set-Location $Root

$Enterprise = Join-Path $Root "scripts\_cr_lock_enterprise_surface_v1.ps1"
if(-not(Test-Path -LiteralPath $Enterprise)){ throw "Missing: $Enterprise" }

$txt = Get-Content -Raw -LiteralPath $Enterprise

# Desired (patched) line + message
$needleLine = '$SchemaFiles = Get-ChildItem -LiteralPath (Join-Path $Root "schemas") -Recurse -File -Filter "*.schema.json" | Sort-Object FullName'
$needleMsg  = 'Ok "schema parse check (only *.schema.json; receipt txt excluded)"'

if($txt -match [regex]::Escape($needleLine) -and $txt -match [regex]::Escape($needleMsg)){
  Write-Host "OK: enterprise already patched (stress test filters *.schema.json)"
  Write-Host "OK: enterprise parse clean (skipping re-patch)"
  exit 0
}

# Backup then patch
$bak = $Enterprise + ".bak_" + (Get-Date -Format "yyyyMMdd_HHmmss")
Copy-Item -LiteralPath $Enterprise -Destination $bak -Force
Write-Host ("OK: backup -> " + $bak)

# Old forms we might see (try a couple patterns)
$old1 = '\$SchemaFiles\s*=\s*Get-ChildItem\s*-LiteralPath\s*\(Join-Path\s*\$Root\s*"schemas"\)\s*-Recurse\s*-File\s*\|\s*Sort-Object\s*FullName'
$old2 = '\$SchemaFiles\s*=\s*Get-ChildItem\s*-LiteralPath\s*\(Join-Path\s*\$Root\s*"schemas"\)\s*-Recurse\s*-File\s*-Filter\s*"\*\.schema\.json"\s*\|\s*Sort-Object\s*FullName'

$txt2 = $txt

if([regex]::Match($txt2, $old1).Success){
  $txt2 = [regex]::Replace($txt2, $old1, [System.Text.RegularExpressions.MatchEvaluator]{ param($mm) $needleLine }, 1)
} elseif([regex]::Match($txt2, $old2).Success){
  # already has filter line (but maybe message not patched); keep line
  # no-op for line
} else {
  # If line not found, we might still be able to patch message only; fail hard otherwise
  if($txt2 -notmatch [regex]::Escape($needleLine)){
    throw "Could not find patch target (SchemaFiles enumeration) and patched line not present either. Manual review required: $Enterprise"
  }
}

# Patch message (if present)
$msgOld = 'Ok\s*"schema parse check"\s*'
if($txt2 -match $msgOld){
  $txt2 = [regex]::Replace($txt2, $msgOld, [System.Text.RegularExpressions.MatchEvaluator]{ param($mm) $needleMsg }, 1)
}

Set-Content -LiteralPath $Enterprise -Value $txt2 -Encoding UTF8 -NoNewline
Write-Host "OK: patched enterprise (idempotent)"

# Parse check
pwsh -NoProfile -Command "[ScriptBlock]::Create((Get-Content -Raw -LiteralPath '$Enterprise')) | Out-Null; 'OK: enterprise parse clean'"

# Re-run enterprise surface deterministically (exit-code strict)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Enterprise

Write-Host "NEXT: git status"
Write-Host "NEXT: git add scripts/_cr_fix_enterprise_stress_filter_v1.ps1 scripts/_cr_stress_test_v1.ps1 scripts/_cr_lock_enterprise_surface_v1.ps1 schemas/_schema_write_status_v1.txt docs/ENGINE_REGISTRY.md docs/LICENSING_ENTITLEMENTS.md docs/STRESS_TEST_PLAN.md docs/INTEGRATION_LAW.md schemas/common/engine_registry.schema.json schemas/common/entitlements.schema.json docs/examples/contracts.lock.sample.json docs/examples/engine_registry.sample.json docs/examples/entitlements.sample.json scripts/_cr_status_check_v1.ps1"
Write-Host 'NEXT: git commit -m "Contract Registry: lock enterprise surface v1 (stress test filters schema JSON; receipt excluded)"'