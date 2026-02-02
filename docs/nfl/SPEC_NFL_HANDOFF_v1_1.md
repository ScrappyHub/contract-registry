# SPEC_NFL_HANDOFF_v1_1 (Canonical NFL Skeleton v1.1)
This document is a contract. Producers MUST obey it to be compatible with NFL witness + replay.
## Repo layout (MUST)
<repo-root>\\
  README.md
  LICENSE
  LAW.md
  SPEC_NFL_HANDOFF_v1_1.md
  schemas\\ (producer-local mirrors of Contract Registry outputs)
  contracts\\ (event types registry + canon/paths text)
  src\\nfl\\ (boring plugin kit: Canon, Hash, Sign, Verify, Packet, LocalPledgeLog, NflIngestEnvelope)
  tests\\vectors\\sample_packet\\ (golden sample packet)
  scripts\\ (bootstrap_repo, make_packet, verify_packet, pledge_local, duplicate_to_nfl)
## Runtime layout (MUST)
Producer:
C:\\ProgramData\\<Producer>\\pledges\\pledges.ndjson
C:\\ProgramData\\<Producer>\\outbox\\<PacketId>\\...
NFL:
C:\\ProgramData\\NFL\\inbox\\<PacketId>\\...
## Packet skeleton (MUST be byte-identical in outbox and NFL inbox)
<PacketRoot>\\
  manifest.json
  sha256sums.txt
  payload\\
    commit.payload.json
    commit_hash.txt
    nfl.ingest.json
    sig_envelope.json
  signatures\\
    ingest.sig
## Hash laws (MUST)
CommitHash = SHA-256(canonical_bytes(commit.payload.json))
PacketId   = SHA-256(canonical_bytes(manifest.json))
Local pledge chain: log_hash = SHA-256(canonical_bytes(line_without_log_hash)), prev_log_hash chains (GENESIS for first)
Repo witness chain: witness_hash = SHA-256(canonical_bytes(entry_without_witness_hash)), prev_witness_hash chains (GENESIS for first)
## Verification routine (MUST)
- sha256sums.txt matches bytes of referenced files
- manifest.json lists exactly the packet files and hashes match
- recompute CommitHash and match commit_hash.txt
- recompute ingest_hash (optional) and match envelope if present
- verify ingest.sig against sig_envelope using key_id
- verify pledge chain integrity (local)
- verify witness chain integrity (repo)