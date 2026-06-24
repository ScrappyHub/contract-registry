param(
  [Parameter(Mandatory=$true)]
  [string]$TargetRepo,

  [Parameter(Mandatory=$false)]
  [string]$MachineId = "local-dev-machine",

  [Parameter(Mandatory=$false)]
  [string]$VerifierIdentity = "cr-verifier-001"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Capture-PathFromOutput {
  param(
    [object[]]$Output,
    [string]$Prefix
  )

  foreach($Line in @($Output)){
    $S = [string]$Line
    if($S.StartsWith($Prefix)){
      return $S.Substring($Prefix.Length).Trim()
    }
  }

  return ""
}

function Run-Step {
  param(
    [string]$StepName,
    [string]$Script,
    [string[]]$StepArgs
  )

  Write-Host ("VERIFIED_RUNTIME_STEP_START: " + $StepName) -ForegroundColor Cyan

  $Cmd = @(
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $Script
  ) + @($StepArgs)

  $Out = & powershell.exe @Cmd 2>&1
  $Exit = $LASTEXITCODE

  foreach($Line in @($Out)){ Write-Host $Line }

  if($Exit -ne 0){
    throw ("VERIFIED_RUNTIME_STEP_FAIL: " + $StepName + " EXIT=" + $Exit)
  }

  Write-Host ("VERIFIED_RUNTIME_STEP_OK: " + $StepName) -ForegroundColor Green
  return @($Out)
}

if(-not (Test-Path -LiteralPath $TargetRepo -PathType Container)){
  throw "TARGET_REPO_NOT_FOUND: $TargetRepo"
}

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ResolvedRepo = (Resolve-Path -LiteralPath $TargetRepo).Path

$MachineScript = Join-Path $ScriptRoot "cr_machine_evidence_v1.ps1"
$VerifyScript = Join-Path $ScriptRoot "cr_remote_attestation_verifier_v1.ps1"
$EvaluatorScript = Join-Path $ScriptRoot "cr_policy_evaluator_v1.ps1"
$ClearanceScript = Join-Path $ScriptRoot "cr_conditional_clearance_v1.ps1"
$BundleScript = Join-Path $ScriptRoot "cr_policy_bundle_v1.ps1"
$TrustScript = Join-Path $ScriptRoot "cr_trust_registry_v1.ps1"
$RuntimeScript = Join-Path $ScriptRoot "cr_governance_runtime_v1.ps1"

$RequiredScripts = @(
  $MachineScript,
  $VerifyScript,
  $EvaluatorScript,
  $ClearanceScript,
  $BundleScript,
  $TrustScript,
  $RuntimeScript
)

foreach($S in $RequiredScripts){
  if(-not (Test-Path -LiteralPath $S -PathType Leaf)){
    throw ("MISSING_SCRIPT: " + $S)
  }
}

$MachineOut = Run-Step -StepName "machine_evidence" -Script $MachineScript -StepArgs @(
  "-TargetRepo", $ResolvedRepo,
  "-MachineId", $MachineId,
  "-Mode", "synthetic"
)

$EvidencePath = Capture-PathFromOutput -Output $MachineOut -Prefix "EVIDENCE:"
if([string]::IsNullOrWhiteSpace($EvidencePath)){
  throw "EVIDENCE_PATH_NOT_CAPTURED"
}

$VerifyOut = Run-Step -StepName "remote_attestation_verifier" -Script $VerifyScript -StepArgs @(
  "-TargetRepo", $ResolvedRepo,
  "-EvidencePath", $EvidencePath,
  "-VerifierIdentity", $VerifierIdentity
)

$VerificationPath = Capture-PathFromOutput -Output $VerifyOut -Prefix "VERIFICATION:"
if([string]::IsNullOrWhiteSpace($VerificationPath)){
  throw "VERIFICATION_PATH_NOT_CAPTURED"
}

$EvalOut = Run-Step -StepName "policy_evaluator" -Script $EvaluatorScript -StepArgs @(
  "-TargetRepo", $ResolvedRepo,
  "-EvidencePath", $EvidencePath,
  "-VerificationPath", $VerificationPath
)

$DecisionPath = Capture-PathFromOutput -Output $EvalOut -Prefix "DECISION:"
if([string]::IsNullOrWhiteSpace($DecisionPath)){
  throw "DECISION_PATH_NOT_CAPTURED"
}

$ClearanceOut = Run-Step -StepName "conditional_clearance" -Script $ClearanceScript -StepArgs @(
  "-TargetRepo", $ResolvedRepo,
  "-DecisionPath", $DecisionPath
)

$ClearancePath = Capture-PathFromOutput -Output $ClearanceOut -Prefix "CLEARANCE:"
if([string]::IsNullOrWhiteSpace($ClearancePath)){
  throw "CLEARANCE_PATH_NOT_CAPTURED"
}

$BundleOut = Run-Step -StepName "policy_bundle" -Script $BundleScript -StepArgs @(
  "-TargetRepo", $ResolvedRepo
)

$BundlePath = Capture-PathFromOutput -Output $BundleOut -Prefix "BUNDLE:"
if([string]::IsNullOrWhiteSpace($BundlePath)){
  throw "BUNDLE_PATH_NOT_CAPTURED"
}

$TrustOut = Run-Step -StepName "trust_registry" -Script $TrustScript -StepArgs @(
  "-TargetRepo", $ResolvedRepo
)

$TrustRegistryPath = Capture-PathFromOutput -Output $TrustOut -Prefix "TRUST_REGISTRY:"
if([string]::IsNullOrWhiteSpace($TrustRegistryPath)){
  throw "TRUST_REGISTRY_PATH_NOT_CAPTURED"
}

$RuntimeOut = Run-Step -StepName "governance_runtime" -Script $RuntimeScript -StepArgs @(
  "-TargetRepo", $ResolvedRepo
)

$RuntimePath = Capture-PathFromOutput -Output $RuntimeOut -Prefix "GOVERNANCE_RUNTIME:"
if([string]::IsNullOrWhiteSpace($RuntimePath)){
  throw "GOVERNANCE_RUNTIME_PATH_NOT_CAPTURED"
}

$RepoName = Split-Path -Leaf $ResolvedRepo
$ProfileRoot = Join-Path $ResolvedRepo ("runtime\shadow_profiles\" + $RepoName)
$Root = Join-Path $ProfileRoot "verified_runtime"
New-Item -ItemType Directory -Force -Path $Root | Out-Null

$Stamp = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss")
$ReceiptPath = Join-Path $Root ($Stamp + ".verified_runtime_receipt.json")

$Receipt = [ordered]@{
  schema = "contract_registry.verified_runtime_receipt.v1"
  utc = [DateTime]::UtcNow.ToString("o")
  repo_name = $RepoName
  target_repo = $ResolvedRepo
  machine_id = $MachineId
  verifier_identity = $VerifierIdentity
  evidence = $EvidencePath
  verification = $VerificationPath
  decision = $DecisionPath
  clearance = $ClearancePath
  policy_bundle = $BundlePath
  trust_registry = $TrustRegistryPath
  governance_runtime = $RuntimePath
}

function Write-Utf8NoBomLf {
  param([string]$Path,[string]$Text)
  $Text = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $Text.EndsWith("`n")){ $Text += "`n" }
  [IO.File]::WriteAllText($Path,$Text,[Text.UTF8Encoding]::new($false))
}

Write-Utf8NoBomLf -Path $ReceiptPath -Text ($Receipt | ConvertTo-Json -Depth 20)

Write-Host "CR_VERIFIED_RUNTIME_OK" -ForegroundColor Green
Write-Host ("RECEIPT: " + $ReceiptPath)
Write-Host ("EVIDENCE: " + $EvidencePath)
Write-Host ("VERIFICATION: " + $VerificationPath)
Write-Host ("DECISION: " + $DecisionPath)
Write-Host ("CLEARANCE: " + $ClearancePath)
Write-Host ("POLICY_BUNDLE: " + $BundlePath)
Write-Host ("TRUST_REGISTRY: " + $TrustRegistryPath)
Write-Host ("GOVERNANCE_RUNTIME: " + $RuntimePath)