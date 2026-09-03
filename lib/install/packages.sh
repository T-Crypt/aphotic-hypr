#!/usr/bin/env bash
# lib/install/packages.sh
set -euo pipefail

_elapsed_str() {
  local s="$1"
  if ((s < 60)); then
    printf '%ds' "$s"
  else
    printf '%dm%02ds' $((s / 60)) $((s % 60))
  fi
}

# Last thing the detached install actually wrote, normalized for a single
# status line: pacman/makepkg redraw with bare CRs and color escapes, and
# the tail of the log is the only place the current activity ("burpsuite-...
# downloading...") is visible at all.
_install_activity_line() {
  [[ -n "${INSTLOG:-}" && -r "${INSTLOG:-}" ]] || return 0
  tail -c 4096 "$INSTLOG" 2>/dev/null \
    | tr '\r' '\n' \
    | sed $'s/\033\\[[0-9;?]*[a-zA-Z]//g' \
    | grep -v '^[[:space:]]*$' \
    | tail -n 1 \
    | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# The install runs detached with all of its output in $INSTLOG, so without
# the package name, an elapsed clock and that log tail on the spinner line
# there is nothing on screen to distinguish a slow package from a hang --
# and some are very slow (burpsuite pulls a ~1 GB transaction with its
# JDK). Liveness is `kill -0`, not `ps | grep "$pid"`: that matched the pid
# digits anywhere in ps's output, including inside another process's pid or
# its TIME column.
show_progress() {
  local pid="$1" label="${2:-}"
  local start=$SECONDS
  if [[ -t 1 ]]; then
    local frames='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0 detail="" width elapsed line
    width=$(tput cols 2>/dev/null) || width=80
    [[ "$width" =~ ^[0-9]+$ ]] && ((width > 20)) || width=80
    while kill -0 "$pid" 2>/dev/null; do
      ((i % 10 == 0)) && detail=$(_install_activity_line || true)
      elapsed=$(_elapsed_str $((SECONDS - start)))
      line="${frames:i++%${#frames}:1} ${label:+$label }[$elapsed]${detail:+ -- $detail}"
      printf '\r\e[K%s' "${line:0:width - 1}"
      sleep 0.1
    done
    printf '\r\e[K'
  else
    echo -n "working..."
    while kill -0 "$pid" 2>/dev/null; do
      sleep 2
    done
    echo ""
  fi
}

install_software() {
  if "$AUR_HELPER" -Q "$1" &>> /dev/null ; then
    echo -e "$COK - $1 is already installed."
    return 0
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "$CNT - [dry-run] would install $1"
    return 0
  fi
  # On a terminal the spinner line carries the name itself; only the
  # non-TTY branch (no spinner) needs it printed up front.
  [[ -t 1 ]] || echo -en "$CNT - Now installing $1 "
  "$AUR_HELPER" -S --noconfirm "$1" &>> "$INSTLOG" &
  show_progress $! "installing $1"
  if "$AUR_HELPER" -Q "$1" &>> /dev/null ; then
    echo -e "$COK - $1 was installed."
  else
    echo -e "$CER - $1 install had failed, please check the install.log"
    exit 1
  fi
}

# Installs each newline-separated package name in $1, skipping blank lines.
install_package_list() {
  local pkgs="$1"
  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] && install_software "$pkg"
  done <<< "$pkgs"
}
