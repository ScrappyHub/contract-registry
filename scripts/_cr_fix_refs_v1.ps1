$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$Root = "C:\dev\contract-registry"
if (-not (Test-Path -LiteralPath $Root)) { throw "Repo root not found: $Root" }

function Replace-InFile {
  param(
    [Parameter(Mandatory=$true)][string]$RelPath,
    [Parameter(Mandatory=$true)][hashtable]$Map
  )
  $p = Join-Path $Root $RelPath
  if (-not (Test-Path -LiteralPath $p)) { throw "Missing: $RelPath" }
  $s = Get-Content -Raw -LiteralPath $p
  foreach ($k in $Map.Keys) { $s = $s.Replace($k, $Map[$k]) }
  Set-Content -LiteralPath $p -Value $s -Encoding UTF8 -NoNewline
}

# Common replacement map (contract: refs -> relative file refs)
$MapCommon = @{
  '"$ref":"contract:sha256_hex@1.0.0"' = '"$ref":"../common/sha256_hex.schema.json"'
  '"$ref":"contract:principal@1.0.0"' = '"$ref":"../common/principal.schema.json"'
  '"$ref":"contract:signature_envelope@1.0.0"' = '"$ref":"../common/signature_envelope.schema.json"'
  '"$ref": "contract:principal@1.0.0"' = '"$ref":"../common/principal.schema.json"'
  '"$ref": "contract:signature_envelope@1.0.0"' = '"$ref":"../common/signature_envelope.schema.json"'
  '"$ref": "contract:sha256_hex@1.0.0"' = '"$ref":"../common/sha256_hex.schema.json"'
}

$Targets = @(
  "schemas\watchtower\identity_update.schema.json",
  "schemas\watchtower\key_rotation.schema.json",
  "schemas\gate\decision.schema.json",
  "schemas\triad\triad_receipt.schema.json",
  "schemas\transport\packet_manifest.schema.json",
  "schemas\trust\trust_bundle.schema.json",
  "schemas\license\license.schema.json",
  "schemas\license\license_usage_log_entry.schema.json"
)

foreach ($t in $Targets) { Replace-InFile -RelPath $t -Map $MapCommon }

# Rebuild receipt
$SchemaFiles = Get-ChildItem -LiteralPath (Join-Path $Root "schemas") -Recurse -File | Sort-Object FullName
$Lines = @()
foreach ($f in $SchemaFiles) {
  $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash.ToLowerInvariant()
  $rel = $f.FullName.Substring($Root.Length).TrimStart("\")
  $Lines += ("{0}  {1}" -f $h, $rel)
}
$Out = Join-Path $Root "schemas\_schema_write_status_v1.txt"
Set-Content -LiteralPath $Out -Value ($Lines -join "`n") -Encoding UTF8 -NoNewline

"OK: refs normalized to relative paths"
"OK: updated receipt {0}" -f $Out