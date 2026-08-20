# Noctis-Hypr — Project Alignment for Claude Code

## Source of truth
**`CLAUDE_ROADMAP.md` is the authoritative, phase-by-phase roadmap.** Check
it for current phase status before starting work. This file is a condensed
orientation + cross-cutting ground rules — it should not duplicate or drift
from the roadmap's phase checklists. If something here disagrees with the
roadmap, the roadmap wins; fix this file.

## What this is
Repo: `T-Crypt/Noctis-Hypr`. A Hyprland desktop environment, moving from
"a rice with an install script" toward a shareable, actively-maintained
setup: modular per-user theming, a movable bar, and a real install
experience for other people — not a ground-up rewrite.

- **Shell**: mid-migration (Phase 3.6, active) from Waybar/Rofi/Mako/
  swaylock to a hand-vendored Quickshell shell, visually cloned from
  **caelestia-dots/shell** specifically (GPL-3.0, vendored source — not an
  installed dependency, no native C++ plugin, hand-written QML singletons
  for tokens/config). This is a full replacement, not a dual-bar
  transition period.
- **end-4/dots-hyprland**'s contribution is narrower than shell code: just
  the "show every command before it runs" installer transparency pattern,
  landing as `install.sh --dry-run`.
- **Color engine**: `wallust` (Rust, actively maintained) is the default,
  replacing the archived `dylanaraps/pywal`. `matugen` is an optional
  second engine for Material-You scheme variants (tonal-spot, vibrant,
  expressive, monochrome). Both render into the same template set — engine/
  scheme choice never touches app configs directly.
- **ML4W** pattern borrowed for the Phase 4 settings/welcome shape
  (CLI-first, optional GTK4 welcome window as a stretch goal later).
- Local dev/staging on Proxmox + SPICE passthrough to Windows host — done,
  out of scope for this doc.

## Ground rules for Claude Code in this repo
- **No explanatory `#` comments by default.** Only comment genuine
  non-obvious "why" — a destructive-command warning (`rm`/`sudo`), an
  external quirk (e.g. wallust's `{alpha}` syntax vs pywal's), or a section
  header in a long config file. Not "what," only the rare "why."
- Keep `install.sh` idempotent and runnable after partial phase
  application — never land a half-migrated state.
- `--dry-run` must exist before any destructive file operation is wired
  into the installer.
- Maintain backward-compat symlinks during repo-restructure phases (e.g.
  `custom_apps.lst` at root) so a half-updated clone doesn't break.
- Bash for install/orchestration; Python is fair game for anything with
  real logic (palette parsing, theme validation) — already a dependency
  via `thunar_wall.py` / `wallswitcher.py`.
- Reuse the existing `hypr/scripts/launcher.sh` Rofi wrapper convention
  rather than introducing a second launcher pattern, until the Quickshell
  launcher sub-phase (Phase 3.6, sub-phase 2) replaces Rofi outright.
- **`Configs/` (non-hidden, capitalized) is the install-target mirror of
  `~/.config/`**, renamed from `.configs/` on 2026-08-19. It also holds a
  HyDE-style `Configs/.local/bin/` and `Configs/.local/lib/` staging tree
  for the `noctis` CLI — see below.

## Resolved: `noctis-scaffold/` merged into `Configs/.local/`
The `noctis` CLI scaffold (`bin/noctis`, `lib/noctis/`, `docs/cli.md`) has
been moved out of the standalone `noctis-scaffold/` staging area (which no
longer exists) into the real repo layout:
- `Configs/.local/bin/noctis` — entry point, symlinked to `~/.local/bin/noctis`
  by `install.sh`'s config-copy step.
- `Configs/.local/lib/noctis/` — CLI internals (`commands/cmd_*.sh`,
  `globalcontrol.sh`, `restore.manifest`). `bin/noctis` resolves this
  relative to its own real path via `readlink -f`, so it works whether
  run from the repo or via the installed symlink — no separate install
  step needed for `lib/`.
- `docs/cli.md` — moved to the repo's real top-level `docs/`.

Still open, not blocking further work: **the scope gap.**
`CLAUDE_ROADMAP.md` Phase 4 describes `noctis` as a thin wrapper with five
subcommands (`theme`, `wallpaper`, `bar-position`, `update`, `doctor`); the
merged CLI is considerably larger (`backup`, `restore`, `config`, `scheme`,
`shell`, `ai`, `iso` too). Pick one later: (a) trim to Phase 4's five and
fold backup/restore into `lib/install/`, (b) keep the fuller CLI and update
Phase 4's description to match, or (c) split — ship the five now, park the
rest. The `iso build` subcommand (live-image tooling) also isn't scoped in
any of the five roadmap phases — treat as a candidate future phase.

## Current state (as of this update)
- Working branch: `test`.
- **Phase 3.6 (Quickshell migration) is the active phase.** Left-bar
  sub-phase: Tasks 1–7 done, bar renders end-to-end via `qs -c noctis`
  (verified via `hyprctl layers`). Known gap: the Task 6 popout flyout
  renders off the bar's window surface — `BarWindow.qml`'s exclusion-zone/
  width handling only reserves space for the bar itself, not the flyout;
  needs a real fix, likely bundled with Task 9 or 10. Task 8 done —
  `services/Colours.qml` is now wallust-generated (real wallpaper-driven
  palette, no longer the Task 2 hardcoded placeholder). Remaining: Task 9
  (system integration, retire Waybar — Waybar is still what actually
  autostarts today), Task 10 (visual tuning).
- Phases 0–2 and most of Phase 3.5 are largely done or superseded — their
  Waybar/Rofi-era outcomes become historical once Phase 3.6 completes.
  Don't build further on Waybar/Rofi assuming they're permanent fixtures.
- `noctis-scaffold/` has been merged into `Configs/.local/` — see
  "Resolved" section above. The scope-gap decision (trim vs. keep the
  fuller CLI) is still open but non-blocking.

## Immediate next actions
- [ ] Phase 3.6 Task 9 — system integration: startup, packages, retire
      Waybar.
- [ ] Fix the Task 6 popout flyout off-surface bug.
- [ ] Phase 3.6 Task 10 — visual tuning pass and final verification.
