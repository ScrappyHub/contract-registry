# Overlay Constitution (Canonical v1)
Authority: Contract Registry
Status: LOCKED
Purpose: define how enterprise/project overlays may extend contract law without weakening or drifting base law.
## Definitions
- Base law: the pinned Contract Registry release (schemas/docs/vectors).
- Overlay law: a pinned, signed contract layer applied on top of base law.
## Precedence (LOCKED)
1) Base contracts apply first.
2) Enterprise overlays apply next (zero or more, in declared order).
3) Project overlays apply last (zero or more, in declared order).
## Allowed overlay operations (MUST)
- Add new contracts (new schema/doc/spec files under overlay namespace).
- Tighten validation (add constraints) IF the base contract explicitly allows extension points.
- Add indexes/mappings that increase legibility without changing meaning.
## Forbidden overlay operations (MUST NOT)
- Weaken canonicalization rules for any signing or hashing context.
- Alter base schema semantics without a version bump that declares incompatibility.
- Redefine PacketId / CommitHash / chain hash laws.
- Override trust rules to accept untrusted signers for base law.
## Overlay identity (MUST)
- Every overlay MUST declare: overlay id, version, required base version range, signer principal, key_id, and trust bundle id.
## Overlay verification (MUST)
- Overlay packets MUST verify sha256sums, signature, and signer trust.
- Overlay MUST be rejected if it violates forbidden operations.
## Breaking changes (MUST)
- If overlay needs behavior incompatible with base, it MUST target a new major base version or declare incompatibility explicitly.