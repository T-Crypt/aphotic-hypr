#!/usr/bin/env bash
# tests/test_theme_download.sh
# `aphotic theme download/update/remove`: pull a community theme out of a
# local aphotic-themes checkout. A theme is a directory plus a
# theme.toml, so "downloaded" is answered by the filesystem and there is
# no state file to assert against. What is worth pinning down is the
# refusals (no manifest, already there, core theme), the staged swap on
# update, and the colorschemes a theme ships alongside its wallpapers.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TESTHOME=$(mktemp -d)
# SCHEMES_DIR below resolves into the checkout (see the symlink note), so
# clean the fixtures out of it rather than leaving them in the worktree.
cleanup() {
    rm -rf "$TESTHOME"
    rm -f "$ROOT/Configs/wallust/colorschemes/scratch.json" \
          "$ROOT/Configs/wallust/colorschemes/shared.json"
}
trap cleanup EXIT

export HOME="$TESTHOME"
export XDG_CONFIG_HOME="$TESTHOME/.config"
export XDG_STATE_HOME="$TESTHOME/.local/state"
export XDG_DATA_HOME="$TESTHOME/.local/share"
export APHOTIC_DOTS_DIR="$ROOT"

COMMANDS_DIR="$ROOT/Configs/.local/lib/aphotic/commands"
source "$ROOT/Configs/.local/lib/aphotic/globalcontrol.sh"
source "$COMMANDS_DIR/cmd_theme.sh"

export APHOTIC_THEMES_REPO="$TESTHOME/fake-themes"

# Reproduce the live layout: install.sh symlinks ~/.config/wallust at the
# dots checkout, so the directory a downloaded scheme lands in and the
# one core schemes are tracked in are the same directory. Testing against
# two separate dirs hides anything that tries to tell them apart by path.
mkdir -p "$XDG_CONFIG_HOME" "$ROOT/Configs/wallust/colorschemes"
ln -sfn "$ROOT/Configs/wallust" "$XDG_CONFIG_HOME/wallust"
SCHEMES_DIR="$XDG_CONFIG_HOME/wallust/colorschemes"
mkdir -p "$APHOTIC_AWWW_DIR"

# The repo the download reads from. Already a git checkout so
# _aphotic_theme_sync_repo takes its `git pull` branch and leaves the
# fixture alone instead of trying to clone over the network.
SRC="$APHOTIC_THEMES_REPO/scratch"
mkdir -p "$SRC/colorschemes"
cat > "$SRC/theme.toml" <<'EOF'
[theme]
display_name = "Scratch"

[engine]
colorscheme = "scratch"
EOF
printf 'x' > "$SRC/one.png"
echo '{"special":{},"colors":{}}' > "$SRC/colorschemes/scratch.json"
git -C "$APHOTIC_THEMES_REPO" init -q
git -C "$APHOTIC_THEMES_REPO" add -A
git -C "$APHOTIC_THEMES_REPO" -c user.email=t@t -c user.name=t commit -qm init

# A directory with no theme.toml is not a theme.
mkdir -p "$APHOTIC_THEMES_REPO/notatheme"
_aphotic_theme_download notatheme >/dev/null 2>&1 && fail "downloaded a directory with no theme.toml"
[[ -e "$APHOTIC_AWWW_DIR/notatheme" ]] && fail "left a directory behind for a rejected download"

_aphotic_theme_download nosuchtheme >/dev/null 2>&1 && fail "downloaded a name that isn't in the repo"

# The happy path, plus the colorscheme the theme ships.
_aphotic_theme_download scratch >/dev/null 2>&1 || fail "download failed"
[[ -f "$APHOTIC_AWWW_DIR/scratch/theme.toml" ]] || fail "no theme.toml after download"
[[ -f "$APHOTIC_AWWW_DIR/scratch/one.png" ]] || fail "no wallpaper after download"
[[ -f "$SCHEMES_DIR/scratch.json" ]] || fail "shipped colorscheme not installed to the wallust dir"

_aphotic_theme_download scratch >/dev/null 2>&1 && fail "downloaded over an existing theme"

# Update refreshes the payload in place and re-lands the colorscheme.
printf 'xx' > "$SRC/two.png"
echo '{"special":{"background":"#111111"},"colors":{}}' > "$SRC/colorschemes/scratch.json"
_aphotic_theme_update scratch >/dev/null 2>&1 || fail "update failed"
[[ -f "$APHOTIC_AWWW_DIR/scratch/two.png" ]] || fail "update didn't bring the new wallpaper"
grep -q '111111' "$SCHEMES_DIR/scratch.json" || fail "update didn't refresh the colorscheme"

# A staging failure must leave the working copy alone. An unreadable
# source makes `cp -r` fail without touching the destination.
chmod 000 "$SRC"
_aphotic_theme_update scratch >/dev/null 2>&1 && fail "update reported success on an unreadable source"
chmod 755 "$SRC"
[[ -f "$APHOTIC_AWWW_DIR/scratch/one.png" ]] || fail "failed update destroyed the downloaded copy"
[[ -e "$APHOTIC_AWWW_DIR/scratch.updating" ]] && fail "failed update left its staging directory behind"

_aphotic_theme_update notdownloaded >/dev/null 2>&1 && fail "updated a theme that was never downloaded"

# Core themes ship with Aphotic and `remove` must refuse them.
CORE_ONE="${APHOTIC_CORE_THEMES[0]:-}"
[[ -n "$CORE_ONE" ]] || fail "no core themes discovered from Configs/awww"
mkdir -p "$APHOTIC_AWWW_DIR/$CORE_ONE"
_aphotic_theme_remove "$CORE_ONE" >/dev/null 2>&1 && fail "removed a core theme"
[[ -d "$APHOTIC_AWWW_DIR/$CORE_ONE" ]] || fail "refused remove deleted the core theme anyway"

# Removing a theme takes its directory and the colorscheme it brought.
# Kept off the active theme deliberately: removing the active one ends in
# _aphotic_theme_apply, which needs awww and wallust running, so its
# fallback is not something this suite can assert headlessly.
_aphotic_theme_write_state "$CORE_ONE" ""
_aphotic_theme_remove scratch >/dev/null 2>&1 || fail "remove failed"
[[ -e "$APHOTIC_AWWW_DIR/scratch" ]] && fail "remove left the theme directory"
[[ -f "$SCHEMES_DIR/scratch.json" ]] && fail "remove left the theme's colorscheme behind"

_aphotic_theme_remove scratch >/dev/null 2>&1 && fail "removed a theme that wasn't downloaded"

# A scheme whose installed copy no longer matches what the theme ships
# belongs to someone else by then -- a core file of the same name, or an
# edit the user made -- and remove must leave it there.
rm -f "$SRC/colorschemes/scratch.json"
echo '{"mine":true}' > "$SRC/colorschemes/shared.json"
_aphotic_theme_download scratch >/dev/null 2>&1 || fail "second download failed"
echo '{"someone-elses":true}' > "$SCHEMES_DIR/shared.json"
_aphotic_theme_remove scratch >/dev/null 2>&1 || fail "second remove failed"
[[ -f "$SCHEMES_DIR/shared.json" ]] || fail "remove deleted a colorscheme it did not install"
rm -f "$SCHEMES_DIR/shared.json"

echo "PASS: tests/test_theme_download.sh"
