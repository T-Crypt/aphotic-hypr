#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/install/aur.sh"

FAKE_BIN=$(mktemp -d)
trap '/bin/rm -rf "$FAKE_BIN"' EXIT
PATH_BACKUP="$PATH"

export PATH="$FAKE_BIN"
result=$(detect_aur_helper)
[[ "$result" == "" ]] || fail "expected empty, got '$result'"

/bin/cat > "$FAKE_BIN/paru" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
/bin/chmod +x "$FAKE_BIN/paru"
result=$(detect_aur_helper)
[[ "$result" == "paru" ]] || fail "expected paru, got '$result'"

/bin/cat > "$FAKE_BIN/yay" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
/bin/chmod +x "$FAKE_BIN/yay"
result=$(detect_aur_helper)
[[ "$result" == "yay" ]] || fail "expected yay (priority over paru), got '$result'"

export PATH="$PATH_BACKUP"
echo "PASS: aur helper detection"
