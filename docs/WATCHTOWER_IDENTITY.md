# Watchtower — Identity & Keying (Canonical v1)

## 1) Device keys

Every enrolled device has a device keypair and uses it to sign:
- ObservationSet
- PlatformAttestationRecord (if separate from ObservationSet)
- any device-originated envelopes written to outbox

## 2) Tier rules

Tier0 (dev): file key allowed; must be explicitly marked identity_class = user-asserted
Tier1: OS-keystore-backed key required
Tier2: TPM-backed key + quote evidence supported by schema; enforced by policy

## 3) Watchtower authority key

Watchtower has an authority keypair used to sign:
- ingestion receipts
- checkpoint seals (ledger.checkpoint.seal)
- export bundle receipts

## 4) Principal format (locked)

principal = ""<tenant>/<role>/<subject>""

Examples:
- single-tenant/device_agent/device/2f3a...
- single-tenant/org_admin/user/alec
- single-tenant/watchtower_authority/authority/watchtower

## 5) Stable vs volatile identity

Stable identity facts (require device.identity.updated):
- device_id (never changes)
- identity_class (user-asserted -> os-rooted -> hardware-rooted only via event)
- device_public_key (rotation via explicit event; prior preserved)
- tpm_ek_pub_hash (if used; change triggers identity update)
- hardware_fingerprint_hash (if used; change triggers identity update)
Optional deep anchors (policy-controlled):
- partition fingerprint summary hash
- secure boot anchor hash summary

Volatile observations (no identity update required; evidence only):
- hostname, OS version/build, installed packages
- NIC/IP/routes
- patch level
- services/process inventory (policy-controlled)
- storage summaries
- posture facts (AV/firewall, etc.)

Key rotation continuity rule:
- old_key_id, new_key_id, rotation_reason
- proof of possession (dual-sign claim if possible; else admin approval)