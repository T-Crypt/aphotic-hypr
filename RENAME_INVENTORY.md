# Rename Inventory — Noctis → Aphotic

Working checklist captured before/during the rename pass on branch
`rename/aphotic-hypr`. See `RENAME_REPORT.md` for the final summary and
validation results.

> **Correction note:** the very first repo-wide grep run before touching
> anything used a case-sensitive `noctis` pattern (no `-i`), so it missed
> files that only contained `Noctis`/`NOCTIS` casing. That gap was caught
> during the content-substitution pass and closed — the "Uppercase/title-case
> only misses" section below lists exactly what the initial pass would have
> skipped. The final validation sweep (Step 6) *was* case-insensitive and is
> the authoritative list.

## Filename/path matches (case-insensitive)

```
assets/noctis-banner.svg
assets/noctis-dull.svg
assets/noctis_home.png
assets/noctis-logo.svg
assets/noctis-orbit.svg
Configs/.local/bin/noctis
Configs/.local/lib/noctis
Configs/quickshell/noctis
Configs/systemd/user/noctis-shell.service
Configs/wallust/templates/Noctis.kvconfig
noctis.toml
noctis.toml.example
```

## Content matches (case-insensitive), by file

Initial (lowercase-only, incomplete) pass — 64 files:

```
assets/noctis-banner.svg
Configs/hypr/custom.lua
Configs/hypr/keybinds.lua
Configs/hypr/scripts/thunar_wall.py
Configs/hypr/scripts/wallswitcher.py
Configs/hypr/startup.lua
Configs/.local/bin/noctis
Configs/.local/lib/noctis/commands/cmd_ai.sh
Configs/.local/lib/noctis/commands/cmd_backup.sh
Configs/.local/lib/noctis/commands/cmd_config.sh
Configs/.local/lib/noctis/commands/cmd_doctor.sh
Configs/.local/lib/noctis/commands/cmd_iso.sh
Configs/.local/lib/noctis/commands/cmd_play.sh
Configs/.local/lib/noctis/commands/cmd_reload.sh
Configs/.local/lib/noctis/commands/cmd_restore.sh
Configs/.local/lib/noctis/commands/cmd_scheme.sh
Configs/.local/lib/noctis/commands/cmd_sddm.sh
Configs/.local/lib/noctis/commands/cmd_shell.sh
Configs/.local/lib/noctis/commands/cmd_theme.sh
Configs/.local/lib/noctis/commands/cmd_update.sh
Configs/.local/lib/noctis/commands/cmd_wallpaper.sh
Configs/.local/lib/noctis/commands/play/guess.sh
Configs/.local/lib/noctis/commands/play/hangman.sh
Configs/.local/lib/noctis/commands/play/snake.sh
Configs/.local/lib/noctis/commands/README.md
Configs/.local/lib/noctis/globalcontrol.sh
Configs/.local/lib/noctis/restore.manifest
Configs/quickshell/noctis/config/Config.qml
Configs/quickshell/noctis/modules/areapicker/AreaPicker.qml
Configs/quickshell/noctis/modules/areapicker/Picker.qml
Configs/quickshell/noctis/modules/background/BackgroundWindow.qml
Configs/quickshell/noctis/modules/bar/BarWindow.qml
Configs/quickshell/noctis/modules/dashboard/DashboardWindow.qml
Configs/quickshell/noctis/modules/launcher/LauncherWindow.qml
Configs/quickshell/noctis/modules/notifications/NotificationsWindow.qml
Configs/quickshell/noctis/modules/osd/OsdWindow.qml
Configs/quickshell/noctis/modules/session/SessionWindow.qml
Configs/quickshell/noctis/modules/settings/panes/SystemPane.qml
Configs/quickshell/noctis/modules/settings/SettingsWindow.qml
Configs/quickshell/noctis/services/ai/AiConfig.qml
Configs/quickshell/noctis/services/ai/AiKeys.qml
Configs/quickshell/noctis/services/Colours.qml
Configs/quickshell/noctis/services/Settings.qml
Configs/quickshell/noctis/services/Themes.qml
Configs/quickshell/noctis/services/Wallpapers.qml
Configs/systemd/user/noctis-shell.service
Configs/wallust/templates/colors-quickshell-colours.qml
Configs/wallust/wallust.toml
CONTRIBUTING.md
docs/cli.md
docs/COMMAND_CENTER.md
docs/exploit-layer.md
docs/terminal_games.md
.gitignore
install.sh
lib/install/wizard.sh
noctis.toml.example
README.md
tests/test_install_dry_run.sh
tests/test_repo_layout.sh
tests/test_uninstall.sh
tests/test_wizard.sh
themes/THEME_SPEC.md
uninstall.sh
```

Uppercase/title-case-only misses caught during the fix pass (missed by the
initial lowercase-only grep, found and fixed before finalizing):

```
lib/install/backup.sh                                        (NOCTIS_BACKUP_ROOT)
tests/test_backup.sh                                          (NOCTIS_BACKUP_ROOT)
Configs/Kvantum/kvantum.kvconfig                               (theme=Noctis)
Configs/hypr/hyprland.lua                                      (-- Noctis — Hyprland config entry point)
Configs/wallust/templates/Noctis.kvconfig                      (author=Noctis, comment)
Configs/quickshell/noctis/modules/settings/panes/AboutPane.qml (repoUrl, display text, VERSION path fallback)
Configs/quickshell/noctis/modules/settings/panes/PowerSecurityPane.qml (prose string)
```

Local-only, gitignored files also edited for consistency (never committed —
listed here only because the task explicitly named them):

```
noctis.toml              (local install state, gitignored)
CLAUDE_ROADMAP.md         (gitignored working doc, not shipped)
ROADMAP_FEATURES.md       (gitignored working doc, not shipped)
```

Intentionally left un-renamed:

```
install.log                          — historical install run log, gitignored, not shipped source
assets/legacy/noctis-banner.svg      — archived legacy asset, kept as-is per Step 3
assets/legacy/noctis-logo.svg        — archived legacy asset, kept as-is per Step 3
assets/legacy/noctis-dull.svg        — archived legacy asset, kept as-is per Step 3
assets/legacy/noctis-orbit.svg       — archived legacy asset, kept as-is per Step 3
assets/legacy/noctis_home.png        — archived legacy asset, kept as-is per Step 3
```

No third-party reference names (`caelestia-dots/shell`, `end-4/dots-hyprland`)
were touched — none exist under `noctis`-branded names to begin with, they
were never at risk.
