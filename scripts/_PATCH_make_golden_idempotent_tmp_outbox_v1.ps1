param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

function Die([string]$m){ throw $m }
function Ok([string]$m){ Write-Host $m -ForegroundColor Green }

$Target = Join-Path $RepoRoot "scripts\contract_registry_make_golden_vectors_v1.ps1"
if(-not (Test-Path -LiteralPath $Target -PathType Leaf)){
    Die ("TARGET_NOT_FOUND: " + $Target)
}

$Text = [System.IO.File]::ReadAllText($Target)

$Marker = "# === CR_GOLDEN_TMP_OUTBOX_INIT_V1 ==="

if($Text.Contains($Marker)){
    Ok "PATCH_ALREADY_PRESENT"
    return
}

$Injection = @'
# === CR_GOLDEN_TMP_OUTBOX_INIT_V1 ===
$TmpOutbox = Join-Path $RepoRoot "golden\tmp_outbox"

if(Test-Path -LiteralPath $TmpOutbox -PathType Container){
    Remove-Item -LiteralPath $TmpOutbox -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $TmpOutbox | Out-Null
# === END_CR_GOLDEN_TMP_OUTBOX_INIT_V1 ===
'@

# Insert after RepoRoot resolution line
$Lines = $Text -split "`r?`n"
$Out   = New-Object System.Collections.Generic.List[string]

$Inserted = $false

foreach($line in $Lines){
    $Out.Add($line)
    if(-not $Inserted -and $line -match '\$RepoRoot\s*=\s*\(Resolve-Path'){
        $Out.Add($Injection)
        $Inserted = $true
    }
}

if(-not $Inserted){
    Die "FAILED_TO_INSERT_MARKER"
}

$NewText = ($Out.ToArray() -join "`n") + "`n"

[System.IO.File]::WriteAllText($Target, $NewText, (New-Object System.Text.UTF8Encoding($false)))

# Parse gate
$tok=$null; $err=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($Target,[ref]$tok,[ref]$err)
if($err.Count -gt 0){
    Die "PARSE_FAILED_AFTER_PATCH"
}

Ok "PATCH_MAKE_GOLDEN_IDEMPOTENT_TMP_OUTBOX_V1_OK"