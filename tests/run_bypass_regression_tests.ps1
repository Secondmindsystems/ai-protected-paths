param(
  # Path to the SHIP zip to test. Defaults to the v1.0.1 artifact; falls back to v1.0.0.
  [string]$ShipZip = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = (git rev-parse --show-toplevel).Trim()
if (-not $ShipZip) {
  $cand = @(
    (Join-Path $repoRoot "dist\AI_Protected_Paths_v1.0.1_SHIP.zip"),
    (Join-Path $repoRoot "dist\AI_Protected_Paths_v1.0.0_SHIP.zip")
  )
  $ShipZip = $cand | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $ShipZip -or -not (Test-Path $ShipZip)) { throw "Ship zip not found. Pass -ShipZip <path>." }
$ShipZip = (Resolve-Path -LiteralPath $ShipZip).Path

# Unzip the kit ONCE to a package dir OUTSIDE the test repos (Flow B: recommended).
$stamp   = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$work    = Join-Path $env:TEMP ("pp_bypass_{0}" -f $stamp)
$pkgDir  = Join-Path $work "pkg"
New-Item -ItemType Directory -Force -Path $pkgDir | Out-Null
Expand-Archive -Path $ShipZip -DestinationPath $pkgDir -Force

$script:pass = 0; $script:fail = 0
function Ok($label)   { Write-Host "  PASS  $label"; $script:pass++ }
function Bad($label,$got) { Write-Host "  FAIL  $label (got=$got)"; $script:fail++ }
function Assert($label,$cond) { if ($cond) { Ok $label } else { Bad $label $cond } }

$repoNo = 0
function New-TestRepo {
  $script:repoNo++
  $r = Join-Path $work ("repo{0}" -f $script:repoNo)
  New-Item -ItemType Directory -Force -Path $r | Out-Null
  Set-Location $r
  git init -q | Out-Null
  git config user.name  "Regression"
  git config user.email "regression@example.com"
  git config commit.gpgsign false
  # Flow B install: package outside repo, invoke launcher by absolute path.
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pkgDir "protected-paths.ps1") install *> $null
  return $r
}
function Commit-Rc([string]$msg) {
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    git commit -q -m $msg *> $null
    return $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $old
  }
}
function Latest-Outcome {
  $d = "proofs\packets"
  if (-not (Test-Path $d)) { return "NONE" }
  $f = Get-ChildItem $d -Filter "proof_*.json" -File -EA SilentlyContinue | Sort-Object LastWriteTimeUtc,Name -Desc | Select-Object -First 1
  if (-not $f) { return "NONE" }
  try { return (Get-Content $f.FullName -Raw | ConvertFrom-Json).outcome } catch { return "PARSE_ERR" }
}
function Cli-Rc([string[]]$a) {
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pkgDir "tools\cli\protected-paths.ps1") @a *> $null
    return $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $old
  }
}

Write-Host "== Ship zip under test: $ShipZip =="
Write-Host ""
Write-Host "############ HAPPY PATH (must stay green) ############"
New-TestRepo | Out-Null
New-Item -ItemType Directory -Force src | Out-Null; "x" | Out-File -Encoding ascii src\app.txt; git add src\app.txt
Assert "H1 normal commit allowed"            ((Commit-Rc "normal") -eq 0)
Add-Content hooks\pre_commit.sh "x"; git add hooks\pre_commit.sh
Assert "H2 protected no-token BLOCK"         ((Commit-Rc "prot") -eq 1)
git reset -q *> $null
"APPROVE" | Out-File -Encoding ascii approvals\APPROVAL_TOKEN.txt; git add hooks\pre_commit.sh
$rc = Commit-Rc "prot+token"
Assert "H3 protected+token ALLOW"            ($rc -eq 0)
Assert "H3b token consumed"                  (-not (Test-Path approvals\APPROVAL_TOKEN.txt))
"APPROVE" | Out-File -Encoding ascii approvals\APPROVAL_TOKEN.txt; git add -f approvals\APPROVAL_TOKEN.txt
Assert "H4 staged-token BLOCK"               ((Commit-Rc "stagetok") -eq 1)
git reset -q *> $null

