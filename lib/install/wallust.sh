#!/usr/bin/env bash
# lib/install/wallust.sh
set -euo pipefail

# wallust derives the whole colour scheme from the active wallpaper. It is
# the one binary the theme engine shells out to that no Arch repo carries,
# and both AUR routes to it broke on a fresh install:
#
#   - `wallust` (stable) sources codeberg's auto-generated
#     archive/<tag>.tar.gz. Gitea regenerates those on request and the gzip
#     output is not byte-stable, so the PKGBUILD's pinned sha256sum stops
#     matching for everyone at once. Measured 2026-09-12: the PKGBUILD
#     expects 46c25922..., the served tarball hashes to 8609d271....
#   - `wallust-git` sidesteps checksums (git sources skip them) but now
#     builds 4.0.0-alpha from HEAD, which is not a version to put under a
#     desktop's theme engine.
#
# Upstream publishes a static musl binary as an uploaded release asset, and
# uploaded assets are served byte for byte rather than regenerated. That is
# the version Aphotic wants (3.5.2), it needs no Rust toolchain, and its
# checksum can be pinned honestly. So wallust is installed here rather than
# through profiles/base/*.toml, the same way gpu_compute.sh keeps the
# Ollama runner out of the layer files: the package lists are for what a
# repo or the AUR can resolve, and this is neither.
WALLUST_VERSION="3.5.2"
WALLUST_SHA256="92e11a841827ea6c2af28290d2cf4908db07dff4aee8dec1b7f1133cbf72c6e2"
WALLUST_URL="https://codeberg.org/explosion-mental/wallust/releases/download/${WALLUST_VERSION}/wallust-${WALLUST_VERSION}-x86_64-unknown-linux-musl.tar.gz"
# /usr/local/bin, not /usr/bin: pacman owns /usr/bin, and dropping an
# unmanaged file there would collide the moment the AUR package works again
# and someone installs it.
WALLUST_BIN_DIR="/usr/local/bin"

# Never fatal. A machine without wallust still gets a working desktop --
# the wallpaper is set by awww before the palette step, and cmd_theme.sh
# already warns and skips palette regeneration when the binary is absent.
setup_wallust() {
  if command -v wallust >/dev/null 2>&1; then
    echo -e "$COK - wallust is already installed ($(command -v wallust)); leaving it alone."
    return 0
  fi

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo -e "$CNT - [dry-run] would install wallust $WALLUST_VERSION from $WALLUST_URL"
    echo -e "$CNT - [dry-run]   verified against sha256 $WALLUST_SHA256, into $WALLUST_BIN_DIR"
    return 0
  fi

  echo -e "$CNT - Installing wallust $WALLUST_VERSION (upstream static binary)..."

  local tmp
  tmp=$(mktemp -d) || { echo -e "$CWR - Could not create a temp dir for wallust; skipping."; return 1; }
  # No early return past this point without clearing the download.
  trap 'rm -rf "$tmp"' RETURN

  if ! curl -fsSL --retry 2 --connect-timeout 15 -o "$tmp/wallust.tar.gz" "$WALLUST_URL" &>> "$INSTLOG"; then
    echo -e "$CWR - Could not download wallust from $WALLUST_URL"
    echo -e "$CWR   The desktop still works; the wallpaper sets, but themes will not regenerate their palette."
    echo -e "$CWR   Install it later with: ./install.sh --config-only, or build wallust from the AUR."
    return 1
  fi

  local got
  got=$(sha256sum "$tmp/wallust.tar.gz" | cut -d' ' -f1)
  if [[ "$got" != "$WALLUST_SHA256" ]]; then
    echo -e "$CWR - wallust download failed its checksum, so it was not installed."
    echo -e "$CWR   expected $WALLUST_SHA256"
    echo -e "$CWR   got      $got"
    echo -e "$CWR   Nothing was written. Report this: upstream may have replaced the release asset."
    return 1
  fi

  if ! tar xzf "$tmp/wallust.tar.gz" -C "$tmp" wallust &>> "$INSTLOG"; then
    echo -e "$CWR - Could not unpack the wallust archive; skipping."
    return 1
  fi

  if ! sudo install -Dm755 "$tmp/wallust" "$WALLUST_BIN_DIR/wallust" &>> "$INSTLOG"; then
    echo -e "$CWR - Could not install wallust into $WALLUST_BIN_DIR; skipping."
    return 1
  fi

  hash -r 2>/dev/null || true
  if command -v wallust >/dev/null 2>&1; then
    echo -e "$COK - wallust $WALLUST_VERSION installed to $WALLUST_BIN_DIR/wallust."
    return 0
  fi

  echo -e "$CWR - wallust landed in $WALLUST_BIN_DIR but is not on PATH."
  echo -e "$CWR   Add $WALLUST_BIN_DIR to PATH, or themes will not regenerate their palette."
  return 1
}
