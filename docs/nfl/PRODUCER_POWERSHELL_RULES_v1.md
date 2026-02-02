# Producer PowerShell Rules (NFL Canonical v1.1)
Authority: Contract Registry
Scope: These rules prevent producer drift and broken witness/packet emission caused by PowerShell execution footguns.
Status: LOCKED
## Rule 1 — No session-local helper functions
- Producers MUST NOT rely on functions defined in an interactive session (e.g., Write-Text, Ensure-Dir) to build scripts or artifacts.
- Any helper function REQUIRED for execution MUST be defined inside the script that uses it.
- Rationale: producers must be deterministic under powershell.exe -File execution with a clean session.
## Rule 2 — No nested here-strings; avoid here-strings when emitting scripts
- Producers MUST NOT embed a here-string delimiter (at-sign quote) inside a here-string that is being written to disk.
- If a producer emits scripts, prefer line arrays joined by `n to avoid unterminated here-string corruption.
- Rationale: unterminated here-strings cause parser failure at runtime (missing terminator).
## Rule 3 — Canonical workflow: write scripts to files, then run via -File
- Producers MUST write scripts to disk using Set-Content (UTF8, NoNewline) and execute them via powershell.exe -NoProfile -ExecutionPolicy Bypass -File <path>.
- Producers MUST NOT paste script bodies into interactive PowerShell as an execution method.
## Rule 4 — Canonical JSON bytes are contract-defined, not ConvertTo-Json-defined
- ConvertTo-Json -Compress is NOT a canonicalizer and MUST NOT be treated as such unless the producer constrains input types and key ordering exactly to the contract.
- Producers MUST follow docs/nfl/CANON_RULES_JSON_v1.md for any bytes that are hashed and/or signed.
## Rule 5 — Fail fast on missing expected outputs
- Producers MUST hard-fail if required packet files or witness ledgers are missing; do not create partial state silently.
## Rule 6 — No overwrite of inbox/outbox packet roots
- Producers MUST refuse overwriting an existing PacketId folder in outbox or NFL inbox; copy/duplicate must be atomic and non-destructive.