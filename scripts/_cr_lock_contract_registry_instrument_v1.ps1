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
  foreach($l in $Lines){
    if($l -eq ""){ throw "Blank line not allowed in: $RelPath" }
  }
  Write-Text -RelPath $RelPath -Content ($Lines -join "`n")
}

function Patch-Expected([string]$StatusPath, [string[]]$Need){
  if(-not(Test-Path -LiteralPath $StatusPath)){ throw "Missing: $StatusPath" }
  $txt = Get-Content -Raw -LiteralPath $StatusPath
  $pat = '(?s)(\$Expected\s*=\s*@\()(.*?)(\r?\n\))'
  $m = [regex]::Match($txt, $pat)
  if(-not $m.Success){ throw "Could not locate `$Expected = @(` block in scripts\_cr_status_check_v1.ps1" }
  $head = $m.Groups[1].Value
  $body = $m.Groups[2].Value
  $tail = $m.Groups[3].Value
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

# ========================================================
# CONTRACT REGISTRY INSTRUMENT — LOCK SURFACE v1 (CANONICAL)
# ========================================================
Ensure-Dir "docs"
Ensure-Dir "schemas\common"

# -------------------------
# 1) docs/RELEASE.md (NO blank lines)
# -------------------------
Write-LinesNoBlanks "docs\RELEASE.md" @(
  "# Contract Registry Release Procedure (Canonical v1)"
  "Authority: Contract Registry"
  "Status: LOCKED"
  "Goal: publish contracts as immutable, verifiable law for other systems and enterprises."
  "## Release invariants (MUST)"
  "- Every release MUST be content-addressed and verifiable (sha256 + signature)."
  "- Releases MUST be deterministic: same inputs => same PacketId."
  "- Consumers MUST pin a release; never track moving branches."
  "## Versioning (MUST)"
  "- Use semantic versioning for the registry interface surface."
  "- Breaking contract changes REQUIRE a major version bump."
  "- Additive-only changes MAY be minor/patch versions."
  "## Canonical release steps (MUST)"
  "1) Update contracts (schemas/docs/vectors) in git working tree."
  "2) Run status check: scripts/_cr_status_check_v1.ps1 (must pass)."
  "3) Refresh schema receipt: schemas/_schema_write_status_v1.txt (schemas only)."
  "4) Commit changes with an explicit message describing contract intent."
  "5) Tag the commit: contract-registry/vX.Y.Z (annotated tag recommended)."
  "6) Build a release packet (Packet Constitution v1): directory bundle + manifest.json + sha256sums.txt."
  "7) Sign the packet manifest using the signing_context contract for packet_manifest."
  "8) Publish the packet to your distribution channel (GitHub release, artifact store, offline outbox/inbox)."
  "9) Publish or reference the Trust Bundle that authorizes the signer principal/key."
  "## Mandatory release outputs (MUST)"
  "- Packet manifest + sha256sums + detached signature."
  "- Release notes MUST include: version, PacketId, signer principal, key_id, and trust bundle id."
)

# -------------------------
# 2) docs/CONSUME.md (NO blank lines)
# -------------------------
Write-LinesNoBlanks "docs\CONSUME.md" @(
  "# Contract Registry Consumption Guide (Canonical v1)"
  "Authority: Contract Registry"
  "Status: LOCKED"
  "Goal: enable any repo or enterprise to adopt contracts without drift."
  "## Core rule (MUST)"
  "- A consumer MUST pin Contract Registry law by PacketId or immutable git ref; never a moving target."
  "## Supported adoption modes (choose one) (MUST)"
  "### Mode A — Pinned packet ingestion (enterprise-grade)"
  "- Consumer stores a contracts.lock.json that pins: base PacketId, trust bundle, signer identity, and optional overlays."
  "- CI verifies: sha256sums match + signature validates + signer is trusted + overlays obey overlay constitution."
  "### Mode B — Git submodule pinned to tag/commit (developer-friendly)"
  "- Add Contract Registry as a submodule and pin to an immutable tag/commit."
  "- CI enforces submodule pointer is exactly the pinned revision and clean."
  "### Mode C — Vendored mirror (offline/airgapped)"
  "- Copy required schemas/docs/vectors into consumer repo under a contracts/ folder."
  "- CI verifies vendored content hashes match the pinned registry release (receipt + signature evidence)."
  "## Drift prevention gate (MUST)"
  "- CI MUST fail if any contract file differs from the pinned release."
  "- CI MUST fail if contracts.lock.json changes without an explicit approval workflow."
  "## overlays (MUST)"
  "- Overlays are additive/tightening layers on top of base law (enterprise + project overlays)."
  "- Overlay precedence: base -> enterprise overlay(s) -> project overlay(s)."
  "- Overlays MUST be explicitly enabled and pinned the same way as base law."
  "## Lock file (MUST)"
  "- Consumers SHOULD use contracts.lock.json validated by schemas/common/contracts_lock.schema.json."
)

# -------------------------
# 3) docs/OVERLAY_CONSTITUTION.md (NO blank lines)
# -------------------------
Write-LinesNoBlanks "docs\OVERLAY_CONSTITUTION.md" @(
  "# Overlay Constitution (Canonical v1)"
  "Authority: Contract Registry"
  "Status: LOCKED"
  "Purpose: define how enterprise/project overlays may extend contract law without weakening or drifting base law."
  "## Definitions"
  "- Base law: the pinned Contract Registry release (schemas/docs/vectors)."
  "- Overlay law: a pinned, signed contract layer applied on top of base law."
  "## Precedence (LOCKED)"
  "1) Base contracts apply first."
  "2) Enterprise overlays apply next (zero or more, in declared order)."
  "3) Project overlays apply last (zero or more, in declared order)."
  "## Allowed overlay operations (MUST)"
  "- Add new contracts (new schema/doc/spec files under overlay namespace)."
  "- Tighten validation (add constraints) IF the base contract explicitly allows extension points."
  "- Add indexes/mappings that increase legibility without changing meaning."
  "## Forbidden overlay operations (MUST NOT)"
  "- Weaken canonicalization rules for any signing or hashing context."
  "- Alter base schema semantics without a version bump that declares incompatibility."
  "- Redefine PacketId / CommitHash / chain hash laws."
  "- Override trust rules to accept untrusted signers for base law."
  "## Overlay identity (MUST)"
  "- Every overlay MUST declare: overlay id, version, required base version range, signer principal, key_id, and trust bundle id."
  "## Overlay verification (MUST)"
  "- Overlay packets MUST verify sha256sums, signature, and signer trust."
  "- Overlay MUST be rejected if it violates forbidden operations."
  "## Breaking changes (MUST)"
  "- If overlay needs behavior incompatible with base, it MUST target a new major base version or declare incompatibility explicitly."
)

# -------------------------
# 4) schemas/common/contracts_lock.schema.json
# -------------------------
$schemaLines = @(
  '{',
  '  "$id": "contract:contracts_lock@1.0.0",',
  '  "type": "object",',
  '  "description": "LOCKED v1: pins Contract Registry law + optional overlays for deterministic consumption.",',
  '  "additionalProperties": false,',
  '  "required": ["schema","generated_at_utc","base","trust_bundle"],',
  '  "properties": {',
  '    "schema": {"type": "string", "const": "contracts.lock.v1"},',
  '    "generated_at_utc": {"type": "string", "format": "date-time"},',
  '    "consumer": {',
  '      "type": "object",',
  '      "additionalProperties": false,',
  '      "properties": {',
  '        "product": {"type": "string"},',
  '        "repo": {"type": "string"},',
  '        "environment": {"type": "string"}',
  '      }',
  '    },',
  '    "base": {',
  '      "type": "object",',
  '      "additionalProperties": false,',
  '      "required": ["packet_id","version","source"],',
  '      "properties": {',
  '        "packet_id": {"$ref": "./sha256_hex.schema.json"},',
  '        "version": {"type": "string", "minLength": 1},',
  '        "source": {"type": "string", "minLength": 1},',
  '        "signer_principal": {"type": "string"},',
  '        "signer_key_id": {"type": "string"},',
  '        "signature_ref": {"type": "string"},',
  '        "signing_context": {"$ref": "./signing_context.schema.json"}',
  '      }',
  '    },',
  '    "trust_bundle": {',
  '      "type": "object",',
  '      "additionalProperties": false,',
  '      "required": ["bundle_id","source"],',
  '      "properties": {',
  '        "bundle_id": {"type": "string", "minLength": 1},',
  '        "source": {"type": "string", "minLength": 1},',
  '        "packet_id": {"$ref": "./sha256_hex.schema.json"},',
  '        "signature_ref": {"type": "string"},',
  '        "signer_principal": {"type": "string"},',
  '        "signer_key_id": {"type": "string"}',
  '      }',
  '    },',
  '    "overlays": {',
  '      "type": "array",',
  '      "description": "Optional overlay layers applied after base (enterprise then project, in order).",',
  '      "items": {',
  '        "type": "object",',
  '        "additionalProperties": false,',
  '        "required": ["overlay_id","version","layer","packet_id","source"],',
  '        "properties": {',
  '          "overlay_id": {"type": "string", "minLength": 1},',
  '          "version": {"type": "string", "minLength": 1},',
  '          "layer": {"type": "string", "enum": ["enterprise","project"]},',
  '          "packet_id": {"$ref": "./sha256_hex.schema.json"},',
  '          "source": {"type": "string", "minLength": 1},',
  '          "requires_base": {"type": "string", "minLength": 1},',
  '          "signer_principal": {"type": "string"},',
  '          "signer_key_id": {"type": "string"},',
  '          "signature_ref": {"type": "string"},',
  '          "signing_context": {"$ref": "./signing_context.schema.json"}',
  '        }',
  '      }',
  '    },',
  '    "notes": {"type": "string"}',
  '  }',
  '}'
)
Write-Text "schemas\common\contracts_lock.schema.json" ($schemaLines -join "`n")

# Parse-check schema JSON (hard fail if invalid)
$null = (Get-Content -Raw -LiteralPath (Join-Path $Root "schemas\common\contracts_lock.schema.json")) | ConvertFrom-Json

# -------------------------
# 5) Refresh schema receipt (schemas only)
# -------------------------
$SchemaFiles = Get-ChildItem -LiteralPath (Join-Path $Root "schemas") -Recurse -File | Sort-Object FullName
$ReceiptLines = foreach ($f in $SchemaFiles) {
  $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash.ToLowerInvariant()
  $rel = $f.FullName.Substring($Root.Length).TrimStart("\")
  "{0}  {1}" -f $h, $rel
}
$Out = Join-Path $Root "schemas\_schema_write_status_v1.txt"
Set-Content -LiteralPath $Out -Value ($ReceiptLines -join "`n") -Encoding UTF8 -NoNewline

# -------------------------
# 6) Patch status check to require these instrument outputs
# -------------------------
$Status = Join-Path $Root "scripts\_cr_status_check_v1.ps1"
$need = @(
  "docs\RELEASE.md",
  "docs\CONSUME.md",
  "docs\OVERLAY_CONSTITUTION.md",
  "schemas\common\contracts_lock.schema.json"
)
Patch-Expected -StatusPath $Status -Need $need

# -------------------------
# 7) Status check
# -------------------------
powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root "scripts\_cr_status_check_v1.ps1")
Write-Host "OK: Contract Registry instrument surface LOCKED (release+consume+overlay constitution+lock schema) + required in status check"
Write-Host ("OK: refreshed receipt {0}" -f $Out)