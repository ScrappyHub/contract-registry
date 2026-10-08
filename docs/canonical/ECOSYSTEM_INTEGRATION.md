# Ecosystem Integration — Contract Registry

## Canonical service identity

| Field | Value |
|---|---|
| Service ID | `contract-registry` |
| Canonical name | Contract Registry |
| Ecosystem layer | `governance.repository-intelligence` |
| Standalone-first | `true` |

## Role

Deterministic Software MRI for all software in the ecosystem: governance IDS and repository shadow-profile engine.

## This service owns

- Repository profiling
- Contract snapshots
- Capability inventory
- Semantic drift detection
- Capability drift detection
- Risk drift detection
- Daily and weekly evidence reports

## This service does not own

- Source-code hosting
- Package installation
- Runtime application orchestration
- Long-term blob preservation

## Upstream services

- `archive-recall`

## Downstream consumers or operators

- `proteusops`
- `assemblelink`
- `live-state-surgeon`
- `operators`

## Contract families

- `repository.*`
- `contract.*`
- `snapshot.*`
- `capability.*`
- `drift.*`
- `risk.*`
- `report.*`
- `receipt.*`

## Integration rules

1. This repository must remain independently understandable, testable, buildable, and releasable.
2. Ecosystem integrations extend capability but do not replace standalone correctness.
3. Integrations use explicit, versioned schemas and receipts.
4. No undocumented database sharing, hidden filesystem coupling, or implicit trust is permitted.
5. Producer claims must be independently verified by the receiving boundary where verification is required.
6. Integration failure must not silently corrupt local authoritative state.
7. Missing upstream services must produce an explicit unavailable, unknown, deferred, or failed state according to the local contract.
8. This repository's current implementation must not be treated as the complete product definition.

## Authoritative ecosystem sources

- `../Constellation/ecosystem/SERVICE_MAP.md`
- `../Constellation/registry/services.json`
- `../Constellation/ecosystem/AGENT_POLICY.md`
- `../Constellation/ecosystem/SHARED_INVARIANTS.md`

## Change governance

Changes to this service's ecosystem role, ownership boundaries, upstream dependencies, or downstream responsibilities require:

1. A proposal under `docs\proposals`.
2. A documented compatibility impact.
3. Updated service-map and registry entries.
4. Updated positive and negative integration tests.
5. A new service-map receipt.
