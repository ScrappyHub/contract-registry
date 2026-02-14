[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$PacketDir
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

# CR_IDEMPOTENT_WRITE_NONL_V1
function CR_WriteTextIdempotentNoNewline([string]$Path,[string]$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  $newBytes = $enc.GetBytes($Text)
  $write = $true
  if (Test-Path -LiteralPath $Path -PathType Leaf) {
    $oldBytes = [System.IO.File]::ReadAllBytes($Path)
    if ($oldBytes.Length -eq $newBytes.Length) {
      $same = $true; for($ii=0; $ii -lt $newBytes.Length; $ii++){ if($newBytes[$ii] -ne $oldBytes[$ii]){ $same=$false; break } }
      if ($same) { $write = $false }
    }
  }
  if ($write) {
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [System.IO.File]::WriteAllBytes($Path, $newBytes)
  }
}

function CR_Sha256HexBytes([byte[]]$b){ if($null -eq $b){ $b=[byte[]]@() }; $sha=[System.Security.Cryptography.SHA256]::Create(); try{ $h=$sha.ComputeHash([byte[]]$b); $sb=New-Object System.Text.StringBuilder; for($i=0;$i -lt $h.Length;$i++){ [void]$sb.Append($h[$i].ToString("x2")) }; return $sb.ToString() } finally { $sha.Dispose() } }
function CR_ToUtf8NoBomLfBytes([string]$Text){ $cr=[string][char]13; $lf=[string][char]10; $t=$Text.Replace($cr+$lf,$lf).Replace($cr,$lf); if(-not $t.EndsWith($lf)){ $t+=$lf }; return (New-Object System.Text.UTF8Encoding($false)).GetBytes($t) }
function CR_ComputeContractShaV1_FromText([string]$rawText){ $obj=$rawText | ConvertFrom-Json; if($obj -and $obj.PSObject -and ($obj.PSObject.Properties.Match("sha256").Count -gt 0)){ [void]$obj.PSObject.Properties.Remove("sha256") }; $names=@(@($obj.PSObject.Properties | ForEach-Object { $_.Name })) | Sort-Object; $ht=[ordered]@{}; foreach($n in $names){ $ht[$n]=$obj.$n }; $json=($ht | ConvertTo-Json -Depth 50 -Compress); return (CR_Sha256HexBytes (CR_ToUtf8NoBomLfBytes $json)) }


# Canonical invariant: pipeline output may collapse => force arrays before .Count
function Force-Array($x) { @(@($x)) }

function Write-Utf8NoBomNoNewline([string]$Path, [string]$Text) {
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllBytes($Path, $enc.GetBytes($Text))
}

function Sha256HexFile([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ("Missing file: " + $Path) }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $fs = [System.IO.File]::OpenRead($Path)
    try { $h = $sha.ComputeHash($fs) } finally { $fs.Dispose() }
  } finally { $sha.Dispose() }
  ($h | ForEach-Object { $_.ToString("x2") }) -join ""
}

