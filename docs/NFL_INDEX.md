# NFL Contract Index (Canonical v1.1)
Authority: Contract Registry
Scope: These files define the ONLY legal interface between any producer (Watchtower, Clarity, Atlas, TRIAD, etc.) and NFL witness transport.

## Rule of precedence (LOCKED)
1. Schemas define structure truth.
2. Canon rules define byte truth.
3. Paths rules define filesystem truth.
4. SPEC defines behavioral truth.
If behavior conflicts with code, the contracts win.

## Schemas (machine law)
- schemas/nfl/commitment.v1.schema.json
- schemas/nfl/nfl.ingest.v1.schema.json
- schemas/nfl/sig_envelope.v1.schema.json
- schemas/nfl/local_pledge.v1.schema.json
- schemas/nfl/repo_witness.v1.schema.json
- schemas/nfl/packet_manifest.v1.schema.json

## Canon + transport rules (byte law)
- docs/nfl/CANON_RULES_JSON_v1.md
- docs/nfl/PATHS_RULES_v1.md

## Behavioral specification (workflow law)
- docs/nfl/SPEC_NFL_HANDOFF_v1_1.md

## Golden vectors (drift prevention)
- vectors/nfl/v1_1/
- vectors/nfl/v1_1/sample_packet/

## Producer obligations (MUST)
- Produce packets byte-identical to the packet skeleton.
- Compute hashes exactly as defined by canonicalization rules.
- Append local pledge chain entries.
- Duplicate packets to NFL inbox.
- Emit readable + replayable repo witness entries.
- Never invent alternate formats.

## Import guidance
Producer repos SHOULD mirror these schemas locally or vendor them as a submodule/package.
Do NOT fork or modify schema semantics without version bump.

## Versioning
Any breaking change requires new contract version (v1_2, v2_0, etc.) and new vectors.

Status: LOCKED
## Producer implementation rules (drift prevention)
- docs/nfl/PRODUCER_POWERSHELL_RULES_v1.md