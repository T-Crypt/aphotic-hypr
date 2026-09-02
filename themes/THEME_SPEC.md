# Theme Spec

A **theme** is a directory of `~/.config/awww/<name>/` containing one or
more wallpapers plus a `theme.toml` manifest. The directory name is the
theme's identity — no separate registry file lists which themes exist,
the filesystem is the registry.

```
~/.config/awww/<name>/
├── theme.toml
├── wallpaper-one.jpg
└── wallpaper-two.png
```

## `theme.toml`

```toml
[theme]
display_name = "Tokyo Night"
description = "Neon purples and blues, city-at-night palette."

[engine]
name = "wallust"        # "wallust" | "matugen" — which colour engine renders
                        # this theme's palette. Omit for wallust. See
                        # "Choosing a colour engine" below.

# wallust-only knobs (ignored under matugen):
backend = "fastresize"  # wallust -b: full | resized | wal | thumb | fastresize
palette = "kmeans"      # wallust -p: salience | ansi | kmeans
colorscheme = "some-name"  # fixed palette, see below — mutually exclusive with backend/palette

# matugen-only knobs (ignored under wallust):
scheme = "scheme-vibrant"  # matugen -t: scheme-content | scheme-expressive |
                           # scheme-fidelity | scheme-fruit-salad |
                           # scheme-monochrome | scheme-neutral | scheme-rainbow |
                           # scheme-tonal-spot (default) | scheme-vibrant | scheme-smart
contrast = "0.3"           # matugen --contrast: -1 (minimum) .. 0 (M3 spec) .. 1 (maximum)

# shared:
style = "light"         # wallust -S / matugen -m: dark | light — omit for dark (the default for every theme but Latte)

[palette]
anchor = "some-name"    # bound how far a wallpaper's derived palette may
                        # drift from the theme's own look. Optional, off
                        # unless set — see "Clamped palettes" below.

[icons]
papirus_color = "green"     # one of `papirus-folders --list`, see below
icon_theme = "Papirus-Dark" # optional, see "Icon/cursor/GTK theme pins" below
cursor_theme = "Bibata-Modern-Ice"  # optional, same section

[gtk]
theme = "adw-gtk3-dark"  # optional, same section

[wallpaper]
default = "wallpaper-one.jpg"   # shown first when the theme is selected

[overrides]
# Optional per-app config snippets this theme wants layered on top of the
# normal wallust-generated output. Keys are template names matching
# Configs/wallust/wallust.toml's [templates] table (kitty, gtk, swaylock, ...).
# Empty/omitted table = no overrides, just use wallust's own output.
```

Every field under `[engine]` is a **pin**, not a requirement — if a theme
omits `theme.toml` entirely, omits `[engine]`, or omits `[engine].name`,
Aphotic uses wallust with `Configs/wallust/wallust.toml`'s own top-level
`backend`/`palette` defaults. A theme only needs to declare a pin when
its wallpapers need something different from the default (e.g. a theme
built around low-contrast pastel art might pin `palette = "ansi"` because
`kmeans` picks muddy clusters on it).

`[wallpaper].default` matters because a theme folder can hold more than
one image — it's the one shown/applied when you switch *into* the theme
for the first time. After that, Aphotic remembers which wallpaper within
the theme you last had active (`~/.local/state/aphotic/theme.json`), so
returning to a theme resumes where you left it rather than resetting to
`default`.

### Choosing a colour engine (`[engine].name`)

Aphotic ships two colour engines. Both derive a palette from the theme's
current wallpaper and both write the *same* set of output files, so
switching a theme between them changes how the colours are chosen, not
which apps get themed:

| | `wallust` (default) | `matugen` |
|---|---|---|
| Config | `Configs/wallust/wallust.toml` | `Configs/matugen/config.toml` |
| Produces | ANSI `color0`–`color15` | real Material You 3 roles |
| Knobs | `backend`, `palette`, `colorscheme` | `scheme`, `contrast` |
| Shared knobs | `style` (`-S`) | `style` (`-m`) |

All four apply sites — `aphotic theme set`/`next`/`prev` (`cmd_theme.sh`),
Settings → Appearance and the wallpaper picker (`Wallpapers.qml`),
SUPER+W (`wallswitcher.py`), and `aphotic scheme set` (`cmd_scheme.sh`) —
read this key and dispatch to the named engine. A name that is neither
`wallust` nor `matugen` warns and falls back to wallust.

