#!/usr/bin/env bash
# lib/install/backup.sh
set -euo pipefail

backup_root() {
  echo "${APHOTIC_BACKUP_ROOT:-$HOME/.config-backup}"
}

snapshot_config() {
  local timestamp="$1"
  shift
  local dirs=("$@")
  local dest
  dest="$(backup_root)/$timestamp"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "[dry-run] would snapshot ${dirs[*]} to $dest"
    return 0
  fi

  mkdir -p "$dest"
  for d in "${dirs[@]}"; do
    if [[ -e "$HOME/.config/$d" ]]; then
      cp -R "$HOME/.config/$d" "$dest/"
    fi
  done
}

prune_backups() {
  local keep="$1"
  local root
  root="$(backup_root)"
  [[ -d "$root" ]] || return 0

  local backups
  mapfile -t backups < <(ls -1 "$root" | sort)
  local total=${#backups[@]}
  (( total <= keep )) && return 0

  local excess=$(( total - keep ))
  for ((i = 0; i < excess; i++)); do
    rm -rf "${root:?}/${backups[$i]}"
  done
}
