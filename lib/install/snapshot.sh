#!/usr/bin/env bash

_snapshot_status_url() {
  printf '%s\n' "${APHOTIC_CANARY_STATUS_URL:-https://raw.githubusercontent.com/T-Crypt/Aphotic-Hypr/canary-status/status.json}"
}

_snapshot_fetch_status() {
  curl -fsSL --max-time 10 "$(_snapshot_status_url)"
}

_snapshot_valid_date() {
  [[ "${1:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}

snapshot_last_green() {
  local snapshot_date="${APHOTIC_SNAPSHOT_DATE:-}" status
  if [[ -z "$snapshot_date" ]]; then
    status=$(_snapshot_fetch_status 2>/dev/null) || return 0
    snapshot_date=$(sed -n 's/.*"last_green"[[:space:]]*:[[:space:]]*"\([0-9][0-9-]*\)".*/\1/p' <<< "$status" | awk 'NR == 1 { print; exit }')
  fi
  _snapshot_valid_date "$snapshot_date" && printf '%s\n' "$snapshot_date"
  return 0
}

_snapshot_package_is_official() {
  local info repo
  if ! info=$(LC_ALL=C pacman -Si "$1" 2>/dev/null); then
    # Gone from today's repos ("target not found") is the case the archive is
    # for; only refuse when the AUR carries it.
    curl -fsS --max-time 10 "https://aur.archlinux.org/rpc/v5/info?arg%5B%5D=$1" 2>/dev/null \
      | grep -q '"resultcount":0'
    return
  fi
  repo=$(awk -F: '
    /^[[:space:]]*Repository[[:space:]]*:/ {
      value = $2
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' <<< "$info")
  [[ "$repo" == "core" || "$repo" == "extra" || "$repo" == "multilib" ]]
}

_snapshot_write_pacman_config() {
  local source_config="$1" output_config="$2" snapshot_date="$3"
  local year month day archive
  _snapshot_valid_date "$snapshot_date" || return 1
  [[ -r "$source_config" ]] || return 1
  IFS=- read -r year month day <<< "$snapshot_date"
  archive="https://archive.archlinux.org/repos/$year/$month/$day/\$repo/os/\$arch"

  awk -v archive="$archive" '
    BEGIN { mode = "preamble" }
    /^\[[^]]+\][[:space:]]*$/ {
      section = $0
      if (section == "[options]") {
        mode = "options"
        print
      } else if (section == "[core]" || section == "[extra]" || section == "[multilib]") {
        mode = "repo"
        print
        print "Server = " archive
      } else {
        mode = "drop"
      }
      next
    }
    mode == "preamble" || mode == "options" { print; next }
    mode == "repo" {
      if ($0 ~ /^[[:space:]]*(Include|Server)[[:space:]]*=/) next
      print
    }
  ' "$source_config" > "$output_config"
}

_snapshot_record_state() {
  local snapshot_date="$1"
  shift
  local state_dir="${XDG_STATE_HOME:-${HOME:-}/.local/state}/aphotic"
  local state_file="$state_dir/snapshot" previous_date="" previous_packages=""
  local package candidate state_tmp
  local -a packages=()

  if [[ -r "$state_file" ]]; then
    previous_date=$(sed -n 's/^snapshot=//p' "$state_file" | awk 'NR == 1 { print; exit }')
    previous_packages=$(sed -n 's/^snapshot_packages=//p' "$state_file" | awk 'NR == 1 { print; exit }')
  fi
  if [[ "$previous_date" == "$snapshot_date" && -n "$previous_packages" ]]; then
    read -r -a packages <<< "$previous_packages"
  fi
  for candidate in "$@"; do
    for package in "${packages[@]}"; do
      [[ "$package" == "$candidate" ]] && continue 2
    done
    packages+=("$candidate")
  done

  mkdir -p "$state_dir" || return 1
  state_tmp=$(mktemp "$state_dir/.snapshot.XXXXXX") || return 1
  if ! {
    printf 'snapshot=%s\n' "$snapshot_date"
    printf 'snapshot_packages=%s\n' "${packages[*]}"
  } > "$state_tmp"; then
    rm -f "$state_tmp"
    return 1
  fi
  chmod 600 "$state_tmp"
  mv -f "$state_tmp" "$state_file"
}

_snapshot_install_packages() {
  local snapshot_date="$1"
  shift
  local -a packages=("$@")
  local -a pacman_cmd=(sudo)
  local config_file rc=0 package_list
  ((${#packages[@]} > 0)) || return 1
  _snapshot_valid_date "$snapshot_date" || return 1
  package_list="${packages[*]}"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '%b\n' "${CNT:-[NOTE]} - [dry-run] would install $package_list with a full system transaction from the $snapshot_date archive."
    return 0
  fi

  config_file=$(mktemp "${TMPDIR:-/tmp}/aphotic-pacman.XXXXXX.conf") || return 1
  if ! _snapshot_write_pacman_config "${APHOTIC_PACMAN_CONF:-/etc/pacman.conf}" "$config_file" "$snapshot_date"; then
    rm -f "$config_file"
    return 1
  fi
  [[ "${DETECTED_OMARCHY:-0}" == "1" ]] && pacman_cmd+=(env OMARCHY_ALLOW_DIRECT_PACMAN=1)
  pacman_cmd+=(pacman --config "$config_file" -Syuu --noconfirm --needed)
  "${pacman_cmd[@]}" "${packages[@]}" &>> "${INSTLOG:-install.log}" || rc=$?
  rm -f "$config_file"
  ((rc == 0)) || return "$rc"

  _snapshot_record_state "$snapshot_date" "${packages[@]}" || return 1
  APHOTIC_ACTIVE_SNAPSHOT_DATE="$snapshot_date"
  printf '%b\n' "${COK:-[OK]} - System packages now use the $snapshot_date snapshot."
}

snapshot_install() {
  local package="$1" snapshot_date="$2"
  _snapshot_install_packages "$snapshot_date" "$package"
}

_snapshot_install_active() {
  snapshot_install "$1" "${APHOTIC_ACTIVE_SNAPSHOT_DATE:-}"
}

snapshot_offer() {
  local -a packages=("$@")
  local package snapshot_date answer subject verb
  ((${#packages[@]} > 0)) || return 1

  for package in "${packages[@]}"; do
    if ! _snapshot_package_is_official "$package"; then
      printf '%b\n' "${CWR:-[WARNING]} - $package is not in an official repository. AUR packages cannot come from the Arch Linux Archive."
      return 1
    fi
  done

  snapshot_date=$(snapshot_last_green)
  _snapshot_valid_date "$snapshot_date" || return 1
  subject="${packages[*]}"
  verb="fails"
  ((${#packages[@]} > 1)) && verb="fail"
  printf '%b\n' "${CWR:-[WARNING]} - $subject $verb to install from today's repositories."
  printf '%b\n' "${CNT:-[NOTE]} - You can use the $snapshot_date archive, the last day every Aphotic package installed cleanly."
  printf '%b\n' "${CNT:-[NOTE]} - Pacman installs that day's versions of the whole system in one transaction, so you do not get a partial upgrade. A later 'sudo pacman -Syu' returns to current versions after the upstream fix lands."

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    _snapshot_install_packages "$snapshot_date" "${packages[@]}"
    return $?
  fi
  if [[ "${APHOTIC_SNAPSHOT_FALLBACK:-0}" != "1" ]]; then
    [[ -t 0 ]] || return 1
    printf 'Install from the %s archive? [y/N] ' "$snapshot_date"
    IFS= read -r answer || answer=""
    [[ "$answer" =~ ^[Yy]$ ]] || return 1
  fi
  _snapshot_install_packages "$snapshot_date" "${packages[@]}"
}
