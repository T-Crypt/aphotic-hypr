#!/usr/bin/env bash
# tests/test_install_assistant.sh
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
rm -f aphotic.toml

FAKEBIN="$(mktemp -d)"
cat > "$FAKEBIN/lspci" <<'FAKE'
#!/usr/bin/env bash
echo "01:00.0 VGA compatible controller: NVIDIA Corporation GA106 [GeForce RTX 3060] (rev a1)"
FAKE
chmod +x "$FAKEBIN/lspci"
trap 'rm -rf "$FAKEBIN"' EXIT

output=$(PATH="$FAKEBIN:$PATH" bash install.sh --dry-run --profile minimal --with dev --with-assistant --theme default < /dev/null 2>&1)
echo "$output" | grep -q "nvidia: true" || fail "expected fake NVIDIA to be detected"
echo "$output" | grep -q "layers: dev,ai" || fail "expected --with-assistant to add the ai layer when it wasn't selected"
echo "$output" | grep -q "assistant: true" || fail "expected assistant: true with --with-assistant + NVIDIA"
echo "$output" | grep -q "would pull model:" || fail "expected a dry-run model line when assistant is true"

output=$(PATH="$FAKEBIN:$PATH" bash install.sh --dry-run --profile minimal --with ai --no-assistant --theme default < /dev/null 2>&1)
echo "$output" | grep -q "assistant: false" || fail "expected --no-assistant to force assistant: false"

output=$(bash install.sh --dry-run --profile minimal --with ai --with-assistant --theme default < /dev/null 2>&1)
echo "$output" | grep -q "assistant: false" || fail "expected assistant: false without an NVIDIA GPU, even with --with-assistant"
echo "$output" | grep -qi "needs an NVIDIA GPU" || fail "expected a warning when --with-assistant is used without NVIDIA"

[[ ! -f aphotic.toml ]] || fail "dry-run should not have written aphotic.toml"

echo "PASS: install.sh Aphotic Assistant gating"
