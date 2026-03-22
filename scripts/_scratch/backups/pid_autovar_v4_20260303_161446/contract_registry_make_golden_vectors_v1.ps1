# CONTRACT_REGISTRY_PATCH_RENAME_PID_TOKEN_V3
# CONTRACT_REGISTRY_PATCH_RENAME_PID_V2
# CONTRACT_REGISTRY_PATCH_RENAME_PID_V1
param(
 [Parameter(Mandatory=$true)][string]$RepoRoot,
 [Parameter()][string]$ContractRef = "example.contract.v1",
 [Parameter()][string]$ContractJsonPath = "",
 [Parameter()][string]$CreatedUtc = "2026-01-01T00:00:00Z",
 [Parameter()][string]$Stamp = "20260101_000000",
 [Parameter()][switch]$NoSign
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
# CONTRACT_REGISTRY_GOLDEN_TMP_OUTBOX_IDEMPOTENT_V3
# Sandbox-only: allow reruns by cleaning golden\tmp_outbox before building vectors
$GoldenTmp = Join-Path (Join-Path $RepoRoot "golden") "tmp_outbox"
if(Test-Path -LiteralPath $GoldenTmp -PathType Container){
  Remove-Item -LiteralPath $GoldenTmp -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $GoldenTmp | Out-Null

function EnsureDir([string]$p){ if (-not (Test-Path -LiteralPath $p -PathType Container)) { New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function RequireFile([string]$p){ if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { Die ("MISSING_FILE: " + $p) } }
function WriteUtf8NoBomLf([string]$Path,[string]$Text){
 $dir = Split-Path -Parent $Path
 if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
 $lf = ($Text -replace "`r`n","`n") -replace "`r","`n"
 if (-not $lf.EndsWith("`n")) { $lf += "`n" }
 [IO.File]::WriteAllText($Path,$lf,[Text.UTF8Encoding]::new($false))
}
function Sha256HexFile([string]$p){
 RequireFile $p
 $fs = [IO.File]::OpenRead($p)
 $sha = [Security.Cryptography.SHA256]::Create()
 try { $h = $sha.ComputeHash($fs) } finally { $sha.Dispose(); $fs.Dispose() }
 $sb = New-Object System.Text.StringBuilder
 for($i=0;$i -lt $h.Length;$i++){ [void]$sb.AppendFormat("{0:x2}", $h[$i]) }
 return $sb.ToString()
}
function ReadTextUtf8([string]$p){ RequireFile $p; return [IO.File]::ReadAllText($p,[Text.UTF8Encoding]::new($false)) }

$ScriptsDir = Join-Path $RepoRoot "scripts"
$Builder = Join-Path $ScriptsDir "contract_registry_make_release_packet_v1_1.ps1"
$Verifier = Join-Path $ScriptsDir "contract_registry_verify_release_packet_v1.ps1"
RequireFile $Builder
RequireFile $Verifier

if ([string]::IsNullOrWhiteSpace($ContractJsonPath)) {
 $ContractJsonPath = Join-Path $RepoRoot ("contracts\" + $ContractRef + ".json")
}
RequireFile $ContractJsonPath

$GoldenRoot = Join-Path $RepoRoot "golden"
$VecRoot = Join-Path (Join-Path $GoldenRoot "release_vectors") $ContractRef
$GoldenPacket = Join-Path $VecRoot "packet_root"
$ExpPid = Join-Path $VecRoot "expected_packet_id.txt"
$ExpSums = Join-Path $VecRoot "expected_sha256sums.txt"

# Build into a temp outbox under golden (never touches your normal outbox)
$TmpOut = Join-Path $GoldenRoot "tmp_outbox"
EnsureDir $TmpOut

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source
$args = @(
 "-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",$Builder,
 "-RepoRoot",$RepoRoot,
 "-ContractJsonPath",$ContractJsonPath,
 "-ContractRef",$ContractRef,
 "-OutDir",$TmpOut,
 "-CreatedUtc",$CreatedUtc,
 "-Stamp",$Stamp
)
if ($NoSign) { $args += "-NoSign" }
$p = Start-Process -FilePath $PSExe -ArgumentList $args -NoNewWindow -Wait -PassThru
if ($p.ExitCode -ne 0) { Die ("GOLDEN_BUILD_FAILED exit_code=" + $p.ExitCode) }

# Locate the deterministic packet directory we just built
$safeRef = ($ContractRef -replace '[^A-Za-z0-9._-]','_')
$Built = Join-Path $TmpOut ("contract_release_" + $safeRef + "_" + $Stamp)
if (-not (Test-Path -LiteralPath $Built -PathType Container)) { Die ("GOLDEN_PACKET_NOT_FOUND: " + $Built) }

# Verify with your real verifier (must pass)
$p2 = Start-Process -FilePath $PSExe -ArgumentList @(
 "-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",$Verifier,
 "-PacketRoot",$Built,
 "-RepoRoot",$RepoRoot
) -NoNewWindow -Wait -PassThru
if ($p2.ExitCode -ne 0) { Die ("GOLDEN_VERIFY_FAILED exit_code=" + $p2.ExitCode) }

$pidPath = Join-Path $Built "packet_id.txt"
$sumsPath = Join-Path $Built "sha256sums.txt"
RequireFile $pidPath
RequireFile $sumsPath
$pid = (ReadTextUtf8 $pidPath).Trim()
$sums = ReadTextUtf8 $sumsPath

if (-not (Test-Path -LiteralPath $VecRoot -PathType Container)) {
 # First-time freeze: create the golden vector pack
 EnsureDir $VecRoot
 if (Test-Path -LiteralPath $GoldenPacket -PathType Container) { Remove-Item -LiteralPath $GoldenPacket -Recurse -Force }
 Copy-Item -LiteralPath $Built -Destination $GoldenPacket -Recurse -Force
 WriteUtf8NoBomLf $ExpPid ($pid + "`n")
 WriteUtf8NoBomLf $ExpSums $sums
 Write-Host ("GOLDEN_VECTOR_CREATED: " + $VecRoot) -ForegroundColor Green
} else {
 # Already frozen: must match exactly
 RequireFile $ExpPid
 RequireFile $ExpSums
 if (-not (Test-Path -LiteralPath $GoldenPacket -PathType Container)) { Die ("GOLDEN_PACKET_MISSING: " + $GoldenPacket) }
 $pidExp = (ReadTextUtf8 $ExpPid).Trim()
 $sumsExp = ReadTextUtf8 $ExpSums
 if ($pidExp -ne $pid) { Die ("GOLDEN_MISMATCH_PACKET_ID expected=" + $pidExp + " got=" + $pid) }
 if ($sumsExp -ne $sums) { Die "GOLDEN_MISMATCH_SHA256SUMS: sha256sums.txt differs from expected" }
 # File-by-file hash compare using sha256sums list
 $lines = @(@($sumsExp -split "`n")) | Where-Object { $_ -and $_.Trim().Length -gt 0 }
 foreach($ln in @(@($lines))){
 $m = [System.Text.RegularExpressions.Regex]::Match($ln,'^([0-9a-f]{64})\s\s(.+)$')
 if (-not $m.Success) { Die ("BAD_SHA256SUMS_LINE: " + $ln) }
 $h = $m.Groups[1].Value
 $rel = $m.Groups[2].Value
 if ($rel -match '^\.\.' ) { Die ("BAD_SHA256SUMS_PATH: " + $rel) }
 $absG = Join-Path $GoldenPacket $rel
 $absB = Join-Path $Built $rel
 RequireFile $absG
 RequireFile $absB
 $hg = Sha256HexFile $absG
 $hb = Sha256HexFile $absB
 if ($hg -ne $h) { Die ("GOLDEN_HASH_MISMATCH: " + $rel + " expected=" + $h + " got=" + $hg) }
 if ($hb -ne $h) { Die ("BUILT_HASH_MISMATCH: " + $rel + " expected=" + $h + " got=" + $hb) }
 }
 Write-Host ("GOLDEN_VECTOR_MATCH_OK: " + $VecRoot) -ForegroundColor Green
}

# Repo-local evidence receipt (non-golden; OK to be time-stamped)
$Proofs = Join-Path $RepoRoot "proofs\receipts\golden_vectors"
EnsureDir $Proofs
$t = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss")
$rPath = Join-Path $Proofs ("golden_vectors_" + $ContractRef + "_" + $t + ".txt")
$r = New-Object System.Collections.Generic.List[string]
[void]$r.Add("schema: contract_registry_golden_vectors_receipt.v1")
[void]$r.Add("utc: " + [DateTime]::UtcNow.ToString("o"))
[void]$r.Add("contract_ref: " + $ContractRef)
[void]$r.Add("created_utc_pinned: " + $CreatedUtc)
[void]$r.Add("stamp_pinned: " + $Stamp)
[void]$r.Add("vector_root: " + $VecRoot)
[void]$r.Add("packet_id: " + $pid)
[void]$r.Add("expected_packet_id_file: " + $ExpPid)
[void]$r.Add("expected_sha256sums_file: " + $ExpSums)
WriteUtf8NoBomLf $rPath ((@($r.ToArray()) -join "`n") + "`n")
Write-Host ("RECEIPT_OK: " + $rPath) -ForegroundColor Gray
Write-Host ("GOLDEN_OK: " + $VecRoot) -ForegroundColor Green
