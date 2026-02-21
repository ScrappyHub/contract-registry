param(
 [Parameter(Mandatory=$true)][string]$RepoRoot,
 [Parameter(Mandatory=$true)][string]$ContractJsonPath,
 [Parameter(Mandatory=$true)][string]$ContractRef,
 [Parameter(Mandatory=$true)][string]$OutDir,
 [Parameter()][string]$Producer = "contract-registry",
 [Parameter()][string]$Namespace = "contract-registry",
 [Parameter()][string]$SigningKeyPath = "",
 [Parameter()][switch]$NoSign,
 [Parameter()][string]$CreatedUtc = "",
 [Parameter()][string]$Stamp = ""
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function EnsureDir([string]$p){ if (-not (Test-Path -LiteralPath $p -PathType Container)) { New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function RequireFile([string]$p){ if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { Die ("MISSING_FILE: " + $p) } }
function WriteUtf8NoBomLf([string]$Path,[string]$Text){
 $dir = Split-Path -Parent $Path
 if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
 $lf = ($Text -replace "`r`n","`n") -replace "`r","`n"
 if (-not $lf.EndsWith("`n")) { $lf += "`n" }
 [IO.File]::WriteAllText($Path,$lf,[Text.UTF8Encoding]::new($false))
}
function Sha256HexBytes([byte[]]$b){
 if ($null -eq $b) { $b = @() }
 $sha = [Security.Cryptography.SHA256]::Create()
 try { $h = $sha.ComputeHash($b) } finally { $sha.Dispose() }
 $sb = New-Object System.Text.StringBuilder
 for($i=0;$i -lt $h.Length;$i++){ [void]$sb.AppendFormat("{0:x2}", $h[$i]) }
 return $sb.ToString()
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

# Canonical JSON (stable ordering, no whitespace, stable escaping).
function _JsonEscape([string]$s){
 if ($null -eq $s) { return "null" }
 $sb = New-Object System.Text.StringBuilder
 [void]$sb.Append("`"")
 for($i=0;$i -lt $s.Length;$i++){
 $ch = [int][char]$s[$i]
 switch($ch){
 34 { [void]$sb.Append('\"'); continue }
 92 { [void]$sb.Append('\\'); continue }
 8 { [void]$sb.Append('\b'); continue }
 12 { [void]$sb.Append('\f'); continue }
 10 { [void]$sb.Append('\n'); continue }
 13 { [void]$sb.Append('\r'); continue }
 9 { [void]$sb.Append('\t'); continue }
 default {
 if ($ch -lt 32) { [void]$sb.AppendFormat("\u{0:x4}", $ch); continue }
 [void]$sb.Append([char]$ch)
 }
 }
 }
 [void]$sb.Append("`"")
 return $sb.ToString()
}
function _CanonJson($v){
 if ($null -eq $v) { return "null" }
 if ($v -is [bool]) { return ($(if($v){"true"}else{"false"})) }
 if ($v -is [string]) { return (_JsonEscape $v) }
 if ($v -is [int] -or $v -is [long] -or $v -is [double] -or $v -is [decimal]) {
 return ([string]::Format([Globalization.CultureInfo]::InvariantCulture, "{0}", $v))
 }
 if ($v -is [System.Collections.IEnumerable] -and -not ($v -is [System.Collections.IDictionary]) -and -not ($v -is [string])) {
 $parts = New-Object System.Collections.Generic.List[string]
 foreach($it in @(@($v))){ [void]$parts.Add((_CanonJson $it)) }
 return ("[" + (($parts.ToArray()) -join ",") + "]")
 }
 $dict = $null
 if ($v -is [System.Collections.IDictionary]) { $dict = $v }
 else {
 $dict = @{}
 $ps = $v.PSObject
 foreach($p in $ps.Properties){ if ($p.MemberType -eq "NoteProperty" -or $p.MemberType -eq "Property") { $dict[$p.Name] = $p.Value } }
 }
 $keys = @(@($dict.Keys)) | Sort-Object
 $kv = New-Object System.Collections.Generic.List[string]
 foreach($k in @(@($keys))){
 $kk = _JsonEscape ([string]$k)
 $vv = _CanonJson $dict[$k]
 [void]$kv.Add(($kk + ":" + $vv))
 }
 return ("{" + (($kv.ToArray()) -join ",") + "}")
}
function CanonJsonBytes($obj){
 $s = _CanonJson $obj
 return [Text.UTF8Encoding]::new($false).GetBytes($s)
}
function CanonJsonFileToBytes([string]$jsonPath){
 RequireFile $jsonPath
 $raw = [IO.File]::ReadAllText($jsonPath, [Text.UTF8Encoding]::new($false))
 $obj = $raw | ConvertFrom-Json
 return (CanonJsonBytes $obj)
}

function ResolveSigningKey([string]$k){
 if ($NoSign) { return "" }
 if ($k -and (Test-Path -LiteralPath $k -PathType Leaf)) { return $k }
 $cand = @(
 (Join-Path $RepoRoot "keys\id_ed25519"),
 (Join-Path $RepoRoot "proofs\keys\id_ed25519")
 )
 foreach($c in @(@($cand))){ if (Test-Path -LiteralPath $c -PathType Leaf) { return $c } }
 Die "MISSING_SIGNING_KEY: provide -SigningKeyPath or create keys\id_ed25519 (or proofs\keys\id_ed25519), or pass -NoSign"
}

# Inputs
RequireFile $ContractJsonPath
EnsureDir $OutDir

# Deterministic knobs (optional)
$created = $CreatedUtc
if ([string]::IsNullOrWhiteSpace($created)) { $created = [DateTime]::UtcNow.ToString("o") }
$stamp = $Stamp
if ([string]::IsNullOrWhiteSpace($stamp)) { $stamp = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss") }

# Packet root
$safeRef = ($ContractRef -replace '[^A-Za-z0-9._-]','_')
$PacketRoot = Join-Path $OutDir ("contract_release_" + $safeRef + "_" + $stamp)
if (Test-Path -LiteralPath $PacketRoot) { Die ("OUT_EXISTS: " + $PacketRoot) }
EnsureDir $PacketRoot
EnsureDir (Join-Path $PacketRoot "payload")
EnsureDir (Join-Path $PacketRoot "receipts")
EnsureDir (Join-Path $PacketRoot "signatures")

# 1) payload/contract.json (canonical bytes) + payload/contract_ref.txt
$contractBytes = CanonJsonFileToBytes $ContractJsonPath
$ContractOut = Join-Path (Join-Path $PacketRoot "payload") "contract.json"
[IO.File]::WriteAllBytes($ContractOut, $contractBytes)
$ContractRefPath = Join-Path (Join-Path $PacketRoot "payload") "contract_ref.txt"
WriteUtf8NoBomLf $ContractRefPath ($ContractRef + "`n")
$contract_sha256 = Sha256HexBytes $contractBytes

# 2) payload/commit.payload.json + payload/commit_hash.txt
$CommitPayload = [ordered]@{
 schema = "commitment.v1"
 producer = $Producer
 created_utc = $created
 event_type = "contract-registry.release.v1"
 contract_ref = $ContractRef
 contract_sha256 = $contract_sha256
}
$commitBytes = CanonJsonBytes $CommitPayload
$CommitPath = Join-Path (Join-Path $PacketRoot "payload") "commit.payload.json"
[IO.File]::WriteAllBytes($CommitPath, $commitBytes)
$commitHash = Sha256HexBytes $commitBytes
$CommitHashPath = Join-Path (Join-Path $PacketRoot "payload") "commit_hash.txt"
WriteUtf8NoBomLf $CommitHashPath ($commitHash + "`n")

# 3) manifest.json (NO packet_id) — Option A
$ManifestObj = [ordered]@{
 schema = "packet_manifest.v1"
 producer = $Producer
 created_utc = $created
 namespace = $Namespace
 kind = "contract_release"
 contract_ref = $ContractRef
 files = @(
 [ordered]@{ path="manifest.json"; purpose="manifest-without-id" },
 [ordered]@{ path="packet_id.txt"; purpose="packet-id" },
 [ordered]@{ path="sha256sums.txt"; purpose="sha256sums-final" },
 [ordered]@{ path="payload/contract.json"; purpose="contract-canon-json" },
 [ordered]@{ path="payload/contract_ref.txt"; purpose="contract-ref" },
 [ordered]@{ path="payload/commit.payload.json"; purpose="commit-payload" },
 [ordered]@{ path="payload/commit_hash.txt"; purpose="commit-hash" }
 )
}
$manifestBytes = CanonJsonBytes $ManifestObj
$ManifestPath = Join-Path $PacketRoot "manifest.json"
[IO.File]::WriteAllBytes($ManifestPath, $manifestBytes)

# 4) PacketId = sha256(canonical bytes(manifest-without-id)) => packet_id.txt
$PacketId = Sha256HexBytes $manifestBytes
$PacketIdPath = Join-Path $PacketRoot "packet_id.txt"
WriteUtf8NoBomLf $PacketIdPath ($PacketId + "`n")

# 5) Optional detached signature over packet_id.txt
$SigPath = ""
if (-not $NoSign) {
 $k = ResolveSigningKey $SigningKeyPath
 $ssh = (Get-Command ssh-keygen.exe -ErrorAction Stop).Source
 $SigPath = Join-Path (Join-Path $PacketRoot "signatures") "packet_id.sig"
 $tmp = $PacketIdPath + ".sig"
 if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
 & $ssh -Y sign -f $k -n $Namespace $PacketIdPath | Out-Null
 if (-not (Test-Path -LiteralPath $tmp -PathType Leaf)) { Die "SIGN_FAIL: expected signature file not created: packet_id.txt.sig" }
 Move-Item -LiteralPath $tmp -Destination $SigPath -Force
}

# 6) sha256sums.txt LAST (final bytes on disk)
$sumLines = New-Object System.Collections.Generic.List[string]
function AddSum([string]$rel){
 $p = Join-Path $PacketRoot $rel
 RequireFile $p
 $h = Sha256HexFile $p
 [void]$sumLines.Add(($h + "  " + $rel))
}
AddSum "manifest.json"
AddSum "packet_id.txt"
AddSum "payload/contract.json"
AddSum "payload/contract_ref.txt"
AddSum "payload/commit.payload.json"
AddSum "payload/commit_hash.txt"
if ($SigPath) { AddSum "signatures/packet_id.sig" }
$ShaPath = Join-Path $PacketRoot "sha256sums.txt"
WriteUtf8NoBomLf $ShaPath ((@($sumLines.ToArray()) -join "`n") + "`n")

# 7) Receipt (packet-local)
$rc = New-Object System.Collections.Generic.List[string]
[void]$rc.Add("schema: contract_registry_release_receipt.v1")
[void]$rc.Add("utc: " + $created)
[void]$rc.Add("repo_root: " + $RepoRoot)
[void]$rc.Add("packet_root: " + $PacketRoot)
[void]$rc.Add("producer: " + $Producer)
[void]$rc.Add("namespace: " + $Namespace)
[void]$rc.Add("contract_ref: " + $ContractRef)
[void]$rc.Add("contract_sha256: " + $contract_sha256)
[void]$rc.Add("commit_hash: " + $commitHash)
[void]$rc.Add("packet_id: " + $PacketId)
[void]$rc.Add("signed: " + $(if($NoSign){"false"}else{"true"}))
if ($SigPath) { [void]$rc.Add("sig_path: signatures/packet_id.sig") }
[void]$rc.Add("sha256sums: sha256sums.txt")
$ReceiptPath = Join-Path (Join-Path $PacketRoot "receipts") "release_receipt.txt"
WriteUtf8NoBomLf $ReceiptPath ((@($rc.ToArray()) -join "`n") + "`n")

Write-Host ("RELEASE_PACKET_OK: " + $PacketRoot) -ForegroundColor Green
Write-Host ("packet_id=" + $PacketId) -ForegroundColor Gray
Write-Host ("receipt=" + $ReceiptPath) -ForegroundColor Gray
