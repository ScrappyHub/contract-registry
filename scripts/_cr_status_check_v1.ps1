$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$Root = "C:\dev\contract-registry"
if (-not (Test-Path -LiteralPath $Root)) { throw "Repo root not found: $Root" }

$Expected = @(
  "schemas\common\principal.schema.json",
  "schemas\common\signature_envelope.schema.json",
  "schemas\common\sha256_hex.schema.json",
  "schemas\common\key_allowlist.schema.json",
  "schemas\watchtower\event_type.schema.json",
  "schemas\watchtower\identity_update.schema.json",
  "schemas\watchtower\key_rotation.schema.json",
  "schemas\gate\decision.schema.json",
  "schemas\triad\triad_receipt.schema.json",
  "schemas\transport\packet_manifest.schema.json",
  "schemas\trust\trust_bundle.schema.json",
  "schemas\license\license.schema.json",
  "schemas\license\license_usage_log_entry.schema.json",
  "schemas\_schema_write_status_v1.txt"
  "schemas\common\signing_context.schema.json",
  "docs\SIGNING_CONTEXT.md",
  "vectors\signing_context\README.md"
)

foreach ($r in $Expected) {
  $p = Join-Path $Root $r
  if (-not (Test-Path -LiteralPath $p)) { throw "Missing required file: $r" }
}

# JSON parse check (not schema validation; just confirms valid JSON)
$SchemaFiles = Get-ChildItem -LiteralPath (Join-Path $Root "schemas") -Recurse -File |
  Where-Object { $_.Name -like "*.json" } | Sort-Object FullName

foreach ($f in $SchemaFiles) {
  try {
    $null = (Get-Content -Raw -LiteralPath $f.FullName) | ConvertFrom-Json
  } catch {
    throw "Invalid JSON: $($f.FullName) :: $($_.Exception.Message)"
  }
}

"OK: status check passed"
"OK: schema json files parsed: {0}" -f $SchemaFiles.Count