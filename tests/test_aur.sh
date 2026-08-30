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

# ensure_pacman_db must run before the AUR bootstrap; in dry-run it declares
# the planned sync and reports success without touching the system.
DRY_RUN=1
db_out=$(ensure_pacman_db)
[[ "$?" == "0" ]] || fail "expected ensure_pacman_db to succeed in dry-run"
[[ "$db_out" == *"sudo pacman -Sy"* ]] || fail "expected dry-run sync message, got '$db_out'"
unset DRY_RUN

# ensure_aur_helper must re-detect after a would-be install instead of
# blindly returning "yay": if the install silently failed, yay is gone and
# handing back a name that won't resolve just turns one install failure into
# a cascade of confusing package-install failures later.
EMPTY_BIN=$(mktemp -d)
export PATH="$EMPTY_BIN"
DRY_RUN=1
# ( ... ) subshell: ensure_aur_helper exits on a failed install, and the
# exit must not kill the whole test process.
if ( ensure_aur_helper >/dev/null 2>&1 ); then
  fail "expected ensure_aur_helper to fail when no helper exists and cannot be installed"
fi
unset DRY_RUN
export PATH="$PATH_BACKUP"
/bin/rm -rf "$EMPTY_BIN"

# Same guarantee against a *real* (non-dry-run) failed build: fake out git so
# the clone step fails, fake sudo so ensure_pacman_db's sync no-ops, and fake
# whatever else install_yay shells to, keeping the test fully self-contained
# on the real host. ensure_aur_helper must still return non-zero.
FAIL_BIN=$(mktemp -d)
export PATH="$FAIL_BIN"
for fake in rm mkdir sudo git install make; do
  /bin/cat > "$FAIL_BIN/$fake" <<'EOF'
#!/bin/bash
exit 0
EOF
  /bin/chmod +x "$FAIL_BIN/$fake"
done
# git must fail so install_yay's clone step returns failure for real
/bin/cat > "$FAIL_BIN/git" <<'EOF'
#!/bin/bash
exit 1
EOF
/bin/chmod +x "$FAIL_BIN/git"
if ( ensure_aur_helper >/dev/null 2>&1 ); then
  fail "expected ensure_aur_helper to fail when the yay build fails"
fi
export PATH="$PATH_BACKUP"
/bin/rm -rf "$FAIL_BIN"

# ensure_pacman_db failing must also make ensure_aur_helper fail (warn-and-
# continue contract: the orchestrator sees an empty AUR_HELPER, never a stale
# "yay"). Fake sudo to fail and confirm the DB guard aborts the helper before
# any build attempt.
DBFAIL_BIN=$(mktemp -d)
trap '/bin/rm -rf "$FAKE_BIN" "$FAIL_BIN" "$DBFAIL_BIN"' EXIT
export PATH="$DBFAIL_BIN"
for fake in rm; do
  /bin/cat > "$DBFAIL_BIN/$fake" <<'EOF'
#!/bin/bash
exit 0
EOF
  /bin/chmod +x "$DBFAIL_BIN/$fake"
done
/bin/cat > "$DBFAIL_BIN/sudo" <<'EOF'
#!/bin/bash
exit 1
EOF
/bin/chmod +x "$DBFAIL_BIN/sudo"
if ( ensure_aur_helper >/dev/null 2>&1 ); then
  fail "expected ensure_aur_helper to fail when the pacman DB sync fails"
fi
export PATH="$PATH_BACKUP"
/bin/rm -rf "$DBFAIL_BIN"

echo "PASS: aur helper detection"
