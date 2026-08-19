# Foundation — Design Spec

Status: approved for planning
Sub-project: A (Foundation), first of six from the v3 roadmap decomposition
Depends on: nothing (this is the substrate)
Depended on by: B (Identity), C (Gaming profile), D (Dev environment), E (Settings CLI), F (Maintenance)

## Context

`T-Crypt/dots` is moving from a flat, single-user pywal rice into a
shareable, actively-maintained Hyprland setup aimed at three combined
identities: developer environment, gaming rig, and AI-assisted
workflow — unique in flavor but consciously borrowing proven ideas from
HyDE, ML4W, caelestia-dots/shell, and end-4/dots-hyprland (see
`CLAUDE_ROADMAP.md` for the sourcing table), plus NixOS's declarative/
reproducible philosophy (not its visual design).

The full scope was too large for one spec, so it was decomposed into
six sub-projects, built in dependency order:

| # | Sub-project | Status |
|---|---|---|
| A | Foundation — repo restructure, declarative manifest, installer overhaul | **this spec** |
| B | Identity — wallust/matugen color engine, bar position toggle | not started |
| C | Gaming profile — GameMode, performance-mode toggle, MangoHud, Steam/Proton | not started |
| D | Dev environment — terminal/editor polish, AI CLI integration | not started |
| E | Settings/Welcome CLI (`dots` command) — unifies B/C/D toggles | not started |
| F | Maintenance tooling — versioning, `dots doctor`/`update`, CI | not started |

Foundation is the substrate: profile/layer format, manifest schema, and
backup/install mechanics that B–F all build on top of. It intentionally
does **not** implement color engines, bar toggling, gaming tuning, or
AI tooling — it only reserves their directories.

## Goals

1. Repo restructure into `lib/`, `profiles/`, `themes/` (skeleton only
   for `themes/`) without changing current runtime behavior.
2. A declarative TOML manifest (`dots.toml`) that is the single source
   of truth for a given install — profile, layers, theme, bar
   position, detected system facts — so a fresh machine can be
   reproduced from one file (NixOS-inspired reproducibility, not its
   tooling).
3. An installer that works for other people: dynamic `$USER`/`$HOME`,
   safe to re-run, AUR-helper-agnostic, backed up, dry-run-able.
4. Composable install layers (`gaming`, `dev`, `ai`) on top of a base
   profile (`minimal`, `full`), so future sub-projects C and D can each
   land their own layer file without touching the base profiles.
5. **New-user experience stays simple.** No-argument `./install.sh`
   must remain a short, prompted wizard — the declarative manifest is
   a byproduct of answering prompts, never a precondition. Power users
   get the same result via flags for scripting/non-interactive use.

## Non-goals (explicitly out of scope for Foundation)

- Color engine work (wallust/matugen) — Phase B
- Bar position toggle logic — Phase B (directory reserved only)
- Gaming performance tuning (GameMode toggle, window rules, MangoHud
  waybar module) — Phase C (this spec only adds the *package layer*)
- AI CLI / editor / terminal integration — Phase D (this spec only
  adds the *package layer*)
