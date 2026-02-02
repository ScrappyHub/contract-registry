$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$Root="C:\dev\contract-registry"
if(-not(Test-Path -LiteralPath $Root)){ throw "Repo root not found: $Root" }
Set-Location $Root

function Ensure-Dir([string]$Rel){
  $p = Join-Path $Root $Rel
  if(-not(Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null }
}

function Write-Text([string]$RelPath, [string]$Content){
  $full = Join-Path $Root $RelPath
  $parent = Split-Path -Parent $full
  if(-not(Test-Path -LiteralPath $parent)){ New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  Set-Content -LiteralPath $full -Value $Content -Encoding UTF8 -NoNewline
}

function Write-LinesNoBlanks([string]$RelPath, [string[]]$Lines){
  foreach($l in $Lines){
    if($l -eq ""){ throw "Blank line not allowed in: $RelPath" }
  }
  Write-Text -RelPath $RelPath -Content ($Lines -join "`n")
}

# -------------------------
# 0) Ensure dirs
# -------------------------
Ensure-Dir "docs\nfl"

# -------------------------
# 1) Publish producer PowerShell rules (NFL v1.1 guidance, canonical)
# -------------------------
Write-LinesNoBlanks "docs\nfl\PRODUCER_POWERSHELL_RULES_v1.md" @(
  '# Producer PowerShell Rules (NFL Canonical v1.1)',
  'Authority: Contract Registry',
  'Scope: These rules prevent producer drift and broken witness/packet emission caused by PowerShell execution footguns.',
  'Status: LOCKED',
  '## Rule 1 — No session-local helper functions',
  '- Producers MUST NOT rely on functions defined in an interactive session (e.g., Write-Text, Ensure-Dir) to build scripts or artifacts.',
  '- Any helper function REQUIRED for execution MUST be defined inside the script that uses it.',
  '- Rationale: producers must be deterministic under powershell.exe -File execution with a clean session.',
  '## Rule 2 — No nested here-strings; avoid here-strings when emitting scripts',
  '- Producers MUST NOT embed a here-string delimiter (at-sign quote) inside a here-string that is being written to disk.',
  '- If a producer emits scripts, prefer line arrays joined by `n to avoid unterminated here-string corruption.',
  '- Rationale: unterminated here-strings cause parser failure at runtime (missing terminator).',
  '## Rule 3 — Canonical workflow: write scripts to files, then run via -File',
  '- Producers MUST write scripts to disk using Set-Content (UTF8, NoNewline) and execute them via powershell.exe -NoProfile -ExecutionPolicy Bypass -File <path>.',
  '- Producers MUST NOT paste script bodies into interactive PowerShell as an execution method.',
  '## Rule 4 — Canonical JSON bytes are contract-defined, not ConvertTo-Json-defined',
  '- ConvertTo-Json -Compress is NOT a canonicalizer and MUST NOT be treated as such unless the producer constrains input types and key ordering exactly to the contract.',
  '- Producers MUST follow docs/nfl/CANON_RULES_JSON_v1.md for any bytes that are hashed and/or signed.',
  '## Rule 5 — Fail fast on missing expected outputs',
  '- Producers MUST hard-fail if required packet files or witness ledgers are missing; do not create partial state silently.',
  '## Rule 6 — No overwrite of inbox/outbox packet roots',
  '- Producers MUST refuse overwriting an existing PacketId folder in outbox or NFL inbox; copy/duplicate must be atomic and non-destructive.'
)

# -------------------------
# 2) Update docs\nfl\README.md to include the new entry (no blank lines)
# -------------------------
$readme = Join-Path $Root "docs\nfl\README.md"
if(-not(Test-Path -LiteralPath $readme)){ throw "Missing: docs\nfl\README.md (expected NFL README to exist)." }
$txt = Get-Content -Raw -LiteralPath $readme
if($txt -notmatch [regex]::Escape("docs/nfl/PRODUCER_POWERSHELL_RULES_v1.md")){
  $lines = Get-Content -LiteralPath $readme
  foreach($l in $lines){ if($l -eq ""){ throw "Blank line detected in existing docs/nfl/README.md — violates canon." } }
  $lines = $lines + "## Producer implementation rules (drift prevention)" + "- docs/nfl/PRODUCER_POWERSHELL_RULES_v1.md"
  Write-LinesNoBlanks "docs\nfl\README.md" $lines
}

# -------------------------
# 3) Update docs\NFL_INDEX.md to include the new entry
# -------------------------
$index = Join-Path $Root "docs\NFL_INDEX.md"
if(-not(Test-Path -LiteralPath $index)){ throw "Missing: docs\NFL_INDEX.md" }
$t = Get-Content -Raw -LiteralPath $index
if($t -notmatch [regex]::Escape("docs/nfl/PRODUCER_POWERSHELL_RULES_v1.md")){
  $add = @("", "## Producer implementation rules (drift prevention)", "- docs/nfl/PRODUCER_POWERSHELL_RULES_v1.md") -join "`n"
  Set-Content -LiteralPath $index -Value ($t.TrimEnd() + $add) -Encoding UTF8 -NoNewline
}

# -------------------------
# 4) Patch status check to require the new doc
# -------------------------
$Status = Join-Path $Root "scripts\_cr_status_check_v1.ps1"
if(-not(Test-Path -LiteralPath $Status)){ throw "Missing: scripts\_cr_status_check_v1.ps1" }
$txt = Get-Content -Raw -LiteralPath $Status
$need = @("docs\nfl\PRODUCER_POWERSHELL_RULES_v1.md")
$pat = '(?s)(\$Expected\s*=\s*@\()(.*?)(\r?\n\))'
$m = [regex]::Match($txt, $pat)
if(-not $m.Success){ throw "Could not locate `$Expected = @(` block in scripts\_cr_status_check_v1.ps1" }
$head = $m.Groups[1].Value
$body = $m.Groups[2].Value
$tail = $m.Groups[3].Value
foreach($n in $need){
  if($txt -notmatch [regex]::Escape($n)){
    if($body -notmatch '\S'){ $body = "`n  `"$n`"" }
    else { $body = $body.TrimEnd() + "`n  `"$n`"" }
  }
}
$newBlock = $head + $body + $tail
$txt = [regex]::Replace($txt, $pat, [System.Text.RegularExpressions.MatchEvaluator]{ param($mm) $newBlock }, 1)
Set-Content -LiteralPath $Status -Value $txt -Encoding UTF8 -NoNewline

# -------------------------
# 5) Status check
# -------------------------
powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root "scripts\_cr_status_check_v1.ps1")
Write-Host "OK: published docs\nfl\PRODUCER_POWERSHELL_RULES_v1.md + required in status check + indexed"