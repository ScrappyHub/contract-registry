param(
  [Parameter(Mandatory=$true)]
  [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function EnsureDir([string]$p){
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path

  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }

  $normalized = $Text -replace "`r`n","`n"
  $normalized = $normalized -replace "`r","`n"

  if(-not $normalized.EndsWith("`n")){
    $normalized += "`n"
  }

  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $normalized, $enc)
}

# -------------------------------
# PATHS (DEFINED HERE — FIXES BUG)
# -------------------------------

$DocsDir = Join-Path $RepoRoot "docs"
$WbsDir  = Join-Path $DocsDir "wbs"
$HDir    = Join-Path $DocsDir "handoffs"

EnsureDir $DocsDir
EnsureDir $WbsDir
EnsureDir $HDir

$p1 = Join-Path $DocsDir "CONTRACT_REGISTRY_WORKBENCH_LAYER_v1.md"
$p2 = Join-Path $WbsDir  "CONTRACT_REGISTRY_WORKBENCH_WBS_v1.md"
$p3 = Join-Path $HDir    "contract-registry-workbench-handoff-v1.txt"

# -------------------------------
# CONTENT
# -------------------------------

$doc1 = @'
# CONTRACT REGISTRY — WORKBENCH LAYER v1
Local deterministic execution engine.
'@

$doc2 = @'
# CONTRACT REGISTRY — WORKBENCH WBS v1
All RED → to GREEN.
'@

$doc3 = @'
CONTRACT REGISTRY WORKBENCH HANDOFF v1
Hybrid model locked.
'@

# -------------------------------
# WRITE FILES
# -------------------------------

Write-Utf8NoBomLf $p1 $doc1
Write-Utf8NoBomLf $p2 $doc2
Write-Utf8NoBomLf $p3 $doc3

Write-Host ("WROTE: " + $p1) -ForegroundColor Green
Write-Host ("WROTE: " + $p2) -ForegroundColor Green
Write-Host ("WROTE: " + $p3) -ForegroundColor Green

Write-Host "WORKBENCH_DOCS_OK" -ForegroundColor Green