**Palette snapshot.** Both engines write
`~/.local/state/aphotic/palette.json`, the one "current resolved palette"
file the plugin system and `Colours.qml` read. wallust's snapshot is
unchanged: `background`/`foreground`/`cursor`/`surfaceContainer`/
`surfaceContainerHigh` plus a `colors` object of `color0`–`color15`.
matugen's carries those same keys — so anything already reading the file
keeps working — plus `"engine": "matugen"` and a `roles` object holding
its real M3 roles (`primary`, `onPrimary`, `secondaryContainer`,
`outlineVariant`, …). `Colours.qml` branches on that `roles` object: when
it's there those values are used directly, and when it isn't (every
wallust theme) each role resolves to exactly the ANSI-derived value it
always did. wallust output is never passed through matugen's vocabulary
or the reverse.

The `colors` block in a matugen snapshot is a compatibility shim for the
consumers whose file format *is* 16 ANSI slots (kitty, cava, swaylock,
`~/.cache/wal/*`, and third-party plugins). Material You is a four-hue
system, so those 16 slots are filled from M3's four hue roles plus the
neutrals and some slots necessarily repeat — the magenta pair shares the
primary hue, the cyan pair the secondary. `Colours.qml` never reads this
block under matugen.

**Contrast.** wallust's `check_contrast = true` is a real, load-bearing
fix (see "Readable contrast and light themes" below) and stays on for
every wallust run. matugen has no equivalent flag and doesn't need one:
its roles come from M3 tonal palettes, where a role's legibility against
its paired surface is fixed by the tone it's generated at (`outline` at
tone 60 against a tone-6 surface, for example) rather than checked after
the fact. matugen's `--contrast` is a *different* knob — it shifts the
whole scheme's contrast level from −1 to 1 — and is exposed as
`[engine].contrast` for themes that want a flatter or punchier look.

None of the 8 shipped themes pin `matugen` today; like
`[engine].colorscheme`, the mechanism is real and tested but currently
unused by the presets.

### Folder-icon accent (`[icons].papirus_color`)

