# SHA256SUMS (Canonical v1)
Contract ID: contract:sha256sums_file@1.0.0
## Purpose
Define a deterministic sha256sums.txt file format for sealing directory bundles (packets, artifacts, receipts).
## Line format (LOCKED)
- Each line: <sha256hex><two spaces><relative_path>
- sha256hex is 64 lowercase hex.
- Paths are relative and normalized with forward slashes (/).
## Path rules (LOCKED)
- No absolute paths.
- No drive letters (e.g., C:).
- No .. segments.
- No leading slash (/).
## Ordering (LOCKED)
- Lines are sorted lexicographically by relative_path (byte order).