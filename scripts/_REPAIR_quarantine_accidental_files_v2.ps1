param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function EnsureDir([string]$p){ if (-not (Test-Path -LiteralPath $p -PathType Container)) { New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function WriteUtf8NoBomLf([string]$p,[string]$t){
  $dir = Split-Path -Parent $p
  if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $x = ($t -replace "`r`n","`n") -replace "`r","`n"
  if (-not $x.EndsWith("`n")) { $x += "`n" }
  [IO.File]::WriteAllText($p,$x,[Text.UTF8Encoding]::new($false))
}
function Sha256HexFile([string]$p){
  $b = [IO.File]::ReadAllBytes($p)
  if ($null -eq $b) { $b = @() }
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $h = $sha.ComputeHash($b) } finally { $sha.Dispose() }
  return ([BitConverter]::ToString($h) -replace "-","").ToLowerInvariant()
}

$ScriptsDir = Join-Path $RepoRoot "scripts"
EnsureDir $ScriptsDir
$Grave = Join-Path $ScriptsDir "_graveyard"
EnsureDir $Grave

$stamp = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss")
$Bucket = Join-Path $Grave ("accidental_" + $stamp)
EnsureDir $Bucket

# Patterns that should NEVER live in contract-registry surface.
# Add/remove patterns here as you discover more "poison" artifacts.
$patterns = @(
  "_PATCH_install_packet_constitution_pack_v1.ps1",
  "_PATCH_install_packet_constitution_pack_*.ps1",
  "*packet_constitution*pack*.ps1",
  "*pcv1*compliance*pack*.ps1",
  "*expo_start_*.log"
)

$Moved = New-Object System.Collections.Generic.List[string]

function IsUnderGraveyard([string]$full){
  $g = (Join-Path (Join-Path $RepoRoot "scripts") "_graveyard")
  $g2 = [IO.Path]::GetFullPath($g).TrimEnd("\") + "\"
  $f2 = [IO.Path]::GetFullPath($full)
  return $f2.StartsWith($g2, [StringComparison]::OrdinalIgnoreCase)
}

function MoveWithReceipt([string]$src){
  if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { return }
  if (IsUnderGraveyard $src) { return }
  $rel = $src.Substring(([IO.Path]::GetFullPath($RepoRoot)).TrimEnd("\").Length).TrimStart("\")
  $dst = Join-Path $Bucket $rel
  EnsureDir (Split-Path -Parent $dst)
  $h = Sha256HexFile $src
  Move-Item -LiteralPath $src -Destination $dst -Force
  [void]$Moved.Add(($rel + " sha256=" + $h))
}

# Scan scripts/ and repo root for matching leaf files (non-recursive + recursive).
foreach($pat in $patterns){
  foreach($p in @(
    (Join-Path $RepoRoot $pat),
    (Join-Path (Join-Path $RepoRoot "scripts") $pat)
  )){
    foreach($f in @(@(Get-ChildItem -LiteralPath (Split-Path -Parent $p) -Filter (Split-Path -Leaf $p) -File -ErrorAction SilentlyContinue))){
      MoveWithReceipt $f.FullName
    }
  }
}

# Also catch anything named like a patcher accidentally placed under scripts/ (but NOT graveyard).
foreach($f in @(@(Get-ChildItem -LiteralPath (Join-Path $RepoRoot "scripts") -Recurse -File -ErrorAction SilentlyContinue))){
  if (IsUnderGraveyard $f.FullName) { continue }
  if ($f.Name -like "_PATCH_*packet_constitution*") { MoveWithReceipt $f.FullName; continue }
  if ($f.Name -like "_PATCH_*") { continue } # don't blanket-move all patchers; only the constitution ones.
}

# Receipt
$rcpt = New-Object System.Collections.Generic.List[string]
[void]$rcpt.Add("schema: quarantine_receipt.v2")
[void]$rcpt.Add("utc: " + [DateTime]::UtcNow.ToString("o"))
[void]$rcpt.Add("repo_root: " + $RepoRoot)
[void]$rcpt.Add("bucket: " + $Bucket)
[void]$rcpt.Add("moved_count: " + (@(@($Moved)).Count))
foreach($m in @(@($Moved))){ [void]$rcpt.Add("moved: " + $m) }
$ReceiptPath = Join-Path $Bucket "quarantine_receipt.txt"
WriteUtf8NoBomLf $ReceiptPath ((@($rcpt.ToArray()) -join "`n") + "`n")

Write-Host ("QUARANTINE_OK: bucket=" + $Bucket) -ForegroundColor Green
Write-Host ("moved_count=" + (@(@($Moved)).Count)) -ForegroundColor Gray
Write-Host ("receipt=" + $ReceiptPath) -ForegroundColor Gray
