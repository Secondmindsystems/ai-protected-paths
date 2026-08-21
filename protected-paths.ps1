param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Args
)

$ErrorActionPreference = "Stop"

$cliCandidates = @(
  (Join-Path $PSScriptRoot "tools\cli\protected-paths.ps1"),
  (Join-Path (Split-Path -Parent $PSScriptRoot) "protected-paths.ps1")
)

$cli = $null
foreach ($candidate in $cliCandidates) {
  if (Test-Path -LiteralPath $candidate) {
    $cli = $candidate
    break
  }
}

if (-not $cli) {
  throw "Missing Protected Paths CLI engine."
}

& $cli @Args
exit $LASTEXITCODE
