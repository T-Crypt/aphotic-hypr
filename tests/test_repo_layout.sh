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

git check-ignore -q aphotic.toml || fail "aphotic.toml is not gitignored"
git check-ignore -q install.log || fail "install.log is not gitignored"

# Colours.qml used to be regenerated wholesale by wallust on every theme
# apply -- a tracked git source file rewritten by ordinary desktop use,
# which made `aphotic update` (`git pull`) hit a real checkout conflict
# against machine-local state (docs/IN_FLIGHT.md item 3). It reads the
# resolved palette from ~/.local/state/aphotic/palette.json at runtime
# now and must stay static in the repo -- this guards against the
# template-substitution regressing back in by hand.
colours_qml="Configs/quickshell/aphotic/services/Colours.qml"
[[ -f "$colours_qml" ]] || fail "missing $colours_qml"
grep -q '{{' "$colours_qml" && fail "$colours_qml contains Jinja template syntax -- it must be a static file, not wallust template output"

echo "PASS: repo layout"
