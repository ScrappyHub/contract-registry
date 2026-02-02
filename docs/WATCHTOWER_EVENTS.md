# Watchtower — Event Types (Closed Set v1)

Lifecycle / enrollment
- device.seen
- device.join.requested
- device.join.approved
- device.enrolled (optional alias; if included must be emitted exactly once after approval)

Identity / keys
- device.identity.updated
- device.key.rotated
- device.key.revoked

Observation / attestation
- device.observation.recorded
- device.attestation.received.platform
- device.attestation.received.triad
- device.attestation.received.wrapper
- device.attestation.verified

Posture / enforcement outcomes
- device.posture.changed
- device.quarantined
- device.quarantine.exited

TRIAD run custody
- device.triad.run.receipt.ingested
- device.triad.run.accepted
- device.triad.run.rejected

Ledger / sealing / export
- ledger.checkpoint.seal
- ledger.export.emitted

End of life
- device.retired