#!/usr/bin/env bash
# tests/test_repo_layout.sh
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

for d in lib/colors lib/bar lib/install lib/toml themes/default profiles/base profiles/layers; do
  [[ -d "$d" ]] || fail "missing directory: $d"
done

[[ -f themes/THEME_SPEC.md ]] || fail "missing themes/THEME_SPEC.md"
[[ -f profiles/custom_apps.lst ]] || fail "missing profiles/custom_apps.lst"
[[ -L custom_apps.lst ]] || fail "custom_apps.lst is not a symlink"

target=$(readlink custom_apps.lst)
[[ "$target" == "profiles/custom_apps.lst" ]] || fail "custom_apps.lst points to '$target', expected profiles/custom_apps.lst"

diff <(cat custom_apps.lst) <(cat profiles/custom_apps.lst) >/dev/null || fail "symlinked content mismatch"

git check-ignore -q noctis.toml || fail "noctis.toml is not gitignored"
git check-ignore -q install.log || fail "install.log is not gitignored"

echo "PASS: repo layout"
