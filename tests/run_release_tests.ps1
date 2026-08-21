param(
  [string]$ShipZip = ""
)

$ErrorActionPreference = "Stop"


function Add-LfLine {
    param(
        [string]$Path,
        [string]$Line
    )
    $existing = ''
    if (Test-Path $Path) {
        $existing = [System.IO.File]::ReadAllText($Path)
    }
    $existing = $existing -replace "`r`n", "`n"
    $existing = $existing -replace "`r", "`n"
    if ($existing.Length -gt 0 -and -not $existing.EndsWith("`n")) {
        $existing += "`n"
    }
    $lf = $existing + $Line + "`n"
    [System.IO.File]::WriteAllText($Path, $lf, (New-Object System.Text.UTF8Encoding($false)))
}

function Test-ReleaseSmokeDecision {
  param(
    [int]$SmokeAExit,
    [int]$SmokeBExit,
    [int]$ProofsBeforeA,
    [int]$ProofsAfterA,
    [int]$ProofsBeforeB,
    [int]$ProofsAfterB,
    [string]$SmokeAOutcome,
    [string]$SmokeBOutcome,
    [bool]$ApprovalTokenRemaining
  )

  if ($SmokeAExit -eq 0) { return $false }
  if ($SmokeBExit -ne 0) { return $false }
  if ($ProofsAfterA -le $ProofsBeforeA) { return $false }
  if ($ProofsAfterB -le $ProofsBeforeB) { return $false }
  if ($SmokeAOutcome -ne "BLOCK") { return $false }
  if ($SmokeBOutcome -ne "ALLOW") { return $false }
  if ($ApprovalTokenRemaining) { return $false }
  return $true
}

function Assert-ReleaseSmokeDecision {
  param(
    [string]$Name,
    [bool]$Expected,
    [bool]$Actual
  )

  if ($Actual -ne $Expected) {
    throw "Release smoke decision self-test failed: $Name expected=$Expected actual=$Actual"
  }
}

function Invoke-ReleaseSmokeDecisionSelfTest {
  $good = @{
    SmokeAExit = 1
    SmokeBExit = 0
    ProofsBeforeA = 1
    ProofsAfterA = 2
    ProofsBeforeB = 2
    ProofsAfterB = 3
    SmokeAOutcome = "BLOCK"
    SmokeBOutcome = "ALLOW"
    ApprovalTokenRemaining = $false
  }

  Assert-ReleaseSmokeDecision -Name "good case" -Expected $true -Actual (Test-ReleaseSmokeDecision @good)

  $badSmokeA = $good.Clone()
  $badSmokeA["SmokeAOutcome"] = "ALLOW"
  Assert-ReleaseSmokeDecision -Name "SmokeA outcome mismatch" -Expected $false -Actual (Test-ReleaseSmokeDecision @badSmokeA)

  $badSmokeB = $good.Clone()
  $badSmokeB["SmokeBOutcome"] = "BLOCK"
  Assert-ReleaseSmokeDecision -Name "SmokeB outcome mismatch" -Expected $false -Actual (Test-ReleaseSmokeDecision @badSmokeB)

  $tokenRemaining = $good.Clone()
  $tokenRemaining["ApprovalTokenRemaining"] = $true
  Assert-ReleaseSmokeDecision -Name "approval token remaining" -Expected $false -Actual (Test-ReleaseSmokeDecision @tokenRemaining)

  Write-Host "Release smoke decision self-test: PASS"
}

Invoke-ReleaseSmokeDecisionSelfTest

$repoRoot = (git rev-parse --show-toplevel).Trim()

