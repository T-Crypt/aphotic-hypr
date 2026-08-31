#!/usr/bin/env bash
# tests/test_theme_ensure_default.sh
# `aphotic theme ensure-default` is the fix for a fresh install showing
# "No wallpaper set" until SUPER+SHIFT+W is used manually: install.sh
# writes aphotic.toml's [theme].name but never actually ran `aphotic
# theme set` (couldn't -- no Wayland session/awww-daemon exists yet at
# install time), so theme.json (the file Wallpaper.qml/Themes.qml read)
# never got written. This is now called once from Hyprland's
# startup.lua instead, after awww-daemon is up.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TESTHOME=$(mktemp -d)
trap 'rm -rf "$TESTHOME"' EXIT

export HOME="$TESTHOME"
export XDG_CONFIG_HOME="$TESTHOME/.config"
export XDG_STATE_HOME="$TESTHOME/.local/state"
export XDG_DATA_HOME="$TESTHOME/.local/share"
export APHOTIC_DOTS_DIR="$ROOT"
# Point away from the real system SDDM theme dir -- this test must never
# touch /usr/share/sddm on the machine running it.
export APHOTIC_SDDM_THEME_DIR="$TESTHOME/no-such-sddm-theme"

# Fake `awww`/`jq` on PATH ahead of the real ones -- `jq` stays real
# (should already be installed; only awww needs stubbing since nothing
# in this test has a real Wayland session/daemon to talk to).
FAKEBIN="$TESTHOME/fakebin"
mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/awww" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    query) echo '{}' ;;
    img) exit 0 ;;
    *) exit 0 ;;
esac
EOF
chmod +x "$FAKEBIN/awww"
cat > "$FAKEBIN/wallust" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$FAKEBIN/wallust"
export PATH="$FAKEBIN:$PATH"

LIB_DIR="$ROOT/Configs/.local/lib/aphotic"
COMMANDS_DIR="$LIB_DIR/commands"
source "$LIB_DIR/globalcontrol.sh"
source "$COMMANDS_DIR/cmd_theme.sh"

# --- scratch theme folders (mirrors the real Configs/awww layout --
# every shipped theme ships a theme.toml, so these do too) ---
mkdir -p "$APHOTIC_AWWW_DIR/alpha" "$APHOTIC_AWWW_DIR/beta"
: > "$APHOTIC_AWWW_DIR/alpha/one.jpg"
: > "$APHOTIC_AWWW_DIR/beta/two.jpg"
cat > "$APHOTIC_AWWW_DIR/alpha/theme.toml" <<'EOF'
[theme]
display_name = "Alpha"

[wallpaper]
default = "one.jpg"
EOF
cat > "$APHOTIC_AWWW_DIR/beta/theme.toml" <<'EOF'
[theme]
display_name = "Beta"

[wallpaper]
default = "two.jpg"
EOF

# --- case 1: aphotic.toml names a real theme -> that theme gets applied ---
mkdir -p "$HOME/Aphotic-Hypr"
cat > "$HOME/Aphotic-Hypr/aphotic.toml" <<'EOF'
[install]
profile = "full"
layers = []

[theme]
name = "beta"
EOF

_aphotic_theme_ensure_default

[[ -f "$APHOTIC_THEME_STATE_FILE" ]] || fail "theme.json was not written"
applied="$(jq -r '.theme' "$APHOTIC_THEME_STATE_FILE")"
[[ "$applied" == "beta" ]] || fail "expected 'beta' applied from aphotic.toml, got '$applied'"

# --- case 2: already-set theme.json is left alone (no clobbering a switch) ---
jq -n '{theme: "alpha", wallpaper: "one.jpg"}' > "$APHOTIC_THEME_STATE_FILE"
_aphotic_theme_ensure_default
still="$(jq -r '.theme' "$APHOTIC_THEME_STATE_FILE")"
[[ "$still" == "alpha" ]] || fail "ensure-default clobbered an existing theme.json, got '$still'"

# --- case 3: no aphotic.toml at all -> falls back to first theme folder ---
rm -f "$APHOTIC_THEME_STATE_FILE" "$HOME/Aphotic-Hypr/aphotic.toml"
_aphotic_theme_ensure_default
fallback="$(jq -r '.theme' "$APHOTIC_THEME_STATE_FILE")"
[[ "$fallback" == "alpha" ]] || fail "expected fallback to first theme folder 'alpha', got '$fallback'"

echo "PASS: aphotic theme ensure-default"
