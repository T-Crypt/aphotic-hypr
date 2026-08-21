#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/install/wizard.sh"

result=$(echo "" | prompt_profile)
[[ "$result" == "full" ]] || fail "expected default 'full', got '$result'"

result=$(echo "minimal" | prompt_profile)
[[ "$result" == "minimal" ]] || fail "expected 'minimal', got '$result'"

result=$(printf "y\nn\ny\nn\n" | prompt_layers)
[[ "$result" == "gaming,ai" ]] || fail "expected 'gaming,ai', got '$result'"

result=$(printf "n\nn\nn\ny\n" | prompt_layers)
[[ "$result" == "exploit" ]] || fail "expected 'exploit', got '$result'"

result=$(echo "" | prompt_theme)
[[ "$result" == "default" ]] || fail "expected 'default', got '$result'"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
write_noctis_toml "$WORKDIR/noctis.toml" "full" "gaming,dev" "default" "true" "yay" "2026-08-18T10:00:00"

grep -q 'profile = "full"' "$WORKDIR/noctis.toml" || fail "profile not written"
grep -q 'layers = \["gaming", "dev"\]' "$WORKDIR/noctis.toml" || fail "layers not written correctly"

python -c "import tomllib; tomllib.load(open('$WORKDIR/noctis.toml','rb'))" || fail "generated noctis.toml is not valid TOML"

echo "PASS: wizard prompts + noctis.toml writer"
