$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$Root="C:\dev\contract-registry"
if(-not(Test-Path -LiteralPath $Root)){ throw "Repo root not found: $Root" }
Set-Location $Root

function Ensure-Dir([string]$Rel){
  $p = Join-Path $Root $Rel
  if(-not(Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null }
}

function Write-Text([string]$RelPath, [string]$Content){
  $full = Join-Path $Root $RelPath
  $parent = Split-Path -Parent $full
  if(-not(Test-Path -LiteralPath $parent)){ New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  Set-Content -LiteralPath $full -Value $Content -Encoding UTF8 -NoNewline
}

function Write-LinesNoBlanks([string]$RelPath, [string[]]$Lines){
  foreach($l in $Lines){ if($l -eq ""){ throw "Blank line not allowed in: $RelPath" } }
  Write-Text -RelPath $RelPath -Content ($Lines -join "`n")
}

function Patch-Expected([string]$StatusPath, [string[]]$Need){
  if(-not(Test-Path -LiteralPath $StatusPath)){ throw "Missing: $StatusPath" }
  $txt = Get-Content -Raw -LiteralPath $StatusPath
  $pat = '(?s)(\$Expected\s*=\s*@\()(.*?)(\r?\n\))'
  $m = [regex]::Match($txt, $pat)
  if(-not $m.Success){ throw "Could not locate `$Expected = @(` block in scripts\_cr_status_check_v1.ps1" }
  $head = $m.Groups[1].Value; $body = $m.Groups[2].Value; $tail = $m.Groups[3].Value
  foreach($n in $Need){
    if($txt -notmatch [regex]::Escape($n)){
      if($body -notmatch '\S'){ $body = "`n  `"$n`"" }
      else { $body = $body.TrimEnd() + "`n  `"$n`"" }
    }
  }
  $newBlock = $head + $body + $tail
  $txt = [regex]::Replace($txt, $pat, [System.Text.RegularExpressions.MatchEvaluator]{ param($mm) $newBlock }, 1)
  Set-Content -LiteralPath $StatusPath -Value $txt -Encoding UTF8 -NoNewline
}

function Invoke-PS([string]$Path){
  if(-not(Test-Path -LiteralPath $Path)){ throw "Missing: $Path" }
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Path
  if($LASTEXITCODE -ne 0){ throw ("FAILED: " + $Path + " (exit=" + $LASTEXITCODE + ")") }
}

Ensure-Dir "docs"
Ensure-Dir "docs\examples"
Ensure-Dir "schemas\common"
Ensure-Dir "scripts"

# -------------------------
# 1) docs/ENGINE_REGISTRY.md
# -------------------------
Write-LinesNoBlanks "docs\ENGINE_REGISTRY.md" @(
  "# Engine Registry (Contract Registry Canonical v1)"
  "Authority: Contract Registry"
  "Status: LOCKED"
  "Purpose: enumerate the enforcement engines that must exist so contract adoption cannot drift."
  "## Engine types (MUST)"
  "- packager"
  "- verifier"
  "- signature_verifier"
  "- overlay_evaluator"
  "- schema_validator"
  "- audit_reporter"
  "## Drift rule (MUST)"
  "- If an engine behavior changes, engine version MUST change and consumers MUST re-pin."
)

# -------------------------
# 2) schemas/common/engine_registry.schema.json
# -------------------------
$engineSchema = @(
  '{',
  '  "$id": "contract:engine_registry@1.0.0",',
  '  "type": "object",',
  '  "additionalProperties": false,',
  '  "required": ["schema","generated_at_utc","registry_version","engines"],',
  '  "properties": {',
  '    "schema": {"type": "string", "const": "engine.registry.v1"},',
  '    "generated_at_utc": {"type": "string", "format": "date-time"},',
  '    "registry_version": {"type": "string", "minLength": 1},',
  '    "engines": {',
  '      "type": "array",',
  '      "minItems": 1,',
  '      "items": {',
  '        "type": "object",',
  '        "additionalProperties": false,',
  '        "required": ["engine_id","engine_type","version","entrypoint","enforced_contracts"],',
  '        "properties": {',
  '          "engine_id": {"type": "string", "minLength": 1},',
  '          "engine_type": {"type": "string", "enum": ["packager","verifier","signature_verifier","overlay_evaluator","schema_validator","audit_reporter"]},',
  '          "version": {"type": "string", "minLength": 1},',
  '          "entrypoint": {"type": "string", "minLength": 1},',
  '          "enforced_contracts": {"type": "array", "minItems": 1, "items": {"type": "string", "minLength": 1}}',
  '        }',
  '      }',
  '    }',
  '  }',
  '}'
) -join "`n"
Write-Text "schemas\common\engine_registry.schema.json" $engineSchema
$null = (Get-Content -Raw -LiteralPath (Join-Path $Root "schemas\common\engine_registry.schema.json")) | ConvertFrom-Json

# -------------------------
# 3) docs/LICENSING_ENTITLEMENTS.md
# -------------------------
Write-LinesNoBlanks "docs\LICENSING_ENTITLEMENTS.md" @(
  "# Licensing and Entitlements (Contract Registry Canonical v1)"
  "Authority: Contract Registry"
  "Status: LOCKED"
  "Principle: licenses gate profiles/verbosity, not verification correctness."
  "Tiers: personal | team | business | enterprise | admin"
)

# -------------------------
# 4) schemas/common/entitlements.schema.json (FIXED JSON)
# -------------------------
$entSchema = @(
  '{',
  '  "$id": "contract:entitlements@1.0.0",',
  '  "type": "object",',
  '  "additionalProperties": false,',
  '  "required": ["schema","issued_at_utc","subject","tier","enabled_profiles","enabled_engines","audit_level"],',
  '  "properties": {',
  '    "schema": {"type": "string", "const": "entitlements.v1"},',
  '    "issued_at_utc": {"type": "string", "format": "date-time"},',
  '    "demo_expiry_utc": {"type": "string", "format": "date-time"},',
  '    "subject": {"type": "string", "minLength": 1},',
  '    "tier": {"type": "string", "enum": ["personal","team","business","enterprise","admin"]},',
  '    "enabled_profiles": {"type": "array", "minItems": 1, "items": {"type": "string", "enum": ["prod","dev"]}},',
  '    "enabled_engines": {"type": "array", "minItems": 1, "items": {"type": "string", "minLength": 1}},',
  '    "audit_level": {"type": "string", "enum": ["none","basic","full"]},',
  '    "notes": {"type": "string"}',
  '  }',
  '}'
) -join "`n"
Write-Text "schemas\common\entitlements.schema.json" $entSchema
$null = (Get-Content -Raw -LiteralPath (Join-Path $Root "schemas\common\entitlements.schema.json")) | ConvertFrom-Json

# -------------------------
# 5) docs/STRESS_TEST_PLAN.md
# -------------------------
Write-LinesNoBlanks "docs\STRESS_TEST_PLAN.md" @(
  "# Stress Test Plan (Contract Registry Canonical v1)"
  "Authority: Contract Registry"
  "Status: LOCKED"
  "Dev downloads MUST include a stress test runner that validates schemas + receipts + examples."
)

# -------------------------
# 6) docs/INTEGRATION_LAW.md
# -------------------------
Write-LinesNoBlanks "docs\INTEGRATION_LAW.md" @(
  "# Integration Law (Contract Registry Canonical v1)"
  "Authority: Contract Registry"
  "Status: LOCKED"
  "Rule: if Contract Registry verification fails, consumers MUST deny/stop regardless of internal policy."
)

# -------------------------
# 7) docs/examples/*.json (NO blank lines)
# -------------------------
Write-LinesNoBlanks "docs\examples\engine_registry.sample.json" @(
  "{","  ""schema"": ""engine.registry.v1"",","  ""generated_at_utc"": ""2026-02-02T00:00:00Z"",","  ""registry_version"": ""1.0.0"",","  ""engines"": [{""engine_id"": ""cr.verifier"", ""engine_type"": ""verifier"", ""version"": ""1.0.0"", ""entrypoint"": ""scripts/cr_verify.ps1"", ""enforced_contracts"": [""docs/CONSUME.md""]}]","}"
)
Write-LinesNoBlanks "docs\examples\entitlements.sample.json" @(
  "{","  ""schema"": ""entitlements.v1"",","  ""issued_at_utc"": ""2026-02-02T00:00:00Z"",","  ""demo_expiry_utc"": ""2026-03-03T00:00:00Z"",","  ""subject"": ""demo-customer-001"",","  ""tier"": ""business"",","  ""enabled_profiles"": [""dev"",""prod""],","  ""enabled_engines"": [""cr.verifier""],","  ""audit_level"": ""full"",","  ""notes"": ""Demo entitlement""","}"
)
Write-LinesNoBlanks "docs\examples\contracts.lock.sample.json" @(
  "{","  ""schema"": ""contracts.lock.v1"",","  ""generated_at_utc"": ""2026-02-02T00:00:00Z"",","  ""base"": {""packet_id"": ""0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"", ""version"": ""1.0.0"", ""source"": ""contract-registry release packet""},","  ""trust_bundle"": {""bundle_id"": ""cr-trust-bundle-v1"", ""source"": ""trust packet""},","  ""overlays"": []","}"
)

# -------------------------
# 8) scripts/_cr_stress_test_v1.ps1
# -------------------------
$stress = @(
  '$ErrorActionPreference="Stop"',
  'Set-StrictMode -Version Latest',
  '',
  '$Root = Split-Path -Parent $PSScriptRoot',
  'Set-Location $Root',
  '',
  'function Ok([string]$m){ Write-Host ("OK: " + $m) }',
  'function Fail([string]$m){ throw $m }',
  '',
  'Ok "running status check"',
  '& (Join-Path $Root "scripts\_cr_status_check_v1.ps1")',
  '',
  'Ok "schema parse check (only *.schema.json; receipt txt excluded)"',
  '$SchemaFiles = Get-ChildItem -LiteralPath (Join-Path $Root "schemas") -Recurse -File -Filter "*.schema.json" | Sort-Object FullName',
  'foreach($f in $SchemaFiles){ try { $null = (Get-Content -Raw -LiteralPath $f.FullName) | ConvertFrom-Json } catch { Fail ("Schema JSON parse failed: " + $f.FullName) } }',
  'Ok ("schema json files parsed: " + $SchemaFiles.Count)',
  '',
  'Ok "stress test complete"'
) -join "`n"
Write-Text "scripts\_cr_stress_test_v1.ps1" $stress

# -------------------------
# 9) Refresh schema receipt (schemas only)
# -------------------------
$SchemaFiles = Get-ChildItem -LiteralPath (Join-Path $Root "schemas") -Recurse -File -Filter "*.schema.json" | Sort-Object FullName
$ReceiptLines = foreach ($f in $SchemaFiles) {
  $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash.ToLowerInvariant()
  $rel = $f.FullName.Substring($Root.Length).TrimStart("\")
  "{0}  {1}" -f $h, $rel
}
$Out = Join-Path $Root "schemas\_schema_write_status_v1.txt"
Set-Content -LiteralPath $Out -Value ($ReceiptLines -join "`n") -Encoding UTF8 -NoNewline

# -------------------------
# 10) Require enterprise surface outputs in status check
# -------------------------
$Status = Join-Path $Root "scripts\_cr_status_check_v1.ps1"
$need = @(
  "docs\ENGINE_REGISTRY.md",
  "docs\LICENSING_ENTITLEMENTS.md",
  "docs\STRESS_TEST_PLAN.md",
  "docs\INTEGRATION_LAW.md",
  "schemas\common\engine_registry.schema.json",
  "schemas\common\entitlements.schema.json",
  "docs\examples\engine_registry.sample.json",
  "docs\examples\entitlements.sample.json",
  "docs\examples\contracts.lock.sample.json",
  "scripts\_cr_stress_test_v1.ps1"
)
Patch-Expected -StatusPath $Status -Need $need

# -------------------------
# 11) Status + stress test (EXIT-CODE STRICT)
# -------------------------
Invoke-PS (Join-Path $Root "scripts\_cr_status_check_v1.ps1")
Invoke-PS (Join-Path $Root "scripts\_cr_stress_test_v1.ps1")
Write-Host "OK: enterprise surface LOCKED + status/stress passed (exit-code strict)"