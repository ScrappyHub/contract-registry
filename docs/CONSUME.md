# Contract Registry Consumption Guide (Canonical v1)
Authority: Contract Registry
Status: LOCKED
Goal: enable any repo or enterprise to adopt contracts without drift.
## Core rule (MUST)
- A consumer MUST pin Contract Registry law by PacketId or immutable git ref; never a moving target.
## Supported adoption modes (choose one) (MUST)
### Mode A — Pinned packet ingestion (enterprise-grade)
- Consumer stores a contracts.lock.json that pins: base PacketId, trust bundle, signer identity, and optional overlays.
- CI verifies: sha256sums match + signature validates + signer is trusted + overlays obey overlay constitution.
### Mode B — Git submodule pinned to tag/commit (developer-friendly)
- Add Contract Registry as a submodule and pin to an immutable tag/commit.
- CI enforces submodule pointer is exactly the pinned revision and clean.
### Mode C — Vendored mirror (offline/airgapped)
- Copy required schemas/docs/vectors into consumer repo under a contracts/ folder.
- CI verifies vendored content hashes match the pinned registry release (receipt + signature evidence).
## Drift prevention gate (MUST)
- CI MUST fail if any contract file differs from the pinned release.
- CI MUST fail if contracts.lock.json changes without an explicit approval workflow.
## overlays (MUST)
- Overlays are additive/tightening layers on top of base law (enterprise + project overlays).
- Overlay precedence: base -> enterprise overlay(s) -> project overlay(s).
- Overlays MUST be explicitly enabled and pinned the same way as base law.
## Lock file (MUST)
- Consumers SHOULD use contracts.lock.json validated by schemas/common/contracts_lock.schema.json.