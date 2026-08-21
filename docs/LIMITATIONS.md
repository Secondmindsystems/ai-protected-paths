# Limitations

AI Protected Paths is a deterministic local checkpoint on the normal Git
pre-commit route for configured paths. It is governance friction, not a
security boundary.

It does not provide cryptographic or tamper-proof enforcement, filesystem
access control, remote or server-side enforcement, branch protection, pull
request enforcement, CI/CD enforcement, organization-wide policy, immutable
audit evidence, malicious-intent detection, universal agent obedience, or
production-enterprise qualification.

Local hooks can be skipped with `git commit --no-verify`. A sufficiently
privileged local actor can remove or alter the hook, configuration, approval
token, or receipts. The tool does not prevent edits, staging, pushes, force
pushes, or changes made outside the normal Git commit route.

Each developer or automation environment must install and validate the hook.
Use branch protection, review, CI policy, and access control when those
different boundaries are required.

## Platform boundary

- Windows v1.0.1: tested and qualified on the current cleanroom route.
- macOS v1.0.1: PENDING.
- Linux v1.0.1: PENDING.
- Historical macOS evidence applies only to the tested v1.0.0 artifact and
  host. It does not automatically transfer to v1.0.1.
