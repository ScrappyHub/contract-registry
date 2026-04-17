\# Contract Registry Workbench — Usage Guide (v0.1)



\## Overview



The Workbench is a local deterministic execution environment for contract bundles.



It does NOT create contracts.

It executes and verifies them.



\---



\# STEP 1 — Start Workbench



```powershell

cd C:\\dev\\contract-registry\\workbench-ui

npm run dev



Open:



http://localhost:5174



STEP 2 — Import Contract Bundle



Click:



Import Bundle



Select:



contract\_bundle\_<name>\_<version>.zip



Expected result:



WORKBENCH\_IMPORT\_OK



UI will display:



contract key

version

overlay counts

hashes

STEP 3 — Run Pipeline



Click:



Run Pipeline



Pipeline stages:



inspect

build

verify

export

STEP 4 — Verify Output



Expected final token:



WORKBENCH\_FULL\_PIPELINE\_GREEN



Output directory:



workbench\\workspace\\output\\



Includes:



releases/

sha256sums.txt

export\_receipt.txt

STEP 5 — Export for Upload (future)



Export bundle for hosted ingestion.



IMPORTANT RULES

Never modify files in workspace manually

Always import via bundle

Only trust outputs with GREEN token



\---

