# `aphotic` CLI reference

Dispatcher: `bin/aphotic`. Each subcommand is a file at
`lib/aphotic/commands/cmd_<name>.sh` defining `aphotic_cmd_<name>()`.
Add a new subcommand by adding a new file — the dispatcher auto-discovers
it via `aphotic --help` / `aphotic commands`, no dispatcher edits needed.

Status key: **done** = works today, **stub** = help text + TODO wiring.

| Command | Status | Notes |
|---|---|---|
| `aphotic shell [-d]` | stub | starts `qs -c aphotic`; IPC passthrough needs real IPC targets |
| `aphotic reload [--full]` | done | quickshell IPC reload + optional `hyprctl reload` |
| `aphotic doctor` | done | dependency + path checks; drift-vs-upstream check is TODO |
| `aphotic config get/set/edit` | done | thin `jq` wrapper over `shell.json` |
| `aphotic theme list/set/next/prev` | done | `set` writes config + reloads; asset swap + next/prev complete |
| `aphotic wallpaper -f/--random/--next` | done | `-f`/`--random` work against a plain file glob; `--next` complete |
| `aphotic scheme set -n` | done | writes config; matugen/palette generation complete |
| `aphotic backup create/list/revert/clean` | done | full snapshot lifecycle, see below |
| `aphotic restore [--populate\|--overwrite]` | done | manifest-driven, see `lib/aphotic/restore.manifest` |
| `aphotic update [--dots-only]` | done | git pull → restore --populate → reload --full |
| `aphotic ai status/profile` | stub | status checks `claude`/`ollama` on PATH; profile switching TODO |
| `aphotic iso build [--live\|--installer]` | stub | calls `mkarchiso`; archiso profile itself doesn't exist yet |

## backup vs restore — the distinction that matters
- **`backup`** = your own point-in-time snapshots. `create` before anything
  risky, `revert <id>` to go back, `clean` to prune. Fully your data.
- **`restore`** = deploying *Aphotic's own defaults* on top of (or into)
  your live config, using HyDE's populate/overwrite split:
  - `--populate` (default): only fills in files that don't exist yet —
    safe for first install or after adding a new default file.
  - `--overwrite`: explicit, always auto-snapshots first via `backup create`.

## Extending
1. Copy an existing `cmd_*.sh` as a starting point — keep the file/function
   naming convention (`cmd_foo.sh` → `aphotic_cmd_foo()`).
2. Use the shared helpers from `globalcontrol.sh`: `aphotic_log/ok/warn/err`,
   `aphotic_confirm`, `aphotic_require`, `aphotic_json_get/set`.
3. Update the CORE/CONFIG/LIFECYCLE/AI/BUILD grouping in `bin/aphotic`'s
   `_aphotic_usage()` if the command is user-facing enough to headline.
4. Add a row to the table above.
