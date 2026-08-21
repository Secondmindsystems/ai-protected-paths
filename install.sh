#!/usr/bin/env sh
set -e

if [ ! -d ".git" ]; then
  echo "Run this from a git repo root (where .git exists)." >&2
  exit 1
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

require_asset() {
  if [ ! -f "$1" ]; then
    echo "Missing package asset: $1" >&2
    exit 1
  fi
}

require_asset "$script_dir/hooks/pre-commit"
require_asset "$script_dir/hooks/pre_commit.ps1"
require_asset "$script_dir/hooks/pre_commit.sh"
require_asset "$script_dir/governance/protected_paths.txt"
require_asset "$script_dir/approvals/APPROVAL_TOKEN_TEMPLATE.txt"

mkdir -p ".git/hooks" "hooks" "governance" "approvals"

cp "$script_dir/hooks/pre-commit" "hooks/pre-commit"
cp "$script_dir/hooks/pre_commit.ps1" "hooks/pre_commit.ps1"
cp "$script_dir/hooks/pre_commit.sh" "hooks/pre_commit.sh"

if [ ! -f "governance/protected_paths.txt" ]; then
  cp "$script_dir/governance/protected_paths.txt" "governance/protected_paths.txt"
fi

if [ ! -f "approvals/APPROVAL_TOKEN_TEMPLATE.txt" ]; then
  cp "$script_dir/approvals/APPROVAL_TOKEN_TEMPLATE.txt" "approvals/APPROVAL_TOKEN_TEMPLATE.txt"
fi

cp "hooks/pre-commit" ".git/hooks/pre-commit"
chmod +x ".git/hooks/pre-commit" "hooks/pre-commit" "hooks/pre_commit.sh"

echo "OK: installed .git/hooks/pre-commit"
echo "Target repo: $(pwd)"
echo "Package root: $script_dir"
echo "Commit behavior: NOT VALIDATED by install"
