# Offline Transport v1 (Locked)

Transport model: Outbox/Inbox folder sync.

Canonical directories (Windows example):
- Outbox: C:\ProgramData\Watchtower\outbox\
- Inbox: C:\ProgramData\Watchtower\inbox\
- Quarantine: C:\ProgramData\Watchtower\inbox_quarantine\

Canonical unit: content-addressed bundle directory:

outbox/<packet_sha256>/
  manifest.json
  sha256sums.txt
  signatures/
  payload/

Ingestion:
- move/copy bundle into inbox
- verify hashes + signatures deterministically
- ingest -> write ledger events
- emit ingestion receipt (written to outbox)

No zip required in v1. Zip wrapper may exist later, but canonical form remains directory bundles.