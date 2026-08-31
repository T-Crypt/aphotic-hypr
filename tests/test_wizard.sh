#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/install/wizard.sh"

result=$(echo "" | prompt_profile)
[[ "$result" == "full" ]] || fail "expected default 'full', got '$result'"

result=$(echo "minimal" | prompt_profile)
[[ "$result" == "minimal" ]] || fail "expected 'minimal', got '$result'"

result=$(printf "3\ny\nn\ny\nn\n" | prompt_layers)
[[ "$result" == "gaming,ai" ]] || fail "expected 'gaming,ai', got '$result'"

# preset 1: everything
result=$(echo "1" | prompt_layers)
[[ "$result" == "gaming,dev,ai,exploit" ]] || fail "expected 'gaming,dev,ai,exploit', got '$result'"

# preset 2: daily driver, no layers
result=$(echo "2" | prompt_layers)
[[ "$result" == "" ]] || fail "expected '', got '$result'"

# exploit enabled, default bundle accepted, no extra sublayers
result=$(printf "3\nn\nn\nn\ny\ny\nn\nn\nn\nn\n" | prompt_layers)
[[ "$result" == "exploit" ]] || fail "expected 'exploit', got '$result'"

# exploit enabled, declines default bundle, hand-picks recon + web only
result=$(printf "3\nn\nn\nn\ny\nn\ny\ny\nn\nn\nn\nn\nn\n" | prompt_layers)
[[ "$result" == "exploit-recon,exploit-web" ]] || fail "expected 'exploit-recon,exploit-web', got '$result'"

# exploit enabled, default bundle accepted, passwords + wordlist opt-in
result=$(printf "3\nn\nn\nn\ny\ny\ny\ny\nn\nn\nn\n" | prompt_layers)
[[ "$result" == "exploit,exploit-passwords,exploit-wordlists" ]] || fail "expected 'exploit,exploit-passwords,exploit-wordlists', got '$result'"

CWR="[WARNING]"

result=$(echo "" | prompt_theme 2>/dev/null)
[[ "$result" == "tokyonight" ]] || fail "expected default 'tokyonight', got '$result'"

result=$(echo "1" | prompt_theme 2>/dev/null)
[[ "$result" == "gruvbox" ]] || fail "expected 'gruvbox' for selection 1, got '$result'"

result=$(echo "99" | prompt_theme 2>/dev/null)
[[ "$result" == "tokyonight" ]] || fail "expected fallback to 'tokyonight' for out-of-range selection, got '$result'"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
write_aphotic_toml "$WORKDIR/aphotic.toml" "full" "gaming,dev" "default" "true" "yay" "2026-08-18T10:00:00"

grep -q 'profile = "full"' "$WORKDIR/aphotic.toml" || fail "profile not written"
grep -q 'layers = \["gaming", "dev"\]' "$WORKDIR/aphotic.toml" || fail "layers not written correctly"

python -c "import tomllib; tomllib.load(open('$WORKDIR/aphotic.toml','rb'))" || fail "generated aphotic.toml is not valid TOML"

echo "PASS: wizard prompts + aphotic.toml writer"
