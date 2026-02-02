$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$Root = "C:\dev\contract-registry"
if (-not (Test-Path -LiteralPath $Root)) { throw "Repo root not found: $Root" }
Set-Location $Root

function Ensure-Dir([string]$Rel){
  $p = Join-Path $Root $Rel
  if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
}

function Write-Text([string]$RelPath, [string]$Content){
  $full = Join-Path $Root $RelPath
  $parent = Split-Path -Parent $full
  if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  Set-Content -LiteralPath $full -Value $Content -Encoding UTF8 -NoNewline
}

function Write-Lines([string]$RelPath, [string[]]$Lines){
  Write-Text -RelPath $RelPath -Content ($Lines -join "`n")
}

# -------------------------
# 0) Dirs
# -------------------------
Ensure-Dir "schemas\nfl"
Ensure-Dir "docs\nfl"
Ensure-Dir "vectors\nfl\v1_1\sample_packet\payload"
Ensure-Dir "vectors\nfl\v1_1\sample_packet\signatures"

# -------------------------
# 1) Schemas (NFL v1.1)
# -------------------------

# 1.1 commitment payload (commit.payload.json)
Write-Lines "schemas\nfl\commitment.v1.schema.json" @(
'{',
'  "$id": "contract:commitment_payload@1.1.0",',
'  "type": "object",',
'  "additionalProperties": false,',
'  "required": ["schema","producer","producer_instance","tenant","principal","event_type","event_time_utc","prev_links","content_ref","strength"],',
'  "properties": {',
'    "schema": {"type": "string", "const": "commitment.v1"},',
'    "producer": {"type": "string", "minLength": 1},',
'    "producer_instance": {"type": "string", "minLength": 1},',
'    "tenant": {"type": "string", "minLength": 1},',
'    "principal": {"type": "string", "minLength": 1},',
'    "event_type": {"type": "string", "minLength": 1},',
'    "event_time_utc": {"type": "string", "format": "date-time"},',
'    "prev_links": {"type": "array", "items": {"type": "string"}, "uniqueItems": true},',
'    "content_ref": {"type": "string", "minLength": 1},',
'    "strength": {"type": "string", "enum": ["evidence","deterministic"]},',
'    "meta": {"type": "object"},',
'    "notes_ref": {"type": "string"}',
'  }',
'}'
)

# 1.2 nfl ingest envelope (payload\nfl.ingest.json)
Write-Lines "schemas\nfl\nfl.ingest.v1.schema.json" @(
'{',
'  "$id": "contract:nfl_ingest@1.1.0",',
'  "type": "object",',
'  "additionalProperties": false,',
'  "required": ["schema","packet_id","commit_hash","producer","producer_instance","tenant","principal","event_type","event_time_utc","prev_links","payload_mode","payload_ref","producer_key_id","producer_sig_ref"],',
'  "properties": {',
'    "schema": {"type": "string", "const": "nfl.ingest.v1"},',
'    "packet_id": {"$ref": "../common/sha256_hex.schema.json"},',
'    "commit_hash": {"$ref": "../common/sha256_hex.schema.json"},',
'    "producer": {"type": "string", "minLength": 1},',
'    "producer_instance": {"type": "string", "minLength": 1},',
'    "tenant": {"type": "string", "minLength": 1},',
'    "principal": {"type": "string", "minLength": 1},',
'    "event_type": {"type": "string", "minLength": 1},',
'    "event_time_utc": {"type": "string", "format": "date-time"},',
'    "prev_links": {"type": "array", "items": {"type": "string"}, "uniqueItems": true},',
'    "payload_mode": {"type": "string", "enum": ["pointer_only","inline_sealed","inline_plain"]},',
'    "payload_ref": {"type": "string", "minLength": 1},',
'    "producer_key_id": {"type": "string", "minLength": 1},',
'    "producer_sig_ref": {"type": "string", "minLength": 1}',
'  }',
'}'
)

