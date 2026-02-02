# Contract Registry Release Procedure (Canonical v1)
Authority: Contract Registry
Status: LOCKED
Goal: publish contracts as immutable, verifiable law for other systems and enterprises.
## Release invariants (MUST)
- Every release MUST be content-addressed and verifiable (sha256 + signature).
- Releases MUST be deterministic: same inputs => same PacketId.
- Consumers MUST pin a release; never track moving branches.
## Versioning (MUST)
- Use semantic versioning for the registry interface surface.
- Breaking contract changes REQUIRE a major version bump.
- Additive-only changes MAY be minor/patch versions.
## Canonical release steps (MUST)
1) Update contracts (schemas/docs/vectors) in git working tree.
2) Run status check: scripts/_cr_status_check_v1.ps1 (must pass).
3) Refresh schema receipt: schemas/_schema_write_status_v1.txt (schemas only).
4) Commit changes with an explicit message describing contract intent.
5) Tag the commit: contract-registry/vX.Y.Z (annotated tag recommended).
6) Build a release packet (Packet Constitution v1): directory bundle + manifest.json + sha256sums.txt.
7) Sign the packet manifest using the signing_context contract for packet_manifest.
8) Publish the packet to your distribution channel (GitHub release, artifact store, offline outbox/inbox).
9) Publish or reference the Trust Bundle that authorizes the signer principal/key.
## Mandatory release outputs (MUST)
- Packet manifest + sha256sums + detached signature.
- Release notes MUST include: version, PacketId, signer principal, key_id, and trust bundle id.