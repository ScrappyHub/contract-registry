# NFL Contracts (Canonical v1.1)
Authority: Contract Registry
Scope: This folder defines the ONLY legal transport + hashing + signing contract surface between any producer and NFL witness ingestion.
## Rule of precedence (LOCKED)
1. Schemas define structure truth.
2. Canon rules define byte truth.
3. Paths rules define filesystem truth.
4. SPEC defines behavioral truth.
If behavior conflicts with code, the contracts win.
## Start here
- docs/NFL_INDEX.md
## Behavioral spec (workflow law)
- docs/nfl/SPEC_NFL_HANDOFF_v1_1.md
## Canon + transport rules (byte law)
- docs/nfl/CANON_RULES_JSON_v1.md
- docs/nfl/PATHS_RULES_v1.md
## Schemas (machine law)
- schemas/nfl/commitment.v1.schema.json
- schemas/nfl/nfl.ingest.v1.schema.json
- schemas/nfl/sig_envelope.v1.schema.json
- schemas/nfl/local_pledge.v1.schema.json
- schemas/nfl/repo_witness.v1.schema.json
- schemas/nfl/packet_manifest.v1.schema.json
## Golden vectors (drift prevention)
- vectors/nfl/v1_1/
- vectors/nfl/v1_1/sample_packet/
Status: LOCKED
## Producer implementation rules (drift prevention)
- docs/nfl/PRODUCER_POWERSHELL_RULES_v1.md