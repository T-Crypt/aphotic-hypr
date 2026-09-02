#!/usr/bin/env bash
# lib/install/wallpapers.sh
set -euo pipefail

# EXTRA_WALLPAPERS is "" (nobody has decided -- ask), "1" or "0"; the
# guided flow answers it in its batched add-ons step, see
# activate_starship's note in shell_activation.sh.
offer_extra_wallpapers() {
  local wanted="${EXTRA_WALLPAPERS:-}"
  if [[ -z "$wanted" ]]; then
    echo -e "\n$CNT - The community wallpaper collection is about 145MB across all 8 themes. Every"
    echo -e "$CNT   theme already comes with its own wallpapers, so this only adds more to choose"
    echo -e "$CNT   from -- skip it if your connection is slow, it can be fetched any time later."
    if confirm "Download the extra wallpapers now?" n; then
      wanted=1
    else
      wanted=0
    fi
  fi

  if [[ "$wanted" == "1" ]]; then
    echo -e "$CNT - Downloading the community wallpaper collection..."
    "$HOME/.local/bin/aphotic" wallpaper --fetch-extra -y || echo -e "$CWR - Could not fetch the extra wallpapers now; run 'aphotic wallpaper --fetch-extra' any time later."
  else
    echo -e "$CNT - Skipping the extra wallpapers. Run 'aphotic wallpaper --fetch-extra' any time later to get them."
  fi
}