Real per-icon recoloring isn't possible with a normal icon theme —
each icon's colors are baked into its own file, unlike wallust's
CSS/terminal-escape color output. The icon theme is
[Papirus](https://github.com/PapirusDevelopmentTeam/papirus-icon-theme)
specifically because its companion
[papirus-folders](https://github.com/PapirusDevelopmentTeam/papirus-folders)
tool can swap its *folder* icons between ~16 preset colors (run
`papirus-folders --list` for the current set) to roughly match a
theme's accent — individual file-type icons stay Papirus's fixed
style regardless. All three theme-apply call sites (`cmd_theme.sh`,
`Wallpapers.qml`/`Themes.qml`, `wallswitcher.py`) run `papirus-folders
-C <color> --theme Papirus-Dark` when a theme declares this key.
`papirus-folders` writes under `/usr/share/icons/`, so — like
`cmd_sddm.sh`'s login-background sync — it needs passwordless sudo to
apply automatically from a theme switch; without it, this step just
no-ops rather than blocking on a password prompt (see
`commands/README.md` for the sudoers snippet convention). Omitting
`[icons]` entirely just leaves the current folder color as-is.

`[overrides]` is reserved for Phase 3's per-app override story — not
consumed by anything yet. A theme author can still write entries now;
they're simply ignored until that lands.

### Icon/cursor/GTK theme pins (`[icons].icon_theme`/`cursor_theme`, `[gtk].theme`)

Unlike `papirus_color`'s folder-tint (always applied when set), these
three keys are pins for the actual icon set, cursor theme, and GTK
window-chrome theme — the same three things Settings → Personalization
lets you pick manually (`Settings.iconTheme`/`cursorTheme`/`gtkTheme`).
A theme can declare any subset of the three; an unset key just leaves
whatever's currently active alone.

Each has a matching `Settings.iconThemeUserSet`/`cursorThemeUserSet`/
`gtkThemeUserSet` boolean, `false` by default and flipped to `true` the
moment you manually pick that setting in Personalization. A theme's pin
only applies while its matching flag is still `false` — so a fresh
install quietly follows whichever theme is active, but the moment you
pick something yourself, theme switching stops touching it, permanently
(picking a different theme later won't silently revert your choice).
There's no UI to reset a flag back to `false` today — it's a one-way
"I've made a manual choice" marker.

All three theme-apply call sites (`cmd_theme.sh`, `Wallpapers.qml`,
`wallswitcher.py`) apply these the same way `Settings.qml`'s own pickers
do: `gsettings` for icon/gtk-theme, `hyprctl setcursor` + `gsettings` for
cursor theme, and a `qt5ct.conf`/`qt6ct.conf` `icon_theme=` patch so Qt
apps track the same icon theme as GTK (Qt apps only pick this up on
their next launch, not live).

**Known limitation**: `papirus_color`'s `papirus-folders -C <color>
--theme Papirus-Dark` call (above) hardcodes `--theme Papirus-Dark`
literally, not read from `icon_theme`/`Settings.iconTheme` — so if a
theme pins `icon_theme` to anything other than Papirus-Dark/Papirus-Light,
that same theme's `papirus_color` folder-tint silently becomes a no-op
(it recolors a Papirus-Dark install that isn't the active icon theme).
Not fixed by this mechanism — a theme that wants both should keep
`icon_theme` on a Papirus variant, or skip `papirus_color`.

### Fixed colorschemes (`[engine].colorscheme`)

`backend`/`palette` both assume the palette is *derived* from the
theme's wallpaper image (`wallust run`). Some themes have a real brand
palette that shouldn't drift with whatever art ships as the default
wallpaper. None of the 8 shipped themes currently use this (HackTheBox
briefly did, but its dynamically-derived look was preferred and it was
reverted back to image-derivation) — the mechanism is still real and
tested, just unused for now. For a theme that wants it, set
`[engine].colorscheme` to a name under
`Configs/wallust/colorschemes/<name>.json` (pywal format: a `special`
object with `background`/`foreground`/`cursor`, and a `colors` object
with `color0`–`color15`) instead. All three call sites that apply a
theme (`cmd_theme.sh`, `Wallpapers.qml`'s `setWallpaper`, and
`wallswitcher.py`) check for this key first and run `wallust cs <name>
--format pywal` instead of `wallust run <image>` when it's set —
`backend`/`palette` are ignored in that case, since they're
image-generation-only knobs.

### Clamped palettes (`[palette].anchor`)

`[engine].colorscheme` above is the all-or-nothing answer to palette
drift: no image derivation at all. `[palette]` is the middle setting.
Every wallpaper still derives its own distinct palette — that
individuality is the point — but how far that palette may drift from the
theme's own look is bounded, tighter for a narrow, earthy theme like
Gruvbox than for something with more range like Rosé Pine. Without it, a
wallpaper that happens to contain an off-palette colour (a pink sign in a
photo, a badly-chosen community download) can push the whole system's
accent somewhere the theme was never meant to go.

```toml
[palette]
anchor = "gruvbox-anchor"   # ref: Configs/wallust/colorschemes/<name>.json
max_hue_shift = 20          # degrees, optional, default 20
max_sat_shift = 15          # percentage points, optional, default 15
max_light_shift = 12        # percentage points, optional, default 12
```

Like `[engine]`, this is a declared pin, not implicit behaviour: a theme
with no `[palette].anchor` behaves exactly as it always has, and clamping
rolls out theme by theme.

`anchor` names a pywal-format file under
`Configs/wallust/colorschemes/<name>.json` — the same directory and format
`[engine].colorscheme` reads, holding the palette this theme's colours are
measured against. `scripts/generate-theme-anchors.sh` bootstraps one per
theme by deriving the palette of that theme's `[wallpaper].default` image
(in an isolated wallust config/cache dir, so it never disturbs the live
session), writing `<theme>-anchor.json`. Generating an anchor doesn't opt
a theme in; that's the separate `[palette].anchor` edit.

The clamp itself (`Configs/.local/lib/aphotic/palette_clamp.py`) runs
after the normal `wallust run <image>`, which always leaves the raw,
unclamped palette at `~/.cache/wal/colors.json` via wallust.toml's
`wal_colors_json` template. Per slot, both the raw and anchor colour are
converted to HSL and:

- **Hue** is a circular clamp: within `max_hue_shift` of the anchor it
  passes through untouched; past it, the raw hue is rotated *toward* the
  anchor by exactly `max_hue_shift` rather than snapped onto it, so a
  wallpaper at the ceiling still keeps its own direction of drift.
- **Saturation** and **lightness** are clipped to `anchor ± max_sat_shift`
  / `anchor ± max_light_shift`.
- `background`, `foreground`, `cursor`, `color0`, `color7`, `color8` and
  `color15` are **exempt from lightness clamping** — only their
  saturation is bounded. Their lightness is what `check_contrast = true`
  (see below) is already guaranteeing, and clamping it toward an anchor
  would fight that check on a very dark or very light wallpaper. The
  hue-bearing accent slots (`color1`–`color6`, `color9`–`color14`) get
  the full treatment.

The clamped result is written to
`Configs/wallust/colorschemes/<theme>-live.json` (gitignored, regenerated
on every apply) and applied with `wallust cs <theme>-live --format pywal`
— literally the `[engine].colorscheme` code path, so every template
(kitty, GTK, hyprland, cava, swaylock, the plugin palette snapshot) is
re-rendered from the clamped colours and nothing downstream of wallust
knows clamping happened. All three apply sites (`cmd_theme.sh`,
`Wallpapers.qml`, `wallswitcher.py`) do this. A missing anchor file warns
and leaves the unclamped palette applied rather than failing the switch.

**The hue clamp assumes slot→hue stability, which only `palette = "ansi"`
gives you.** The clamp compares slot to slot: raw `color6` against anchor
`color6`. That is only meaningful if a slot holds the same *kind* of hue
from one wallpaper to the next. Measured as circular hue spread across
each theme's own shipped wallpapers:

| theme | `[engine].palette` | spread of `color1`–`color6` |
|---|---|---|
| nordic | `ansi` | 1°–8° |
| gruvbox | kmeans (default) | 13°–75° |
| tokyonight | kmeans (default) | 52°–103° |
| lofi | kmeans (default) | 74°–125° |

`ansi` orders slots by the classic TTY convention (`color1` red-ish,
`color2` green-ish, …), so a slot means the same thing every time and the
clamp does exactly what it says: Nordic's `color1 #B77142` → `#C36F36`,
a small push toward the theme's own orange. `kmeans` and `salience` order
slots by cluster prominence instead, so `color6` can be neon blue in one
wallpaper and dusty pink in another. Clamping *those* slot-to-slot rotates
toward whatever hue happened to land in that slot for the anchor
wallpaper, which is arbitrary — Tokyo Night's `color6 #2DB0F0` (neon blue)
becomes `#C16BA3` (pink) for exactly this reason.

So a theme that wants the hue ceiling to mean anything should pin
`[engine].palette = "ansi"` alongside `[palette].anchor`. A theme that
wants to keep kmeans should set `max_hue_shift = 180` (which disables the
hue clamp; it can never exceed 180° of circular distance) and rely on the
saturation and lightness ceilings alone — those are slot-order-independent
and still stop a wallpaper from blowing out a theme's intensity. Matching
raw colours to their *nearest* anchor hue instead of their same-numbered
slot would remove this constraint, but that is a different algorithm from
the one implemented here.

**Mutually exclusive with `[engine].colorscheme`.** A fixed colorscheme
derives nothing from the image, so there is no raw palette to clamp; a
theme setting both warns and keeps the fixed colorscheme.

**matugen themes can't use this.** matugen doesn't derive a palette that
can be post-processed the way ANSI slots can — it generates M3 roles from
a single seed colour, and its `-s/--source-color` flag takes that seed
explicitly. Clamping there would have to happen on the seed *before*
generation, a different mechanism from this one. `[palette]` is ignored
under `[engine].name = "matugen"`; none of the shipped themes pin matugen
today.

### Readable contrast and light themes

`Configs/wallust/wallust.toml` sets `check_contrast = true` globally,
which is wallust's own built-in fix for a real bug: without it, a
dark/desaturated wallpaper region can generate an ANSI color (`color8`
dim-gray was the actual offender) with barely any contrast against the
background, making things like `ls` output or zsh-autosuggestions text
nearly invisible. This applies automatically to every `wallust run`
call across all three theme-apply sites — no per-theme opt-in needed.

`[engine].style` (`"dark"` or `"light"`) controls which side of that
contrast check wallust generates for — light-background/dark-foreground
instead of the default dark/light. Latte is the only shipped theme
that sets it (`style = "light"`); every other theme omits it and gets
wallust's own default (`dark`). Under matugen the same key becomes
`-m dark|light`, selecting which side of every generated M3 role the
snapshot records. Either way this only affects the engine's own
generation — it doesn't touch `Colours.qml`'s separate,
currently-hardcoded `light: false`, which drives a couple of
Quickshell-side visual tweaks (icon weight, desktop clock inversion)
independently and would need its own theme.toml-driven wiring to
actually flip for Latte.

## Minimal valid theme

`theme.toml` can be a single line:

```toml
[theme]
display_name = "Lofi"
```

No `[engine]`, no `[wallpaper]`, no `[overrides]` — Aphotic uses the
global wallust defaults and treats the alphabetically-first wallpaper in
the folder as the default. This is intentionally the whole contract for
a "just drop some wallpapers in a folder" theme; the rest of the spec
exists for themes that need to pin something specific, not because every
theme must fill it in.

## Curated presets

The 8 themes shipped under `Configs/awww/<name>/` in this repo
(`lofi`, `hackthebox`, `windows11`, `nordic`, `gruvbox`, `tokyonight`,
`rosepine`, `latte`) are real examples of this contract, not just
scaffolding — each ships a `theme.toml` following the format above.
Each ships an original, hand-authored wallpaper matching its palette
(a Gruvbox desert sunset, a Tokyo Night neon skyline, and so on) rather
than a third-party stock image — see the individual `theme.toml`
`description` fields for what each depicts.
