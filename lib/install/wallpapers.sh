#!/usr/bin/env bash
# lib/install/wallpapers.sh
set -euo pipefail

offer_extra_wallpapers() {
  if confirm "Download the larger community wallpaper pool now? ~145MB across all 8 themes; each theme already ships a handful of wallpapers regardless, this just adds more choice. Skip if you're on a slow connection" n; then
    "$HOME/.local/bin/aphotic" wallpaper --fetch-extra -y || echo -e "$CWR - Could not fetch extra wallpapers now; run 'aphotic wallpaper --fetch-extra' any time later."
  else
    echo -e "$CNT - Skipping the extra wallpaper pool. Run 'aphotic wallpaper --fetch-extra' any time later to get it."
  fi
}