# Paths
if (-not $ShipZip) {
  $ShipZip = @(
    (Join-Path $repoRoot "dist\AI_Protected_Paths_v1.0.1_SHIP.zip"),
    (Join-Path $repoRoot "dist\AI_Protected_Paths_v1.0.0_SHIP.zip")
  ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
$shipZip = $ShipZip
if (!$shipZip -or !(Test-Path -LiteralPath $shipZip)) { throw "Missing ship zip. Pass -ShipZip <path>." }
$shipZip = (Resolve-Path -LiteralPath $shipZip).Path

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$runRoot = Join-Path $env:TEMP ("pp_ship_cleanroom_{0}" -f $timestamp)

# Clean run directory
if (Test-Path $runRoot) { Remove-Item $runRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
Set-Location $runRoot

# Create repo + unzip ship into repo root
git init | Out-Null
Expand-Archive -Path $shipZip -DestinationPath $runRoot -Force

# Install
if (Test-Path ".\install.ps1") {
  powershell -NoProfile -ExecutionPolicy Bypass -File ".\install.ps1" | Out-Host
} else {
  throw "Missing install.ps1 in ship zip (expected at repo root after unzip)."
}

# Baseline commit to ensure HEAD exists (important for bootstrap logic)
"baseline" | Out-File -Encoding utf8 -NoNewline ".\README.md"
git add ".\README.md" | Out-Null
Write-Host "`n=== DEBUG: $(Get-Date -Format o) BEFORE COMMIT (baseline) ==="
Write-Host "PWD=$((Get-Location).Path)"
Write-Host "--- git diff --cached --name-only ---"
git diff --cached --name-only
Write-Host "--- git status --porcelain ---"
git status --porcelain
 $baselineOut = (cmd /c "git commit -m ""baseline"" 2>&1" | Out-String)
$baselineExit = $LASTEXITCODE

# Proofs
$proofDir = Join-Path $runRoot "proofs\packets"
New-Item -ItemType Directory -Force -Path $proofDir | Out-Null
function Get-ProofNamesAsc {
  if (!(Test-Path $proofDir)) { return @() }
  return (Get-ChildItem -Path $proofDir -File -Filter "proof_*.json" |
      Sort-Object Name |
      Select-Object -ExpandProperty Name)
}

function Read-ProofOutcome {
  param([string]$name)
  $p = Join-Path $proofDir $name
  try {
    $j = Get-Content $p -Raw | ConvertFrom-Json
    return $j.outcome
  } catch {
    return "UNKNOWN"
  }
}

$proofs0 = Get-ProofNamesAsc
$baselineProof = if ($proofs0.Count -ge 1) { $proofs0[-1] } else { $null }

# Smoke A: NO token + protected change => expect BLOCK + new proof
Remove-Item ".\approvals\APPROVAL_TOKEN.txt" -Force -ErrorAction SilentlyContinue
Add-LfLine -Path (Join-Path $runRoot "governance\protected_paths.txt") -Line "auth/"
git add ".\governance\protected_paths.txt" | Out-Null

$proofsBeforeA = (Get-ProofNamesAsc).Count
Write-Host "`n=== DEBUG: $(Get-Date -Format o) BEFORE COMMIT (SmokeA) ==="
Write-Host "PWD=$((Get-Location).Path)"
Write-Host "--- git diff --cached --name-only ---"
git diff --cached --name-only
Write-Host "--- git status --porcelain ---"
git status --porcelain
 $smokeAOut = (cmd /c "git commit -m ""smokeA: protected no token"" 2>&1" | Out-String)
$smokeAExit = $LASTEXITCODE
$proofsAfterA = (Get-ProofNamesAsc).Count

# Smoke B: token present + protected change => expect ALLOW + new proof
New-Item -ItemType File -Force -Path ".\approvals\APPROVAL_TOKEN.txt" | Out-Null
Add-LfLine -Path (Join-Path $runRoot "governance\protected_paths.txt") -Line "payments/"
git add ".\governance\protected_paths.txt" | Out-Null

$proofsBeforeB = (Get-ProofNamesAsc).Count
Write-Host "`n=== DEBUG: $(Get-Date -Format o) BEFORE COMMIT (SmokeB) ==="
Write-Host "PWD=$((Get-Location).Path)"
Write-Host "--- git diff --cached --name-only ---"
git diff --cached --name-only
Write-Host "--- git status --porcelain ---"
git status --porcelain
 $smokeBOut = (cmd /c "git commit -m ""smokeB: protected with token"" 2>&1" | Out-String)
$smokeBExit = $LASTEXITCODE
$proofsAfterB = (Get-ProofNamesAsc).Count

# Deterministic proof labeling by order of creation
$proofs = Get-ProofNamesAsc
$baselineLabel = $null
$smokeALabel = $null
$smokeBLabel = $null

if ($proofs.Count -ge 1) { $baselineLabel = $proofs[0] }
if ($proofs.Count -ge 2) { $smokeALabel  = $proofs[1] }
if ($proofs.Count -ge 3) { $smokeBLabel  = $proofs[2] }

$smokeAOutcome = if ($smokeALabel) { Read-ProofOutcome $smokeALabel } else { "MISSING" }
$smokeBOutcome = if ($smokeBLabel) { Read-ProofOutcome $smokeBLabel } else { "MISSING" }
$approvalTokenRemaining = Test-Path ".\approvals\APPROVAL_TOKEN.txt"

Write-Host "SmokeA output:"
Write-Host $smokeAOut.TrimEnd()
Write-Host "SmokeB output:"
Write-Host $smokeBOut.TrimEnd()

Write-Host "=== RELEASE TEST SUMMARY ==="
Write-Host ("run_root: {0}" -f $runRoot)
Write-Host ("ship_zip: {0}" -f $shipZip)
Write-Host ("SmokeA exit={0} proofs_before={1} proofs_after={2}" -f $smokeAExit, $proofsBeforeA, $proofsAfterA)
Write-Host ("SmokeB exit={0} proofs_before={1} proofs_after={2}" -f $smokeBExit, $proofsBeforeB, $proofsAfterB)

if ($baselineLabel) { Write-Host ("Baseline proof: {0} outcome={1}" -f $baselineLabel, (Read-ProofOutcome $baselineLabel)) }
if ($smokeALabel)  { Write-Host ("SmokeA proof:   {0} outcome={1}" -f $smokeALabel,  $smokeAOutcome) }
if ($smokeBLabel)  { Write-Host ("SmokeB proof:   {0} outcome={1}" -f $smokeBLabel,  $smokeBOutcome) }
Write-Host ("Approval token remaining after SmokeB: {0}" -f $approvalTokenRemaining)

$pass = Test-ReleaseSmokeDecision `
  -SmokeAExit $smokeAExit `
  -SmokeBExit $smokeBExit `
  -ProofsBeforeA $proofsBeforeA `
  -ProofsAfterA $proofsAfterA `
  -ProofsBeforeB $proofsBeforeB `
  -ProofsAfterB $proofsAfterB `
  -SmokeAOutcome $smokeAOutcome `
  -SmokeBOutcome $smokeBOutcome `
  -ApprovalTokenRemaining $approvalTokenRemaining

if ($pass) {
  Write-Host "FINAL: PASS"
  exit 0
} else {
  Write-Host "FINAL: FAIL"
  exit 1
}
