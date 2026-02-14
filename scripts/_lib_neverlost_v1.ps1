$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

# =========================
# NeverLost v1 portable lib
# =========================

function Write-Utf8NoBom {
  param([Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Text,
        [switch]$Append)
  $enc = New-Object System.Text.UTF8Encoding($false) # no BOM
  $bytes = $enc.GetBytes($Text)
  if ($Append) {
    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
    try { $fs.Write($bytes, 0, $bytes.Length) } finally { $fs.Dispose() }
  } else {
    [System.IO.File]::WriteAllBytes($Path, $bytes)
  }
}

function Read-Utf8 {
  param([Parameter(Mandatory=$true)][string]$Path)
  return [System.IO.File]::ReadAllText($Path, (New-Object System.Text.UTF8Encoding($false)))
}

function Sha256HexBytes {
  param([Parameter(Mandatory=$true)][byte[]]$Bytes)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $h = $sha.ComputeHash($Bytes)
    return ([System.BitConverter]::ToString($h) -replace "-", "").ToLowerInvariant()
  } finally { $sha.Dispose() }
}

function Sha256HexPath {
  param([Parameter(Mandatory=$true)][string]$Path)
  $b = [System.IO.File]::ReadAllBytes($Path)
  return Sha256HexBytes -Bytes $b
}

function ResolveRealPath {
  param([Parameter(Mandatory=$true)][string]$Path)
  $p = (Resolve-Path -LiteralPath $Path).Path
  return $p
}

function RelPathUnix {
  param([Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$true)][string]$FullPath)
  $r = (ResolveRealPath $Root).TrimEnd('\')
  $f = (ResolveRealPath $FullPath)
  if (-not $f.StartsWith($r, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Path is not under root. root=$r full=$f"
  }
  $rel = $f.Substring($r.Length).TrimStart('\')
  return ($rel -replace '\\','/')
}

function AssertPrincipalFormat {
  param([Parameter(Mandatory=$true)][string]$Principal)
  # single-tenant/<tenant_authority>/authority/<producer>
  $re = '^single-tenant\/[A-Za-z0-9._-]+\/authority\/[A-Za-z0-9._-]+$'
  if ($Principal -notmatch $re) { throw "Invalid principal format: $Principal" }
}

function AssertKeyIdFormat {
  param([Parameter(Mandatory=$true)][string]$KeyId)
  # stable string identifier (not filename/fingerprint) ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Å“ keep strict
  $re = '^[A-Za-z0-9][A-Za-z0-9._:-]{0,62}$'
  if ($KeyId -notmatch $re) { throw "Invalid key_id format: $KeyId" }
}

function To-CanonObject {
  param([Parameter(Mandatory=$true)]$Value)

  if ($null -eq $Value) { return $null }

  # arrays: keep order
  if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string]) -and -not ($Value -is [System.Collections.IDictionary])) {
    $arr = @()
    foreach ($v in $Value) { $arr += (To-CanonObject $v) }
    return ,$arr
  }

  # dictionaries/PSCustomObject: sort keys ordinal
  if ($Value -is [System.Collections.IDictionary] -or $Value -is [pscustomobject]) {
    $ht = @{}
    if ($Value -is [System.Collections.IDictionary]) {
      foreach ($k in $Value.Keys) { $ht["$k"] = $Value[$k] }
    } else {
      foreach ($p in $Value.PSObject.Properties) { $ht[$p.Name] = $p.Value }
    }

    $ordered = [ordered]@{}
    foreach ($k in ($ht.Keys | Sort-Object)) {
      $ordered[$k] = To-CanonObject $ht[$k]
    }
    return $ordered
  }

  return $Value
}

function To-CanonJson {
  param([Parameter(Mandatory=$true)]$Object)
  # Stable key ordering + stable whitespace: minified JSON with LF only.
  $canon = To-CanonObject $Object
  $json = ($canon | ConvertTo-Json -Depth 64 -Compress)
  # ConvertTo-Json uses CRLF in some contexts; enforce LF
  $json = $json -replace "`r`n","`n"
  return $json
}

