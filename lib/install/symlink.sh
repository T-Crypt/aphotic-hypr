#!/usr/bin/env bash
set -euo pipefail

install_config_dir() {
  local src="$1"
  local dest="$2"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "[dry-run] would copy $src -> $dest"
    return 0
  fi

  mkdir -p "$(dirname "$dest")"
  cp -R "$src" "$dest"
}

link_active_variant() {
  local variant_dir="$1"
  local link_path="$2"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo "[dry-run] would symlink $link_path -> $variant_dir"
    return 0
  fi

  rm -f "$link_path"
  ln -s "$variant_dir" "$link_path"
}
