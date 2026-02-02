$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Ok([string]$m){ Write-Host ("OK: " + $m) }
function Fail([string]$m){ throw $m }

Ok "running status check"
& (Join-Path $Root "scripts\_cr_status_check_v1.ps1")

Ok "schema parse check (only *.schema.json; receipt txt excluded)"
$SchemaFiles = Get-ChildItem -LiteralPath (Join-Path $Root "schemas") -Recurse -File -Filter "*.schema.json" | Sort-Object FullName
foreach($f in $SchemaFiles){ try { $null = (Get-Content -Raw -LiteralPath $f.FullName) | ConvertFrom-Json } catch { Fail ("Schema JSON parse failed: " + $f.FullName) } }
Ok ("schema json files parsed: " + $SchemaFiles.Count)

Ok "stress test complete"