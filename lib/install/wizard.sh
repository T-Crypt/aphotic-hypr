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

  local IFS=","
  echo "${layers[*]}"
}

prompt_theme() {
  local answer
  read -rp "Theme? (default): " answer
  echo "${answer:-default}"
}

prompt_bar_position() {
  local answer
  read -rp "Bar position? [top/left] (top): " answer
  answer="${answer:-top}"
  if [[ "$answer" != "top" && "$answer" != "left" ]]; then
    echo "top"
  else
    echo "$answer"
  fi
}

write_noctis_toml() {
  local path="$1" profile="$2" layers="$3" theme="$4" bar_position="$5" nvidia="$6" aur_helper="$7" installed_at="$8"

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

[bar]
position = "$bar_position"

[system]
nvidia = $nvidia
aur_helper = "$aur_helper"
EOF
}
