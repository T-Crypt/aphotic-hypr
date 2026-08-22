# Contributing to Aphotic-Hypr

Aphotic-Hypr is a full custom Quickshell desktop environment for Hyprland,
built in the same weight class as `end-4/dots-hyprland` and
`caelestia-dots/shell` — everything is first-party (bar, launcher,
notifications, OSD, lock, session menu, dashboard, area picker), not a
wrapper around third-party tools. Contributions are welcome, but should
fit the conventions already established so the project stays uniform as
more hands touch it.

## Before you start

- **Branch model:** active development happens on `test`. `main` is the
  stable/production line. Base your work off `test`, not `main`.
- **Read `CLAUDE_ROADMAP.md` first.** It's the authoritative source of
  truth for what's done, what's in progress, what's intentionally
  deferred, and what's explicitly out of scope. If your PR touches
  something the roadmap already has an opinion on, follow it — open an
  issue first if you think the roadmap itself needs to change.
- **Check for drift before extending CLI/script behavior.** State
  contracts (theme/wallpaper, settings) have changed shape before. If
  you're not sure the local checkout reflects the latest agreed model,
  diff against `origin/test` before building on top of it.

## Module conventions (QML)

Every Quickshell module follows the same shape:

- **Singleton/component split** — shared state and logic live in a
  singleton (e.g. `Config.qml`, `Settings.qml`, `Themes.qml`); visual
  components consume it, they don't own state themselves.
- **`qmldir` wiring** — every module directory needs a proper `qmldir`
  entry, not ad hoc imports.
- **IPC-toggle pattern for overlays** — popouts/overlays are toggled via
  `qs -c aphotic ipc call <target> <action>`, matching the existing lock/
  session/settings examples. Don't invent a second mechanism for opening
  UI.
- **`Tokens`/`Config`/`Settings` layering** — visual tokens (spacing,
  radius, color) come from the existing `Colours.qml`/token layer.
  Runtime defaults come from `Config.qml`/`GlobalConfig.qml`. User
  overrides that persist across restarts go through `Settings.qml`'s
  `FileView`-backed save pattern (`_loaded` guard, `onChanged` re-save).
  Don't introduce a parallel config or token system for a new module —
  extend the existing layers.
- **No explanatory comments by default.** Code should read clearly
  without narration. Only comment when the code can't carry the
  information itself: a non-obvious workaround, a safety warning above a
  destructive call, or a reference to an external quirk (a library's
  syntax, a Quickshell engine limitation).
- **Flyout/popout chrome is shared, not reinvented.** All bar popouts use
  the same `PanelWindow` + open/close transition + hover-dismiss
  `HoverHandler` pattern. New overlay surfaces should reuse this harness
  rather than building bespoke animation/dismiss logic.

## CLI conventions (`aphotic`)

The `aphotic` CLI is a real dispatcher (`Configs/.local/bin/aphotic` +
`lib/aphotic/commands/cmd_*.sh`), auto-discovering one file per
subcommand.

- **Simple commands:** add `lib/aphotic/commands/cmd_<name>.sh`. It's
  auto-discovered — no registration step needed.
- **Multi-verb commands:** if your command has its own sub-verbs (like
  `aphotic play hangman`), use the grouped convention:
  `commands/<name>/*.sh`, **no `cmd_` prefix** on the helper files. This
  keeps helper files from being auto-discovered as phantom top-level
  commands.
- **Use the shared helpers** in `globalcontrol.sh` — XDG paths, logging,
  `aphotic_json_get`/`aphotic_json_set`, `aphotic_confirm`, `aphotic_require`
  — rather than reimplementing them per-command.
- **State contracts are shared, not command-local.** If your command
  touches theme/wallpaper/scheme state, it must agree with `Themes.qml`
  and `wallswitcher.py` — this is a real three-way contract
  (`~/.local/state/aphotic/theme.json`). Changing the shape of that file
  is a three-way change: update and re-verify all three call sites
  together, never one at a time.
- **Settings additions** go through `Settings.qml`'s persisted schema
  (`~/.local/state/aphotic/settings.json`), not a second state file.

## Installer conventions

- `install.sh` must stay **idempotent** after partial application — if a
  contribution adds an install stage, guard repeated appends (`tee -a`,
  `>>`) with a grep check first, matching the existing PATH-export/
  wifi-powersave/nvidia-modprobe pattern.
- If your change adds a binary dependency the shell shells out to (bar,
  OSD, area-picker, session menu, etc.), add it to **both**
  `profiles/base/full.toml` and `profiles/base/minimal.toml` — the
  Quickshell shell always loads in full regardless of install profile,
  so a missing dep in `minimal` is a silent runtime gap, not a smaller
  install.
- Add or update a test under `tests/` for any install/uninstall/CLI
  behavior change. The suite runs on every push/PR via
  `.github/workflows/tests.yml` — a PR that doesn't pass it won't be
  merged.

## Verification before opening a PR

This project verifies live, not just "it parses":

1. `pkill -x qs` then a fresh `qs -c aphotic` restart — never rely on
   hot-reload alone to confirm a change works.
2. Check logs for `Configuration Loaded` and zero new errors.
3. Confirm the shell is actually still running afterward
   (`pgrep -f "qs -c aphotic"`) — don't assume a clean load means it's
   still up a minute later.
4. For visual changes, include a `grim` screenshot in the PR description.
5. Revert any temporary debug overrides and check `git diff` before
   marking the PR ready — no debug residue.

## Scope boundaries

- Arch/AUR-only — no multi-distro installer branching.
- No fingerprint/face auth on the lock screen.
- Not vendoring caelestia's native C++ plugin. If your feature would
  depend on functionality that plugin provides, either write a real
  substitute (as was done for OSD sliders, session buttons, dashboard
  cards) or document it as an explicit scope cut in your PR — never ship
  a silent stub.
- Native DBus tray context menus are blocked on a Quickshell-side
  `QsMenuHandle` bridge — not something to work around locally.

## Opening a PR

- Target `test`, not `main`.
- Reference the relevant `CLAUDE_ROADMAP.md` item (Quality debt # or
  Feature update #) if your change maps to one.
- If your change closes, resolves, or explicitly defers a roadmap item,
  say so in the PR description — the roadmap gets updated as part of the
  merge, not after.
- Keep PRs scoped to one module/command/fix where possible. Large,
  multi-surface PRs are harder to verify live and harder to review.

Questions about whether something fits the project's direction are
welcome as an issue before you write code — better to align early than
rework a finished PR to match scope.
