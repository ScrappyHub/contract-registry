# CONTRACT REGISTRY — WORKBENCH LAYER V1

## STATUS: LOCKED
## PURPOSE: Local execution engine + hosted portal split for Contract Registry

---

# 1) INTENT

This document defines the canonical Workbench layer for Contract Registry.

Contract Registry is not a pure SaaS and it is not a pure local tool.

It is a two-layer product:

- Hosted Control Plane
- Local Workbench Execution Layer

This split is REQUIRED.

---

# 2) PRODUCT SHAPE

## Hosted Control Plane

The hosted application is the authority and distribution layer.

It owns:

- authentication
- organizations
- members
- roles
- capabilities
- billing
- entitlements
- contracts
- versions
- overlays
- release registry
- workbench release catalog
- workbench download portal
- audit visibility

It does NOT perform the full local deterministic execution workload.

---

## Local Workbench

The Workbench is the downloadable local execution engine.

It owns:

- local environment checking
- local workspace selection
- contract inspection
- overlay inspection
- effective set resolution
- local release build execution
- local release verification
- receipt inspection
- packet inspection
- evidence export
- offline-capable operations where possible

It does NOT own:

- billing
- Stripe
- org authority
- public account management
- subscription enforcement source of truth

---

# 3) CANONICAL SYSTEM MODEL

Contract Registry MUST be understood as:

> Hosted authority + downloadable execution engine

This means:

- the website is the control plane
- the workbench is the execution plane

This is the canonical architecture for this project.

---

# 4) HOSTED CONTROL PLANE RESPONSIBILITIES

The hosted layer MUST provide:

- sign in
- password reset
- invite acceptance
- organization selection
- contract management
- version management
- overlay profile management
- release visibility
- billing views
- entitlement views
- workbench download access
- download audit visibility

The hosted layer SHOULD gate access to the Workbench by:

- plan
- entitlement
- org membership
- role/capability where relevant

---

# 5) WORKBENCH RESPONSIBILITIES

The Workbench MUST provide:

## A. Environment Check
- runtime/tool availability
- writable workspace validation
- version display
- path validation

## B. Contract Inspection
- selected contract summary
- selected version summary
- source artifact location
- source hash visibility

## C. Overlay Inspection
- policy overlays
- schema overlays
- canonical vs overlay distinction

## D. Effective Set Resolution
- effective policy set
- effective schema set
- effective hashes

## E. Release Build
- build release packet locally
- emit receipts
- emit packet id
- emit sha256sums
- preserve deterministic output

## F. Release Verification
- verify packet
- verify receipts
- verify expected evidence
- surface pass/fail clearly

## G. Evidence Inspection
- manifest
- packet_id
- sha256sums
- release receipts
- verification receipts
- effective sets receipts

## H. Export
- export release bundle
- export evidence bundle
- copy packet ids / hashes / refs

---

# 6) WORKBENCH UI SHAPE

The Workbench UI MUST remain simple.

It should be a thin local shell over a deterministic engine.

Recommended areas:

1. Home
2. Workspace
3. Contracts
4. Overlays
5. Build
6. Verify
7. Evidence
8. Export
9. Settings

The Workbench UI is NOT a replacement for the hosted dashboard.

---

# 7) WORKBENCH RUNTIME MODEL

The engine should be command-driven first.

The local UI should wrap deterministic commands rather than inventing hidden behavior.

Canonical command surface:

- workbench env check
- workbench contract inspect
- workbench overlays resolve
- workbench release build
- workbench release verify
- workbench evidence export

The UI layer should display:
- status
- parameters
- outputs
- logs
- evidence references

---

# 8) HOSTED ↔ WORKBENCH HANDSHAKE

## Hosted → Workbench

The hosted system provides:

- authenticated identity
- org context
- entitlement to use/download workbench
- workbench release catalog
- selected contract/version/overlay metadata
- optional future job packages

## Workbench → Hosted

The Workbench may later provide back:

- packet id
- receipt references
- verification references
- effective set references
- status summary
- optional uploaded result metadata

For v1, manual or semi-manual result registration is acceptable.

---

# 9) DOWNLOAD / ENTITLEMENT MODEL

The website MUST be the download portal.

The Workbench MUST be downloadable from the hosted app.

Canonical behavior:

- user signs into hosted app
- user has org context
- plan/entitlement is checked
- workbench release catalog is shown
- user downloads entitled workbench version
- download event is audited

Trial MAY block workbench.
Starter and above MAY enable workbench according to plan law.

---

# 10) WORKBENCH UPDATE MODEL

For v1, updates SHOULD be simple.

Preferred initial behavior:

- hosted app shows available versions
- user manually downloads newer version
- workbench may show update available status
- workbench should not require a complex self-updater in v1

---

# 11) LOCAL WORKSPACE MODEL

Recommended local workspace shape:

```text
workspace/
  input/
    contract/
    overlays/
  output/
    releases/
    verification/
    exports/
  receipts/
  logs/
  cache/

This MUST keep inputs and outputs legible.

The operator should always be able to tell:

what came in
what was resolved
what was built
what was verified
what was exported
12) EVIDENCE / OPERATOR RULES

The Workbench MUST make these visible:

packet id
hashes
paths
receipt references
verification results
effective set hashes

These should be:

copyable
readable
not buried

Failure states MUST be explicit:

missing input
invalid workspace
overlay conflict
build failure
verification failure
missing receipt
mismatched hash
inaccessible output path
13) SECURITY RULES

The Workbench MUST NOT:

bypass hosted entitlement
embed permanent privileged secrets
anonymously fetch protected downloads
mutate governed inputs silently

The Workbench MUST:

respect org/session context
respect artifact access controls
keep local file operations explicit
keep verification and build operations auditable
14) FIRST MILESTONE
CONTRACT REGISTRY WORKBENCH ALPHA

Definition of done:

downloadable from hosted portal
launches locally
displays version/build info
performs environment check
allows workspace selection
loads selected contract/version/overlay context
resolves effective sets
builds release packet locally
verifies packet locally
displays evidence
exports output bundle

No fake flows are allowed.

15) IMPLEMENTATION ORDER
Phase 1 — Engine

Implement:

env check
contract inspect
overlays resolve
release build
release verify
evidence export
Phase 2 — Thin Local UI

Implement local shell around engine commands.

Phase 3 — Hosted Handshake

Implement:

sign-in/session awareness
org context
metadata fetch
download/update awareness
Phase 4 — Result Registration

Implement optional result registration/binding back into hosted app.

16) FINAL RULE

Contract Registry SHOULD ship as:

a hosted dashboard/control plane
plus a downloadable local Workbench engine

This is the correct architecture for the product.

The hosted app is where users manage access and releases.
The Workbench is where users execute deterministic local work.