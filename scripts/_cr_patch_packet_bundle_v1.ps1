$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$Root = "C:\dev\contract-registry"
if (-not (Test-Path -LiteralPath $Root)) { throw "Repo root not found: $Root" }

function Write-File {
  param(
    [Parameter(Mandatory=$true)][string]$RelPath,
    [Parameter(Mandatory=$true)][string[]]$ContentLines
  )
  $Full = Join-Path $Root $RelPath
  $Parent = Split-Path -Parent $Full
  if (-not (Test-Path -LiteralPath $Parent)) { New-Item -ItemType Directory -Path $Parent -Force | Out-Null }
  Set-Content -LiteralPath $Full -Value ($ContentLines -join "`n") -Encoding UTF8 -NoNewline
}

Write-File "schemas\transport\sha256sums_file.schema.json" @(
  "{",
  "  `"$id`": `"contract:sha256sums_file@1.0.0`",",
  "  `"type`": `"object`",",
  "  `"description`": `"Canonical sha256sums.txt format for directory bundle sealing.`",",
  "  `"required`": [`"format`",`"hash_alg`",`"line_pattern`",`"path_rules`"],",
  "  `"properties`": {",
  "    `"format`": {`"type`": `"string`", `"enum`": [`"sha256sums.txt`"]},",
  "    `"hash_alg`": {`"type`": `"string`", `"enum`": [`"sha256`"]},",
  "    `"line_pattern`": {",
  "      `"type`": `"string`",",
  "      `"description`": `"Each line: <64 lowercase hex><two spaces><relative path> using forward slashes.`",",
  "      `"const`": `"^[a-f0-9]{64}  [A-Za-z0-9._/\\\\-]+$`"",
  "    },",
  "    `"path_rules`": {",
  "      `"type`": `"object`",",
  "      `"required`": [`"relative_only`",`"no_dotdot`",`"no_drive_letters`",`"no_leading_slash`",`"separator`",`"sort_order`"],",
  "      `"properties`": {",
  "        `"relative_only`": {`"type`": `"boolean`", `"const`": true},",
  "        `"no_dotdot`": {`"type`": `"boolean`", `"const`": true},",
  "        `"no_drive_letters`": {`"type`": `"boolean`", `"const`": true},",
  "        `"no_leading_slash`": {`"type`": `"boolean`", `"const`": true},",
  "        `"separator`": {`"type`": `"string`", `"enum`": [`"/`"]},",
  "        `"sort_order`": {`"type`": `"string`", `"enum`": [`"lexicographic_by_path`"]}",
  "      },",
  "      `"additionalProperties`": false",
  "    }",
  "  },",
  "  `"additionalProperties`": false",
  "}",
)

Write-File "schemas\transport\packet_bundle_layout.schema.json" @(
  "{",
  "  `"$id`": `"contract:packet_bundle_layout@1.0.0`",",
  "  `"type`": `"object`",",
  "  `"description`": `"Canonical directory bundle layout for offline transport packets.`",",
  "  `"required`": [`"layout_version`",`"required_paths`",`"path_rules`",`"signing_rules`"],",
  "  `"properties`": {",
  "    `"layout_version`": {`"type`": `"string`", `"const`": `"v1`"},",
  "    `"required_paths`": {",
  "      `"type`": `"array`",",
  "      `"items`": {`"type`": `"string`"},",
  "      `"minItems`": 4,",
  "      `"uniqueItems`": true,",
  "      `"const`": [",
  "        `"manifest.json`",",
  "        `"sha256sums.txt`",",
  "        `"signatures/`",",
  "        `"payload/`"",
  "      ]",
  "    },",
  "    `"path_rules`": {",
  "      `"type`": `"object`",",
  "      `"required`": [`"canonical_separator`",`"deny_absolute_paths`",`"deny_dotdot`",`"deny_drive_letters`"],",
  "      `"properties`": {",
  "        `"canonical_separator`": {`"type`": `"string`", `"enum`": [`"/`"]},",
  "        `"deny_absolute_paths`": {`"type`": `"boolean`", `"const`": true},",
  "        `"deny_dotdot`": {`"type`": `"boolean`", `"const`": true},",
  "        `"deny_drive_letters`": {`"type`": `"boolean`", `"const`": true}",
  "      },",
  "      `"additionalProperties`": false",
  "    },",
  "    `"signing_rules`": {",
  "      `"properties`": {",
  "        `"detached_signatures`": {`"type`": `"boolean`", `"const`": true},",
  "        `"signature_dir`": {`"type`": `"string`", `"const`": `"signatures/`"},",
  "        `"sig_extension`": {`"type`": `"string`", `"const`": `".sig`"},",
  "        `"verification_tool`": {`"type`": `"string`", `"enum`": [`"ssh-keygen -Y verify`"]}",
  "      },",
  "      `"additionalProperties`": false",
  "    }",
  "  },",
  "  `"additionalProperties`": false",
  "}",
)

Write-File "docs\SHA256SUMS.md" @(
  "# SHA256SUMS (Canonical v1)",
  "",
  "Contract ID: contract:sha256sums_file@1.0.0",
  "",
  "## Purpose",
  "Define a deterministic sha256sums.txt file format for sealing directory bundles (packets, artifacts, receipts).",
  "",
  "## Line format (LOCKED)",
  "- Each line: `<sha256hex>␠␠<relative_path>` (two spaces).",
  "- sha256hex is 64 lowercase hex.",
  "- Paths are relative and normalized with forward slashes (`/`).",
  "",
  "## Path rules (LOCKED)",
  "- No absolute paths.",
  "- No drive letters (e.g., `C:`).",
  "- No `..` segments.",
  "- No leading `/`.",
  "",
  "## Ordering (LOCKED)",
  "- Lines are sorted lexicographically by `<relative_path>` using byte-order of UTF-8.",
)

Write-File "docs\PACKET_BUNDLE_LAYOUT.md" @(
  "# Packet Bundle Layout (Canonical v1)",
  "",
  "Contract ID: contract:packet_bundle_layout@1.0.0",
  "",
  "## Purpose",
  "Define a deterministic directory layout for offline transport packets.",
  "",
  "## Required paths (LOCKED)",
  "- `manifest.json`",
  "- `sha256sums.txt`",
  "- `signatures/` (directory)",
  "- `payload/` (directory)",
  "",
  "## Signing (LOCKED v1)",
  "- Detached signatures in `signatures/*.sig`.",
  "- Verification tool: `ssh-keygen -Y verify`.",
  "",
  "## Hashing (LOCKED v1)",
  "- `sha256sums.txt` is computed over all files in the bundle except `signatures/*.sig` (signatures do not sign themselves).",
  "- Paths in sha256sums use forward slashes.",
)

$SchemaFiles = Get-ChildItem -LiteralPath (Join-Path $Root "schemas") -Recurse -File | Sort-Object FullName
$ReceiptLines = foreach ($f in $SchemaFiles) {
  $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash.ToLowerInvariant()
  $rel = $f.FullName.Substring($Root.Length).TrimStart("\")
  "{0}  {1}" -f $h, $rel
}
$Out = Join-Path $Root "schemas\_schema_write_status_v1.txt"
Set-Content -LiteralPath $Out -Value ($ReceiptLines -join "`n") -Encoding UTF8 -NoNewline
"OK: added sha256sums + packet bundle layout contracts"
"OK: updated receipt {0}" -f $Out

powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root "scripts\_cr_status_check_v1.ps1")