Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

param(
    [Parameter(Mandatory=$true)][string]$RepoRoot
)

function Write-Utf8NoBomLf {
    param([string]$Path,[string]$Content)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path,$Content,$enc)
}

function Parse-Gate {
    param([string]$Path)
    $tok=$null;$err=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)
    if($err){
        throw ("PARSE_FAIL: " + $Path)
    }
}

$Targets = @(
    "scripts\workbench_cli_v1.ps1",
    "scripts\workbench_doctor_v1.ps1",
    "scripts\workbench_bootstrap_v1.ps1",
    "scripts\workbench_verify_download_v1.ps1"
)

foreach($rel in $Targets){
    $path = Join-Path $RepoRoot $rel
    if(-not (Test-Path -LiteralPath $path)){
        continue
    }

    $txt = Get-Content -Raw -LiteralPath $path

    # 🔥 Inject deterministic root block if missing
    if($txt -notmatch "WORKBENCH_ROOT_RESOLVE_V1"){
        $inject = @'
# WORKBENCH_ROOT_RESOLVE_V1
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $ScriptDir "..")
$ScriptsRoot = Join-Path $RepoRoot "scripts"
# END_WORKBENCH_ROOT_RESOLVE_V1
'@

        $txt = $inject + "`n" + $txt
    }

    # Replace any direct $ScriptsRoot assumptions
    $txt = $txt -replace '\$ScriptsRoot', '$ScriptsRoot'

    Write-Utf8NoBomLf $path $txt
    Parse-Gate $path

    Write-Host ("PATCHED_WORKBENCH_ROOT: " + $path) -ForegroundColor Green
}

Write-Host "WORKBENCH_ROOT_FIX_OK" -ForegroundColor Green