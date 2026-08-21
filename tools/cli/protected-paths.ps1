param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Args
)

$ErrorActionPreference = "Stop"

function Write-PPHelp {
  Write-Host "Protected Paths CLI v0.1"
  Write-Host ""
  Write-Host "Protected Paths is a local repo governance tool for normal Git commit workflows."
  Write-Host ""
  Write-Host "Commands:"
  Write-Host "  protected-paths help"
  Write-Host "      Show this help."
  Write-Host "  protected-paths install"
  Write-Host "      Install Protected Paths runtime files into the current target Git repo."
  Write-Host "  protected-paths status"
  Write-Host "      Inspect local repo setup without changing files."
  Write-Host "  protected-paths doctor"
  Write-Host "      Show a read-only diagnostic report for the current target repo."
  Write-Host "  protected-paths verify"
  Write-Host "      Run non-destructive install/config state checks."
  Write-Host "  protected-paths protect list"
  Write-Host "      List active protected path prefixes from governance/protected_paths.txt."
  Write-Host "  protected-paths protect add <path>"
  Write-Host "      Add an active protected path prefix to governance/protected_paths.txt."
  Write-Host "  protected-paths protect remove <path>"
  Write-Host "      Remove an exact active protected path prefix from governance/protected_paths.txt."
  Write-Host "  protected-paths authorize [--reason <text>]"
  Write-Host "      Create approvals/APPROVAL_TOKEN.txt as a local one-use approval token."
  Write-Host "  protected-paths proofs latest"
  Write-Host "      Summarize the latest local proof packet without schema validation."
  Write-Host ""
  Write-Host "Notes:"
  Write-Host "  The CLI is a wrapper/control surface. The Git hook remains the enforcement authority."
  Write-Host "  The approval token is local. Do not stage it."
}

function Get-GitRoot {
  try {
    $root = (& git rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -eq 0 -and $root) {
      return ($root | Select-Object -First 1).Trim()
    }
  }
  catch {}
  return $null
}

