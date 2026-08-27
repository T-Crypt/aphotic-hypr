# Plugin System — Design Doc

Status: **Phase 1 shipped** (`cmd_plugin.sh`, the OpenRGB reference
plugin) — see the resolutions noted inline below for where the shipped
version diverged from this doc's original sketch. A manifest v2
expansion (category, project/workspace hooks, the security-category
index) has also shipped on top of Phase 1, per `CLAUDE.md`'s Plugin
Ecosystem plan. §6's own Phase 2 (CLI subcommands)/Phase 3 (UI surfaces)
are still unbuilt.

## 0. What already exists that this builds on

Aphotic already has three precedents that a plugin system should reuse
rather than reinvent:

- **The CLI's auto-discovery convention** — `Configs/.local/bin/aphotic`
  discovers `lib/aphotic/commands/cmd_*.sh` by filename, no registration
  step. A plugin that adds a subcommand should look identical to a
  first-party one from the dispatcher's point of view.
- **The theme-apply contract** — `themes/THEME_SPEC.md` already documents
  that applying a theme is a **three-way call site**: `cmd_theme.sh`,
  `Wallpapers.qml`'s `setWallpaper`, and `wallswitcher.py`. All three
  already resolve a theme down to a concrete 19-value palette (background/
  foreground/cursor + 16 ANSI colors) before doing anything else with it.
  This is the natural hook point for "do something with the active
  palette" plugins like OpenRGB sync — the palette-resolution work is
  already done, a plugin just needs to receive it.
- **The theme folder convention** — `~/.config/awww/<name>/theme.toml` is
  a real precedent for "a plugin is a directory with a manifest," reused
  below for the plugin manifest shape.

## 1. Phased scope

| Phase | What a plugin can do | Needs |
|---|---|---|
| **1 — Theme hooks** | Run a script whenever the active theme/palette changes, receiving the resolved palette | A hook-firing loop added to the three theme-apply call sites above. No QML changes to the shell's own UI. |
| **2 — CLI subcommands** | Add a real `aphotic <name> ...` subcommand | Extending the dispatcher's discovery path to also scan a plugin directory, same `cmd_*.sh` convention. |
| **3 — UI surfaces** | A real Settings pane / bar module / dashboard tab | Dynamic QML loading against a stable, versioned subset of `qs.services`/`qs.components` — the hard, deferred part. Needs its own design pass once Phase 1/2 are real and a couple more plugins exist to generalize from. |

**Phase 1 is the only phase this doc fully specifies.** It's scoped
tightly enough to ship the OpenRGB plugin end to end. Phases 2/3 are
sketched (§6) so Phase 1's manifest/install mechanism doesn't need
reshaping later, not because they're being built now.

## 2. Distribution model

- **`aphotic-plugins`** is a new, separate repository (own local clone,
  own eventual GitHub remote under the same account) — a curated
  monorepo of first-party plugins, each in its own top-level directory
  (`openrgb/`, future plugins alongside it). Not one repo per plugin —
  that's more overhead than a handful of maintainer-curated plugins need
  right now, and matches how `Configs/awww/<name>/` already holds every
  shipped theme in one repo rather than one-repo-per-theme.
- **Install location:** `~/.local/share/aphotic/plugins/<name>/` (a new
  XDG data-home directory, sibling to the existing state/config dirs
  `globalcontrol.sh` already creates). A plugin here is just a directory
  with a manifest — nothing to compile, matching every other "drop a
  folder in the right place" convention in this project.
- **Install mechanism:** a new `aphotic plugin` command group —
  - `aphotic plugin list` — installed + (if `aphotic-plugins` is cloned
    locally at a known path, or reachable over git) available plugins.
  - `aphotic plugin install <name>` — copies `<name>/` out of a local
    clone of `aphotic-plugins` (path configurable, default
    `~/aphotic-plugins`) into the install location. Cloning the repo
    itself is a manual, explicit step the first time (`git clone
    .../aphotic-plugins`) — this command does not silently `git clone`
    on a user's behalf.
  - `aphotic plugin enable|disable <name>` — toggles an `enabled: bool`
    in the plugin's own state, not a filesystem move — matches
    `Config.bar.entries.values`' `enabled` flag convention already used
    throughout `Config.qml`.
  - `aphotic plugin remove <name>` — deletes the installed copy.
- **Local dev workflow:** for someone writing a plugin against their own
  checkout of `aphotic-plugins`, `aphotic plugin install --link <name>`
  symlinks instead of copies, so edits in the plugin repo take effect
  without reinstalling — mirroring how `Configs/.local/bin/aphotic` itself
  is symlinked onto `PATH` rather than copied.

## 3. Plugin manifest (`plugin.toml`)

