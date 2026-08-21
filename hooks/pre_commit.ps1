$ErrorActionPreference = "Stop"

# Run a native git command WITHOUT letting its stderr throw a NativeCommandError
# under $ErrorActionPreference='Stop' (a Windows PowerShell 5.1 gotcha). Returns
# the exit code and stdout so callers branch on Code, not on a thrown error.
function Invoke-GitCapture {
  param([Parameter(ValueFromRemainingArguments = $true)][string[]]$GitArgs)
  $old = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $out = & git @GitArgs 2>$null
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
  }
  finally { $ErrorActionPreference = $old }
}

$protectedFile = "governance/protected_paths.txt"
$approvalToken = "approvals/APPROVAL_TOKEN.txt"

$proofDir      = "proofs/packets"

New-Item -ItemType Directory -Force -Path $proofDir | Out-Null

# Repo + identity metadata (best-effort, never fail commit because of metadata)
$repoRoot = $null
$gitUserName = $null
$gitUserEmail = $null

try { $repoRoot = (git rev-parse --show-toplevel).Trim() } catch {}
try { $gitUserName  = (git config user.name) } catch {}
try { $gitUserEmail = (git config user.email) } catch {}

# FIX-4: case-insensitive matching on case-insensitive filesystems (Win/macOS).
$ignorecase = (((git config --get core.ignorecase 2>$null) -join '').Trim() -eq 'true')
function Norm([string]$s) { if ($ignorecase) { return $s.ToLowerInvariant() } else { return $s } }

# FIX-3: --no-renames so a git mv of a protected file exposes the deleted source.
$changed = (Invoke-GitCapture diff --cached --name-only --no-renames).Out -split "`n" |
  ForEach-Object { $_.Trim() } |
  Where-Object { $_ }

if (-not $changed -or $changed.Count -eq 0) { exit 0 }

