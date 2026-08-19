#!/bin/bash
# uninstall.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT_DIR/lib/install/python.sh"
source "$ROOT_DIR/lib/install/backup.sh"

NOCTIS_TOML="$ROOT_DIR/noctis.toml"
PURGE_PACKAGES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge-packages) PURGE_PACKAGES=1; shift ;;
    --noctis-toml) NOCTIS_TOML="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: ./uninstall.sh [--purge-packages] [--noctis-toml <path>]"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ ! -f "$NOCTIS_TOML" ]]; then
  echo "No noctis.toml found ($NOCTIS_TOML) — nothing recorded to uninstall."
  exit 1
fi

PYTHON_BIN=$(resolve_python_bin)

latest_backup() {
  local root
  root="$(backup_root)"
  [[ -d "$root" ]] || return 1
  ls -1 "$root" | sort | tail -n 1
}

restore_latest_backup() {
  local latest
  latest=$(latest_backup) || { echo "No backups found to restore."; return 1; }
  echo "Restoring backup: $latest"
  cp -R "$(backup_root)/$latest/." "$HOME/.config/"
}

read -rep $'Restore most recent backup? (y,n) ' CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "Aborted, no changes made."
  exit 0
fi

restore_latest_backup || exit 1

if [[ "$PURGE_PACKAGES" == "1" ]]; then
  AUR_HELPER=$("$PYTHON_BIN" -c "import tomllib; print(tomllib.load(open('$NOCTIS_TOML','rb'))['system']['aur_helper'])")
  read -rep $"This will run $AUR_HELPER -R against every package this profile installed (including custom_apps.lst entries). Continue? (y,n) " PURGE_CONFIRM
  if [[ "$PURGE_CONFIRM" == "y" || "$PURGE_CONFIRM" == "Y" ]]; then
    PROFILE=$("$PYTHON_BIN" -c "import tomllib; print(tomllib.load(open('$NOCTIS_TOML','rb'))['install']['profile'])")
    LAYERS=$("$PYTHON_BIN" -c "import tomllib; print(','.join(tomllib.load(open('$NOCTIS_TOML','rb'))['install']['layers']))")
    layer_args=""
    if [[ -n "$LAYERS" ]]; then
      IFS=',' read -ra layer_names <<< "$LAYERS"
      paths=()
      for name in "${layer_names[@]}"; do
        paths+=("$ROOT_DIR/profiles/layers/$name.toml")
      done
      layer_args=$(IFS=,; echo "${paths[*]}")
    fi
    packages=$("$PYTHON_BIN" "$ROOT_DIR/lib/toml/merge.py" --base "$ROOT_DIR/profiles/base/$PROFILE.toml" --layers "$layer_args" --custom-apps "$ROOT_DIR/profiles/custom_apps.lst" --field main)
    while IFS= read -r pkg; do
      [[ -n "$pkg" ]] && "$AUR_HELPER" -R --noconfirm "$pkg"
    done <<< "$packages"
  fi
fi

echo "Uninstall complete."
