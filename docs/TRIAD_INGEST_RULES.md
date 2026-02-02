# Watchtower — TRIAD Receipt Ingest Rules (Canonical v1)

Watchtower records accepted TRIAD runs only when all required checks pass.

Required for ""triad run accepted"":
- TRIAD receipt signature verifies
- signature algorithm allowed
- signer principal/key_id trusted for TRIAD receipts (policy-scoped)
- artifact folder integrity present (sha256sums.txt exists)
- roots present:
  - artifact_id
  - block_root
  - semantic_root
  - transcript_root
  - policy_hash
  - identity_hash
- result present: PASS|FAIL
- if FAIL: may be ingested but recorded as rejected for acceptance
- policy-required independent agreement threshold (optional):
  - if policy requires N, receipt must declare verifier count >= N
  - Watchtower checks presence + signature authenticity + declared counts; does not re-check semantics

Output events:
- always: device.triad.run.receipt.ingested
- then:
  - device.triad.run.accepted (if checks pass and PASS)
  - device.triad.run.rejected (otherwise; include reason_code list)

Watchtower emits an ingestion receipt artifact referencing the TRIAD receipt hash.