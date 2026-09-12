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

# Layer/custom-apps packages that failed and were skipped. Reported once
# at the end of the run so the list doesn't scroll away behind the rest of
# the install.
FAILED_OPTIONAL_PACKAGES=()

_issue_url_for() {
  local pkg="${1//+/%2B}"
  printf '%s/new?title=Install%%20package%%20failed:%%20%s' "$APHOTIC_ISSUES_URL" "$pkg"
}

_package_in_list() {
  [[ $'\n'"$2"$'\n' == *$'\n'"$1"$'\n'* ]]
}

# Installed-state and repo lookups go to pacman directly. Routing them
# through "$AUR_HELPER" meant an empty helper (a failed yay bootstrap, which
# install.sh only warns about) ran as the empty command: every package died
# with a bare "command not found" in the log, starting with the first entry
# of the base prep list, qt5-wayland, which is a plain repo package pacman
# would have installed without an AUR helper at all.
_pkg_installed() {
  pacman -Qq "$1" &>/dev/null
}

_pkg_in_repos() {
  pacman -Si "$1" &>/dev/null
}

# Omarchy's pacman-guard hook wants its documented opt-out on direct pacman
# calls (same reason install.sh's -Syu carries it).
_pacman_install_cmd() {
  PKG_INSTALL_CMD=(sudo)
  [[ "${DETECTED_OMARCHY:-0}" == "1" ]] && PKG_INSTALL_CMD+=(env OMARCHY_ALLOW_DIRECT_PACMAN=1)
  PKG_INSTALL_CMD+=(pacman -S --needed --noconfirm)
  return 0
}

# Fills PKG_INSTALL_CMD with what should install <package>: pacman for
# anything a configured repo carries, the AUR helper otherwise. Preferring
# pacman for repo packages also keeps a helper from fuzzy-matching a repo
# name onto a broken AUR package (the lib32-gamemode-git trap install.sh's
# multilib step already calls out). With no helper at all, pacman still gets
# the attempt so the log carries a real "target not found" rather than a
# "command not found" that says nothing about the package.
_resolve_install_cmd() {
  local pkg="$1"
  if [[ -z "${AUR_HELPER:-}" ]] || _pkg_in_repos "$pkg"; then
    _pacman_install_cmd
    return 0
  fi
  # --removemake: AUR builds (wallust-git needs rust, python-pyamdgpuinfo
  # needs cython/python-build/python-installer, etc.) otherwise leave their
  # makedepends behind as orphans forever -- harmless, but Omarchy's own
  # `omarchy update` surfaces exactly those as "orphan packages" and offers
  # to remove them, which reads as if it's targeting Aphotic's own install.
  PKG_INSTALL_CMD=("$AUR_HELPER" -S --noconfirm --removemake)
}

# A failure used to print nothing but "check the install.log" -- on a log
# that is megabytes of pacman progress bars, the one line that says why
# (an unresolved target, a bad signature, a 404 off a stale mirror) is
# unfindable. Surface it where the failure is reported.
_print_install_failure_detail() {
  [[ -n "${INSTLOG:-}" && -r "${INSTLOG:-}" ]] || return 0
  local detail
  detail=$(tail -n 200 "$INSTLOG" 2>/dev/null \
    | tr '\r' '\n' \
    | sed $'s/\033\\[[0-9;?]*[a-zA-Z]//g' \
    | grep -iE '^[[:space:]]*(error|warning|::.*failed|.*: command not found)' \
    | tail -n 5)
  [[ -n "$detail" ]] || return 0
  echo -e "$CER   Last error lines from $INSTLOG:"
  while IFS= read -r line; do
    echo -e "$CER     $line"
  done <<< "$detail"
}

