# `noctis` CLI reference

Dispatcher: `bin/noctis`. Each subcommand is a file at
`lib/noctis/commands/cmd_<name>.sh` defining `noctis_cmd_<name>()`.
Add a new subcommand by adding a new file — the dispatcher auto-discovers
it via `noctis --help` / `noctis commands`, no dispatcher edits needed.

Status key: **done** = works today, **stub** = help text + TODO wiring.

| Command | Status | Notes |
|---|---|---|
| `noctis shell [-d]` | stub | starts `qs -c noctis`; IPC passthrough needs real IPC targets |
| `noctis reload [--full]` | done | quickshell IPC reload + optional `hyprctl reload` |
| `noctis doctor` | done | dependency + path checks; drift-vs-upstream check is TODO |
| `noctis config get/set/edit` | done | thin `jq` wrapper over `shell.json` |
| `noctis theme list/set/next/prev` | done | `set` writes config + reloads; asset swap + next/prev complete |
| `noctis wallpaper -f/--random/--next` | done | `-f`/`--random` work against a plain file glob; `--next` complete |
| `noctis scheme set -n` | done | writes config; matugen/palette generation complete |
| `noctis backup create/list/revert/clean` | done | full snapshot lifecycle, see below |
| `noctis restore [--populate\|--overwrite]` | done | manifest-driven, see `lib/noctis/restore.manifest` |
| `noctis update [--dots-only]` | done | git pull → restore --populate → reload --full |
| `noctis ai status/profile` | stub | status checks `claude`/`ollama` on PATH; profile switching TODO |
| `noctis iso build [--live\|--installer]` | stub | calls `mkarchiso`; archiso profile itself doesn't exist yet |

## backup vs restore — the distinction that matters
- **`backup`** = your own point-in-time snapshots. `create` before anything
  risky, `revert <id>` to go back, `clean` to prune. Fully your data.
- **`restore`** = deploying *Noctis's own defaults* on top of (or into)
  your live config, using HyDE's populate/overwrite split:
  - `--populate` (default): only fills in files that don't exist yet —
    safe for first install or after adding a new default file.
  - `--overwrite`: explicit, always auto-snapshots first via `backup create`.

## Extending
1. Copy an existing `cmd_*.sh` as a starting point — keep the file/function
   naming convention (`cmd_foo.sh` → `noctis_cmd_foo()`).
2. Use the shared helpers from `globalcontrol.sh`: `noctis_log/ok/warn/err`,
   `noctis_confirm`, `noctis_require`, `noctis_json_get/set`.
3. Update the CORE/CONFIG/LIFECYCLE/AI/BUILD grouping in `bin/noctis`'s
   `_noctis_usage()` if the command is user-facing enough to headline.
4. Add a row to the table above.