# 1.3 sig envelope (payload\sig_envelope.json)
Write-Lines "schemas\nfl\sig_envelope.v1.schema.json" @(
'{',
'  "$id": "contract:sig_envelope@1.1.0",',
'  "type": "object",',
'  "additionalProperties": false,',
'  "required": ["schema","algo","key_id","signing_context","signs"],',
'  "properties": {',
'    "schema": {"type": "string", "const": "sig_envelope.v1"},',
'    "algo": {"type": "string", "const": "ed25519"},',
'    "key_id": {"type": "string", "minLength": 1},',
'    "signing_context": {"type": "string", "const": "nfl.ingest.v1"},',
'    "signs": {',
'      "type": "object",',
'      "additionalProperties": false,',
'      "required": ["commit_hash","packet_id"],',
'      "properties": {',
'        "commit_hash": {"$ref": "../common/sha256_hex.schema.json"},',
'        "packet_id": {"$ref": "../common/sha256_hex.schema.json"},',
'        "ingest_hash": {"$ref": "../common/sha256_hex.schema.json"}',
'      }',
'    }',
'  }',
'}'
)

# 1.4 local pledge chain (pledges.ndjson line)
Write-Lines "schemas\nfl\local_pledge.v1.schema.json" @(
'{',
'  "$id": "contract:local_pledge@1.1.0",',
'  "type": "object",',
'  "additionalProperties": false,',
'  "required": ["schema","created_at_utc","seq","producer","producer_instance","tenant","principal","key_id","commit_hash","sig_path","prev_log_hash","log_hash"],',
'  "properties": {',
'    "schema": {"type": "string", "const": "local_pledge.v1"},',
'    "created_at_utc": {"type": "string", "format": "date-time"},',
'    "seq": {"type": "integer", "minimum": 1},',
'    "producer": {"type": "string", "minLength": 1},',
'    "producer_instance": {"type": "string", "minLength": 1},',
'    "tenant": {"type": "string", "minLength": 1},',
'    "principal": {"type": "string", "minLength": 1},',
'    "key_id": {"type": "string", "minLength": 1},',
'    "commit_hash": {"$ref": "../common/sha256_hex.schema.json"},',
'    "sig_path": {"type": "string", "minLength": 1},',
'    "prev_log_hash": {"type": "string", "minLength": 1},',
'    "log_hash": {"$ref": "../common/sha256_hex.schema.json"}',
'  }',
'}'
)

# 1.5 repo witness chain (repo-local readable + replayable commits)
Write-Lines "schemas\nfl\repo_witness.v1.schema.json" @(
'{',
'  "$id": "contract:repo_witness@1.1.0",',
'  "type": "object",',
'  "additionalProperties": false,',
'  "required": ["schema","created_at_utc","producer","producer_instance","tenant","principal","packet_id","commit_hash","sig_path","outbox_rel","prev_witness_hash","witness_hash"],',
'  "properties": {',
'    "schema": {"type": "string", "const": "repo.witness.v1"},',
'    "created_at_utc": {"type": "string", "format": "date-time"},',
'    "producer": {"type": "string", "minLength": 1},',
'    "producer_instance": {"type": "string", "minLength": 1},',
'    "tenant": {"type": "string", "minLength": 1},',
'    "principal": {"type": "string", "minLength": 1},',
'    "packet_id": {"$ref": "../common/sha256_hex.schema.json"},',
'    "commit_hash": {"$ref": "../common/sha256_hex.schema.json"},',
'    "sig_path": {"type": "string", "minLength": 1},',
'    "outbox_rel": {"type": "string", "minLength": 1},',
'    "nfl_inbox_rel": {"type": "string"},',
'    "pledge_log_hash": {"type": "string"},',
'    "prev_witness_hash": {"type": "string", "minLength": 1},',
'    "witness_hash": {"$ref": "../common/sha256_hex.schema.json"}',
'  }',
'}'
)

