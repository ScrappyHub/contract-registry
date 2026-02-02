# Signing Context (Canonical v1)
Contract ID: contract:signing_context@1.0.0
## Purpose
Define exactly what bytes are hashed and signed so every product signs the same thing deterministically.
## Canonical bytes (LOCKED v1)
- Serialize the target JSON object using UTF-8, LF line endings, and lexicographic key ordering.
- Compute sha256 over the resulting bytes.
- Record signed_sha256 in the signing_context object.
## Where this applies
- packet_manifest
- triad_receipt
- watchtower_ingestion_receipt
- trust_bundle
- license
- gate_decision
## Multi-file contexts
If a context covers multiple files, include signed_components entries with each component name and sha256. Then compute signed_sha256 over the canonical JSON of the signing_context object that contains those component hashes.