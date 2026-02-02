# Contract Registry

Deterministic contract schemas, invariants, and conformance tests that define how platform components interoperate. No runtime. No decisions. Pure contracts.

## Scope

Contract Registry owns:
- schemas
- invariants
- canonical encoding rules
- conformance requirements
- golden vectors (optional)

Contract Registry does not own:
- policy decisions (Covenant Gate)
- device inventory or observation collection (Watchtower)
- capture/restore/verify/attest (TRIAD)
- repair/execution logic (Doctor)
- runtime environment (GOS)

## Canonical integration model

Systems integrate by exchanging:
- schema-valid objects
- content-addressed bundles (sha256)
- detached signatures (ed25519 via ssh-keygen -Y in v1)
- append-only transcript/ledger entries

## Canonical v1 decisions (locked)

- Signature verify tool: ssh-keygen -Y verify
- Trust bundles: separate per product
- Artifact signing: additive co-signatures (never replace)
- License binding: org public key (offline, never reset)
- Toolchain identity: toolchain_manifest.json required in sealed artifacts
- Offline transport: outbox/inbox directory bundles (no zip required in v1)
- Watchtower principal format: <tenant>/<role>/<subject> (v1)
- Watchtower event types: closed set v1 (see docs)