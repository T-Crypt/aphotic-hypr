# Noctis CLI Commands

This directory contains the individual command implementations for the `noctis` CLI tool.

## Adding New Commands

To add a new command:
1. Create a file named `cmd_<name>.sh` following the existing pattern
2. The file should define a function named `noctis_cmd_<name>()`
3. Include proper documentation with @cmd, @cmd.desc, @cmd.group, and @cmd.opt annotations
4. The dispatcher will automatically discover and load the command, *and*
   `noctis --help`/`noctis`'s summary screen is generated entirely from
   these annotations — nothing else needs editing for a new command to
   show up there correctly grouped.

`@cmd.group` picks which heading it's grouped under in `noctis --help`
(`CORE`, `CONFIG`, `LIFECYCLE`, `AI`, `BUILD`, `FUN`, or a new group name
of your choosing — unknown groups just render as their own heading,
appended after the known ones). Omitting it puts the command under
`OTHER` rather than dropping it from the list.

## Grouped Subcommands

The dispatcher only auto-discovers files matching `cmd_*.sh` directly inside
this directory (`-maxdepth 1`), and treats *every* match as its own
top-level command — `cmd_foo_bar.sh` becomes a real, callable `noctis
foo_bar`, whether or not that's what you meant. If a command has its own
sub-verbs (`noctis play hangman`, `noctis play snake`, ...), put the
sub-verb implementations in a subdirectory named after the command
(`commands/play/hangman.sh`, `commands/play/snake.sh` — no `cmd_` prefix)
and have the top-level `cmd_<name>.sh` `source` them explicitly by path.
That keeps them out of discovery and out of `noctis`'s command list, while
the top-level file still dispatches to them normally.

## Command Structure

Each command file should:
- Start with a shebang (`#!/usr/bin/env bash`)
- Include a header comment with documentation
- Define the `noctis_cmd_<name>()` function
- Use the helper functions from `globalcontrol.sh` (noctis_log, noctis_ok, noctis_warn, noctis_err)
- Follow the existing pattern for help text and argument parsing

## Available Helper Functions

- `noctis_log(message)` - Log a message with cyan prefix
- `noctis_ok(message)` - Log a success message with green prefix  
- `noctis_warn(message)` - Log a warning message with yellow prefix
- `noctis_err(message)` - Log an error message with red prefix
- `noctis_confirm(prompt)` - Prompt user for confirmation
- `noctis_require(binary)` - Check if a binary exists on PATH

## `noctis sddm sync` and passwordless sudo

`cmd_sddm.sh` copies the current wallpaper into the SDDM theme and
rewrites its `Background=` line, so the login screen tracks whatever
wallpaper is active. It's called automatically (best-effort) from
`noctis theme`/`wallpaper`, `wallswitcher.py`, and the QML wallpaper
picker — but those `cp`/`sed` calls need root, so without passwordless
sudo for exactly that pair of commands, the hook just warns and no-ops
instead of blocking on a password prompt. To enable full automatic
sync, add a sudoers drop-in (`sudo visudo -f /etc/sudoers.d/noctis-sddm`)
scoped narrowly to those two commands, e.g.:

```
your_user ALL=(root) NOPASSWD: /usr/bin/cp * /usr/share/sddm/themes/sugar-candy/Backgrounds/, /usr/bin/sed -i * /usr/share/sddm/themes/sugar-candy/theme.conf
```

Without it, run `noctis sddm sync` manually (or `sudo -v` once per
session before switching themes) whenever you want the login background
refreshed.

## `papirus-folders` and passwordless sudo

Same story as sddm sync above, for a different reason: `cmd_theme.sh`
runs `papirus-folders -C <color> --theme Papirus-Dark -u` when a theme
declares `[icons].papirus_color` (see `themes/THEME_SPEC.md`), which
writes under `/usr/share/icons/` and so also needs root. Add a second
sudoers drop-in scoped to just that command:

```
your_user ALL=(root) NOPASSWD: /usr/bin/papirus-folders
```

Without it, folder icons keep whatever color they were last set to
manually (or Papirus's default) and the theme switch just warns instead
of blocking on a password prompt.

## Environment Variables

The following variables are available:
- `NOCTIS_VERSION` - The version of Noctis
- `NOCTIS_CONFIG_HOME` - XDG config directory for Noctis
- `NOCTIS_STATE_HOME` - XDG state directory for Noctis
- `NOCTIS_DATA_HOME` - XDG data directory for Noctis
- `NOCTIS_RUNTIME_DIR` - XDG runtime directory for Noctis
- `NOCTIS_CONFIG_FILE` - Path to the main config file
- `NOCTIS_BACKUP_DIR` - Directory for backups
- `NOCTIS_DOTS_DIR` - Path to the dots repository
- `QUICKSHELL_CONFIG_DIR` - Quickshell configuration directory