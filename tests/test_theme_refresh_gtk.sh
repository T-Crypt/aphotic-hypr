#!/usr/bin/env bash
# tests/test_theme_refresh_gtk.sh
# `aphotic theme refresh-gtk` deploys the GTK4/libadwaita stylesheet the
# color engine staged, with the live UI font stamped in, and restarts the
# GTK4 apps that are sitting idle in the background so libadwaita reads
# it (it reads the file once, at process start, and never again).
#
# The three things worth pinning down here: the font actually lands, the
# destination is written by replacement rather than edited in place (it
# can be a symlink, and `sed -i` would break the link), and an app with a
# window open is left alone instead of being quit out from under someone.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TESTHOME=$(mktemp -d)
export TESTHOME
trap 'rm -rf "$TESTHOME"' EXIT

export HOME="$TESTHOME"
export XDG_CONFIG_HOME="$TESTHOME/.config"
export XDG_STATE_HOME="$TESTHOME/.local/state"
export XDG_DATA_HOME="$TESTHOME/.local/share"
export APHOTIC_DOTS_DIR="$ROOT"
export APHOTIC_SDDM_THEME_DIR="$TESTHOME/no-such-sddm-theme"

FAKEBIN="$TESTHOME/fakebin"
mkdir -p "$FAKEBIN"

cat > "$FAKEBIN/gsettings" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == "get org.gnome.desktop.interface font-name" ]] && echo "'Cantarell Test 11'"
exit 0
EOF

# Records that it was asked to quit, so the assertions below can tell a
# restart that happened from one that was skipped.
cat > "$FAKEBIN/nautilus" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "-q" ]] && echo quit >> "$TESTHOME/nautilus-quit.log"
exit 0
EOF

# The daemon is "running" for every case below; what changes between them
# is whether hyprctl reports a window for it.
cat > "$FAKEBIN/pgrep" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == *nautilus* ]] && exit 0
exit 1
EOF

cat > "$FAKEBIN/hyprctl" <<'EOF'
#!/usr/bin/env bash
cat "$TESTHOME/clients.json"
EOF

chmod +x "$FAKEBIN"/*
export PATH="$FAKEBIN:$PATH"

LIB_DIR="$ROOT/Configs/.local/lib/aphotic"
COMMANDS_DIR="$LIB_DIR/commands"
source "$LIB_DIR/globalcontrol.sh"
source "$COMMANDS_DIR/cmd_theme.sh"

STAGED="$APHOTIC_STATE_HOME/gtk4.css"
DEST="$XDG_CONFIG_HOME/gtk-4.0/gtk.css"

# --- nothing staged yet: warn, do not fail, do not write ---
echo '[]' > "$TESTHOME/clients.json"
_aphotic_theme_refresh_gtk >/dev/null 2>&1 || fail "refresh-gtk should not fail with nothing staged"
[[ -e "$DEST" ]] && fail "refresh-gtk wrote a stylesheet with nothing staged"

# --- staged: font stamped, destination written ---
mkdir -p "$APHOTIC_STATE_HOME"
cat > "$STAGED" <<'EOF'
@define-color window_bg_color #101010;
window, popover, dialog, .background {
  font-family: "Inter", sans-serif;
}
EOF

_aphotic_theme_refresh_gtk >/dev/null 2>&1 || fail "refresh-gtk failed with a staged stylesheet"
[[ -f "$DEST" ]] || fail "refresh-gtk did not write $DEST"
grep -q 'font-family: "Cantarell Test", sans-serif;' "$DEST" \
    || fail "the live UI font was not stamped in: $(grep font-family "$DEST")"
grep -q '#101010' "$DEST" || fail "the staged colors did not survive the stamp"
grep -q '"Inter"' "$DEST" && fail "the placeholder font was left in place"

# --- idle daemon gets restarted ---
[[ -f "$TESTHOME/nautilus-quit.log" ]] || fail "an idle GTK4 daemon was not restarted"

# --- a symlinked destination stays a symlink's target, not the link ---
rm -f "$DEST"
REAL="$TESTHOME/real-gtk4.css"
: > "$REAL"
ln -s "$REAL" "$DEST"
_aphotic_theme_refresh_gtk >/dev/null 2>&1 || fail "refresh-gtk failed against a symlinked destination"
[[ -L "$DEST" ]] || fail "refresh-gtk replaced the symlink with a regular file"
grep -q '#101010' "$REAL" || fail "refresh-gtk did not write through the symlink"

# --- a daemon with a window open is left alone ---
rm -f "$TESTHOME/nautilus-quit.log"
cat > "$TESTHOME/clients.json" <<'EOF'
[{"class": "org.gnome.Nautilus", "title": "Home"}]
EOF
out="$(_aphotic_theme_refresh_gtk 2>&1)" || fail "refresh-gtk failed with a window open"
[[ -f "$TESTHOME/nautilus-quit.log" ]] && fail "a GTK4 app with a window open was quit"
grep -q "leaving it alone" <<<"$out" || fail "no warning explained why the app was skipped: $out"
grep -q '#101010' "$REAL" || fail "the stylesheet was not deployed when the restart was skipped"

echo "PASS: theme refresh-gtk"
