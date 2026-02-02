# Engine Registry (Contract Registry Canonical v1)
Authority: Contract Registry
Status: LOCKED
Purpose: enumerate the enforcement engines that must exist so contract adoption cannot drift.
## Engine types (MUST)
- packager
- verifier
- signature_verifier
- overlay_evaluator
- schema_validator
- audit_reporter
## Drift rule (MUST)
- If an engine behavior changes, engine version MUST change and consumers MUST re-pin.