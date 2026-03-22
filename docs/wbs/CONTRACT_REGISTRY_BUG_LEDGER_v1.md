# CONTRACT REGISTRY — BUG LEDGER V1

## STATUS: LOCKED
## PURPOSE: Live E2E Proof Alpha Bug Tracking (Deterministic Intake + Triage)

---

# 1) INTENT

This document defines the canonical bug intake, classification, and triage system for the Contract Registry hosted product.

It ensures:
- no issue is lost
- no issue is misclassified
- no issue is hand-waved
- all failures are reproducible and actionable

This is REQUIRED for Live E2E Proof Alpha validation.

---

# 2) BUG LEDGER SCHEMA

Each bug MUST include the following fields:

```text
BUG_ID
DISCOVERED_AT_UTC
DISCOVERED_BY
TEST_ID
ROUTE
ACTOR
AREA
CATEGORY
SEVERITY
PRECONDITION
ACTION
EXPECTED_UI
EXPECTED_BACKEND
ACTUAL_UI
ACTUAL_BACKEND
ERROR_TEXT
REPRO_STEPS
REPRODUCIBLE
SECURITY_IMPACT
DATA_INTEGRITY_IMPACT
WORKAROUND
STATUS
OWNER
FIX_TARGET
VERIFICATION_STEPS
VERIFIED_AT_UTC
NOTES
3) FIELD DEFINITIONS
BUG_ID

Format:

CR-BUG-0001
CR-BUG-0002
DISCOVERED_AT_UTC
Must be UTC
ISO8601 format
AREA

One of:

Auth
AppShell
Dashboard
Contracts
Versions
Releases
Overlays
Billing
Members
SupportAccess
Workbench
Storage
OrgContext
Security
CATEGORY

Use EXACT values:

AUTH
ORG_CONTEXT
ROLE_GATING
PLAN_GATING
RPC_BINDING
VIEW_BINDING
MUTATION_FLOW
STORAGE_ACCESS
DOWNLOAD_AUDIT
UI_STATE
DATA_RENDER
SECURITY
REPRODUCIBLE
Always
Intermittent
Once
Unknown
SECURITY_IMPACT
None
Low
Medium
High
Critical
DATA_INTEGRITY_IMPACT
None
Low
Medium
High
Critical
STATUS
New
Confirmed
In Progress
Fixed
Verified
Won’t Fix
Deferred
4) SEVERITY RUBRIC
S0 — CRITICAL

Use when:

unauthenticated access to protected data
cross-organization data leakage
unauthorized mutations succeed
protected downloads bypass auth
wrong release data exposed
data corruption
account takeover risk

RULE:
STOP. FIX IMMEDIATELY. PRODUCT NOT SAFE.

S1 — HIGH

Use when:

core workflows fail (contracts, releases, members)
owner/admin cannot complete actions
workbench gating incorrect
org switching broken
audit/download missing
UI lies about backend state

RULE:
BLOCKS ALPHA COMPLETION

S2 — MEDIUM

Use when:

partial or incorrect data rendering
incorrect empty states
UI not refreshing after mutation
incorrect messaging
missing non-critical fields

RULE:
NON-BLOCKING BUT REDUCES TRUST

S3 — LOW

Use when:

UI polish issues
layout problems
labeling inconsistencies
non-critical UX issues

RULE:
CLEANUP, DOES NOT BLOCK

5) PRIORITY ORDER

Fix order:

S0
S1
S2
S3

Within same severity:

Security
Data integrity
Core workflows
UI polish
6) BUG ENTRY TEMPLATE
BUG_ID: CR-BUG-0001
DISCOVERED_AT_UTC: 2026-03-13T13:10:00Z
DISCOVERED_BY: Alec
TEST_ID: CR-E2E-WB-003
ROUTE: /app/workbench
ACTOR: Owner
AREA: Workbench
CATEGORY: DOWNLOAD_AUDIT
SEVERITY: S1

PRECONDITION:
Org on starter plan, authenticated owner session, artifact visible.

ACTION:
Clicked Download.

EXPECTED_UI:
Download starts and confirms.

EXPECTED_BACKEND:
download.granted event written.

ACTUAL_UI:
Download starts.

ACTUAL_BACKEND:
No audit row created.

ERROR_TEXT:
None.

REPRO_STEPS:
1. Sign in
2. Select org
3. Open workbench
4. Click download

REPRODUCIBLE: Always
SECURITY_IMPACT: Low
DATA_INTEGRITY_IMPACT: Medium
WORKAROUND: None
STATUS: New
OWNER: Unassigned
FIX_TARGET: UI Alpha

VERIFICATION_STEPS:
Repeat and confirm audit row appears.

VERIFIED_AT_UTC:

NOTES:
Likely missing RPC call before file delivery.
7) MINIMAL TRACKING TABLE

Use this for quick logging:

| BUG_ID | TEST_ID | ROUTE | AREA | CATEGORY | SEVERITY | ACTOR | SUMMARY | STATUS | OWNER |
8) TRIAGE RULE

For every bug:

Confirm it is real
Confirm reproducibility
Identify layer:
frontend
backend
auth
org-context
storage
Assign severity
Determine if it blocks E2E proof
9) EXIT CRITERIA — LIVE E2E PROOF ALPHA

The system is considered ALIVE when:

S0 bugs = 0
S1 bugs = 0
S2/S3 bugs tracked with owners
All core flows succeed:
auth
org scoping
contracts
releases
overlays
billing gates
workbench
downloads + audit
10) FINAL RULE

No feature is considered complete until:

it passes E2E UI interaction
it writes correct backend state
it is logged in this ledger if it fails