function LoadTrustBundle {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true)][string]$TrustBundlePath,
    [int]$Depth = 64
  )

  if (-not (Test-Path -LiteralPath $TrustBundlePath -PathType Leaf)) {
    throw ("trust_bundle.json not found: " + $TrustBundlePath)
  }

  $raw = Read-Utf8 -Path $TrustBundlePath

  $cmd = Get-Command ConvertFrom-Json -ErrorAction Stop
  if ($cmd.Parameters.ContainsKey("Depth")) {
    return ($raw | ConvertFrom-Json -Depth $Depth)
  }

  return ($raw | ConvertFrom-Json)
}


function MakeAllowedSignersLine {
  param(
    [Parameter(Mandatory=$true)][string]$Principal,
    [Parameter(Mandatory=$true)][string[]]$Namespaces,
    [Parameter(Mandatory=$true)][string]$PubKey
  )
  AssertPrincipalFormat $Principal
  if ($Namespaces.Count -lt 1) { throw "Namespaces must be non-empty" }

  $ns = ($Namespaces | Sort-Object) -join ","
  $pk = $PubKey.Trim()
  # OpenSSH allowed_signers supports options. We pin namespaces here.
  return ("{0} namespaces=""{1}"" {2}" -f $Principal, $ns, $pk)
}

function WriteAllowedSignersFile {
  param(
    [Parameter(Mandatory=$true)]$TrustBundleObject,
    [Parameter(Mandatory=$true)][string]$AllowedSignersPath
  )
  $lines = @()
  foreach ($r in ($TrustBundleObject.records | Sort-Object principal, key_id)) {
    $lines += (MakeAllowedSignersLine -Principal $r.principal -Namespaces $r.namespaces -PubKey $r.pubkey)
  }
  $text = ($lines -join "`n") + "`n"
  Write-Utf8NoBom -Path $AllowedSignersPath -Text $text
}

function Write-NeverLostReceipt {
  param(
    [Parameter(Mandatory=$true)][string]$ReceiptsPath,
    [Parameter(Mandatory=$true)]$ReceiptObject
  )
  $line = (To-CanonJson $ReceiptObject) + "`n"
  Write-Utf8NoBom -Path $ReceiptsPath -Text $line -Append
}

function SshYSignFile {
  param(
    [Parameter(Mandatory=$true)][string]$SignerKeyPath,
    [Parameter(Mandatory=$true)][string]$Namespace,
    [Parameter(Mandatory=$true)][string]$Principal,
    [Parameter(Mandatory=$true)][string]$FilePath
  )
  if (-not (Test-Path -LiteralPath $SignerKeyPath -PathType Leaf)) { throw "Signer key not found: $SignerKeyPath" }
  if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { throw "File not found: $FilePath" }
  AssertPrincipalFormat $Principal
  if ($Namespace.Trim().Length -lt 1) { throw "Namespace required" }

  $p = "C:\Windows\System32\OpenSSH\ssh-keygen.exe"
  if (Test-Path -LiteralPath $p) { $ssh = $p } else { $ssh = "ssh-keygen.exe" }

  $sig = $FilePath + ".sig"
  if (-not (Test-Path -LiteralPath $sig -PathType Leaf)) { throw "Signature file not created: $sig" }
  return $sig
}

function SshYVerifyFile {
  param(
    [Parameter(Mandatory=$true)][string]$AllowedSignersPath,
    [Parameter(Mandatory=$true)][string]$Principal,
    [Parameter(Mandatory=$true)][string]$Namespace,
    [Parameter(Mandatory=$true)][string]$SigPath,
    [Parameter(Mandatory=$true)][string]$FilePath
  )
  if (-not (Test-Path -LiteralPath $AllowedSignersPath -PathType Leaf)) { throw "allowed_signers not found: $AllowedSignersPath" }
  if (-not (Test-Path -LiteralPath $SigPath -PathType Leaf)) { throw "sig not found: $SigPath" }
  if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { throw "file not found: $FilePath" }
  AssertPrincipalFormat $Principal
  if ($Namespace.Trim().Length -lt 1) { throw "Namespace required" }

  $p = "C:\Windows\System32\OpenSSH\ssh-keygen.exe"
  if (Test-Path -LiteralPath $p) { $ssh = $p } else { $ssh = "ssh-keygen.exe" }
}
