$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$Root="C:\dev\contract-registry"
if(-not(Test-Path -LiteralPath $Root)){ throw "Repo root not found: $Root" }

function Write-FileLines {
  param(
    [Parameter(Mandatory=$true)][string]$RelPath,
    [Parameter(Mandatory=$true)][string[]]$Lines
  )
  $Full = Join-Path $Root $RelPath
  $Parent = Split-Path -Parent $Full
  if(-not(Test-Path -LiteralPath $Parent)){ New-Item -ItemType Directory -Path $Parent -Force | Out-Null }
  Set-Content -LiteralPath $Full -Value ($Lines -join "`n") -Encoding UTF8 -NoNewline
}

Write-FileLines "schemas\common\signing_context.schema.json" @(
  "{",
  "  `"$id`": `"contract:signing_context@1.0.0`",",
  "  `"type`": `"object`",",
  "  `"description`": `"LOCKED v1: defines what bytes are signed and how to interpret a detached signature.`",",
  "  `"required`": [`"context_type`",`"canonicalization`",`"signed_sha256`",`"signature_envelope`"],",
  "  `"properties`": {",
  "    `"context_type`": {",
  "      `"type`": `"string`",",
  "      `"enum`": [",
  "        `"packet_manifest`",",
  "        `"triad_receipt`",",
  "        `"watchtower_ingestion_receipt`",",
  "        `"trust_bundle`",",
  "        `"license`",",
  "        `"gate_decision`"",
  "      ]",
  "    },",
  "    `"canonicalization`": {",
  "      `"type`": `"object`",",
  "      `"description`": `"Canonical JSON rules used to produce the bytes that are hashed and signed.`",",
  "      `"required`": [`"format`",`"encoding`",`"line_endings`",`"key_order`"],",
  "      `"properties`": {",
  "        `"format`": {`"type`": `"string`", `"const`": `"json`"},",
  "        `"encoding`": {`"type`": `"string`", `"const`": `"utf-8`"},",
  "        `"line_endings`": {`"type`": `"string`", `"const`": `"lf`"},",
  "        `"key_order`": {`"type`": `"string`", `"const`": `"lexicographic`"}",
  "      },",
  "      `"additionalProperties`": false",
  "    },",
  "    `"signed_sha256`": {",
  "      `"$ref`": `"./sha256_hex.schema.json`",
  "    },",
  "    `"signed_components`": {",
  "      `"type`": `"array`",",
  "      `"description`": `"Optional list of named components included in the signed hash, for multi-file contexts.`",",
  "      `"items`": {",
  "        `"type`": `"object`",",
  "        `"required`": [`"name`",`"sha256`"],",
  "        `"properties`": {",
  "          `"name`": {`"type`": `"string`"},",
  "          `"sha256`": {`"$ref`": `"./sha256_hex.schema.json`"}",
  "        },",
  "        `"additionalProperties`": false",
  "      }",
  "    },",
  "    `"signature_envelope`": {",
  "      `"$ref`": `"./signature_envelope.schema.json`"",
  "    },",
  "    `"notes`": {`"type`": `"string`"}",
  "  },",
  "  `"additionalProperties`": false",
  "}",
)

Write-FileLines "docs\SIGNING_CONTEXT.md" @(
  "# Signing Context (Canonical v1)",
  "Contract ID: contract:signing_context@1.0.0",
  "## Purpose",
  "Define exactly what bytes are hashed and signed so every product signs the same thing deterministically.",
  "## Canonical bytes (LOCKED v1)",
  "- Serialize the target JSON object using UTF-8, LF line endings, and lexicographic key ordering.",
  "- Compute sha256 over the resulting bytes.",
  "- The signature is a detached signature over the sha256 digest (implementation may sign digest or the canonical bytes, but signed_sha256 is always recorded).",
  "## Where this applies",
  "- packet_manifest",
  "- triad_receipt",
  "- watchtower_ingestion_receipt",
  "- trust_bundle",
  "- license",
  "- gate_decision",
  "## Multi-file contexts",
  "If a context covers multiple files, include signed_components entries with each component name and sha256. The signed_sha256 is then computed over the canonical JSON of the signing context object containing those component hashes.",
)

Write-FileLines "vectors\signing_context\README.md" @(
  "Golden vectors for signing_context live here.",
  "v1: placeholder only. Freeze vectors once implementations exist to prevent drift.",
)

$SchemaFiles = Get-ChildItem -LiteralPath (Join-Path $Root "schemas") -Recurse -File | Sort-Object FullName
$ReceiptLines = foreach ($f in $SchemaFiles) {
  $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash.ToLowerInvariant()
  $rel = $f.FullName.Substring($Root.Length).TrimStart("\")
  "{0}  {1}" -f $h, $rel
}
$Out = Join-Path $Root "schemas\_schema_write_status_v1.txt"
Set-Content -LiteralPath $Out -Value ($ReceiptLines -join "`n") -Encoding UTF8 -NoNewline
Write-Host "OK: added signing_context contract + doc + vector; refreshed receipt"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root "scripts\_cr_status_check_v1.ps1")