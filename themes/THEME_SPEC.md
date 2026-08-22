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
name = "wallust"        # "wallust" | "matugen" (matugen not wired yet — Phase 3)
backend = "fastresize"  # wallust -b: full | resized | wal | thumb | fastresize
palette = "kmeans"      # wallust -p: salience | ansi | kmeans
colorscheme = "some-name"  # fixed palette, see below — mutually exclusive with backend/palette
style = "light"         # wallust -S: dark | light — omit for dark (the default for every theme but Latte)

[icons]
papirus_color = "green"  # one of `papirus-folders --list`, see below

[wallpaper]
default = "wallpaper-one.jpg"   # shown first when the theme is selected

[overrides]
# Optional per-app config snippets this theme wants layered on top of the
# normal wallust-generated output. Keys are template names matching
# Configs/wallust/wallust.toml's [templates] table (kitty, gtk, swaylock, ...).
# Empty/omitted table = no overrides, just use wallust's own output.
```

Every field under `[engine]` is a **pin**, not a requirement — if a theme
omits `theme.toml` entirely, or omits `[engine]`, Aphotic falls back to
`Configs/wallust/wallust.toml`'s own top-level `backend`/`palette`
defaults. A theme only needs to declare a pin when its wallpapers need
something different from the default (e.g. a theme built around
low-contrast pastel art might pin `palette = "ansi"` because `kmeans`
picks muddy clusters on it).

`[wallpaper].default` matters because a theme folder can hold more than
one image — it's the one shown/applied when you switch *into* the theme
for the first time. After that, Aphotic remembers which wallpaper within
the theme you last had active (`~/.local/state/aphotic/theme.json`), so
returning to a theme resumes where you left it rather than resetting to
`default`.

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
wallust's own default (`dark`). This only affects wallust's own
image-derived generation — it doesn't touch `Colours.qml`'s separate,
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