```toml
[plugin]
name = "openrgb"
display_name = "OpenRGB Sync"
description = "Syncs the active theme's accent color to RGB lighting via OpenRGB."
version = "1.0.0"
author = "T-Crypt"
# Phases this plugin uses -- lets `aphotic doctor`/the Settings Plugins
# pane show what a plugin actually does before you enable it, and lets
# the loader skip capabilities it doesn't support yet.
capabilities = ["theme-hook"]

[requires]
# Checked via `aphotic_require` (globalcontrol.sh) before enabling --
# same "warn and no-op, don't block" pattern as the papirus-folders/sddm
# passwordless-sudo checks in commands/README.md, not a hard install-time
# dependency.
binaries = ["openrgb"]

[hooks]
# Relative to the plugin's own directory. Phase 1 only defines this one
# hook; see §4.
on_theme_change = "hooks/on_theme_change.sh"
```

Deliberately **not** in scope for the manifest yet: a plugin-to-plugin
dependency graph, a semver-range compatibility check against the shell's
own version, or a signing/checksum field — none of these matter until
there's more than a handful of first-party plugins to worry about, and
adding them speculatively now just gives the format more surface to get
wrong before it's been used once.

## 4. Phase 1: the theme-hook mechanism

Each of the three existing theme-apply call sites gains one small,
identical step after it finishes resolving the palette: loop over every
**enabled** plugin under `~/.local/share/aphotic/plugins/*/` that
declares `capabilities = ["theme-hook"]`, and run its `on_theme_change`
script, passing the resolved palette as positional arguments in a fixed
order:

```sh
on_theme_change.sh <background> <foreground> <cursor> <color0> <color1> ... <color15>
```

Plain positional hex strings (`#rrggbb`), not a JSON blob — this is
intentionally the simplest possible contract a shell-script plugin author
can consume with zero parsing dependencies, matching this project's own
`cmd_*.sh` style. A plugin needing more structure than 19 positional
args can always re-derive it from `~/.local/state/aphotic/theme.json`
(already the source of truth for the active theme name), which every
Phase 1 plugin can read regardless of what triggered the hook.

**Failure handling:** a hook script that errors or hangs must never break
the actual theme switch it's piggybacking on. Each hook runs
`Quickshell.execDetached`-style (QML side) or backgrounded with a timeout
(bash side) — fire-and-forget, logged if it fails, never blocking or
failing the theme-apply call site itself. Consistent with how
`papirus-folders`/`sddm sync` calls already no-op-and-warn today rather
than blocking a theme switch.

**Where the loop itself lives:** a new shared helper,
`aphotic_run_theme_hooks` in `globalcontrol.sh` (bash side, used by
`cmd_theme.sh` and importable by `wallswitcher.py` via a thin subprocess
call to keep the actual plugin-discovery logic in exactly one place), and
a QML-side equivalent in `Themes.qml` for `Wallpapers.qml`'s call site.
Two implementations of the same loop (bash + QML) is an accepted
duplication here — the alternative (QML shelling out to a bash helper for
every theme change, or bash calling into the QML process) is more
coupling for less benefit than just keeping the loop itself trivial
enough to duplicate correctly twice.

## 5. Worked example: the OpenRGB plugin

`aphotic-plugins/openrgb/`:

```
openrgb/
├── plugin.toml
└── hooks/
    └── on_theme_change.sh
```

`hooks/on_theme_change.sh` (sketch, not final):

```sh
#!/usr/bin/env bash
# args: background foreground cursor color0..color15 (see PLUGIN_SYSTEM.md §4)
accent="${5:-$2}"  # color4 (the "blue"/accent slot in every shipped theme.json) falls back to foreground
command -v openrgb >/dev/null 2>&1 || exit 0
openrgb --mode Static --color "${accent#\#}" >/dev/null 2>&1
```

This shells out to the real `openrgb` CLI (already how this project talks
to `hyprctl`/`wallust`/`papirus-folders` — no new SDK client dependency,
no new language runtime). `--mode Static --color <hex>` sets every
detected device to one flat color; per-device zone mapping (e.g. a
different color per RAM stick vs. case fan header) is a real, useful
follow-up but is explicitly **not** Phase 1 — this ships the simplest
version that proves the hook mechanism end to end, matching how the
Theme Creator shipped a flat-gradient wallpaper generator before anything
fancier.

**Open question for review:** which palette slot is "the accent" is
theme-author-dependent in practice (`color4` reads as a reasonable
default given every shipped `theme.json`'s blue/accent slot, but isn't
guaranteed). Worth deciding whether `theme.toml` should eventually gain
an explicit `[plugin_hints].accent_slot` a theme author can set, or
whether this is a plugin-side heuristic forever. Not blocking Phase 1 —
just flagging it now so it doesn't get silently decided by whichever
value happens to work on the themes tested against.

## 6. Sketch of Phases 2/3 (not specified yet, just not painted out of the corner)