# 1.6 packet manifest (manifest.json)
Write-Lines "schemas\nfl\packet_manifest.v1.schema.json" @(
'{',
'  "$id": "contract:packet_manifest@1.1.0",',
'  "type": "object",',
'  "additionalProperties": false,',
'  "required": ["schema","packet_id","producer","producer_instance","created_at_utc","files"],',
'  "properties": {',
'    "schema": {"type": "string", "const": "packet_manifest.v1"},',
'    "packet_id": {"$ref": "../common/sha256_hex.schema.json"},',
'    "producer": {"type": "string", "minLength": 1},',
'    "producer_instance": {"type": "string", "minLength": 1},',
'    "created_at_utc": {"type": "string", "format": "date-time"},',
'    "files": {',
'      "type": "array",',
'      "minItems": 1,',
'      "items": {',
'        "type": "object",',
'        "additionalProperties": false,',
'        "required": ["path","bytes","sha256"],',
'        "properties": {',
'          "path": {"type": "string", "minLength": 1},',
'          "bytes": {"type": "integer", "minimum": 0},',
'          "sha256": {"$ref": "../common/sha256_hex.schema.json"}',
'        }',
'      }',
'    }',
'  }',
'}'
)

# -------------------------
# 2) Docs (NFL v1.1) — canonical text
# -------------------------
Write-Lines "docs\nfl\PATHS_RULES_v1.md" @(
'# Paths Rules (Canonical v1)',
'Contract Scope: NFL transport + sealing paths',
'## Rules (LOCKED)',
'- All bundle paths MUST be relative.',
'- Canonical separator is forward slash (/).',
'- No absolute paths.',
'- No drive letters (e.g., C:).',
'- No .. segments.',
'- No leading slash (/).'
)

Write-Lines "docs\nfl\CANON_RULES_JSON_v1.md" @(
'# Canonicalization Rules (JSON/NDJSON) — Canonical v1',
'Contract Scope: bytes that are hashed + signed',
'## JSON canonical bytes (LOCKED)',
'- UTF-8 without BOM.',
'- Object keys sorted ascending (ordinal).',
'- No insignificant whitespace.',
'- Numbers serialized minimally (no trailing zeros).',
'- Newlines: \\n only (LF).',
'- Arrays preserve order.',
'- Strings preserved exactly (no normalization beyond JSON escaping).',
'## NDJSON line canonicalization (LOCKED)',
'- Each log entry is a single JSON object serialized with the JSON rules above.',
'- Exactly one object per line.',
'- No blank lines.'
)

Write-Lines "docs\nfl\SPEC_NFL_HANDOFF_v1_1.md" @(
'# SPEC_NFL_HANDOFF_v1_1 (Canonical NFL Skeleton v1.1)',
'This document is a contract. Producers MUST obey it to be compatible with NFL witness + replay.',
'## Repo layout (MUST)',
'<repo-root>\\',
'  README.md',
'  LICENSE',
'  LAW.md',
'  SPEC_NFL_HANDOFF_v1_1.md',
'  schemas\\ (producer-local mirrors of Contract Registry outputs)',
'  contracts\\ (event types registry + canon/paths text)',
'  src\\nfl\\ (boring plugin kit: Canon, Hash, Sign, Verify, Packet, LocalPledgeLog, NflIngestEnvelope)',
'  tests\\vectors\\sample_packet\\ (golden sample packet)',
'  scripts\\ (bootstrap_repo, make_packet, verify_packet, pledge_local, duplicate_to_nfl)',
'## Runtime layout (MUST)',
'Producer:',
'C:\\ProgramData\\<Producer>\\pledges\\pledges.ndjson',
'C:\\ProgramData\\<Producer>\\outbox\\<PacketId>\\...',
'NFL:',
'C:\\ProgramData\\NFL\\inbox\\<PacketId>\\...',
'## Packet skeleton (MUST be byte-identical in outbox and NFL inbox)',
'<PacketRoot>\\',
'  manifest.json',
'  sha256sums.txt',
'  payload\\',
'    commit.payload.json',
'    commit_hash.txt',
'    nfl.ingest.json',
'    sig_envelope.json',
'  signatures\\',
'    ingest.sig',
'## Hash laws (MUST)',
'CommitHash = SHA-256(canonical_bytes(commit.payload.json))',
'PacketId   = SHA-256(canonical_bytes(manifest.json))',
'Local pledge chain: log_hash = SHA-256(canonical_bytes(line_without_log_hash)), prev_log_hash chains (GENESIS for first)',
'Repo witness chain: witness_hash = SHA-256(canonical_bytes(entry_without_witness_hash)), prev_witness_hash chains (GENESIS for first)',
'## Verification routine (MUST)',
'- sha256sums.txt matches bytes of referenced files',
'- manifest.json lists exactly the packet files and hashes match',
'- recompute CommitHash and match commit_hash.txt',
'- recompute ingest_hash (optional) and match envelope if present',
'- verify ingest.sig against sig_envelope using key_id',
'- verify pledge chain integrity (local)',
'- verify witness chain integrity (repo)'
)

