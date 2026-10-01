#!/bin/bash
# uninstall.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$ROOT_DIR/lib/install/python.sh"
source "$ROOT_DIR/lib/install/backup.sh"

APHOTIC_TOML="$ROOT_DIR/aphotic.toml"
PURGE_PACKAGES=0
ASSUME_YES=0

# One prompt helper so every question in here has the same answer to --yes.
# --yes means yes to what the prompt itself offers: it restores the backup,
# and it removes the assistant's model, the greeter scaffold and the profile's
# packages if they are there. It never reaches past a guard that exists to
# stop damage, so greetd stays refused while it is the active display manager.
confirm() {
  local prompt="$1" answer
  if [[ "$ASSUME_YES" == "1" ]]; then
    answer="y"
  else
    read -rep "$prompt" answer
  fi
  [[ "$answer" == "y" || "$answer" == "Y" ]]
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge-packages) PURGE_PACKAGES=1; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --aphotic-toml) APHOTIC_TOML="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: ./uninstall.sh [--yes] [--purge-packages] [--aphotic-toml <path>]"
      echo
      echo "  --yes, -y          answer every prompt with yes, for a non-interactive run"
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ ! -f "$APHOTIC_TOML" ]]; then
  echo "No aphotic.toml found ($APHOTIC_TOML) — nothing recorded to uninstall."
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

if ! confirm $'Restore most recent backup? (y,n) '; then
  echo "Aborted, no changes made."
  exit 0
fi

restore_latest_backup || exit 1

if [[ -L "$HOME/.local/bin/aphotic" ]]; then
  rm -f "$HOME/.local/bin/aphotic"
  echo "Removed ~/.local/bin/aphotic"
fi

if systemctl --user list-unit-files aphotic-shell.service &>/dev/null; then
  systemctl --user disable --now aphotic-shell.service &>/dev/null || true
  echo "Disabled aphotic-shell.service"
fi

for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  [[ -f "$rc" ]] || continue
  sed -i '/# Added by aphotic install.sh so ~\/.local\/bin (aphotic CLI) is on PATH/,+1d' "$rc"
done

ASSISTANT_CONFIG="$HOME/.config/aphotic/ai-config.json"
if [[ -f "$ASSISTANT_CONFIG" ]]; then
  ASSISTANT_MODEL=$("$PYTHON_BIN" -c 'import json, sys
try:
    data = json.load(open(sys.argv[1]))
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
print(data.get("assistantModel", "") if data.get("assistantEnabled") else "")' "$ASSISTANT_CONFIG")
  if [[ -n "$ASSISTANT_MODEL" ]]; then
    if confirm $"Remove the Aphotic Assistant's pulled model ($ASSISTANT_MODEL)? Your other Ollama models are untouched. (y,n) "; then
      if command -v ollama >/dev/null 2>&1; then
        ollama rm "$ASSISTANT_MODEL" || echo "Could not remove $ASSISTANT_MODEL via 'ollama rm' -- it may already be gone, or Ollama may not be running."
      else
        echo "ollama CLI not found; remove $ASSISTANT_MODEL yourself (e.g. via Settings -> AI, or the Ollama API) if it's still pulled."
      fi
      "$PYTHON_BIN" -c 'import json, sys
path = sys.argv[1]
try:
    data = json.load(open(path))
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
data["assistantEnabled"] = False
data["assistantModel"] = ""
data["assistantInstalledAt"] = ""
json.dump(data, open(path, "w"), indent=2)' "$ASSISTANT_CONFIG"
      echo "Aphotic Assistant removed."
    fi
  fi
fi

GREETER_DIRS=(/etc/xdg/quickshell/aphotic-greeter /etc/greetd/aphotic /etc/aphotic/greeter)

# The scaffold is keyed off a shell.qml or hyprland-greeter.lua that really
# exists, which is why the branch above never ran in CI: the runner has
# neither. GREETER_PROBE_DIR lets the test point that check at a seeded tree
# so the prompt and the guard it sits behind are covered everywhere, not only
# on a box where Aphotic happens to be installed.
GREETER_PROBE_DIR="${GREETER_PROBE_DIR:-/etc}"

if [[ -f "$GREETER_PROBE_DIR/xdg/quickshell/aphotic-greeter/shell.qml" \
   || -f "$GREETER_PROBE_DIR/greetd/aphotic/hyprland-greeter.lua" ]]; then
  # Refuse outright, before ever asking, if greetd is the active display
  # manager -- deleting /etc/greetd/aphotic/hyprland-greeter.lua out from
  # under a live greetd.service leaves its config.toml pointing at a
  # compositor config that no longer exists, and the next boot/VT switch
  # gets no login screen at all with no TTY-accessible warning printed in
  # advance. Checked here, not just documented after the fact.
  GREETD_ACTIVE=0
  if systemctl is-enabled greetd.service &>/dev/null || systemctl is-active greetd.service &>/dev/null; then
    GREETD_ACTIVE=1
  fi

  if [[ "$GREETD_ACTIVE" == "1" ]] && pacman -Qq sddm &>/dev/null; then
    echo "Putting sddm back as the login screen..."
    sudo systemctl disable greetd.service &>/dev/null || true
    if [[ -f /etc/greetd/config.toml.aphotic-backup ]]; then
      sudo mv /etc/greetd/config.toml.aphotic-backup /etc/greetd/config.toml
    fi
    sudo systemctl enable sddm.service &>/dev/null && GREETD_ACTIVE=0
  fi

  # The refusal above is a guard, not a prompt, so --yes does not reach it:
  # confirm() is only ever called from this else, never in place of the check.
  if [[ "$GREETD_ACTIVE" == "1" ]]; then
    echo "greetd is currently enabled/active as the display manager -- not touching the greeter scaffold."
    echo "Run 'aphotic displaymanager switch sddm --confirm-tested' first to restore sddm, then re-run uninstall.sh to remove the scaffold."
  else
    if confirm $'Remove the Aphotic greeter (/etc/xdg/quickshell/aphotic-greeter, /etc/greetd/aphotic, /etc/aphotic/greeter)? sddm is unaffected either way. (y,n) '; then
      sudo rm -rf "$GREETER_PROBE_DIR/xdg/quickshell/aphotic-greeter" \
                 "$GREETER_PROBE_DIR/greetd/aphotic" \
                 "$GREETER_PROBE_DIR/aphotic/greeter"
      systemctl --user disable --now aphotic-greeter-sync.timer &>/dev/null || true
      echo "Removed the Aphotic greeter."
    fi
  fi
fi

if [[ "$PURGE_PACKAGES" == "1" ]]; then
  AUR_HELPER=$("$PYTHON_BIN" -c 'import sys, tomllib; print(tomllib.load(open(sys.argv[1], "rb"))["system"]["aur_helper"])' "$APHOTIC_TOML")
  if confirm $"This will run $AUR_HELPER -R against every package this profile installed (including custom_apps.lst entries). Continue? (y,n) "; then
    PROFILE=$("$PYTHON_BIN" -c 'import sys, tomllib; print(tomllib.load(open(sys.argv[1], "rb"))["install"]["profile"])' "$APHOTIC_TOML")
    LAYERS=$("$PYTHON_BIN" -c 'import sys, tomllib; print(",".join(tomllib.load(open(sys.argv[1], "rb"))["install"]["layers"]))' "$APHOTIC_TOML")
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