# install_software <package> [required|optional]
#
# Defaults to "required" -- every direct caller (hyprland, the NVIDIA
# driver) is something the desktop cannot come up without, and those still
# abort the run. "optional" is for packages a layer or custom_apps.lst
# added: those are reported with an issue link and skipped.
install_software() {
  local pkg="$1" requirement="${2:-required}"
  if _pkg_installed "$pkg"; then
    echo -e "$COK - $pkg is already installed."
    return 0
  fi
  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "$CNT - [dry-run] would install $pkg"
    return 0
  fi
  # On a terminal the spinner line carries the name itself; only the
  # non-TTY branch (no spinner) needs it printed up front.
  [[ -t 1 ]] || echo -en "$CNT - Now installing $pkg "
  # --removemake: AUR builds (wallust needs rust, python-pyamdgpuinfo
  # needs cython/python-build/python-installer, etc.) otherwise leave their
  # makedepends behind as orphans forever -- harmless, but Omarchy's own
  # `omarchy update` surfaces exactly those as "orphan packages" and offers
  # to remove them, which reads as if it's targeting Aphotic's own install.
  "$AUR_HELPER" -S --noconfirm --removemake "$pkg" &>> "$INSTLOG" &
  local pkg_pid=$!
  show_progress "$pkg_pid" "installing $pkg"
  local rc=0
  wait "$pkg_pid" 2>/dev/null || rc=$?

  if _pkg_installed "$pkg"; then
    echo -e "$COK - $pkg was installed."
    return 0
  fi

  # 130/143: the helper died from the user's Ctrl+C or a TERM, not from
  # anything wrong with the package. Now that an optional failure no
  # longer aborts, skipping on a signal would make an interrupt
  # unstoppable -- it would just walk to the next package.
  if ((rc == 130 || rc == 143)); then
    echo -e "$CER - Interrupted while installing $pkg -- stopping here. Nothing further will be installed."
    exit "$rc"
  fi

  # An AUR package with no helper on PATH is its own diagnosis, and the
  # generic "submit an issue" line sends the user down the wrong path.
  local why=""
  if [[ -z "${AUR_HELPER:-}" ]] && ! _pkg_in_repos "$pkg"; then
    why="$pkg isn't in any configured repo and no AUR helper (yay/paru) is on PATH, so nothing could build it."
  fi

  if [[ "$requirement" == "optional" ]]; then
    FAILED_OPTIONAL_PACKAGES+=("$pkg")
    echo -e "$CER - Error installing -- $pkg -- Submit issue request for install package -- $pkg"
    [[ -n "$why" ]] && echo -e "$CWR   $why"
    echo -e "$CWR   Skipped, the install continues. Output: $INSTLOG"
    echo -e "$CWR   $(_issue_url_for "$pkg")"
    return 0
  fi

  echo -e "$CER - $pkg install had failed, please check the install.log"
  echo -e "$CER   $pkg is required, so the install can't continue without it."
  if [[ -n "$why" ]]; then
    echo -e "$CER   $why"
  else
    _print_install_failure_detail
  fi
  echo -e "$CER   Submit issue request for install package -- $pkg"
  echo -e "$CER   $(_issue_url_for "$pkg")"
  exit 1
}

report_failed_optional_packages() {
  ((${#FAILED_OPTIONAL_PACKAGES[@]} > 0)) || return 0
  local pkg
  echo -e "\n\e[1;31m── ${#FAILED_OPTIONAL_PACKAGES[@]} optional package(s) failed to install ──\e[0m"
  echo -e "  None of these are part of the shell itself, so the install finished without them."
  for pkg in "${FAILED_OPTIONAL_PACKAGES[@]}"; do
    echo -e "  Error installing -- $pkg -- Submit issue request for install package -- $pkg"
    echo -e "    $(_issue_url_for "$pkg")"
  done
  echo -e "  Full output for each failure: $INSTLOG"
  echo -e "  To retry them after a fix: re-run ./install.sh with the same --with layers."
}

# install_package_list <newline-separated packages> [required-subset]
#
# Anything in <required-subset> is fatal on failure; everything else in
# the list came from a layer or custom_apps.lst and is reported-and-
# skipped. Omitting the subset makes every package required, which is
# what the pre-existing single-argument behavior was.
install_package_list() {
  local pkgs="$1" required="${2-}" pkg requirement
  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] || continue
    if [[ -z "$required" ]] || _package_in_list "$pkg" "$required"; then
      requirement="required"
    else
      requirement="optional"
    fi
    install_software "$pkg" "$requirement"
  done <<< "$pkgs"
}

# Dry-run plan rendering, so the plan says which failures would be fatal.
print_package_plan() {
  local pkgs="$1" required="${2-}" pkg
  while IFS= read -r pkg; do
    [[ -n "$pkg" ]] || continue
    if [[ -z "$required" ]] || _package_in_list "$pkg" "$required"; then
      echo "    - $pkg"
    else
      echo "    - $pkg (optional: a failure is reported, not fatal)"
    fi
  done <<< "$pkgs"
}
