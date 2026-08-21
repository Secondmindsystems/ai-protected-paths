#!/usr/bin/env sh
set -eu

protected_file="governance/protected_paths.txt"
approval_token="approvals/APPROVAL_TOKEN.txt"
proof_dir="proofs/packets"

if ! command -v git >/dev/null 2>&1; then
  echo "AI Protected Paths: git is required for the pre-commit hook." >&2
  exit 1
fi

# FIX-3: --no-renames so a git mv of a protected file exposes BOTH the deleted
# source path and the new destination (default rename detection hid the source).
changed="$(git diff --cached --name-only --no-renames)"
if [ -z "$changed" ]; then
  exit 0
fi

mkdir -p "$proof_dir"

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
git_user_name="$(git config user.name 2>/dev/null || true)"
git_user_email="$(git config user.email 2>/dev/null || true)"

# FIX-4: case-insensitive matching when the repo is on a case-insensitive
# filesystem (Windows/macOS default), so HOOKS/x cannot slip past hooks/.
ignorecase="$(git config --get core.ignorecase 2>/dev/null || true)"

lc() {
  if [ "$ignorecase" = "true" ]; then
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
  else
    printf '%s' "$1"
  fi
}

# FIX-1/FIX-2: resolve the protected ruleset from a TRUSTED baseline, not the
# mutable working tree. Order: staged index -> HEAD -> working tree. This makes
# an unstaged blank/delete of the config ineffective once it is committed, and
# a config change that IS staged is itself a governance/ protected hit.
resolve_protected_rules() {
  if git diff --cached --name-only --no-renames | grep -qx "$protected_file"; then
    git show ":$protected_file" 2>/dev/null && return 0
  fi
  if git cat-file -e "HEAD:$protected_file" 2>/dev/null; then
    git show "HEAD:$protected_file" 2>/dev/null && return 0
  fi
  if [ -f "$protected_file" ]; then
    cat "$protected_file"
    return 0
  fi
  return 1
}

if protected_rules="$(resolve_protected_rules)"; then
  rules_status=0
else
  rules_status=1
  protected_rules=""
fi

is_protected() {
  path="$(printf '%s' "$1" | sed 's#\\#/#g')"
  path="$(lc "$path")"
  if [ "$path" = "$(lc "$protected_file")" ]; then
    return 0
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    pat="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s#\\#/#g')"
    case "$pat" in
      ""|\#*) continue ;;
    esac
    pat="$(lc "$pat")"
    case "$path" in
      "$pat"*) return 0 ;;
    esac
  done <<EOF
$protected_rules
EOF

  return 1
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

json_array_from_lines() {
  first=1
  printf '['
  while IFS= read -r item || [ -n "$item" ]; do
    [ -n "$item" ] || continue
    if [ "$first" -eq 0 ]; then
      printf ','
    fi
    first=0
    printf '"%s"' "$(json_escape "$item")"
  done
  printf ']'
}

hits=""
approval_token_staged=0
approval_token_lc="$(lc "$approval_token")"
while IFS= read -r path || [ -n "$path" ]; do
  [ -n "$path" ] || continue
  normalized_path="$(lc "$(printf '%s' "$path" | sed 's#\\#/#g')")"
  if [ "$normalized_path" = "$approval_token_lc" ]; then
    approval_token_staged=1
  fi
  if is_protected "$path"; then
    hits="${hits}${path}
"
  fi
done <<EOF
$changed
EOF

ts_base="$(date -u '+%Y%m%dT%H%M%S')"
ts_fraction="$(date -u '+%N' 2>/dev/null || true)"
case "$ts_fraction" in
  ""|*N*) ts_fraction="$(printf '%03d' "$(($$ % 1000))")" ;;
  *) ts_fraction="$(printf '%.3s' "$ts_fraction")" ;;
esac
ts_file="${ts_base}${ts_fraction}Z"
ts_iso="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
proof="$proof_dir/proof_$ts_file.json"