# -------------------------
# 3) Vectors placeholders (freeze later)
# -------------------------
Write-Lines "vectors\nfl\v1_1\README.md" @(
'Golden vectors for NFL Skeleton v1.1 live here.',
'Freeze these once at least one reference implementation exists.',
'Any contract change MUST update vectors and corresponding tests in producer repos.'
)

Write-Lines "vectors\nfl\v1_1\sample_packet\README.md" @(
'Placeholder sample_packet directory.',
'Replace with a real golden packet once producer implementations exist.',
'This directory structure MUST match SPEC_NFL_HANDOFF_v1_1 exactly.'
)

# -------------------------
# 4) Refresh schema receipt (schemas only)
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
# 5) Patch status check to require these outputs (NO helper left behind)
# -------------------------
$Status = Join-Path $Root "scripts\_cr_status_check_v1.ps1"
if (-not (Test-Path -LiteralPath $Status)) { throw "Missing: scripts\_cr_status_check_v1.ps1" }

$txt = Get-Content -Raw -LiteralPath $Status

$need = @(
  "schemas\nfl\commitment.v1.schema.json",
  "schemas\nfl\nfl.ingest.v1.schema.json",
  "schemas\nfl\sig_envelope.v1.schema.json",
  "schemas\nfl\local_pledge.v1.schema.json",
  "schemas\nfl\repo_witness.v1.schema.json",
  "schemas\nfl\packet_manifest.v1.schema.json",
  "docs\nfl\SPEC_NFL_HANDOFF_v1_1.md",
  "docs\nfl\CANON_RULES_JSON_v1.md",
  "docs\nfl\PATHS_RULES_v1.md",
  "vectors\nfl\v1_1\README.md",
  "vectors\nfl\v1_1\sample_packet\README.md"
)

# Locate $Expected = @( ... )
$pat = '(?s)(\$Expected\s*=\s*@\()(.*?)(\r?\n\))'
$m = [regex]::Match($txt, $pat)
if (-not $m.Success) {
  throw "Could not locate `$Expected = @(` block in scripts\_cr_status_check_v1.ps1"
}

$head = $m.Groups[1].Value
$body = $m.Groups[2].Value
$tail = $m.Groups[3].Value

foreach ($n in $need) {
  if ($txt -notmatch [regex]::Escape($n)) {
    # Insert as a quoted string line in the array body
    if ($body -notmatch '\S') {
      $body = "`n  `"$n`""
    } else {
      $body = $body.TrimEnd() + "`n  `"$n`""
    }
  }
}

# Rebuild without introducing trailing commas
$newBlock = $head + $body + $tail
$txt = [regex]::Replace($txt, $pat, [System.Text.RegularExpressions.MatchEvaluator]{ param($mm) $newBlock }, 1)

Set-Content -LiteralPath $Status -Value $txt -Encoding UTF8 -NoNewline

# -------------------------
# 6) Status check
# -------------------------
powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root "scripts\_cr_status_check_v1.ps1")

Write-Host "OK: Contract Registry now publishes NFL Skeleton v1.1 contracts (schemas+docs+vectors) + requires them in status check"
Write-Host ("OK: refreshed receipt {0}" -f $Out)