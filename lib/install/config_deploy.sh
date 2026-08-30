#!/usr/bin/env bash
# lib/install/config_deploy.sh
set -euo pipefail

# Everything a config refresh needs: the Configs/ copy, the symlinks that
# must track repo edits, the user systemd units, the Claude Code hook
# wiring, and PATH. Deliberately stops short of anything needing sudo
# (SDDM theme, wayland-sessions) so --config-only never asks for a
# password -- extracted rather than duplicated so the sync path and the
# full install can never drift apart.
deploy_user_configs() {
  echo -e "$CNT - Copying config files..."
  CUSTOM_LUA="$HOME/.config/hypr/custom.lua"
  CUSTOM_LUA_BACKUP=""
  if [[ -f "$CUSTOM_LUA" ]]; then
    CUSTOM_LUA_BACKUP=$(mktemp)
    cp "$CUSTOM_LUA" "$CUSTOM_LUA_BACKUP"
  fi

  cp -R "$ROOT_DIR/Configs/"* "$HOME/.config/"

  # A handful of paths under Configs/ need to track repo edits directly
  # rather than sit as the one-shot copy above -- a plain `cp -R` means
  # any later edit (bug fixes included) silently stops matching what's
  # actually live, with zero indication anything drifted, until a full
  # reinstall. Not hypothetical: this exact drift is what silently broke
  # SUPER+SHIFT+A (intelligence), SUPER+CTRL+SHIFT+B (bar cycle),
  # SUPER+SHIFT+D (dnd), and SUPER+N/SUPER+Y (keybinds.lua stale since
  # before those binds existed); kept regenerating Colours.qml from an
  # old wallust template (docs/IN_FLIGHT.md item 3); and left the
  # Kvantum theme selector pointed at the pre-rename "Noctis" name.
  # Symlinking these closes the whole bug class instead of patching it
  # path by path as each instance is separately noticed. ln -sfn (not
  # -sf) so re-running this on an existing install replaces a stale
  # symlink/copy in place instead of nesting one inside the other.
  #
  # Configs/hypr/* except three files that must stay real, independent
  # copies rather than track the repo:
  #   - custom.lua: the user's own local override (see the backup/
  #     restore immediately below), meant to diverge per-machine.
  #   - monitors.lua: hardware config (output name, exact resolution,
  #     position, scale) is inherently per-machine too -- the repo's own
  #     copy is only a generic "output='', mode=preferred" placeholder.
  #     Symlinking this one was a real regression, caught live: it threw
  #     away this machine's pinned "Virtual-1, 1920x1080" for the
  #     placeholder's "preferred", which negotiated down to 1280x800.
  #   - hyprland.lua: install.sh appends `require("nvidia")` to it below
  #     when Nvidia is detected -- a symlink would write that append
  #     straight into the tracked repo file instead of a local copy, and
  #     (since cp -R can no longer "reset" a symlinked target the way it
  #     resets a plain file) re-running install.sh would keep appending
  #     duplicate require lines with nothing ever clearing them.
  for entry in "$ROOT_DIR/Configs/hypr/"*; do
    name="$(basename "$entry")"
    case "$name" in
      custom.lua|monitors.lua|hyprland.lua) continue ;;
    esac
    rm -rf "$HOME/.config/hypr/$name"
    ln -sfn "$entry" "$HOME/.config/hypr/$name"
  done
  chmod +x "$HOME/.config/hypr/scripts/"*

  rm -rf "$HOME/.config/wallust"
  ln -sfn "$ROOT_DIR/Configs/wallust" "$HOME/.config/wallust"

  # Just the selector file -- Kvantum/Aphotic/Aphotic.kvconfig alongside
  # it is wallust template *output* (wallust.toml's `kvantum` entry), not
  # repo source, and must stay a real file wallust can keep overwriting.
  mkdir -p "$HOME/.config/Kvantum"
  rm -f "$HOME/.config/Kvantum/kvantum.kvconfig"
  ln -sfn "$ROOT_DIR/Configs/Kvantum/kvantum.kvconfig" "$HOME/.config/Kvantum/kvantum.kvconfig"

  if [[ -n "$CUSTOM_LUA_BACKUP" ]]; then
    cp "$CUSTOM_LUA_BACKUP" "$CUSTOM_LUA"
    rm -f "$CUSTOM_LUA_BACKUP"
    echo -e "$CNT - Preserved your existing hypr/custom.lua"
  fi

  mkdir -p "$HOME/.local/bin"
  ln -sf "$ROOT_DIR/Configs/.local/bin/aphotic" "$HOME/.local/bin/aphotic"

  # The cp -R above just wiped modules/plugins/* (any installed
  # ui-surface plugin's QML module symlink) along with the rest of
  # quickshell/aphotic -- see docs/archive/PLUGIN_SYSTEM.md manifest v3.
  # Re-link them now; a no-op if no such plugin is installed.
  "$HOME/.local/bin/aphotic" plugin relink-ui-modules &>> "$INSTLOG" || true

  echo -e "$CNT - Enabling the Aphotic shell restart-supervision unit..."
  mkdir -p "$HOME/.config/systemd/user"
  # Same symlink treatment as above -- these three unit files are only
  # ever added to or edited in the repo, never hand-written per machine,
  # so there's no user-owned-copy case to preserve the way custom.lua
  # has one. Concretely bit already: aphotic-agent-usage.service/.timer
  # postdated this machine's last cp -R and were never installed at all
  # (`systemctl --user is-enabled` reported "not-found"), so the Live
  # Agent Activity Module silently never ran.
  for unit in "$ROOT_DIR/Configs/systemd/user/"*; do
    ln -sfn "$unit" "$HOME/.config/systemd/user/$(basename "$unit")"
  done
  systemctl --user daemon-reload &>> "$INSTLOG"
  systemctl --user enable aphotic-shell.service &>> "$INSTLOG" || echo -e "$CWR - Could not enable aphotic-shell.service; the shell will still start via Hyprland's exec-once but won't auto-restart on crash."
  # A --config-only run on a clone that has never been installed has no saved
  # layer list, and "no layers" must not be read as "the user turned ai off" --
  # that would strip hooks and disable a timer nobody asked to remove.
  if [[ "$CONFIG_ONLY" == "1" && "$LAYERS_KNOWN" != "1" ]]; then
    echo -e "$CWR - No aphotic.toml found; leaving the agent usage timer and Claude Code hooks exactly as they are."
  elif layer_selected "ai"; then
    echo -e "$CNT - Enabling the agent usage-tracking timer..."
    systemctl --user enable --now aphotic-agent-usage.timer &>> "$INSTLOG" || echo -e "$CWR - Could not enable aphotic-agent-usage.timer; the bar's agent popout will show stale/no usage data until it's enabled manually."
  else
    echo -e "$CNT - AI layer not selected; leaving the agent usage-tracking timer off."
    systemctl --user disable --now aphotic-agent-usage.timer &>> "$INSTLOG" || true
  fi
  echo -e "$CNT - Enabling the SDDM background sync timer..."
  systemctl --user enable --now aphotic-sddm-sync.timer &>> "$INSTLOG" || echo -e "$CWR - Could not enable aphotic-sddm-sync.timer; the SDDM login background will only update via the per-theme-change best-effort call, not this periodic catch-up. Enable manually with 'systemctl --user enable --now aphotic-sddm-sync.timer'."
  # Writing hooks into someone's ~/.claude/settings.json is not something to
  # do to a user who never asked for the agent stack, so it follows the `ai`
  # layer -- and de-selecting that layer on a re-run removes what a previous
  # run added rather than leaving it behind.
  if [[ "$CONFIG_ONLY" == "1" && "$LAYERS_KNOWN" != "1" ]]; then
    :
  elif layer_selected "ai"; then
    echo -e "$CNT - Configuring the Claude Code hook for live agent session tracking..."
    if command -v jq >/dev/null 2>&1; then
      configure_claude_code_hooks "$ROOT_DIR/Configs/.local/lib/aphotic/agent_hook.sh" &>> "$INSTLOG" || echo -e "$CWR - Could not update ~/.claude/settings.json; the bar's agent popout will only show session presence/count, not live per-session status. Wire it manually — see docs/AGENT_TRACKING.md."
    else
      echo -e "$CWR - jq not found; skipping Claude Code hook setup. Wire it manually — see docs/AGENT_TRACKING.md."
    fi
  elif command -v jq >/dev/null 2>&1; then
    echo -e "$CNT - AI layer not selected; removing any Aphotic Claude Code hook entries..."
    remove_claude_code_hooks "$ROOT_DIR/Configs/.local/lib/aphotic/agent_hook.sh" &>> "$INSTLOG" || echo -e "$CWR - Could not clean ~/.claude/settings.json; remove the aphotic agent_hook.sh entries by hand if they are still there."
  fi

  # Make sure `aphotic` (and anything else under ~/.local/bin) resolves on
  # PATH without relying on the optional zsh-activation step below, since
  # bash users need this too and Configs/.zshrc only lands on disk if they
  # opt in.
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [[ "$rc" == "$HOME/.zshrc" && ! -f "$rc" ]] && continue
    touch "$rc"
    if ! grep -qF '.local/bin' "$rc"; then
      printf '\n# Added by aphotic install.sh so ~/.local/bin (aphotic CLI) is on PATH\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
    fi
  done

  KVARCDARK_SVG="/usr/share/Kvantum/KvArcDark/KvArcDark.svg"
  mkdir -p "$HOME/.config/Kvantum/Aphotic"
  if [[ -f "$KVARCDARK_SVG" ]]; then
    cp "$KVARCDARK_SVG" "$HOME/.config/Kvantum/Aphotic/Aphotic.svg"
  else
    echo -e "$CWR - KvArcDark theme assets not found at $KVARCDARK_SVG (should ship with the kvantum package); Kvantum will fall back to its default style."
  fi

  if [[ "$ISNVIDIA" == "true" ]]; then
    echo -e '\nrequire("nvidia")' >> "$HOME/.config/hypr/hyprland.lua"
  fi
}