- **Phase 2 (CLI subcommands):** `aphotic <plugin-name> ...` would need
  the dispatcher's `_aphotic_dispatch` to also check
  `~/.local/share/aphotic/plugins/*/commands/cmd_*.sh` after its own
  `COMMANDS_DIR`, first-party commands winning on a name collision. The
  manifest's `capabilities` list gains `"cli"`, and the manifest specifies
  a `[commands]` table analogous to `[hooks]` above.
- **Phase 3 (UI surfaces):** genuinely harder — needs a stable subset of
  `qs.services`/`qs.components` a third-party QML file can import without
  the shell's internal refactors silently breaking it, plus real
  decisions about trust (a Settings pane plugin runs arbitrary QML inside
  the same process, not a sandboxed one — this needs its own explicit
  writeup, not a paragraph here). Deliberately deferred until Phase 1/2
  have real mileage.

## 7. Settings UI

A new "Plugins" Settings category (already named as a placeholder in
`README.md`'s Roadmap) becomes real in Phase 1: list installed plugins
(name, description, capability badges, enable/disable toggle, a "missing
dependency" warning driven by `[requires].binaries`), matching the same
`SettingsGroup`/`SettingsRow` shell every other pane already uses. No new
visual language needed.

## Open questions checklist (resolve before Phase 1 implementation)

**Phase 1 has shipped** (`Configs/.local/lib/aphotic/commands/cmd_plugin.sh`).
Resolutions, for whoever next reads this list expecting it to still be
open:

- [x] Install path: `~/.local/share/aphotic/plugins/` (`APHOTIC_PLUGINS_DIR`), as sketched.
- [x] Hook contract: **JSON-on-stdin, not positional args** — `on_theme_change`
      receives the resolved palette by reading `~/.local/state/aphotic/palette.json`
      on stdin, not 19 positional hex strings. The positional sketch in §4/§5
      below is what was *proposed*; it's not what shipped. `[hooks]` keys are
      still plain relative script paths, unchanged from the sketch.
- [ ] Accent-slot question (§5): still genuinely open, not resolved by
      the shipped OpenRGB plugin (it hardcodes the same `color4`-or-fallback
      heuristic this doc flagged as not guaranteed).
- [x] Plugin source: `APHOTIC_PLUGINS_REPO` env var (default `~/aphotic-plugins`),
      not a `Settings.qml`-persisted path.
- [x] Hook timeout: 5 seconds (`timeout 5 ...`).

## Plugin manifest v2 (category, project/workspace hooks, security index)

Shipped on top of Phase 1, per `CLAUDE.md`'s Plugin Ecosystem Phase 2a
plan — **not** the same thing as this doc's own "Phase 2 (CLI
subcommands)"/"Phase 3 (UI surfaces)" in §6 below, which are still
unbuilt. This is a separate, additive expansion of what a Phase-1-shaped
plugin (a directory + `plugin.toml` + hook scripts) can declare, layered
in before those two original phases:

- **`[plugin].category`** (optional string) — one of `dev` / `security` /
  `mobile` / `ai` / `theming` / `productivity`. Drives Settings → Plugins'
  category rail and `aphotic plugin list --remote --category <name>`.
  Absent on a v1 manifest, reads back as `""` (no error, no filter match
  except explicit `""` queries, which nothing issues).
- **`capabilities` gains two more tags** (still the same flat array
  Phase 1 shipped, e.g. `["theme-hook", "project-hook"]` — not a
  separate `[capabilities]` table, despite `CLAUDE.md`'s own sketch
  suggesting one; reconciled with the real shipped shape instead):
  - `project-hook` + `[hooks].on_project_open = "hooks/....sh"` — fired
    (single positional arg: the project's absolute path) from the
    launcher's `@` project-switcher (`ProjectItem.qml`) after it
    launches its own terminal+editor.
  - `workspace-hook` + `[hooks].on_workspace_launch = "hooks/....sh"` —
    fired (single positional arg: the profile's name) from Workspace
    Profiles' `launchProfile()` after it dispatches its own `hyprctl`
    execs.
  - Both only fire for a plugin that **declares** the matching
    capability tag, not every enabled plugin — an intentional choice so
    a theming-only plugin doesn't get invoked on every project switch.
    Same fire-and-forget/5s-timeout/never-blocks contract as
    `on_theme_change`.
- **Security-category plugins live in a separate index**
  (`APHOTIC_PLUGINS_SECURITY_INDEX_URL`), never fetched by
  `aphotic plugin list --remote` until `aphotic plugin trust-security-index`
  has been run once (real warning text, explicit y/N, `--yes` for the
  Settings-UI caller which renders its own confirm UI first) — mirrors
  the `exploit` layer's BlackArch confirmation precedent. `aphotic plugin
  untrust-security-index` reverses it; already-installed security plugins
  are unaffected either way. `aphotic plugin security-index-status`
  returns `{"trusted": bool}` for UI callers that need to distinguish
  "untrusted" from "trusted but currently empty."

No manifest migration needed — every v2 field is optional, and a v1
plugin with only `[plugin]` + `on_theme_change` parses and behaves
identically under this.
