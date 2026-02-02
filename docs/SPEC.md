# Contract Registry — Specification (Canonical)

## 0. Mission (immutable)

Define deterministic, portable, verifiable contracts that allow independent systems to interoperate without shared runtime or hidden coupling.

## 1. Hard boundaries

Registry defines shapes and invariants only.

Registry never enforces policy, performs execution, or stores operational state.

## 2. Canonical encoding

JSON canonicalization (v1):
- UTF-8
- LF line endings
- deterministic key ordering (lexicographic)
- stable numeric formatting
- no trailing whitespace

Hash:
- sha256(bytes) in lowercase hex

Signatures (v1):
- ed25519 detached signatures
- tooling: ssh-keygen -Y sign / ssh-keygen -Y verify
- signatures are additive; never replace previous signatures

## 3. Keying and principals (v1 locks)

- Device keys exist for every enrolled device.
- Watchtower authority key exists for Watchtower signed outputs.
- Principal string format is locked:
  principal = ""<tenant>/<role>/<subject>""

Roles (v1 closed set):
owner, org_admin, device_admin, operator, auditor, device_agent, watchtower_authority

Subjects:
- device/<device_id>
- user/<user_id> (opaque)
- authority/watchtower

Key binding:
Every signature carries principal, key_id, alg, sig.
Watchtower maintains allowlist principal -> public keys.