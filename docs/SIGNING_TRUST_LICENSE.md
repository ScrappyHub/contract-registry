# Signing, Trust Bundles, and License Binding (Canonical v1)

## A) Verification tool (v1)
Use: ssh-keygen -Y verify (and -Y sign for signing).
Reason: offline, minimal dependencies, ecosystem consistency.

Detached signatures stored as: signatures/*.sig

## A2) Trust bundles (v1)
Separate trust bundles per product:
- triad/trust_bundle.json
- clarity/trust_bundle.json
- watchtower/trust_bundle.json (if/when)

Optional later: meta bundle aggregator that imports bundles but never merges silently.

## B) Artifact signing policy

B1) Who may sign TRIAD artifacts?
- TRIAD release signatures (supply chain trust)
- Org/customer signatures (custody/governance trust)
Co-sign is supported; signatures are additive and never replace.

B2) Co-sign model
Multiple signatures allowed:
- signatures/triad_release.sig
- signatures/org_<keyid>.sig

Signed message (v1):
artifact_id + sha256sums_digest + optional transcript_root

B3) Required signature levels per tier
- Individual/Dev: signature optional; sealing required
- Team: org signature required for commit restores
- Enterprise: org signature required; release recommended unless policy demands
- Authority: policy may require both

Signatures are enforced by policy + license capability, not UI settings.

## C) License binding model (offline, never reset)

C1) Binding primitive (v1)
Bind license to org public key.

C2) License contains
- capabilities (feature flags)
- limits (hard numeric)
- expiry: none by default (perpetual), revocation via trust bundle updates

Minimal limits in v1:
- max_devices (optional local enforcement)
- max_verifiers
- allow_raw_partition
- allow_raw_disk
- allow_boot_commit
- parity_max_data_bytes
- require_signatures_for_commit

C3) Never reset / never corrupt
License immutable + signed.
TRIAD maintains local append-only license usage log (hash-chained).

## D) Toolchain identity (supply chain)

D1) toolchain_manifest.json required in v1 sealed artifacts.
Must include:
- triad executable sha256
- verifier executable sha256
- build_id (git commit)
- runtime version
- OS/arch
- hash algorithm ids

Every receipt includes at least:
- triad_binary_sha256
- verifier_binary_sha256[]
- trust_bundle_hash
- policy_hash

## E) Raw disk boundary (v1)
Raw disk/partition requires ALL:
- policy allow
- license capability allow
- OS privilege (admin/device access)

Default policy denies raw disk.