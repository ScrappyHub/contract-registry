\# Contract Registry — Workbench WBS v1 (Tier-0 → Launch)



\## Purpose

Define the exact work required to take the Workbench from current GREEN pipeline state to a fully shippable product surface with hosted integration.



\---



\# CURRENT STATE (PROVEN)



\- UI runner exists (React + Vite)

\- Local bridge exists (Express)

\- Pipeline executes deterministically via UI

\- Streaming logs implemented

\- Outputs:

&#x20; - releases/

&#x20; - exports/

&#x20; - sha256sums

&#x20; - export\_receipt

\- Token proven:

&#x20; WORKBENCH\_FULL\_PIPELINE\_GREEN



\---



\# PHASE 1 — WORKBENCH COMPLETION



\## WB-01 Import Contract Bundle

Status: YELLOW



\- Accept `.zip`

\- Extract → workspace\\input\\contract

\- Validate required files:

&#x20; - manifest.json

&#x20; - contract.json

&#x20; - version.json



Emit:

\- WORKBENCH\_IMPORT\_OK

\- IMPORT\_FAIL\_MISSING\_FILE

\- IMPORT\_FAIL\_INVALID\_JSON



\---



\## WB-02 Import Summary UI

Status: YELLOW



Display:

\- contract\_key

\- version\_label

\- overlay counts

\- sha256 hashes



\---



\## WB-03 Pipeline Gating

Status: RED



\- Disable Run until import success

\- Prevent stale workspace usage



\---



\## WB-04 Export Packaging

Status: YELLOW



Output bundle:



release\_bundle\_v1/

&#x20; release/

&#x20; sha256sums.txt

&#x20; export\_receipt.txt



\---



\## WB-05 Export-for-Upload Helper

Status: RED



\- Button: "Export for Upload"

\- Zip export directory

\- Deterministic naming



\---



\## WB-06 Full Green Runner

Status: RED



Script:

\_RUN\_workbench\_tier0\_full\_green.ps1



Must:

\- parse-gate scripts

\- import test bundle

\- run pipeline

\- verify outputs

\- emit:

&#x20; WORKBENCH\_TIER0\_FULL\_GREEN



\---



\# PHASE 2 — HOSTED APPLICATION



\## HA-01 Contract Authoring

\- Create contract

\- Create version

\- Upload source



\---



\## HA-02 Overlay System

\- Attach policy overlays

\- Attach schema overlays

\- Version overlays



\---



\## HA-03 Export to Workbench

Button:

Export to Workbench



Output:

contract\_bundle\_<id>\_<version>.zip



\---



\## HA-04 Import Evidence

\- Upload release bundle

\- Validate:

&#x20; - sha256sums

&#x20; - receipt

\- Store evidence



\---



\## HA-05 Registry View

\- Show releases

\- Show verification state

\- Show hashes



\---



\# PHASE 3 — INTEGRATION



\## INT-01 WatchTower

\- Verify release bundles



\## INT-02 NFL

\- Store receipts



\## INT-03 Clarity (optional)

\- Execution witness



\---



\# DEFINITION OF DONE



Workbench:

\- Import works

\- Pipeline runs from UI

\- Export bundle deterministic

\- Full green runner exists



Hosted:

\- Export bundle works

\- Upload evidence works

\- Registry displays results



System:

\- hosted → workbench → hosted loop completes