Write-Host ""
Write-Host "############ BYPASS REGRESSIONS (must BLOCK/FAIL after fix) ############"

# R1 rename-out of a committed protected file, no token
New-TestRepo | Out-Null
"APPROVE" | Out-File -Encoding ascii approvals\APPROVAL_TOKEN.txt
"secret" | Out-File -Encoding ascii hooks\secret.txt; git add hooks\secret.txt; Commit-Rc "seed" | Out-Null
Remove-Item approvals\APPROVAL_TOKEN.txt -Force -ErrorAction SilentlyContinue
git mv hooks\secret.txt exfil.txt *> $null
$rc = Commit-Rc "moveout"
Assert "R1 rename-out BLOCK"                 ($rc -eq 1)
Assert "R1 proof outcome=BLOCK"              ((Latest-Outcome) -eq "BLOCK")
git reset -q *> $null

# R2 config deleted (never committed), protected file, no token
New-TestRepo | Out-Null
Remove-Item governance\protected_paths.txt -Force
Add-Content hooks\pre_commit.sh "x"; git add hooks\pre_commit.sh
Assert "R2 missing-config BLOCK (fail-closed)" ((Commit-Rc "nocfg") -eq 1)
git reset -q *> $null

# R3 config blanked in WORKING TREE unstaged (config in HEAD), protected file, no token
New-TestRepo | Out-Null
"APPROVE" | Out-File -Encoding ascii approvals\APPROVAL_TOKEN.txt
git add governance\protected_paths.txt; Commit-Rc "seedcfg" | Out-Null
Remove-Item approvals\APPROVAL_TOKEN.txt -Force -ErrorAction SilentlyContinue
"# blanked" | Out-File -Encoding ascii governance\protected_paths.txt
Add-Content hooks\pre_commit.sh "evil"; git add hooks\pre_commit.sh
Assert "R3 TOCTOU-blank BLOCK (rules from HEAD)" ((Commit-Rc "toctou") -eq 1)
git reset -q *> $null

# R7 staged config tamper cannot self-unprotect
New-TestRepo | Out-Null
"# blanked" | Out-File -Encoding ascii governance\protected_paths.txt
git add governance\protected_paths.txt
Assert "R7 staged-config tamper BLOCK"      ((Commit-Rc "stagedcfg") -eq 1)
git reset -q *> $null

# R4 case-variant new file into protected hooks/ (Windows/macOS case-insensitive FS)
New-TestRepo | Out-Null
New-Item -ItemType Directory -Force HOOKS | Out-Null; "evil" | Out-File -Encoding ascii HOOKS\evil.txt; git add HOOKS\evil.txt
$rc = Commit-Rc "casevar"
# Only meaningful on a case-insensitive FS (where HOOKS==hooks physically).
$ci = ((git config --get core.ignorecase) -join '').Trim() -eq 'true'
if ($ci) { Assert "R4 case-variant BLOCK" ($rc -eq 1) } else { Write-Host "  SKIP  R4 (case-sensitive FS)" }
git reset -q *> $null

# R5 verify must FAIL when the runtime hook script is missing
New-TestRepo | Out-Null
Remove-Item hooks\pre_commit.sh -Force
Assert "R5 verify FAIL when runtime missing" ((Cli-Rc @("verify")) -eq 1)

# R6 Flow-B install writes .gitignore into the target repo
$r6 = New-TestRepo
$giOk = $false
if (Test-Path ".gitignore") {
  $gi = Get-Content .gitignore -Raw
  $giOk = ($gi -match "proofs/") -and ($gi -match "APPROVAL_TOKEN\.txt")
}
Assert "R6 installer wrote .gitignore (proofs/ + token)" $giOk

Write-Host ""
Write-Host "############ RESULT: PASS=$($script:pass) FAIL=$($script:fail) ############"
Set-Location $repoRoot
if ($script:fail -gt 0) { Write-Host "FINAL: FAIL"; exit 1 } else { Write-Host "FINAL: PASS"; exit 0 }
