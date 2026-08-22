#!/usr/bin/env bash
set -euo pipefail

prompt_profile() {
  local answer
  read -rp "Profile? [minimal/full] (full): " answer
  answer="${answer:-full}"
  if [[ "$answer" != "minimal" && "$answer" != "full" ]]; then
    echo "full"
  else
    echo "$answer"
  fi
}

prompt_layers() {
  local layers=()
  local answer

  read -rp "Enable gaming layer? [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]] && layers+=("gaming")

  read -rp "Enable dev layer? [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]] && layers+=("dev")

  read -rp "Enable ai layer? [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]] && layers+=("ai")

  read -rp "Enable exploit layer? Adds the BlackArch repo -- less stable than Arch's official repos, see docs/exploit-layer.md [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]] && layers+=("exploit")

  local IFS=","
  echo "${layers[*]}"
}

prompt_theme() {
  local answer
  read -rp "Theme? (default): " answer
  echo "${answer:-default}"
}

write_aphotic_toml() {
  local path="$1" profile="$2" layers="$3" theme="$4" nvidia="$5" aur_helper="$6" installed_at="$7"

  local layers_toml="[]"
  if [[ -n "$layers" ]]; then
    layers_toml="[$(echo "$layers" | sed -E 's/([^,]+)/"\1"/g; s/,/, /g')]"
  fi

  cat > "$path" <<EOF
[install]
profile = "$profile"
layers = $layers_toml
installed_at = "$installed_at"

[theme]
name = "$theme"

[system]
nvidia = $nvidia
aur_helper = "$aur_helper"
EOF
}
