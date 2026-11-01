#!/usr/bin/env bash
# shellcheck disable=SC2034  # the globals below are read by config_deploy.sh
# tests/test_install_keeps_user_wallpapers.sh
# Core ships one wallpaper per theme; the rest moved to the wallpaper-packs
# plugin. A user who installed before that keeps every wallpaper they had:
# an update copies Configs/ over ~/.config and never prunes a theme folder.
# Also checks the pack hint is only shown to someone without a collection.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

REPO="$WORKDIR/repo"
mkdir -p "$REPO/Configs/awww/gruvbox" "$REPO/Configs/hypr/scripts" "$REPO/Configs/wallust" \
         "$REPO/Configs/matugen" "$REPO/Configs/Kvantum" "$REPO/Configs/.local/bin" \
         "$REPO/Configs/.local/lib/aphotic"
printf 'default\n' > "$REPO/Configs/awww/gruvbox/default.png"
printf '[wallpaper]\ndefault = "default.png"\n' > "$REPO/Configs/awww/gruvbox/theme.toml"
: > "$REPO/Configs/hypr/scripts/noop.sh"
: > "$REPO/Configs/Kvantum/kvantum.kvconfig"
printf '#!/bin/sh\nexit 0\n' > "$REPO/Configs/.local/bin/aphotic"
chmod +x "$REPO/Configs/.local/bin/aphotic"
cp "$ROOT/Configs/.local/lib/aphotic/wallpaper_packs.py" "$ROOT/Configs/.local/lib/aphotic/harnesses_merge.py" \
   "$REPO/Configs/.local/lib/aphotic/"

CNT="[NOTE]" CWR="[WARNING]" INSTLOG="$WORKDIR/install.log"
CONFIG_ONLY=1 LAYERS_KNOWN=0 APHOTIC_CONTAINER=1 ISNVIDIA=false
ROOT_DIR="$REPO" APHOTIC_DOTS_DIR="$REPO"
layer_selected() { return 1; }
# shellcheck source=lib/install/config_deploy.sh
source "$ROOT/lib/install/config_deploy.sh"

deploy_as() {
    export HOME="$1"
    export XDG_CONFIG_HOME="$1/.config"
    mkdir -p "$HOME/.config"
    deploy_user_configs 2>&1
}

upgrader="$WORKDIR/upgrader"
mkdir -p "$upgrader/.config/awww/gruvbox"
printf 'dragon\n' > "$upgrader/.config/awww/gruvbox/dragon.png"
printf 'mine\n' > "$upgrader/.config/awww/gruvbox/my-own-photo.jpg"
out="$(deploy_as "$upgrader")"

[[ "$(cat "$upgrader/.config/awww/gruvbox/dragon.png")" == "dragon" ]] || fail "a wallpaper core stopped shipping was removed on update"
[[ "$(cat "$upgrader/.config/awww/gruvbox/my-own-photo.jpg")" == "mine" ]] || fail "a user's own wallpaper was removed on update"
[[ -f "$upgrader/.config/awww/gruvbox/default.png" ]] || fail "the theme's shipped default was not deployed"
[[ "$out" != *"wallpaper-packs plugin"* ]] || fail "an upgrader with a collection was told to fetch packs"

fresh="$WORKDIR/fresh"
out="$(deploy_as "$fresh")"
[[ "$out" == *"wallpaper-packs plugin"* ]] || fail "a fresh install with one wallpaper per theme got no pack hint"

echo "PASS: update keeps existing wallpapers; pack hint only without a collection"