# The sugar-candy SDDM theme + Hyprland's wayland-sessions entry -- the only
# sudo-requiring pieces of "deploying configs", which is why they're kept
# out of deploy_user_configs() (used as-is by --config-only, which must
# never ask for a password).
setup_login_manager_theme() {
  echo -e "$CNT - Setting up the login screen..."
  sudo tar -xf "$ROOT_DIR/src/sugar-candy.tar.gz" -C /usr/share/sddm/themes/
  sudo chown -R "$USER:$USER" /usr/share/sddm/themes/sugar-candy
  sudo mkdir -p /etc/sddm.conf.d
  if ! sudo grep -qF "Current=sugar-candy" /etc/sddm.conf.d/10-theme.conf 2>/dev/null; then
    echo -e "[Theme]\nCurrent=sugar-candy" | sudo tee -a /etc/sddm.conf.d/10-theme.conf &>> "$INSTLOG"
  fi
  local wldir=/usr/share/wayland-sessions
  [[ -d "$wldir" ]] || sudo mkdir -p "$wldir"
  sudo cp "$ROOT_DIR/src/hyprland.desktop" /usr/share/wayland-sessions/
}

install_vscode_extensions() {
  echo -e "$CNT - Adding VScode Extensions..."
  mkdir -p "$HOME/.vscode"
  tar -xf "$ROOT_DIR/src/extensions.tar.gz" -C "$HOME/.vscode/"
}