outcome="ALLOW"
reason="No protected files changed."
consume_approval_token=0
# FIX-1: fail CLOSED when the ruleset cannot be resolved at all.
if [ "$rules_status" -ne 0 ]; then
  outcome="BLOCK"
  reason="Protected paths config could not be resolved (missing from index, HEAD, and working tree). Run: protected-paths install, or restore governance/protected_paths.txt, then retry."
elif [ "$approval_token_staged" -eq 1 ]; then
  outcome="BLOCK"
  reason="Approval token is staged. APPROVAL_TOKEN.txt is local runtime approval and should not be committed. Run: git reset approvals/APPROVAL_TOKEN.txt. Do not run: git add approvals/. Then commit again with only the intended protected files staged."
elif [ -n "$hits" ] && [ ! -f "$approval_token" ]; then
  outcome="BLOCK"
  reason="Protected commit blocked because approval token is missing. Run: protected-paths authorize --reason \"brief reason\". Do not stage approvals/APPROVAL_TOKEN.txt or run: git add approvals/. Then retry with only intended files staged."
elif [ -n "$hits" ]; then
  reason="Approval token consumed for protected files changed."
  consume_approval_token=1
fi

{
  printf '{\n'
  printf '  "change_id": "precommit",\n'
  printf '  "timestamp": "%s",\n' "$(json_escape "$ts_iso")"
  printf '  "intent": "commit",\n'
  printf '  "repo_root": "%s",\n' "$(json_escape "$repo_root")"
  printf '  "git_user": {\n'
  printf '    "name": "%s",\n' "$(json_escape "$git_user_name")"
  printf '    "email": "%s"\n' "$(json_escape "$git_user_email")"
  printf '  },\n'
  printf '  "hook": {\n'
  printf '    "name": "pre_commit.sh",\n'
  printf '    "version": "lite-0.2"\n'
  printf '  },\n'
  printf '  "checks_run": ["protected_paths_check","approval_token_present_check","config_resolution_check"],\n'
  printf '  "outcome": "%s",\n' "$outcome"
  printf '  "reason": "%s",\n' "$(json_escape "$reason")"
  printf '  "artifacts": '
  printf '%s\n' "$changed" | json_array_from_lines
  printf ',\n'
  printf '  "protected_hits": '
  printf '%s\n' "$hits" | json_array_from_lines
  printf '\n'
  printf '}\n'
} > "$proof"

if [ "$outcome" = "BLOCK" ]; then
  if [ "$rules_status" -ne 0 ]; then
    echo "BLOCKED: protected paths config could not be resolved."
    echo "Checked staged index, HEAD, and working tree for: $protected_file"
    echo "Run: protected-paths install (or restore the config), then retry."
    echo "Local proof receipt written: $proof"
    exit 1
  fi
  if [ "$approval_token_staged" -eq 1 ]; then
    echo "Approval token is staged."
    echo "approvals/APPROVAL_TOKEN.txt is local runtime approval and should not be committed."
    echo "Run:"
    echo "  git reset approvals/APPROVAL_TOKEN.txt"
    echo "Do not run: git add approvals/"
    echo "Then commit again with only the intended protected files staged."
    echo "Local proof receipt written: $proof"
    exit 1
  fi
  echo "BLOCKED: protected commit requires approval token."
  echo "Approval token missing: approvals/APPROVAL_TOKEN.txt"
  echo "Run: protected-paths authorize --reason \"brief reason\""
  echo "Do not stage approvals/APPROVAL_TOKEN.txt or run: git add approvals/"
  echo "Then retry the commit with only intended files staged."
  echo "Local proof receipt written: $proof"
  exit 1
fi

if [ "$consume_approval_token" -eq 1 ]; then
  if rm -f -- "$approval_token"; then
    echo "ALLOW: approval token consumed."
    echo "Local proof receipt written: $proof"
    echo "View latest proof: protected-paths proofs latest"
  else
    echo "ERROR: approved commit blocked because approval token could not be consumed." >&2
    exit 1
  fi
fi

exit 0