- `dots` command / Settings CLI — Phase E
- Versioning, `dots doctor`, migrations, CI — Phase F
- Generations-style atomic rollback (NixOS's actual mechanism) — chose
  simple timestamped-backup-dir instead; revisit only if that proves
  insufficient in practice
- Quickshell, Lua-based Hyprland config, multi-distro branching — out
  of scope per `CLAUDE_ROADMAP.md`'s existing exclusions

## Architecture

```
dots/
├── install.sh                  # thin orchestrator: wizard OR flags → resolved plan → execute
├── uninstall.sh                # reads dots.toml + restores latest backup
├── dots.toml.example           # committed template, comments explain each field
├── dots.toml                   # generated on first install; gitignored; resolved source of truth
├── lib/
│   ├── install/
│   │   ├── wizard.sh           # interactive prompts (profile, layers, theme, bar position)
│   │   ├── aur.sh               # yay/paru detection + install-one-if-missing fallback
│   │   ├── backup.sh            # snapshot + prune ~/.config-backup/<timestamp>/
│   │   └── symlink.sh           # config copy/symlink helpers, dry-run aware
│   ├── toml/
│   │   └── merge.py            # resolves base + layers + custom_apps.lst → flat package list
│   ├── colors/                  # reserved for Phase B — .gitkeep only
│   └── bar/                     # reserved for Phase B — .gitkeep only
├── profiles/
│   ├── base/
│   │   ├── minimal.toml
│   │   └── full.toml
│   ├── layers/
│   │   ├── gaming.toml
│   │   ├── dev.toml
│   │   └── ai.toml
│   └── custom_apps.lst          # unchanged format, back-compat
├── custom_apps.lst -> profiles/custom_apps.lst   # symlink, back-compat
├── themes/                      # reserved for Phase B — default/ + THEME_SPEC.md stub
├── .configs/                    # unchanged: mirrors ~/.config/
├── assets/
└── src/
```

`lib/colors/`, `lib/bar/`, and `themes/` are created empty (per the
roadmap's Phase 0 skeleton) so Phase B has a landing spot, but Foundation
does not populate them.

## Manifest & profile schema

All files use TOML. Reading uses stdlib `tomllib` (Python 3.11+,
guaranteed present on Arch and already a transitive dependency via
`python-requests`). Writing `dots.toml` uses a small hand-rolled writer
— the schema is fixed and simple enough that pulling in a `tomli-w`-class
dependency isn't justified.

**`profiles/base/minimal.toml`**
```toml
[meta]
name = "minimal"
description = "Bare Hyprland + Waybar, no extras"

[packages]
prep = ["qt5-wayland", "qt6-wayland", "qt5ct", "qt6ct", "gtk3", "polkit-gnome", "pipewire", "wireplumber", "jq", "wl-clipboard", "cliphist", "python-requests", "pacman-contrib"]
main = ["hyprland", "waybar", "kitty", "mako", "swww", "rofi-lbonn-wayland-git", "xdg-desktop-portal-hyprland"]
```

**`profiles/base/full.toml`** — same shape; `main` carries today's full
`install_stage` array (zsh, starship, thunar, cava, btop, firefox, etc,
migrated verbatim from the current `install.sh`).

**`profiles/layers/gaming.toml`**
```toml
[meta]
name = "gaming"
description = "Performance profile + launcher polish"

[packages]
main = ["gamemode", "lib32-gamemode", "mangohud", "lib32-mangohud", "steam"]

[gaming]
enabled_by_default = true
```

`layers/dev.toml` and `layers/ai.toml` follow the same `[meta]` +
`[packages]` shape. Deliberately package-lists-only for Foundation —
the actual terminal/editor/AI-CLI config wiring is Phase D's job.

**`dots.toml`** (generated, root, gitignored — the resolved record)
```toml
[install]
profile = "full"
layers = ["gaming", "dev"]
installed_at = "2026-08-18T10:00:00"

[theme]
name = "default"

[bar]
position = "top"

[system]
nvidia = true
aur_helper = "yay"
```

Only `profile`, `layers`, `theme.name`, and `bar.position` are wizard
questions. `system.*` is always auto-detected, never asked.

**Merge logic (`lib/toml/merge.py`)**: reads
`profiles/base/<profile>.toml` + each selected
`profiles/layers/<layer>.toml`, unions `packages.prep`/`packages.main`
(dedup, preserve first-seen order), appends `custom_apps.lst` entries
into `main`. Output is a flat resolved list that `install.sh` iterates
with the existing `install_software` function — package installation
mechanics don't change, only how the list is built.

## Installer flow

- **No `dots.toml` found** → wizard: profile (minimal/full) → layers
  (gaming/dev/ai, multi y/n) → theme (only `default` exists until
  Phase B) → bar position (top/left, recorded now, inert until Phase
  B). Writes `dots.toml`, then proceeds to execution.
- **`dots.toml` found** → "Existing config found (profile=full,
  layers=gaming,dev). Reinstall same config? [Y/n]" — yes skips
  straight to execution, no re-asking.
- **Flags** bypass the matching wizard question: `--profile
  <minimal|full>`, `--with <gaming,dev,ai>`, `--theme <name>`,
  `--bar-position <top|left>`, `--dry-run`, `--no-backup`,
  `--keep-backups <N>` (default 5), `-h/--help`. All required flags
  present → fully non-interactive.
- **`--dry-run`** prints every planned action (installs, copies,
  symlinks, service enables) and executes nothing. Implemented as a
  shared `DRY_RUN` check inside every `lib/install/*.sh` function
  before any mutating call — built before any destructive operation is
  wired up, per the roadmap's existing safety-rail-first instruction.
- **Backup**: before touching any `~/.config/<dir>` the profile/layers
  target, snapshot it to `~/.config-backup/<timestamp>/`, then prune
  to keep the last N.
- **`uninstall.sh`**: reads `dots.toml` for what was installed,
  restores the most recent backup, removes symlinks it created. Does
  **not** uninstall pacman packages by default — that requires an
  explicit `--purge-packages` flag with its own separate confirmation.
- **Never assume it's you**: `$USER`/`$HOME` resolved dynamically
  everywhere; `sudo` only for pacman/systemctl calls, never for the
  invoking user's own file operations.
- **AUR helper**: detect `yay` then `paru`; if neither present, prompt
  to install `yay` (existing bootstrap logic, moved into `lib/install/aur.sh`
  unchanged in behavior).

## Error handling

- `lib/install/*.sh` uses `set -euo pipefail`.
- The orchestrator traps failures, logs to `install.log` using the
  existing `CNT`/`COK`/`CER`/`CWR`/`CAC` visual style, and halts — no
  silent continuation.
- Malformed TOML produces a caught, readable error (`malformed
  profiles/layers/gaming.toml: <reason>`), never a raw Python
  traceback.
- Every phase leaves `install.sh` runnable and idempotent after
  partial application (per roadmap working notes) — re-running after a
  failed run should not double-backup or double-install.

## Testing

- No live pacman installs in dev/CI, so `--dry-run` is the primary
  test surface: assert `install.sh --dry-run --profile full --with
  gaming,dev,ai` exits 0 and its printed plan includes the expected
  package names from all three layers.
- `lib/toml/merge.py` gets plain-assert unit tests: base-only,
  base+one layer, base+multiple layers, duplicate-package dedup across
  base and a layer.
- Shellcheck over `install.sh` + `lib/**.sh` — seeds the CI step
  Phase F wants, doesn't have to wait for it.

## Backward compatibility

- `custom_apps.lst` stays readable at the repo root via a symlink to
  `profiles/custom_apps.lst`, so a half-updated clone or muscle-memory
  edit doesn't break.
- Current `install.sh` prompts/flow (Nvidia detection, bluetooth/sddm
  enable, VSCode extensions, starship/zsh setup) are preserved as-is;
  only the package-list *sourcing* changes from hardcoded bash arrays
  to the resolved TOML output.

## Open questions carried into later phases

- Exact `dots.toml` fields Phase B will add (`theme.engine`,
  `theme.backend`, `theme.colorspace`) — schema has room via
  `[theme]` already existing, just currently under-populated.
- Whether `[gaming] enabled_by_default` in the layer file ends up
  driving Phase C's runtime toggle default, or Phase C introduces its
  own state file — Phase C's call, not Foundation's.