config_sync() {
  TOTAL_STAGES=3
  print_stage 1 "Backup"
  if [[ "$NO_BACKUP" != "1" ]]; then
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    echo -e "$CNT - Snapshotting existing configs..."
    mapfile -t CONFIG_DIRS < <(find "$ROOT_DIR/Configs" -maxdepth 1 -mindepth 1 -not -name '.*' -exec basename {} \;)
    snapshot_config "$TIMESTAMP" "${CONFIG_DIRS[@]}"
    prune_backups "$KEEP_BACKUPS"
    echo -e "$COK - Backup saved under $(backup_root)/$TIMESTAMP"
  else
    echo -e "$CWR - Skipping backup (--no-backup)."
  fi

  print_stage 2 "Syncing configs"
  deploy_user_configs

  print_stage 3 "Restarting the shell"
  if systemctl --user is-enabled aphotic-shell.service &>/dev/null; then
    systemctl --user restart aphotic-shell.service &>> "$INSTLOG" && echo -e "$COK - Restarted aphotic-shell.service." || echo -e "$CWR - Could not restart aphotic-shell.service; restart Quickshell manually (SUPER+B)."
  else
    echo -e "$CNT - aphotic-shell.service isn't enabled; restart Quickshell manually (SUPER+B) to pick up the new config."
  fi

  echo -e "\n\e[1;32m── Config sync summary ──\e[0m"
  echo -e "  Layers:        ${LAYERS:-none}"
  echo -e "  Configs:       copied from $ROOT_DIR/Configs"
  echo -e "  Packages:      untouched"
  echo -e "  aphotic.toml:  left as-is"
  echo -e "$COK - Config sync complete."

  "$HOME/.local/bin/aphotic" whatsnew &>> "$INSTLOG" || true
}
