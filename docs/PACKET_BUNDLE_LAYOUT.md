# Packet Bundle Layout (Canonical v1)
Contract ID: contract:packet_bundle_layout@1.0.0
## Purpose
Define a deterministic directory layout for offline transport packets.
## Required paths (LOCKED)
- manifest.json
- sha256sums.txt
- signatures/ (directory)
- payload/ (directory)
## Hashing (LOCKED v1)
- sha256sums.txt is computed over all files in the bundle excluding signatures/*.sig.
- Paths in sha256sums.txt use forward slashes (/).
## Signing (LOCKED v1)
- Detached signatures in signatures/*.sig.
- Verification tool: ssh-keygen -Y verify.