function Get-FullPath {
  param([string]$Path)

  return ([System.IO.Path]::GetFullPath($Path)).TrimEnd([char[]]@("\", "/"))
}

function Test-PackageAssetRoot {
  param([string]$Path)

  if (-not $Path -or !(Test-Path -LiteralPath $Path -PathType Container)) {
    return $false
  }

  $required = @(
    "hooks\pre-commit",
    "hooks\pre_commit.ps1",
    "hooks\pre_commit.sh",
    "governance\protected_paths.txt",
    "approvals\APPROVAL_TOKEN_TEMPLATE.txt"
  )

  foreach ($relativePath in $required) {
    if (!(Test-Path -LiteralPath (Join-Path $Path $relativePath))) {
      return $false
    }
  }

  return $true
}

function Get-PackageAssetRootCandidates {
  $candidates = @()
  $scriptDir = $PSScriptRoot

  if ($scriptDir) {
    $candidates += $scriptDir

    $scriptParent = Split-Path -Parent $scriptDir
    if ($scriptParent) {
      $packageRoot = Split-Path -Parent $scriptParent
      if ($packageRoot) {
        $candidates += $packageRoot
        $candidates += (Join-Path $packageRoot "ship")
      }
    }
  }

  $seen = @{}
  return @($candidates |
    Where-Object { $_ } |
    ForEach-Object { Get-FullPath $_ } |
    Where-Object {
      if ($seen.ContainsKey($_)) {
        $false
      }
      else {
        $seen[$_] = $true
        $true
      }
    })
}

function Get-PackageAssetRoot {
  foreach ($candidate in Get-PackageAssetRootCandidates) {
    if (Test-PackageAssetRoot -Path $candidate) {
      return $candidate
    }
  }

  return $null
}

function Normalize-ProtectedPathEntry {
  param([string]$Path)

  if ($null -eq $Path) {
    return ""
  }

  $normalized = $Path.Trim().Replace("\", "/")
  while ($normalized.StartsWith("./")) {
    $normalized = $normalized.Substring(2)
  }
  return $normalized
}

function Get-ActiveProtectedPaths {
  param([string]$ProtectedFile)

  if (!(Test-Path -LiteralPath $ProtectedFile)) {
    return @()
  }

  return @(
    Get-Content -LiteralPath $ProtectedFile |
      ForEach-Object { $_.Trim() } |
      Where-Object { $_ -and -not $_.StartsWith("#") }
  )
}

function Read-TextLinesPreserveEmpty {
  param([string]$Path)

  if (!(Test-Path -LiteralPath $Path)) {
    return @()
  }

  return @([System.IO.File]::ReadAllLines($Path))
}

function Write-TextLinesUtf8NoBom {
  param(
    [string]$Path,
    [string[]]$Lines
  )

  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, (($Lines -join "`n") + "`n"), $utf8NoBom)
}

function Ensure-GitignoreEntries {
  param(
    [string]$Path,
    [string[]]$Entries
  )

  $existing = @()
  if (Test-Path -LiteralPath $Path) {
    $existing = Read-TextLinesPreserveEmpty -Path $Path
  }

  $missing = @($Entries | Where-Object { $existing -notcontains $_ })
  if ($missing.Count -eq 0) {
    Write-Host "Preserved .gitignore entries for local proof/token artifacts."
    return
  }

  Write-TextLinesUtf8NoBom -Path $Path -Lines @($existing + $missing)
  Write-Host ("Updated .gitignore: {0}" -f ($missing -join ", "))
}

function Copy-IfMissing {
  param(
    [string]$Source,
    [string]$Destination,
    [string]$Label
  )

  if (Test-Path -LiteralPath $Destination) {
    Write-Host ("Preserved existing {0}: {1}" -f $Label, $Destination)
    return $false
  }

  $parent = Split-Path -Parent $Destination
  if (!(Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }

  Copy-Item -LiteralPath $Source -Destination $Destination -Force
  Write-Host ("Installed {0}: {1}" -f $Label, $Destination)
  return $true
}

function Copy-RuntimeFile {
  param(
    [string]$Source,
    [string]$Destination,
    [string]$Label
  )

  if ((Test-Path -LiteralPath $Source) -and (Test-Path -LiteralPath $Destination)) {
    if ((Get-FullPath $Source) -ieq (Get-FullPath $Destination)) {
      Write-Host ("Runtime {0} already in place: {1}" -f $Label, $Destination)
      return
    }
  }

  $parent = Split-Path -Parent $Destination
  if (!(Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
  }

  Copy-Item -LiteralPath $Source -Destination $Destination -Force
  Write-Host ("Installed {0}: {1}" -f $Label, $Destination)
}

function Install-ProtectedPaths {
  $repoRoot = Get-GitRoot
  if (-not $repoRoot) {
    throw "Not inside a Git repo. Run install from the target repository."
  }

  $assetRoot = Get-PackageAssetRoot
  if (-not $assetRoot) {
    $searched = (Get-PackageAssetRootCandidates | ForEach-Object { "  - {0}" -f $_ }) -join "`n"
    throw "Missing Protected Paths package assets. Searched:`n$searched"
  }

  $assetHookShim = Join-Path $assetRoot "hooks\pre-commit"
  $assetHookPs = Join-Path $assetRoot "hooks\pre_commit.ps1"
  $assetHookSh = Join-Path $assetRoot "hooks\pre_commit.sh"
  $assetProtectedPaths = Join-Path $assetRoot "governance\protected_paths.txt"
  $assetTokenTemplate = Join-Path $assetRoot "approvals\APPROVAL_TOKEN_TEMPLATE.txt"

  foreach ($required in @($assetHookShim, $assetHookPs, $assetHookSh, $assetProtectedPaths, $assetTokenTemplate)) {
    if (!(Test-Path -LiteralPath $required)) {
      throw "Missing required package asset: $required"
    }
  }

  Write-Host "Protected Paths install"
  Write-Host ("Target repo root: {0}" -f $repoRoot)
  Write-Host ("Package asset root: {0}" -f $assetRoot)

  Copy-RuntimeFile -Source $assetHookShim -Destination (Join-Path $repoRoot "hooks\pre-commit") -Label "hook shim"
  Copy-RuntimeFile -Source $assetHookPs -Destination (Join-Path $repoRoot "hooks\pre_commit.ps1") -Label "PowerShell hook runtime"
  Copy-RuntimeFile -Source $assetHookSh -Destination (Join-Path $repoRoot "hooks\pre_commit.sh") -Label "shell hook runtime"

  Copy-IfMissing -Source $assetProtectedPaths -Destination (Join-Path $repoRoot "governance\protected_paths.txt") -Label "protected path config"
  Copy-IfMissing -Source $assetTokenTemplate -Destination (Join-Path $repoRoot "approvals\APPROVAL_TOKEN_TEMPLATE.txt") -Label "approval token template"

  $gitHookDir = Join-Path $repoRoot ".git\hooks"
  if (!(Test-Path -LiteralPath $gitHookDir)) {
    New-Item -ItemType Directory -Force -Path $gitHookDir | Out-Null
  }

  $targetHook = Join-Path $gitHookDir "pre-commit"
  Copy-Item -LiteralPath (Join-Path $repoRoot "hooks\pre-commit") -Destination $targetHook -Force
  Ensure-GitignoreEntries -Path (Join-Path $repoRoot ".gitignore") -Entries @(
    "proofs/",
    "approvals/APPROVAL_TOKEN.txt"
  )
  Write-Host ("Installed Git pre-commit hook: {0}" -f $targetHook)
  Write-Host ("Hook installed after execution: {0}" -f (Test-Path -LiteralPath $targetHook))
  Write-Host "Commit behavior: NOT VALIDATED by install"
}

function Write-PPStatus {
  $repoRoot = Get-GitRoot
  $insideGitRepo = [bool]$repoRoot

  Write-Host "Protected Paths status"
  Write-Host ("Inside Git repo: {0}" -f $insideGitRepo)

  if (-not $repoRoot) {
    Write-Host "Repo root: NOT FOUND"
    Write-Host "Hook installed: UNKNOWN"
    Write-Host "Config file: UNKNOWN"
    Write-Host "Approval token: UNKNOWN"
    Write-Host "Proof packets directory: UNKNOWN"
    Write-Host "Commit behavior: NOT VALIDATED by status"
    return
  }

  $current = (Get-Location).Path
  $atRoot = ([System.IO.Path]::GetFullPath($current).TrimEnd("\", "/") -ieq [System.IO.Path]::GetFullPath($repoRoot).TrimEnd("\", "/"))
  $hookPath = Join-Path $repoRoot ".git\hooks\pre-commit"
  $protectedFile = Join-Path $repoRoot "governance\protected_paths.txt"
  $approvalToken = Join-Path $repoRoot "approvals\APPROVAL_TOKEN.txt"
  $proofDir = Join-Path $repoRoot "proofs\packets"
  $entries = Get-ActiveProtectedPaths -ProtectedFile $protectedFile

  Write-Host ("Repo root: {0}" -f $repoRoot)
  Write-Host ("Current directory is repo root: {0}" -f $atRoot)
  Write-Host ("Hook installed (.git/hooks/pre-commit): {0}" -f (Test-Path -LiteralPath $hookPath))
  Write-Host ("Config file (governance/protected_paths.txt): {0}" -f (Test-Path -LiteralPath $protectedFile))
  Write-Host ("Active protected entries: {0}" -f $entries.Count)
  Write-Host ("Approval token exists (approvals/APPROVAL_TOKEN.txt): {0}" -f (Test-Path -LiteralPath $approvalToken))
  Write-Host ("Proof packets directory (proofs/packets): {0}" -f (Test-Path -LiteralPath $proofDir))
  Write-Host "Commit behavior: NOT VALIDATED by status"
}

function Test-RelativePathStaged {
  param(
    [string]$RepoRoot,
    [string]$RelativePath
  )

  if (-not $RepoRoot) {
    return $null
  }

  Push-Location $RepoRoot
  try {
    $staged = @(& git diff --cached --name-only 2>$null)
    if ($LASTEXITCODE -ne 0) {
      return $null
    }
  }
  catch {
    return $null
  }
  finally {
    Pop-Location
  }

  $target = Normalize-ProtectedPathEntry -Path $RelativePath
  return (@($staged |
    ForEach-Object { Normalize-ProtectedPathEntry -Path $_ } |
    Where-Object { $_ -eq $target }).Count -gt 0)
}

function Get-ProofPacketFiles {
  param([string]$RepoRoot)

  $proofDir = Join-Path $RepoRoot "proofs\packets"
  if (!(Test-Path -LiteralPath $proofDir)) {
    return @()
  }

  $preferred = @(Get-ChildItem -LiteralPath $proofDir -Filter "proof_*.json" -ErrorAction SilentlyContinue |
    Where-Object { -not $_.PSIsContainer })
  if ($preferred.Count -gt 0) {
    return @($preferred | Sort-Object -Property LastWriteTimeUtc, Name -Descending)
  }

  return @(Get-ChildItem -LiteralPath $proofDir -Filter "*.json" -ErrorAction SilentlyContinue |
    Where-Object { -not $_.PSIsContainer } |
    Sort-Object -Property LastWriteTimeUtc, Name -Descending)
}

function Get-JsonField {
  param(
    [object]$Object,
    [string[]]$Names
  )

  if ($null -eq $Object) {
    return $null
  }

  foreach ($name in $Names) {
    foreach ($property in $Object.PSObject.Properties) {
      if ($property.Name -ieq $name) {
        return $property.Value
      }
    }
  }

  return $null
}

function Format-ProofValue {
  param([object]$Value)

  if ($null -eq $Value) {
    return $null
  }

  if ($Value -is [System.Array]) {
    if ($Value.Count -eq 0) {
      return "[]"
    }

    return (($Value | ForEach-Object { Format-ProofValue -Value $_ }) -join ", ")
  }

  if ($Value -is [System.Management.Automation.PSCustomObject]) {
    return ($Value | ConvertTo-Json -Compress -Depth 8)
  }

  return [string]$Value
}

function Write-OptionalProofField {
  param(
    [string]$Label,
    [object]$Value
  )

  $formatted = Format-ProofValue -Value $Value
  if ($null -ne $formatted -and $formatted -ne "") {
    Write-Host ("{0}: {1}" -f $Label, $formatted)
    return $true
  }

  return $false
}

function Write-PPDoctor {
  $repoRoot = Get-GitRoot
  $insideGitRepo = [bool]$repoRoot

  Write-Host "Protected Paths doctor"
  Write-Host ""
  Write-Host "[Git target context]"
  Write-Host ("Inside Git repo: {0}" -f $insideGitRepo)

  if (-not $repoRoot) {
    Write-Host "Target repo root: NOT FOUND"
    Write-Host ""
    Write-Host "[Caveats]"
    Write-Host "Doctor is read-only and does not validate commit behavior."
    Write-Host "Protected Paths remains local Git pre-commit governance."
    return
  }

  $protectedFile = Join-Path $repoRoot "governance\protected_paths.txt"
  $hookShim = Join-Path $repoRoot "hooks\pre-commit"
  $hookPs = Join-Path $repoRoot "hooks\pre_commit.ps1"
  $hookSh = Join-Path $repoRoot "hooks\pre_commit.sh"
  $gitHook = Join-Path $repoRoot ".git\hooks\pre-commit"
  $approvalToken = Join-Path $repoRoot "approvals\APPROVAL_TOKEN.txt"
  $proofDir = Join-Path $repoRoot "proofs\packets"
  $entries = Get-ActiveProtectedPaths -ProtectedFile $protectedFile
  $tokenStaged = Test-RelativePathStaged -RepoRoot $repoRoot -RelativePath "approvals/APPROVAL_TOKEN.txt"
  $proofPackets = Get-ProofPacketFiles -RepoRoot $repoRoot

  Write-Host ("Target repo root: {0}" -f $repoRoot)
  Write-Host ""
  Write-Host "[Runtime/config assets]"
  Write-Host ("Config exists (governance/protected_paths.txt): {0}" -f (Test-Path -LiteralPath $protectedFile))
  Write-Host ("Active protected entries: {0}" -f $entries.Count)
  Write-Host ("Runtime hook shim exists (hooks/pre-commit): {0}" -f (Test-Path -LiteralPath $hookShim))
  Write-Host ("PowerShell hook runtime exists (hooks/pre_commit.ps1): {0}" -f (Test-Path -LiteralPath $hookPs))
  Write-Host ("Shell hook runtime exists (hooks/pre_commit.sh): {0}" -f (Test-Path -LiteralPath $hookSh))
  Write-Host ("Installed Git pre-commit hook exists (.git/hooks/pre-commit): {0}" -f (Test-Path -LiteralPath $gitHook))
  Write-Host ""
  Write-Host "[Approval state]"
  Write-Host ("Approval token exists (approvals/APPROVAL_TOKEN.txt): {0}" -f (Test-Path -LiteralPath $approvalToken))
  Write-Host ("Approval token staged: {0}" -f $tokenStaged)
  if ($tokenStaged -eq $true) {
    Write-Host "WARNING: staged approval tokens are blocked by current Protected Paths hook semantics."
  }
  Write-Host ""
  Write-Host "[Proof state]"
  Write-Host ("Proof packet directory exists (proofs/packets): {0}" -f (Test-Path -LiteralPath $proofDir))
  Write-Host ("Observed proof JSON packets: {0}" -f $proofPackets.Count)
  Write-Host ""
  Write-Host "[Caveats]"
  Write-Host "Hook presence does not prove commit-block or commit-allow behavior."
  Write-Host "verify is non-destructive state inspection, not a full commit smoke test."
  Write-Host "Proof packet display is based on observed JSON files, not schema validation."
  Write-Host "Protected Paths is local Git pre-commit governance; git commit --no-verify can bypass local hooks."
}

function Invoke-PPVerify {
  $repoRoot = Get-GitRoot
  $fail = @()
  $warn = @()
  $info = @()

  Write-Host "Protected Paths verify"

  if (-not $repoRoot) {
    $fail += "Target Git repo was not detected."
    Write-Host "Target Git repo detected: False"
    Write-Host "Target repo root: NOT FOUND"
  }
  else {
    $protectedFile = Join-Path $repoRoot "governance\protected_paths.txt"
    $gitHook = Join-Path $repoRoot ".git\hooks\pre-commit"
    $runtimeHookShim = Join-Path $repoRoot "hooks\pre-commit"
    $runtimeHookSh = Join-Path $repoRoot "hooks\pre_commit.sh"
    $approvalToken = Join-Path $repoRoot "approvals\APPROVAL_TOKEN.txt"
    $proofDir = Join-Path $repoRoot "proofs\packets"
    $entries = Get-ActiveProtectedPaths -ProtectedFile $protectedFile
    $tokenStaged = Test-RelativePathStaged -RepoRoot $repoRoot -RelativePath "approvals/APPROVAL_TOKEN.txt"
    $proofPackets = Get-ProofPacketFiles -RepoRoot $repoRoot

    Write-Host "Target Git repo detected: True"
    Write-Host ("Target repo root: {0}" -f $repoRoot)

    if (!(Test-Path -LiteralPath $gitHook)) {
      $fail += "Missing installed Git hook: .git/hooks/pre-commit"
    }

    if (!(Test-Path -LiteralPath $runtimeHookShim)) {
      $fail += "Missing hook runtime shim: hooks/pre-commit"
    }

    if (!(Test-Path -LiteralPath $runtimeHookSh)) {
      $fail += "Missing hook runtime: hooks/pre_commit.sh (the installed .git hook shim requires it)."
    }

    if (!(Test-Path -LiteralPath $protectedFile)) {
      $fail += "Missing config: governance/protected_paths.txt"
    }
    elseif ($entries.Count -eq 0) {
      $warn += "Config exists but has zero active protected path entries."
    }

    if ((Test-Path -LiteralPath $approvalToken) -and $tokenStaged -eq $true) {
      $fail += "Approval token is staged; current hook semantics block staged approval tokens."
    }

    if (!(Test-Path -LiteralPath $proofDir)) {
      $info += "Proof packet directory does not exist yet: proofs/packets"
    }
    elseif ($proofPackets.Count -eq 0) {
      $info += "Proof packet directory exists but no proof JSON packets were found."
    }
    else {
      $info += ("Observed proof JSON packets: {0}" -f $proofPackets.Count)
    }

    Write-Host ("Installed Git hook (.git/hooks/pre-commit): {0}" -f (Test-Path -LiteralPath $gitHook))
    Write-Host ("Config exists (governance/protected_paths.txt): {0}" -f (Test-Path -LiteralPath $protectedFile))
    Write-Host ("Active protected entries: {0}" -f $entries.Count)
    Write-Host ("Approval token staged: {0}" -f $tokenStaged)
    Write-Host ("Proof packet directory exists (proofs/packets): {0}" -f (Test-Path -LiteralPath $proofDir))
  }

  $result = "PASS"
  if ($fail.Count -gt 0) {
    $result = "FAIL"
  }
  elseif ($warn.Count -gt 0) {
    $result = "WARN"
  }

  Write-Host ("VERIFY RESULT: {0}" -f $result)
  foreach ($item in $fail) {
    Write-Host ("FAIL: {0}" -f $item)
  }
  foreach ($item in $warn) {
    Write-Host ("WARN: {0}" -f $item)
  }
  foreach ($item in $info) {
    Write-Host ("INFO: {0}" -f $item)
  }
  Write-Host "Commit behavior: NOT VALIDATED by verify"

  if ($result -eq "FAIL") {
    exit 1
  }

  exit 0
}

function Write-LatestProofSummary {
  $repoRoot = Get-GitRoot

  Write-Host "Protected Paths proofs latest"

  if (-not $repoRoot) {
    Write-Host "Not inside a Git repo. Cannot locate proofs/packets."
    return
  }

  $proofDir = Join-Path $repoRoot "proofs\packets"
  if (!(Test-Path -LiteralPath $proofDir)) {
    Write-Host "No proof packet directory found: proofs/packets"
    return
  }

  $preferred = @(Get-ChildItem -LiteralPath $proofDir -Filter "proof_*.json" -ErrorAction SilentlyContinue |
    Where-Object { -not $_.PSIsContainer } |
    Sort-Object -Property LastWriteTimeUtc, Name -Descending)
  $usingFallback = $false
  $packets = $preferred

  if ($packets.Count -eq 0) {
    $usingFallback = $true
    $packets = @(Get-ChildItem -LiteralPath $proofDir -Filter "*.json" -ErrorAction SilentlyContinue |
      Where-Object { -not $_.PSIsContainer } |
      Sort-Object -Property LastWriteTimeUtc, Name -Descending)
  }

  if ($packets.Count -eq 0) {
    Write-Host "No proof packets found in proofs/packets."
    return
  }

  $latest = $packets[0]
  Write-Host ("Latest proof packet: {0}" -f $latest.FullName)
  if ($usingFallback) {
    Write-Host "Naming note: no proof_*.json file was found; using the latest JSON file in proofs/packets."
  }

  try {
    $packet = Get-Content -Raw -LiteralPath $latest.FullName | ConvertFrom-Json
  }
  catch {
    Write-Host "Latest proof packet exists but could not be safely summarized."
    Write-Host "No repair or schema validation was attempted."
    return
  }

  Write-Host "Summary (schema validation not performed):"
  $shown = $false
  $shown = (Write-OptionalProofField -Label "timestamp" -Value (Get-JsonField -Object $packet -Names @("timestamp", "created_utc", "createdUtc"))) -or $shown
  $shown = (Write-OptionalProofField -Label "outcome" -Value (Get-JsonField -Object $packet -Names @("outcome"))) -or $shown
  $shown = (Write-OptionalProofField -Label "reason" -Value (Get-JsonField -Object $packet -Names @("reason"))) -or $shown
  $shown = (Write-OptionalProofField -Label "artifacts" -Value (Get-JsonField -Object $packet -Names @("artifacts"))) -or $shown
  $shown = (Write-OptionalProofField -Label "protected_hits" -Value (Get-JsonField -Object $packet -Names @("protected_hits", "protectedHits"))) -or $shown

  $hook = Get-JsonField -Object $packet -Names @("hook")
  $hookName = Get-JsonField -Object $packet -Names @("hook_name", "hookName")
  $hookVersion = Get-JsonField -Object $packet -Names @("hook_version", "hookVersion")
  if ($null -ne $hook) {
    $hookNameFromObject = Get-JsonField -Object $hook -Names @("name")
    $hookVersionFromObject = Get-JsonField -Object $hook -Names @("version")
    if ($null -ne $hookNameFromObject) {
      $hookName = $hookNameFromObject
    }
    if ($null -ne $hookVersionFromObject) {
      $hookVersion = $hookVersionFromObject
    }
  }

  $shown = (Write-OptionalProofField -Label "hook_name" -Value $hookName) -or $shown
  $shown = (Write-OptionalProofField -Label "hook_version" -Value $hookVersion) -or $shown

  if (-not $shown) {
    Write-Host "No known summary fields were present."
  }
}

function Write-ProtectedPathList {
  $repoRoot = Get-GitRoot
  if (-not $repoRoot) {
    Write-Host "Not inside a Git repo. Cannot locate governance/protected_paths.txt."
    return
  }

  $protectedFile = Join-Path $repoRoot "governance\protected_paths.txt"
  if (!(Test-Path -LiteralPath $protectedFile)) {
    Write-Host "No protected path config found: governance/protected_paths.txt"
    return
  }

  $entries = Get-ActiveProtectedPaths -ProtectedFile $protectedFile
  if ($entries.Count -eq 0) {
    Write-Host "No active protected path entries."
    return
  }

  Write-Host "Active protected path prefixes:"
  foreach ($entry in $entries) {
    Write-Host ("  {0}" -f $entry)
  }
}

function Get-ProtectedPathConfigPath {
  $repoRoot = Get-GitRoot
  if (-not $repoRoot) {
    throw "Not inside a Git repo. Cannot locate governance/protected_paths.txt."
  }

  return (Join-Path $repoRoot "governance\protected_paths.txt")
}

function Add-ProtectedPathEntry {
  param([string[]]$CommandArgs)

  if ($CommandArgs.Count -ne 1) {
    throw "protect add requires exactly one path argument."
  }

  $entry = Normalize-ProtectedPathEntry -Path $CommandArgs[0]
  if ([string]::IsNullOrWhiteSpace($entry)) {
    throw "protect add requires a non-empty path argument."
  }

  $protectedFile = Get-ProtectedPathConfigPath
  if (!(Test-Path -LiteralPath $protectedFile)) {
    Write-Host "No protected path config found: governance/protected_paths.txt"
    Write-Host "Run protected-paths install first, or create the config before adding entries."
    return
  }

  $lines = Read-TextLinesPreserveEmpty -Path $protectedFile
  $active = @($lines |
    ForEach-Object { Normalize-ProtectedPathEntry -Path $_ } |
    Where-Object { $_ -and -not $_.StartsWith("#") })

  if (@($active | Where-Object { $_ -eq $entry }).Count -gt 0) {
    Write-Host ("Protected path already present: {0}" -f $entry)
    return
  }

  $updated = @($lines) + $entry
  Write-TextLinesUtf8NoBom -Path $protectedFile -Lines $updated
  Write-Host ("Added protected path: {0}" -f $entry)
  Write-Host "No files were staged or committed."
}

function Remove-ProtectedPathEntry {
  param([string[]]$CommandArgs)

  if ($CommandArgs.Count -ne 1) {
    throw "protect remove requires exactly one path argument."
  }

  $entry = Normalize-ProtectedPathEntry -Path $CommandArgs[0]
  if ([string]::IsNullOrWhiteSpace($entry)) {
    throw "protect remove requires a non-empty path argument."
  }

  $protectedFile = Get-ProtectedPathConfigPath
  if (!(Test-Path -LiteralPath $protectedFile)) {
    Write-Host "No protected path config found: governance/protected_paths.txt"
    return
  }

  $lines = Read-TextLinesPreserveEmpty -Path $protectedFile
  $removedCount = 0
  $updated = @()

  foreach ($line in $lines) {
    $trimmed = $line.Trim()
    $isActive = $trimmed -and -not $trimmed.StartsWith("#")
    $normalized = Normalize-ProtectedPathEntry -Path $line

    if ($isActive -and $normalized -eq $entry) {
      $removedCount += 1
      continue
    }

    $updated += $line
  }

  if ($removedCount -eq 0) {
    Write-Host ("No matching active protected path found: {0}" -f $entry)
    return
  }

  Write-TextLinesUtf8NoBom -Path $protectedFile -Lines $updated
  Write-Host ("Removed protected path: {0}" -f $entry)
  Write-Host ("Active entries removed: {0}" -f $removedCount)
  Write-Host "No files were staged or committed."
}

function Get-ReasonValue {
  param([string[]]$CommandArgs)

  for ($i = 0; $i -lt $CommandArgs.Count; $i++) {
    if ($CommandArgs[$i] -eq "--reason") {
      if ($i + 1 -ge $CommandArgs.Count -or [string]::IsNullOrWhiteSpace($CommandArgs[$i + 1])) {
        throw "--reason requires a value."
      }
      return $CommandArgs[$i + 1]
    }
  }

  return $null
}

function New-ApprovalToken {
  param([string[]]$CommandArgs)

  $repoRoot = Get-GitRoot
  if (-not $repoRoot) {
    throw "Not inside a Git repo. Run this from the repository where Protected Paths is installed."
  }

  $approvalDir = Join-Path $repoRoot "approvals"
  $approvalToken = Join-Path $approvalDir "APPROVAL_TOKEN.txt"

  if (Test-Path -LiteralPath $approvalToken) {
    Write-Host "Approval token already exists: approvals/APPROVAL_TOKEN.txt"
    Write-Host "Refusing to overwrite. Remove it after you are done with the pending approval."
    return
  }

  if (!(Test-Path -LiteralPath $approvalDir)) {
    New-Item -ItemType Directory -Force -Path $approvalDir | Out-Null
  }

  $reason = Get-ReasonValue -CommandArgs $CommandArgs
  $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  $lines = @(
    "APPROVE",
    "created_utc: $timestamp",
    "note: local one-use approval token for Protected Paths",
    "hook_semantics: presence only; current hook does not parse or validate these contents"
  )

  if ($reason) {
    $lines += "reason: $reason"
  }

  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($approvalToken, (($lines -join "`n") + "`n"), $utf8NoBom)

  Write-Host "Created local approval token: approvals/APPROVAL_TOKEN.txt"
  Write-Host "Do not stage this file."
  Write-Host "Do not run: git add approvals/"
  Write-Host "Stage only the intended protected files."
  Write-Host "APPROVAL_TOKEN_TEMPLATE.txt is reference material, not the approval token."
  Write-Host "The current hook consumes it after an approved protected commit."
  Write-Host "This is not cryptographic or commit-bound authorization."
  if ($reason) {
    Write-Host "Reason was written as a human-readable note only; the hook does not parse it."
  }
}

if (-not $Args -or $Args.Count -eq 0) {
  Write-PPHelp
  exit 0
}

$command = $Args[0].ToLowerInvariant()
$rest = @()
if ($Args.Count -gt 1) {
  $rest = @($Args[1..($Args.Count - 1)])
}

switch ($command) {
  "help" {
    Write-PPHelp
  }
  "install" {
    Install-ProtectedPaths
  }
  "status" {
    Write-PPStatus
  }
  "doctor" {
    Write-PPDoctor
  }
  "verify" {
    Invoke-PPVerify
  }
  "protect" {
    if ($rest.Count -eq 1 -and $rest[0].ToLowerInvariant() -eq "list") {
      Write-ProtectedPathList
    }
    elseif ($rest.Count -ge 1 -and $rest[0].ToLowerInvariant() -eq "add") {
      $protectArgs = @()
      if ($rest.Count -gt 1) {
        $protectArgs = @($rest[1..($rest.Count - 1)])
      }
      Add-ProtectedPathEntry -CommandArgs $protectArgs
    }
    elseif ($rest.Count -ge 1 -and $rest[0].ToLowerInvariant() -eq "remove") {
      $protectArgs = @()
      if ($rest.Count -gt 1) {
        $protectArgs = @($rest[1..($rest.Count - 1)])
      }
      Remove-ProtectedPathEntry -CommandArgs $protectArgs
    }
    else {
      throw "Unknown protect command. Use: protected-paths protect list | add <path> | remove <path>"
    }
  }
  "authorize" {
    New-ApprovalToken -CommandArgs $rest
  }
  "proofs" {
    if ($rest.Count -eq 1 -and $rest[0].ToLowerInvariant() -eq "latest") {
      Write-LatestProofSummary
    }
    else {
      throw "Unknown proofs command. Use: protected-paths proofs latest"
    }
  }
  default {
    throw "Unknown command '$command'. Use: protected-paths help"
  }
}
