# AI Protected Paths

## GitHub protects branches. Protected Paths governs files.

GitHub branch-protection controls operate at the branch and repository-hosting
layer. AI Protected Paths adds a deterministic local pre-commit checkpoint for
configured file paths on the normal Git commit route.

AI coding tools can modify many files quickly. Instructions can describe which
files should or should not be changed, but instruction-following alone is not
deterministic enforcement. Protected Paths makes selected repository paths
machine-checkable at the normal local pre-commit boundary and requires explicit
one-use approval where configured.

```text
increased modification capability
-> sensitive paths need a distinct boundary
-> instructions alone are not deterministic enforcement
-> configured paths become machine-checkable
-> staged change reaches the normal pre-commit checkpoint
-> unauthorized protected change BLOCKS
-> valid approval permits that governed route
-> local decision evidence is recorded
```

## The distinction

Capability and authority are different questions. An AI tool may know how to
change a sensitive file without having authorization to include that change in
the current commit. Protected Paths makes one narrow authority boundary
deterministic: whether configured paths may cross the normal local commit
checkpoint.

It is stronger than advisory instruction on that tested route. It is not a
security boundary against an actor with unrestricted local control.

## What Protected Paths does

Protected Paths installs a local Git `pre-commit` hook and reads configured
path prefixes from `governance/protected_paths.txt`.

```text
file outside configured protected set
-> Protected Paths itself does not block

configured protected file + no valid one-use approval
-> BLOCK

configured protected file + valid one-use approval
-> ALLOW
-> approval consumed after successful governed use

governed decision
-> local JSON receipt
```

Other Git controls can independently block any commit. An ALLOW result means
only that Protected Paths did not block the governed route.

The current package also fails closed when its protected-path configuration
cannot be resolved, blocks staged approval tokens, and covers the tested
rename/move-out, case-variant, and staged-config-tamper paths.

## What the operator sees

- An unprotected staged path proceeds without a Protected Paths block.
- A configured protected path without approval produces a BLOCK message.
- `authorize --reason` creates a local one-use approval token.
- A successful governed commit consumes that token.
- Hook decisions create local JSON receipts under `proofs/packets/`.

Receipts are local operational evidence. They are not immutable or externally
trusted audit records.

## Try it

Download and verify the exact v1.0.1 ZIP in [`dist/`](dist/), or clone this
repository and use the included launchers directly.

For the shortest Windows walkthrough, follow
[`QUICKSTART.txt`](QUICKSTART.txt). The primary flow is:

```powershell
cd C:\path\to\your-repository
C:\path\to\AI-Protected-Paths\protected-paths.cmd install
C:\path\to\AI-Protected-Paths\protected-paths.cmd verify
```

The shipped defaults protect:

```text
governance/
hooks/
```

Test in a disposable repository. Stage an ordinary file, then a configured
protected file without approval, then authorize and retry:

```powershell
C:\path\to\AI-Protected-Paths\protected-paths.cmd authorize --reason "reviewed protected change"
C:\path\to\AI-Protected-Paths\protected-paths.cmd proofs latest
```

Never stage `approvals/APPROVAL_TOKEN.txt`.

## What has been tested

For the exact reconciled v1.0.1 artifact:

- Windows cleanroom release path: **PASS**
- Bypass regression suite: **13/13 PASS**
- Embedded payload manifest: **15/15 MATCH**
- Runtime payload comparison: **12 expected files, PASS**
- ZIP SHA-256:
  `29A58EAB69D0922C90DE96558607CFB8C605EC7669E4C5BC9C1466F93FC34D58`

See [`docs/VALIDATION.md`](docs/VALIDATION.md) and the reproducible test
scripts under [`tests/`](tests/).

## What has not been tested or proven

Protected Paths does not establish cryptographic security, tamper-proof
enforcement, filesystem access control, remote enforcement, branch or pull
request enforcement, CI/CD enforcement, server-side enforcement,
organization-wide enforcement, malicious-intent detection, universal agent
obedience, or production-enterprise qualification.

It can be bypassed with `git commit --no-verify`. An actor with sufficient
local access can remove or modify local hooks. Each developer or automation
environment must install the hook separately.

Platform qualification for v1.0.1:

| Platform | State |
| --- | --- |
| Windows | Tested and qualified on the current cleanroom path |
| macOS | **PENDING** |
| Linux | **PENDING** |

Historical native macOS evidence applies to v1.0.0 only and does not
automatically qualify v1.0.1. See [`docs/LIMITATIONS.md`](docs/LIMITATIONS.md).

## Release identity

The published in-tree binary is the byte-identical reconciled v1.0.1 ZIP:

[`dist/AI_Protected_Paths_v1.0.1_RECONCILED_29A58EAB_SHIP.zip`](dist/AI_Protected_Paths_v1.0.1_RECONCILED_29A58EAB_SHIP.zip)

Verify it with the adjacent `.sha256` sidecar. Full identity details are in
[`docs/RELEASE_IDENTITY.md`](docs/RELEASE_IDENTITY.md).

## Where this fits

- **Behavior Profiles** make expected agent conduct explicit.
- **Protected Paths** provides a deterministic local checkpoint for configured
  repository paths.
- **Governed Change** evaluates declared proposed changes against broader
  acceptance conditions.

These are related architectural layers. They are not presented here as one
deployed production runtime.

## Rights

AI Protected Paths is proprietary source-available software, not an
OSI-approved open-source project. Personal and internal organizational use and
modification are permitted; redistribution, resale, sublicensing, or offering
it as a standalone third-party product or service requires prior written
permission. See [`LICENSE.txt`](LICENSE.txt) for the controlling terms.
