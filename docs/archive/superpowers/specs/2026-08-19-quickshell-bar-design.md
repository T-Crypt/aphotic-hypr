> **Archived 2026-08-30.** Design spec for the now-shipped Quickshell bar. Noted in [`docs/APHOTIC_UNIFIED_VISION.md`](../../../APHOTIC_UNIFIED_VISION.md)'s Historical/Superseded section. Kept here as the historical spec.

# Noctis Shell — Phase 1: Left Bar (Quickshell)

## Context

Noctis currently uses Waybar + Rofi + Mako + swaylock, themed via a wallust
pipeline that generates per-app color templates from the active wallpaper
(fixed and verified working earlier this session). Waybar has just been
polished (island layout, hover states, color-matched module pills), but the
user considers Waybar/Rofi "legacy" compared to what end-4 and
caelestia-dots use, and wants to move the whole shell to
[Quickshell](https://quickshell.outfoxxed.me) (QML, actively developed,
first-class Hyprland/layer-shell support), using
[caelestia-dots/shell](https://github.com/caelestia-dots/shell) as visual
and structural inspiration.

This is a full replacement, not a side-by-side option: Waybar, Rofi, Mako,
and swaylock are all intended to be retired across the full project, phase
by phase. This spec covers **Phase 1 only: the left-hand vertical bar**,
which replaces Waybar. Later phases (launcher, notifications, OSD, lock,
session/power menu, and optional dashboard/sidebar/drawers/nexus/areapicker
extras) are listed for sequencing but are out of scope here and will get
their own spec/plan cycles.

## Decisions already made (not open for reconsideration in this doc)

- **Target framework:** Quickshell, not eww/AGS/Ironbar/Fabric. eww is
  functional but stagnant (no tagged release since April 2024, one
  effectively-solo maintainer); Quickshell has active, fast-growing
  development and is what both end-4's and caelestia's current rices use.
- **Vendor, don't depend:** caelestia-shell's QML is a *starting reference*,
  copied and adapted into this repo — not installed as an AUR package/
  dependency. The user wants this to be genuinely Noctis's own code, not a
  themed skin on top of someone else's project.
- **Drop the native C++ plugin:** caelestia-shell ships a compiled
  CMake/Qt6 plugin (`plugin/`) providing its `Config`/`Tokens` system and an
  audio beat-detector for reactive visuals. We are **not** vendoring this.
  Reasons: it would require adding a C++/CMake/Qt6-dev build step to
  `install.sh` and package profiles, and it's C++ the user didn't write and
  would now have to maintain against a Quickshell API that can change. The
  beat-detector's use case (audio-reactive visuals) is already covered
  elsewhere in the repo by `cava`. This is consistent with the rest of
  Noctis, which favors hand-authored config (the `hyprland.lua` rewrite)
  over inherited black-box systems.
- **Visual target:** as close to caelestia's actual bar as reasonably
  achievable on first pass. Pixel-level tuning (exact spacing/radius
  values, hover animations) happens after the first install and live test
  on the VM, not before.
- **Phase order:** Bar → Launcher → Notifications → OSD → Lock →
  Session/power menu → (optional) dashboard/sidebar/drawers/nexus/
  areapicker/utilities/windowinfo.

## Phase 1 scope

Port caelestia's bar module, matching its actual sub-component breakdown:

- `OsIcon` — logo / launcher-trigger icon (top of bar)
- `Workspaces` — Hyprland workspace indicators
- `ActiveWindow` — focused window title
- `Tray` — system tray (with compact/expand behavior)
- `Clock`
- `StatusIcons` — battery, bluetooth, lock-state indicators
- `Power` — power button (bottom of bar)
- Popout panels — the slide-out panels triggered by clicking tray/clock/
  status-icon entries

This fully replaces Waybar. There is no dual-bar transition period —
`.configs/waybar/` is deleted in the same change that lands a verified
working replacement.

Out of scope for Phase 1: keyboard capslock/numlock/layout indicator (the
caelestia version of this depends on their native `Caelestia.Internal`
plugin, which we're not vendoring — can be reimplemented later via a
`hyprctl`-polling Process if wanted), and all non-bar modules (launcher,
notifications, OSD, lock, session, dashboard/sidebar/etc.) covered by later
phases.

## Architecture

**Location:** `.configs/quickshell/noctis/`, run via `qs -c noctis`
(Quickshell configs live under `~/.config/quickshell/<name>/`, matching how
caelestia itself is invoked as `qs -c caelestia`).

**Vendoring:** Pull over the relevant QML from caelestia-dots/shell:
- `modules/bar/` (Bar.qml, BarWrapper.qml, components/, popouts/)
- Shared primitives from `components/` that the bar depends on
  (`StyledRect`, `StyledText`, `MaterialIcon`, animation helpers,
  containers/controls)
- Relevant `services/` (`Hypr`, `Audio`, `Brightness`, `Time`, and whatever
  `StatusIcons`/`Tray` pull in)

caelestia-shell is GPL-3.0. Vendored files are a derivative work: keep a
short attribution comment pointing at the source repo and preserve license
obligations (carry the license text/notice in the vendored directory).
This is a licensing requirement, not just courtesy.

**Replacing the C++ config layer:** Every vendored file that imports
`Caelestia.Config`/`Tokens` gets that import swapped for two singletons we
write ourselves, isolated in their own files so upgrading later doesn't
touch consumers:
- `Tokens.qml` — hardcoded spacing/padding/radius values (seeded from
  caelestia's screenshots/behavior, tuned after live VM testing)
- `Config.qml` — hardcoded bar entry order/toggles (logo, workspaces,
  spacer, activeWindow, tray, clock, statusIcons, power) and per-module
  options (tray compact mode, scroll actions), as plain properties rather
  than a JSON-file-backed reactive system

**Hyprland integration:** Use Quickshell's own built-in
`Quickshell.Hyprland` module (framework-native, ships with Quickshell
itself, not caelestia's C++) for workspaces/active-window/monitor state.
This is what caelestia's `Hypr.qml` already wraps for that portion, so it
ports directly. The keyboard-state portion of `Hypr.qml` (which depends on
their native plugin) is dropped for Phase 1 per the out-of-scope note
above.

**Colors:** Keep wallust as the single source of truth for theming — this
is the part of "the nature of Noctis" worth explicitly preserving. Add one
more wallust template (`colors-quickshell` → generates a `Colours.qml`
singleton under the vendored tree) using wallust's native Jinja2
double-brace syntax (required because the output is a QML object literal
containing real braces, same reasoning already applied to `gtk.css` and
`colors-hyprland.lua` earlier this session). Wallpaper changes re-theme the
bar exactly like they already re-theme kitty/gtk/hyprland/rofi/mako. We are
explicitly *not* adopting caelestia's own Material-You-style `Colours.qml`
color-generation service — that would be a second, competing color
pipeline.

**System integration:**
- `hyprland.lua` → `startup.lua`: replace the Waybar exec-once with
  launching the new shell (`qs -c noctis`)
- `profiles/base/*.toml`: remove `waybar`; add `quickshell` (or
  `quickshell-git`, whichever exact package name package-hygiene
  verification confirms against the Arch/AUR APIs at implementation time —
  not guessed here) plus whatever icon/font packages the vendored
  components require (`material-symbols`, a Nerd Font already covered by
  the existing kitty/rofi Nerd Font dependency — confirm no gap)
- `.configs/waybar/` is deleted in the same change, once the replacement is
  verified working
- Any keybind currently shelling out to Waybar-specific scripts gets
  repointed at the Quickshell equivalent (exact IPC invocation syntax to be
  confirmed during implementation rather than assumed here)

**Verification:** Built and tested on the existing Proxmox test VM (VM 115,
`qm guest exec` + `grim` screenshot workflow already established this
session) with before/after screenshots, same as every other visual change
this session.

## Testing

- Visual: side-by-side screenshot comparison against caelestia's bar and
  against the previous Waybar layout, on the VM
- Functional smoke test on the VM: workspace switching, active window title
  updates, tray icon presence/click, clock display, status icons
  (battery/bluetooth/lock) reflect real state, power button triggers
  expected action, wallpaper switch re-themes the bar
- No automated test suite exists for the dotfiles repo generally
  (config/QML, not application code) — verification is manual/visual,
  consistent with how the rest of this repo has always been validated

## Explicitly not doing (Phase 1)

- Not vendoring caelestia's native C++ plugin or its build system
- Not adopting caelestia's Material-You color engine
- Not implementing capslock/numlock/keyboard-layout indicator
- Not touching Rofi, Mako, or swaylock yet (later phases)
- Not implementing any of caelestia's non-bar modules (launcher,
  notifications, OSD, lock, session, dashboard, sidebar, drawers, nexus,
  areapicker, utilities, windowinfo)
