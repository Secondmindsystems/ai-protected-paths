# AI Protected Paths

## Require approval before selected files pass a local Git commit

AI coding tools can change a lot of files quickly. Some files—repository governance, hooks, deployment configuration, or anything else you choose—may deserve an extra checkpoint before they are committed.

AI Protected Paths adds that checkpoint to your normal local Git workflow.

You choose which path prefixes to protect. When a staged change touches one of them, the `pre-commit` hook blocks the commit until a valid one-use approval is present.

**[Start with the Windows quickstart](QUICKSTART.txt)** · [Inspect the validation results](docs/VALIDATION.md)

## How it works

Protected Paths reads the configured prefixes in `governance/protected_paths.txt` when a commit reaches the local pre-commit hook.

An ordinary staged path proceeds without a Protected Paths block.

A protected path without approval is blocked.

A protected path with a valid one-use approval can proceed through Protected Paths. After a successful governed commit, that approval is consumed.

Each governed decision produces a local JSON receipt under `proofs/packets/`.

Other Git controls still make their own decisions. Passing Protected Paths does not guarantee that the commit itself will succeed.

The package also fails closed when its configuration cannot be resolved, blocks staged approval tokens, and covers tested rename/move-out, case-variant, and staged-configuration-tamper cases.

## Try it

Use the exact v1.0.1 ZIP included in [`dist/`](dist/), or clone the repository and use the included launchers directly.

For the shortest Windows walkthrough, follow [`QUICKSTART.txt`](QUICKSTART.txt).

The primary setup is:

```powershell
cd C:\path\to\your-repository
C:\path\to\AI-Protected-Paths\protected-paths.cmd install
C:\path\to\AI-Protected-Paths\protected-paths.cmd verify
```

The default configuration protects:

```text
governance/
hooks/
```

Try it in a disposable repository.

Stage an ordinary file and commit it. Then stage a configured protected file and try again without approval. Protected Paths should block the second commit.

When you're ready to approve the protected change:

```powershell
C:\path\to\AI-Protected-Paths\protected-paths.cmd authorize --reason "reviewed protected change"
C:\path\to\AI-Protected-Paths\protected-paths.cmd proofs latest
```

The approval is for one governed use. After a successful governed commit, it is consumed.

Never stage `approvals/APPROVAL_TOKEN.txt`.

## What has been tested

For the exact reconciled v1.0.1 artifact:

- Windows cleanroom release path: **PASS**
- Bypass regression suite: **13/13 PASS**
- Embedded payload manifest: **15/15 MATCH**
- Runtime payload comparison: **12 expected files, PASS**
- ZIP SHA-256: `29A58EAB69D0922C90DE96558607CFB8C605EC7669E4C5BC9C1466F93FC34D58`

See [`docs/VALIDATION.md`](docs/VALIDATION.md) and the reproducible test scripts under [`tests/`](tests/).

## Before you use it

Protected Paths is a **local Git commit checkpoint**.

Each developer or automation environment must install the hook separately. Someone with sufficient local access can remove or modify it or bypass it with `git commit --no-verify`.

The receipts are local files and can also be changed by someone with access to them.

Platform qualification for v1.0.1:

| Platform | State |
| --- | --- |
| Windows | Tested and qualified on the current cleanroom path |
| macOS | **PENDING** |
| Linux | **PENDING** |

Historical native macOS testing applies to v1.0.0. See [operating limitations](docs/LIMITATIONS.md) for the release-specific details.

## Release identity

The v1.0.1 ZIP included in this repository is:

[`dist/AI_Protected_Paths_v1.0.1_RECONCILED_29A58EAB_SHIP.zip`](dist/AI_Protected_Paths_v1.0.1_RECONCILED_29A58EAB_SHIP.zip)

Verify it with the adjacent `.sha256` file.

Full artifact identity and reconciliation details are in [`docs/RELEASE_IDENTITY.md`](docs/RELEASE_IDENTITY.md).

## How this relates to the other work

[Behavior Profiles](https://github.com/Secondmindsystems/Behavior-Profiles) make expected agent conduct explicit in instructions.

AI Protected Paths adds an executable checkpoint when selected repository paths need approval before a local commit proceeds.

[Governed Change Demo](https://github.com/Secondmindsystems/governed-change-demo) shows a broader evaluation of a proposed change against declared paths, authority, and evidence.

These are separate implementations that address different parts of the surrounding AI harness.

For more of the engineering, visit the [Governed AI Systems Portfolio](https://github.com/Secondmindsystems/governed-ai-systems-portfolio).

## About Second Mind Systems

Built by Tavio Lawrence as part of Second Mind Systems' work on AI harnesses, agent systems, developer safeguards, evaluation, and reviewable execution.

For engineering roles, consulting, implementation, or technical collaboration: [secondmindsystems@gmail.com](mailto:secondmindsystems@gmail.com).

## Rights

AI Protected Paths is proprietary source-available software. Personal and internal organizational use and modification are permitted. Redistribution, resale, sublicensing, or offering it as a standalone third-party product or service requires prior written permission.

See [`LICENSE.txt`](LICENSE.txt) for the controlling terms.
