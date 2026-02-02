# Canonicalization Rules (JSON/NDJSON) — Canonical v1
Contract Scope: bytes that are hashed + signed
## JSON canonical bytes (LOCKED)
- UTF-8 without BOM.
- Object keys sorted ascending (ordinal).
- No insignificant whitespace.
- Numbers serialized minimally (no trailing zeros).
- Newlines: \\n only (LF).
- Arrays preserve order.
- Strings preserved exactly (no normalization beyond JSON escaping).
## NDJSON line canonicalization (LOCKED)
- Each log entry is a single JSON object serialized with the JSON rules above.
- Exactly one object per line.
- No blank lines.