function UtcNowZ() { (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ") }

function Ensure-Dir([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Append-NeverLostReceipt([string]$RepoRoot, [hashtable]$ReceiptObj) {
  $rf = Join-Path $RepoRoot "proofs\receipts\neverlost.ndjson"
  Ensure-Dir (Split-Path -Parent $rf)

  # Deterministic NDJSON: UTF-8 no BOM, LF newline
  $line = ($ReceiptObj | ConvertTo-Json -Compress) + "`n"
  $enc = New-Object System.Text.UTF8Encoding($false)
  $bytes = $enc.GetBytes($line)

  $fs = [System.IO.File]::Open($rf, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
  try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }
}

function Move-ToQuarantine([string]$RepoRoot, [string]$PacketDir, [string]$PacketId) {
  $qRoot = Join-Path $RepoRoot "packets\quarantine"
  Ensure-Dir $qRoot

  $dest = Join-Path $qRoot $PacketId
  if (Test-Path -LiteralPath $dest) {
    $i = 1
    while (Test-Path -LiteralPath ($dest + "_dup" + $i)) { $i++ }
    $dest = ($dest + "_dup" + $i)
  }
  Move-Item -LiteralPath $PacketDir -Destination $dest -Force
  $dest
}

function Verify-PacketSignature([string]$AllowedSignersPath, [string]$Principal, [string]$Namespace, [string]$MessagePath, [string]$SigPath) {
  if (-not (Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue)) {
    throw "ssh-keygen.exe not found on PATH (required)."
  }
  if (-not (Test-Path -LiteralPath $AllowedSignersPath -PathType Leaf)) { throw ("Missing allowed_signers: " + $AllowedSignersPath) }
  if (-not (Test-Path -LiteralPath $MessagePath -PathType Leaf)) { throw ("Missing message: " + $MessagePath) }
  if (-not (Test-Path -LiteralPath $SigPath -PathType Leaf)) { throw ("Missing signature: " + $SigPath) }

  # ssh-keygen -Y verify reads message from stdin; use cmd.exe redirection deterministically
  $msgQ = '"' + $MessagePath.Replace('"','""') + '"'
  $asQ  = '"' + $AllowedSignersPath.Replace('"','""') + '"'
  $sigQ = '"' + $SigPath.Replace('"','""') + '"'
  $cmd = 'ssh-keygen -Y verify -f ' + $asQ + ' -I "' + $Principal + '" -n "' + $Namespace + '" -s ' + $sigQ + ' < ' + $msgQ

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "cmd.exe"
  $psi.Arguments = "/c " + $cmd
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true

  $proc = New-Object System.Diagnostics.Process
  $proc.StartInfo = $psi
  [void]$proc.Start()
  $stdout = $proc.StandardOutput.ReadToEnd()
  $stderr = $proc.StandardError.ReadToEnd()
  $proc.WaitForExit()

  if ($proc.ExitCode -ne 0) { throw ("Signature verification failed. stderr=" + $stderr.Trim()) }
  $stdout.Trim()
}

function Read-JsonFile([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw ("Missing JSON: " + $Path) }
  $raw = Get-Content -Raw -LiteralPath $Path
  try { $obj = $raw | ConvertFrom-Json } catch { throw ("JSON parse failed: " + $Path + " :: " + $_.Exception.Message) }
  @{ Raw = $raw; Obj = $obj }
}

function Require-NonEmpty([string]$Name, [string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { throw ("Missing/empty: " + $Name) }
}

function Validate-ContractManifest([object]$C, [string]$ContractJsonPath, [string]$PacketDir) {
  $contract_id = [string]$C.contract_id
  $version     = [string]$C.version
  $name        = [string]$C.name
  $namespace   = [string]$C.namespace
  $sha256      = [string]$C.sha256
  $created_utc = [string]$C.created_utc

  Require-NonEmpty "contract.contract_id" $contract_id
  Require-NonEmpty "contract.version" $version
  Require-NonEmpty "contract.name" $name
  Require-NonEmpty "contract.namespace" $namespace
  Require-NonEmpty "contract.sha256" $sha256
  Require-NonEmpty "contract.created_utc" $created_utc

  if ($contract_id -notmatch '^[a-z0-9][a-z0-9._-]+$') { throw ("contract_id invalid: " + $contract_id) }
  if ($version -notmatch '^[0-9]+\.[0-9]+(\.[0-9]+)?$') { throw ("version invalid: " + $version) }
  if ($sha256 -notmatch '^[0-9a-f]{64}$') { throw ("sha256 invalid: " + $sha256) }
  if ($created_utc -notmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$') { throw ("created_utc invalid: " + $created_utc) }

  # sha256 refers to contract.json bytes on disk
  $actual = Sha256HexFile -Path $ContractJsonPath
  # CR_COMPUTE_ACTUAL_CANON_V1
  $contractPath2 = ""
  if (Get-Variable -Name ContractJsonPath -Scope Local -ErrorAction SilentlyContinue) { if (-not [string]::IsNullOrWhiteSpace($ContractJsonPath)) { $contractPath2 = $ContractJsonPath } }
  if ([string]::IsNullOrWhiteSpace($contractPath2)) { if (Get-Variable -Name ContractPath -Scope Local -ErrorAction SilentlyContinue) { if (-not [string]::IsNullOrWhiteSpace($ContractPath)) { $contractPath2 = $ContractPath } } }
  if ([string]::IsNullOrWhiteSpace($contractPath2)) { throw "CONTRACT_SHA_PATCH_RUNTIME: missing $ContractJsonPath/$ContractPath" }
  $rawC = [System.IO.File]::ReadAllText($contractPath2,(New-Object System.Text.UTF8Encoding($false)))
  $actual = CR_ComputeContractShaV1_FromText $rawC
  if ($actual -ne $sha256) { throw ("contract.sha256 mismatch. expected=" + $sha256 + " actual=" + $actual) }

  # artifacts[] optional: verify declared hashes against packet contents
  # CANON: tolerate missing $C.artifacts under StrictMode
  $arts = @()
  if ($C -and $C.PSObject -and ($C.PSObject.Properties.Match("artifacts").Count -gt 0)) {
  # CANON: tolerate missing $c.artifacts under StrictMode
  $arts = @()
  if ($c -and $c.PSObject -and ($c.PSObject.Properties.Match("artifacts").Count -gt 0)) {
  # CANON: tolerate missing $c.artifacts under StrictMode
  $arts = @()
  if ($c -and $c.PSObject -and ($c.PSObject.Properties.Match("artifacts").Count -gt 0)) {
    $arts = Force-Array $c.artifacts
  }
  $arts = @(@($arts))
  }
  $arts = @(@($arts))
  }
  $arts = @(@($arts))
  if ($arts.Count -gt 0) {
    foreach ($a in $arts) {
      if ($null -eq $a) { continue }
      $p = [string]$a.path
      $h = [string]$a.sha256
      Require-NonEmpty "artifact.path" $p
      Require-NonEmpty "artifact.sha256" $h
      if ($h -notmatch '^[0-9a-f]{64}$') { throw ("artifact.sha256 invalid: " + $h) }

      $full = Join-Path $PacketDir $p
      $ah = Sha256HexFile -Path $full
      if ($ah -ne $h) { throw ("artifact sha256 mismatch for " + $p + ". expected=" + $h + " actual=" + $ah) }
    }
  }

  @{ contract_id=$contract_id; version=$version; name=$name; namespace=$namespace; sha256=$sha256; created_utc=$created_utc }
}

function Write-RegistryIndex([string]$RepoRoot){
  # CANON: deterministic registry builder (stable ordering + preserve timestamps)
  $regDir = Join-Path $RepoRoot "registry"
  Ensure-Dir $regDir
  $outPath = Join-Path $regDir "registry.json"
  $shaPath = Join-Path $regDir "registry.json.sha256"

  $old = $null
  if (Test-Path -LiteralPath $outPath -PathType Leaf) {
    try { $old = (Read-JsonFile -Path $outPath).Obj } catch { $old = $null }
  }

  $oldIndex = @{}
  if ($old -and $old.PSObject -and ($old.PSObject.Properties.Match("contracts").Count -gt 0)) {
    foreach($e in @(@(Force-Array $old.contracts))){
      if ($null -eq $e) { continue }
      $cid = [string]$e.contract_id
      $ver = [string]$e.version
      if ([string]::IsNullOrWhiteSpace($cid) -or [string]::IsNullOrWhiteSpace($ver)) { continue }
      $k = ($cid + "@" + $ver)
      $oldIndex[$k] = $e
    }
  }

  $contractsRoot = Join-Path $RepoRoot "contracts"
  Ensure-Dir $contractsRoot

  $items = New-Object System.Collections.Generic.List[object]
  $cidDirs = @(Get-ChildItem -LiteralPath $contractsRoot -Directory -ErrorAction Stop | Sort-Object Name)
  foreach($cidDir in $cidDirs){
    $verDirs = @(Get-ChildItem -LiteralPath $cidDir.FullName -Directory -ErrorAction Stop | Sort-Object Name)
    foreach($verDir in $verDirs){
      $contractPath = Join-Path $verDir.FullName "contract.json"
      if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) { continue }
      $cid = [string]$cidDir.Name
      $ver = [string]$verDir.Name
      $sha = Sha256HexFile -Path $contractPath
      $key = ($cid + "@" + $ver)

      $pub = ""; $cre=""; $upd=""
      if ($oldIndex.ContainsKey($key)) {
        $oe = $oldIndex[$key]
        if ($oe -and $oe.PSObject) {
          if (($oe.PSObject.Properties.Match("published_utc").Count -gt 0)) { $pub = [string]$oe.published_utc }
          if (($oe.PSObject.Properties.Match("created_utc").Count   -gt 0)) { $cre = [string]$oe.created_utc }
          if (($oe.PSObject.Properties.Match("updated_utc").Count   -gt 0)) { $upd = [string]$oe.updated_utc }
        }
      }
      if ([string]::IsNullOrWhiteSpace($pub)) { $pub = UtcNowZ }
      if ([string]::IsNullOrWhiteSpace($cre)) { $cre = $pub }
      if ([string]::IsNullOrWhiteSpace($upd)) { $upd = $pub }

      $rel = ("contracts/" + $cid + "/" + $ver + "/contract.json")
      $e = [ordered]@{ contract_id=$cid; version=$ver; path=$rel; sha256=$sha; published_utc=$pub; created_utc=$cre; updated_utc=$upd }
      [void]$items.Add($e)
    }
  }

  $items2 = @(@($items.ToArray()) | Sort-Object contract_id, version)

  $regPub = ""
  if ($old -and $old.PSObject -and ($old.PSObject.Properties.Match("published_utc").Count -gt 0)) { $regPub = [string]$old.published_utc }
  if ([string]::IsNullOrWhiteSpace($regPub)) { $regPub = UtcNowZ }

  $reg = [ordered]@{ schema="contract_registry.v1"; published_utc=$regPub; contract_count=$items2.Count; contracts=$items2 }
  $json = ($reg | ConvertTo-Json -Depth 50 -Compress)

  Write-Utf8NoBomNoNewline -Path $outPath -Text $json
  $sha = Sha256HexFile -Path $outPath
  Write-Utf8NoBomNoNewline -Path $shaPath -Text ($sha + "  registry.json`r`n")

  return @{ registry_path=$outPath; registry_sha256=$sha; contract_count=$items2.Count }
}

# ---------------------------
# Main: ingest packet (canonical packet_id MUST equal folder name)
# ---------------------------
if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) { throw "RepoRoot missing: $RepoRoot" }
if (-not (Test-Path -LiteralPath $PacketDir -PathType Container)) { throw "PacketDir missing: $PacketDir" }

$packetFolder = [System.IO.Path]::GetFileName($PacketDir.TrimEnd("\","/"))

$tbPath = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"
$asPath = Join-Path $RepoRoot "proofs\trust\allowed_signers"

$packetJsonPath   = Join-Path $PacketDir "packet.json"
$packetSigPath    = Join-Path $PacketDir "packet.json.sig"
$contractJsonPath = Join-Path $PacketDir "contract.json"

$tbSha = Sha256HexFile -Path $tbPath
$asSha = Sha256HexFile -Path $asPath

$receiptBase = [ordered]@{
  schema="neverlost.receipt.v1"; time_utc=(UtcNowZ); action="contract-registry.ingest_packet"
  ok=$false; reason=""; repo_root=$RepoRoot; namespace=""; identity=""; packet_id=""
  inputs=[ordered]@{ packet_dir=$PacketDir; packet_json=$packetJsonPath; sig_path=$packetSigPath; contract_json=$contractJsonPath }
  hashes=[ordered]@{ trust_bundle_sha256=$tbSha; allowed_signers_sha256=$asSha; packet_json_sha256=""; sig_sha256=""; contract_json_sha256="" }
  outputs=[ordered]@{ installed_contract_path=""; registry_path=""; registry_sha256="" }
}

try {
  if (-not (Test-Path -LiteralPath $packetJsonPath -PathType Leaf)) { throw "Missing packet.json in PacketDir" }
  if (-not (Test-Path -LiteralPath $packetSigPath  -PathType Leaf)) { throw "Missing packet.json.sig in PacketDir" }
  if (-not (Test-Path -LiteralPath $contractJsonPath -PathType Leaf)) { throw "Missing contract.json in PacketDir" }

  $receiptBase.hashes.packet_json_sha256   = Sha256HexFile -Path $packetJsonPath
  $receiptBase.hashes.sig_sha256           = Sha256HexFile -Path $packetSigPath
  $receiptBase.hashes.contract_json_sha256 = Sha256HexFile -Path $contractJsonPath

  $pj = Read-JsonFile -Path $packetJsonPath
  $p = $pj.Obj

  $packet_id = [string]$p.packet_id
  $principal = [string]$p.principal
  $ns        = [string]$p.namespace

  Require-NonEmpty "packet.packet_id" $packet_id
  if ($packet_id -ne $packetFolder) { throw ("packet_id must equal folder name. packet_id=" + $packet_id + " folder=" + $packetFolder) }

  Require-NonEmpty "packet.principal" $principal
  Require-NonEmpty "packet.namespace" $ns

  $receiptBase.packet_id = $packet_id
  $receiptBase.identity  = $principal
  $receiptBase.namespace = $ns

  [void](Verify-PacketSignature -AllowedSignersPath $asPath -Principal $principal -Namespace $ns -MessagePath $packetJsonPath -SigPath $packetSigPath)

  $cj = Read-JsonFile -Path $contractJsonPath
  $c = $cj.Obj
  $info = Validate-ContractManifest -C $c -ContractJsonPath $contractJsonPath -PacketDir $PacketDir

  $dstDir = Join-Path $RepoRoot ("contracts\" + $info.contract_id + "\" + $info.version)
  Ensure-Dir $dstDir

  $dstContract = Join-Path $dstDir "contract.json"
  Copy-Item -LiteralPath $contractJsonPath -Destination $dstContract -Force

  # CANON: tolerate missing $c.artifacts under StrictMode
  $arts = @()
  if ($c -and $c.PSObject -and ($c.PSObject.Properties.Match("artifacts").Count -gt 0)) {
    $arts = Force-Array $c.artifacts
  }
  $arts = @(@($arts))
  if ($arts.Count -gt 0) {
    foreach ($a in $arts) {
      if ($null -eq $a) { continue }
      $rel = [string]$a.path
      if ([string]::IsNullOrWhiteSpace($rel)) { continue }
      $src = Join-Path $PacketDir $rel
      $dst = Join-Path $dstDir $rel
      Ensure-Dir (Split-Path -Parent $dst)
      Copy-Item -LiteralPath $src -Destination $dst -Force
    }
  }

  $receiptBase.outputs.installed_contract_path = $dstContract

  $regOut = Write-RegistryIndex -RepoRoot $RepoRoot
  $receiptBase.outputs.registry_path   = [string]$regOut.registry_path
  $receiptBase.outputs.registry_sha256 = [string]$regOut.registry_sha256

  $receiptBase.ok = $true
  $receiptBase.reason = ""
  Append-NeverLostReceipt -RepoRoot $RepoRoot -ReceiptObj $receiptBase

  Write-Host ("OK: ingested packet_id=" + $packet_id + " contract=" + $info.contract_id + "@" + $info.version)
  Write-Host ("OK: published registry contracts=" + $regOut.contract_count + " sha256=" + $regOut.registry_sha256)
}
catch {
  $receiptBase.ok = $false
  $receiptBase.reason = [string]$_.Exception.Message

  try {
    if ([string]::IsNullOrWhiteSpace($receiptBase.packet_id)) { $receiptBase.packet_id = $packetFolder }
    $q = Move-ToQuarantine -RepoRoot $RepoRoot -PacketDir $PacketDir -PacketId $receiptBase.packet_id
    $receiptBase.outputs = [ordered]@{ quarantined_to = $q }
  } catch { }

  Append-NeverLostReceipt -RepoRoot $RepoRoot -ReceiptObj $receiptBase
  throw
}
