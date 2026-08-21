param()

$ErrorActionPreference = "Stop"

if (!(Test-Path ".git")) { throw "Run this from a git repo root (where .git exists)." }

$launcher = Join-Path $PSScriptRoot "protected-paths.ps1"
if (!(Test-Path -LiteralPath $launcher)) { throw "Missing package launcher: $launcher" }

& $launcher install
exit $LASTEXITCODE
