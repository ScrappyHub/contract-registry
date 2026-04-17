\# Contract Bundle Spec v1



\## Purpose



Defines the deterministic bundle format exported by the hosted app and consumed by the Workbench.



\---



\# STRUCTURE



contract\_bundle\_v1/



&#x20; manifest.json

&#x20; contract.json

&#x20; version.json



&#x20; overlays/

&#x20;   policy/

&#x20;     policy.overlay.json

&#x20;   schema/

&#x20;     schema.overlay.json



\---



\# REQUIRED FILES



\- manifest.json

\- contract.json

\- version.json



Missing any file must fail import.



\---



\# JSON RULES



\- UTF-8 (no BOM)

\- LF line endings

\- Canonical JSON (sorted keys)

\- No trailing whitespace



\---



\# HASHING



All files must be stable under SHA-256.



Workbench will compute hashes during inspect.



\---



\# MANIFEST RULES



\- MUST NOT include packet\_id

\- MUST include:

&#x20; - contract\_key

&#x20; - version\_label



\---



\# OVERLAYS



Optional but structured:



overlays/

&#x20; policy/

&#x20; schema/



\---



\# VALIDATION TOKENS



Success:

WORKBENCH\_IMPORT\_OK



Failures:

IMPORT\_FAIL\_MISSING\_FILE

IMPORT\_FAIL\_INVALID\_JSON



\---



\# VERSIONING



This document defines v1.

Future versions must remain backward compatible.

