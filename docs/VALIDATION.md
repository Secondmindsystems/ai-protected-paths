# Validation summary

This evidence applies only to the exact reconciled AI Protected Paths v1.0.1
artifact identified below.

| Surface | Result |
| --- | --- |
| Windows cleanroom release route | PASS |
| Bypass regression suite | 13/13 PASS |
| Embedded payload manifest | 15/15 MATCH |
| Runtime payload | 12 expected files; PASS |
| Native macOS v1.0.1 | PENDING |
| Native Linux v1.0.1 | PENDING |

Artifact SHA-256:

```text
29A58EAB69D0922C90DE96558607CFB8C605EC7669E4C5BC9C1466F93FC34D58
```

The Windows cleanroom demonstrates an ordinary path ALLOW, configured
protected path without approval BLOCK, configured protected path with approval
ALLOW, post-success token consumption, and local receipt creation on the
declared route.

The bypass suite covers the packaged happy path and the declared rename-out,
missing-configuration, working-tree configuration tamper, staged-configuration
tamper, case-variant, missing-runtime, and installer-ignore behaviors.

These results do not establish universal enforcement, security, production
reliability, external validation, or qualification on untested platforms.

Run the included PowerShell validations against the in-tree ZIP:

```powershell
.\tests\run_release_tests.ps1 -ShipZip .\dist\AI_Protected_Paths_v1.0.1_RECONCILED_29A58EAB_SHIP.zip
.\tests\run_bypass_regression_tests.ps1 -ShipZip .\dist\AI_Protected_Paths_v1.0.1_RECONCILED_29A58EAB_SHIP.zip
```
