#!/usr/bin/env bash
# lib/install/fonts.sh
set -euo pipefail

APHOTIC_ICON_FONT="Material Symbols Rounded"

# install_software runs one pacman transaction per package, so the fontconfig
# hook fires every second or two while fonts keep landing in the same
# directory. Fontconfig keeps a directory's cache when the recorded mtime
# matches, at one-second resolution, so a font added in the same second as
# the last cache write can stay invisible. The shell then draws every icon
# as its name ("wifi", "volume_up"). One forced rebuild after the package
# lists closes that window.
refresh_font_cache() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo -e "$CNT - [dry-run] would rebuild the font cache and check for $APHOTIC_ICON_FONT"
    return 0
  fi
  if ! command -v fc-cache >/dev/null 2>&1; then
    echo -e "$CWR - fc-cache is missing, so the font cache was not rebuilt. Install fontconfig, then run 'fc-cache -f'."
    return 0
  fi

  echo -e "$CNT - Rebuilding the font cache..."
  sudo fc-cache -f -s &>> "$INSTLOG" || true
  fc-cache -f &>> "$INSTLOG" || true

  if fc-list : family 2>/dev/null | grep -qF "$APHOTIC_ICON_FONT"; then
    echo -e "$COK - $APHOTIC_ICON_FONT is available to the shell."
  else
    echo -e "$CWR - $APHOTIC_ICON_FONT is still missing, so the shell will show icon names instead of icons."
    echo -e "$CWR   Fix it: sudo pacman -S --needed ttf-material-symbols-variable && fc-cache -f && systemctl --user restart aphotic-shell.service"
  fi
}