$approvalTokenStaged = @($changed | Where-Object {
  (Norm ($_.Replace("\","/"))) -eq (Norm $approvalToken)
}).Count -gt 0

# FIX-1/FIX-2: resolve the ruleset from a trusted baseline (staged index -> HEAD
# -> working tree); fail closed when it cannot be resolved at all.
function Resolve-ProtectedRules {
  if (@($changed) -contains $protectedFile) {
    $g = Invoke-GitCapture show ":$protectedFile"
    if ($g.Code -eq 0) { return @{ ok = $true; lines = @($g.Out) } }
  }
  $head = Invoke-GitCapture rev-parse --verify -q "HEAD:$protectedFile"
  if ($head.Code -eq 0) {
    $g = Invoke-GitCapture show "HEAD:$protectedFile"
    if ($g.Code -eq 0) { return @{ ok = $true; lines = @($g.Out) } }
  }
  if (Test-Path $protectedFile) { return @{ ok = $true; lines = @(Get-Content $protectedFile) } }
  return @{ ok = $false; lines = @() }
}

$resolved = Resolve-ProtectedRules
$rulesOk  = [bool]$resolved.ok
$protected = @($resolved.lines |
  ForEach-Object { $_.Trim() } |
  Where-Object { $_ -and -not $_.StartsWith("#") })

function Is-Protected($path) {
  $p = Norm ($path.Replace("\","/"))
  if ($p -eq (Norm $protectedFile)) { return $true }
  foreach ($pat in $protected) {
    $q = Norm ($pat.Replace("\","/"))
    if ($p.StartsWith($q, [System.StringComparison]::Ordinal)) { return $true }
  }
  return $false
}

$hits = @($changed | Where-Object { Is-Protected $_ })

$tsFile = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssfffZ")
$tsIso  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$proof  = Join-Path $proofDir ("proof_{0}.json" -f $tsFile)

$payload = [ordered]@{
  change_id  = "precommit"
  timestamp  = $tsIso
  intent     = "commit"

  repo_root  = $repoRoot
  git_user   = [ordered]@{
    name  = $gitUserName
    email = $gitUserEmail
  }

  hook       = [ordered]@{
    name    = "pre_commit.ps1"
    version = "lite-0.2"
  }

  checks_run     = @("protected_paths_check","approval_token_present_check","config_resolution_check")
  outcome        = ""
  reason         = ""
  artifacts      = @($changed)
  protected_hits = @($hits)
}

$hasProtectedHits = $hits.Count -gt 0
$hasApprovalToken = Test-Path $approvalToken
$consumeApprovalToken = $false

# FIX-1: fail CLOSED when the ruleset cannot be resolved.
if (-not $rulesOk) {
  $payload.outcome = "BLOCK"
  $payload.reason  = "Protected paths config could not be resolved (missing from index, HEAD, and working tree). Run: protected-paths install, or restore governance/protected_paths.txt, then retry."
  ($payload | ConvertTo-Json -Depth 10) | Set-Content -Encoding UTF8 $proof

  Write-Host "BLOCKED: protected paths config could not be resolved."
  Write-Host "Checked staged index, HEAD, and working tree for: $protectedFile"
  Write-Host "Run: protected-paths install (or restore the config), then retry."
  Write-Host ("Local proof receipt written: {0}" -f $proof)
  exit 1
}

if ($approvalTokenStaged) {
  $payload.outcome = "BLOCK"
  $payload.reason  = "Approval token is staged. APPROVAL_TOKEN.txt is local runtime approval and should not be committed. Run: git reset approvals/APPROVAL_TOKEN.txt. Do not run: git add approvals/. Then commit again with only the intended protected files staged."
  ($payload | ConvertTo-Json -Depth 10) | Set-Content -Encoding UTF8 $proof

  Write-Host "Approval token is staged."
  Write-Host "approvals/APPROVAL_TOKEN.txt is local runtime approval and should not be committed."
  Write-Host "Run:"
  Write-Host "  git reset approvals/APPROVAL_TOKEN.txt"
  Write-Host "Do not run: git add approvals/"
  Write-Host "Then commit again with only the intended protected files staged."
  Write-Host ("Local proof receipt written: {0}" -f $proof)
  exit 1
}

if ($hasProtectedHits -and -not $hasApprovalToken) {
  $payload.outcome = "BLOCK"
  $payload.reason  = "Protected commit blocked because approval token is missing. Run: protected-paths authorize --reason `"brief reason`". Do not stage approvals/APPROVAL_TOKEN.txt or run: git add approvals/. Then retry with only intended files staged."
  ($payload | ConvertTo-Json -Depth 10) | Set-Content -Encoding UTF8 $proof

  Write-Host "BLOCKED: protected commit requires approval token."
  Write-Host "Approval token missing: approvals/APPROVAL_TOKEN.txt"
  Write-Host "Run: protected-paths authorize --reason `"brief reason`""
  Write-Host "Do not stage approvals/APPROVAL_TOKEN.txt or run: git add approvals/"
  Write-Host "Then retry the commit with only intended files staged."
  Write-Host ("Local proof receipt written: {0}" -f $proof)
  exit 1
}

$payload.outcome = "ALLOW"
if ($hasProtectedHits) {
  $payload.reason = "Approval token consumed for protected files changed."
  $consumeApprovalToken = $true
}
else {
  $payload.reason = "No protected files changed."
}
($payload | ConvertTo-Json -Depth 10) | Set-Content -Encoding UTF8 $proof

if ($consumeApprovalToken) {
  try {
    Remove-Item -LiteralPath $approvalToken -Force -ErrorAction Stop
    Write-Host "ALLOW: approval token consumed."
    Write-Host ("Local proof receipt written: {0}" -f $proof)
    Write-Host "View latest proof: protected-paths proofs latest"
  }
  catch {
    Write-Host ("ERROR: approved commit blocked because approval token could not be consumed: {0}" -f $_.Exception.Message)
    exit 1
  }
}

exit 0
