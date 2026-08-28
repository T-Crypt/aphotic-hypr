# Roadmap

Single source of truth for what's shipped, what's open, and known bugs.
Replaces three maintainer-local working docs (`CLAUDE.md`,
`CLAUDE_ROADMAP.md`, `ROADMAP_FEATURES.md`) that used to track this
piecemeal and were gitignored — this file is tracked in git instead, so
it stays current for anyone working on the repo, not just on one
machine.

For the day-to-day contributor rule ("read the shipped Roadmap section
first, follow it"), see `README.md`'s own Roadmap section and
`CONTRIBUTING.md`. This file is the fuller backlog behind that summary.

---

## Shipped

### Settings Menu Overhaul
Substantially complete: theme grid, wallpaper picker (active theme +
browse-all + slideshow), Theme Creator, Personalization (accent color,
cursor/icon theme, per-status-icon overrides), Bar style picker with
live previews, Displays (read-only info), Clock/Date, OSD/Notifications,
AI (provider/model manager, Hardware Advisor, Assistant status), Power &
Security, Network/VPN, Workspace Profiles, Plugins (installed +
browse-available with category rail), System (`aphotic doctor` output,
Overview, Hardware), About.

Remaining gaps are tracked under [Open — Settings panel](#settings-panel).

### Feature tiers (from the original phased feature roadmap)
- **Tier 1 (AI-native):** Agent module (bar icon, session tracking),
  Intelligence quick-chat popout, AI Chat tab in Command Center. Two
  items still open — see [Open — AI-native](#ai-native-tier-1).
- **Tier 2 (dev-workflow):** launcher `@` project-switcher, VS Code live
  wallust theming. Three items still open — see
  [Open — dev-workflow](#dev-workflow-tier-2).
- **Tier 3:** partially open — see [Open — misc UX](#misc-ux-tier-3).
- **Tier 4:** fully shipped (no remaining items).

### OpenVPN / Network
All of Part C's OpenVPN integration shipped: NetworkManager-backed VPN
status/connect in Settings → Network, a bar VPN icon, quick-toggle
surfacing in the Dashboard.

### Plugin Ecosystem — Phase 2a/2b
(Folded in from the old `CLAUDE.md` planning doc, which scoped Phase
2a/2b/3 of the plugin system beyond Phase 1's single `on_theme_change`
hook.)

Shipped on `feature/plugin-ecosystem-phase2a`, same day
(2026-08-27):
- `plugin.toml` schema v2 — `[plugin].category` (`dev` / `security` /
  `mobile` / `ai` / `theming` / `productivity`), backward-compatible
  with v1 manifests (a v1 plugin with only `[plugin]` +
  `on_theme_change` still parses and runs unchanged).
- Two new hooks: `on_project_open` (fires from the launcher's `@`
  project-switcher) and `on_workspace_launch` (fires from Workspace
  Profiles). Both are declared via `capabilities` tags
  (`project-hook`/`workspace-hook`) and only fire for plugins that
  declare interest — not every enabled plugin. Same fire-and-forget,
  backgrounded, 5-second-timeout contract as `on_theme_change`.
  **Note:** the shipped shape uses the same flat `capabilities` array
  Phase 1 already had (e.g. `["theme-hook", "project-hook"]`), not the
  separate `[capabilities]` table the original planning doc sketched —
  documented as-built in `docs/PLUGIN_SYSTEM.md`.
- Security-category plugins live in a **separate index**
  (`APHOTIC_PLUGINS_SECURITY_INDEX_URL`), never fetched until
  `aphotic plugin trust-security-index` has been explicitly run once —
  mirrors the `exploit` layer's BlackArch confirmation pattern.
- Settings → Plugins category rail (reuses the existing Settings
  Control Center rail component).

Two plugins shipped the same day to validate the new hooks:
`direnv` (project-hook) and `workspace-session-log` (workspace-hook),
committed and pushed to `aphotic-plugins`' origin/main (`bbb5683`). The
doc's original third first-wave candidate
(libimobiledevice-bridge / an agent-session tracker) was dropped in
favor of these two, since both would have shipped inert — they need
capabilities that don't exist yet (CLI-subcommand registration,
`on_agent_event`; see [Open — Plugin system](#plugin-system)).

### Bug fixes / small QoL (2026-08-27 → 2026-08-28)
- Multi-monitor popout/IPC targeting scope — fixed.
- `aphotic reload` bug — fixed.
- `aphotic wallpaper --next` — now a real ordered cycle, not random.
- Silent matugen fallback — now warns instead of failing silently.
- Settings menu scrollbar width — widened, easier to grab without
  needing the scroll wheel.
- Bar popout switching no longer shifts button alignment (status icons
  stay at a fixed height; only the popout window below moves) — Reddit
  (r/UNIXPORN) feedback fix.
- `Settings.barVertical` inverted-name bug (2026-08-28) — the property
  actually controlled *horizontal* placement (full-width, top/bottom
  dock), backwards from its name and from the "Vertical orientation"
  toggle label in Settings → Bar/Personalization. Renamed to
  `barHorizontal` everywhere (pure identifier rename, ~150 call sites
  across `BarWindow.qml`, `Bar.qml`, `Workspace.qml`, `StatusIcons.qml`,
  and the rest of `modules/bar/` — no conditional logic changed, since
  every consumer's actual visual behavior was already correct, only the
  name was wrong); both Settings UI toggles relabeled to "Horizontal
  orientation" to match. `services/Settings.qml` migrates existing
  users' persisted `barVertical` key in `settings.json` on next load,
  same boolean value under the new name — no behavior change for
  existing installs. Verified live: toggling the property now correctly
  switches between a left/right-docked vertical bar and a top/bottom
  full-width horizontal bar.
- Launcher custom presets / visual style (2026-08-28) — a real second
  visual layout for the launcher, matching how Rofi ships different UI
  presets (not the config-preset interpretation originally guessed —
  clarified with the user before building). New Settings → Launcher
  category with a List/Grid picker (`Settings.launcherStyle`,
  persisted). Grid is a Rofi-drun-style icon grid, app-search mode
  only (a new `AppGridItem.qml` delegate, `GridView`-based, 4 columns
  × 3 rows); every other prefix mode (clipboard/emoji/windows/theme/
  wallpaper/project) always renders as the existing list regardless of
  the setting, since a grid doesn't suit those result shapes. The
  apps filter/sort logic was factored into one shared `appResults`
  property so list and grid can never drift against each other.
  Verified live via screenshot in both styles.
- Bar popout "snap-to"/clunky motion (2026-08-28) — longstanding
  complaint (r/UNIXPORN feedback, several partial fixes over prior
  sessions) that the hover popout felt jumpy and inconsistent across
  bar configurations. Root-caused by comparing against
  `caelestia-dots/shell`'s own popout wrapper (fetched from GitHub for
  the comparison): `modules/bar/popouts/Wrapper.qml`'s flyout computed
  its x/y position using its own `width`/`height` — which are
  Behavior-animated whenever the popout content resizes — so every
  frame of a resize animation fed a slightly different value back into
  the position formula, compounding with the position's own Behavior
  into visible wobble/jank, worst exactly when switching between two
  differently-sized popouts. Fixed the same way caelestia's wrapper
  does it: added `nonAnimWidth`/`nonAnimHeight` (read directly from the
  loader's raw `implicitWidth`/`implicitHeight`, bypassing the
  animated `width`/`height`) and drive x/y off those instead, so
  position always animates toward a stable target from frame one.
  Applied to both the main flyout and the agent flyout. Also fixed a
  real "SNAP-to" bug in `DockBar.qml`: its auto-hide reveal/hide slide
  used `Behavior on transform` targeting a `Translate`'s x/y, which
  never actually animates in QML (a `Behavior` fires on the target
  property's own value changing — `transform` stayed the same object
  reference the whole time, only its nested x/y changed — so the pill
  was snapping instantly with zero animation, unlike every other bar
  style). Moved the Behaviors onto the Translate's own x/y properties.
  Also fixed a minor consistency gap in `TaskbarBar.qml`'s task-group
  popout trigger, which set `currentCenter` as a one-shot value instead
  of `Qt.binding()` like every other popout trigger (Bar.qml,
  TaskbarBar's own statusIcons/tray branches) — could go stale if the
  taskbar row reflowed while the popout was open.
  **Follow-up gap found but not fixed here** (out of scope for "fix the
  existing animation," a real feature gap not an animation bug): Dock
  and Minimal bar styles have **no hover-popout system at all** —
  `DockBar.qml` never wires up a `popouts` property or `checkPopout`,
  and `MinimalBar.qml`'s `checkPopout` is a literal empty no-op. Only
  Full and Taskbar show popouts on hover today. This is real
  "not uniform across bar configurations," just a missing-feature kind
  rather than a broken-animation kind — building real popout support
  for Dock/Minimal is a separate, larger piece of work.

### Low-lift shell features
(From the old `CLAUDE_ROADMAP.md`'s "Planned: Shell Features" entry,
`feature/low-lift-shell-features`.) All of the low-lift tier shipped:
weather Dashboard card, eyedropper, DND toggle, wallpaper slideshow,
launcher app sorting by actual usage, Wi-Fi/Bluetooth/DND quick-toggle
card. Confirmed shipped via `docs/CHANGELOG.md`'s v1.1.0 entry.
Medium/bigger-lift items from the same doc are still open — see
[Open — Shell features](#shell-features-medium-lift).

### Aphotic Assistant
(From the old `CLAUDE_ROADMAP.md`, `feature/aphotic-assistant`.) Local
NVIDIA-only chatbot, opt-in via `install.sh --with-assistant`, shows up
as a fifth AI provider once installed. Its dependency on
`feature/llmfit-ai-layer` and `feature/intelligence-popout` is resolved
— both merged into `main` long ago (`guessOllamaTag` and the
Intelligence popout are both confirmed present and working). Remaining
gap: AMD/ROCm and CPU-only are not supported, gated on
`detect_nvidia()` — no near-term plan to change that.

---

## Open

### Bar
- Dock and Minimal bar styles have no hover-popout system at all (Full
  and Taskbar do). Found 2026-08-28 while fixing the popout
  animation's jank — see the "Bar popout snap-to/clunky motion" shipped
  entry above for the full writeup. `DockBar.qml` never wires up a
  `popouts` property; `MinimalBar.qml`'s `checkPopout` is a literal
  empty no-op. Real feature work, not a quick patch.

### Settings panel
- Sidebar module — not yet built.
- System updates action — not yet wired up.
- Theme-palette swatch view — not yet built.
- Theme picker overlay — likely obsolete given the shipped Theme grid;
  needs a decision rather than implementation.
- Tray context menus — blocked on Quickshell upstream (`QsMenuHandle`
  doesn't support this yet).
- Displays pane — partial (`[~]`). Live per-monitor resolution/scale
  editing is blocked on a real Hyprland limitation:
  `hyprctl keyword monitor` fails and `hyprctl eval` doesn't reapply.
  Not a quick patch.
- Settings tabs still to add: **Widgets**, plus the Displays gap above.
  (Time & Weather is already covered — `ClockPane.qml` has weather
  location + units; no separate tab is needed. Launcher custom presets
  shipped 2026-08-28, see below. An earlier working doc listed Time &
  Weather as still-open; that was stale and is corrected here.)

### Theming engine
- matugen as a second color-generation engine alongside wallust — not
  implemented (silent-failure case is fixed with a warning, but the
  engine itself doesn't exist).
- `theme.toml`'s `[overrides]` table — parsed but not consumed anywhere
  yet.

### Dashboard
- Organize the Dashboard into real tabs per `docs/COMMAND_CENTER.md`'s
  design — still just the current card layout.
- (Weather card is done — shipped as part of the low-lift shell
  features batch. An earlier working doc listed it as still-open; that
  was stale and is corrected here.)

### `aphotic` CLI polish
- `aphotic theme list` — no swatch thumbnail yet, text-only.

### AI-native (Tier 1)
- AI Chat context injection.
- Session handoff widget.

### Dev-workflow (Tier 2)
- Git status bar module.
- Build/test status OSD.
- Clipboard history with code-awareness.

### Misc UX (Tier 3)
- Workspace previews.
- Load-reactive bar accent.
- Focus mode.

### New component
- System monitor Quickshell component — track current processes,
  resources, PID, CPU, RAM, GPU, and process name, same GLASS UI as
  `Settings.qml`. Not started.

### Plugin system
Two genuinely separate "Phase 2/3" tracks exist here — easy to
conflate, kept distinct:

1. **Plugin Ecosystem Phase 3** (`on_agent_event`, from the old
   `CLAUDE.md` planning doc): blocked on the Live Agent Activity
   Module's own event schema landing first. Confirmed still not the
   case — `agent_hook.sh` only writes a bare `{event, tool,
   updatedAt}` per session; nothing downstream consumes it as real
   status yet. Also blocked on this phase: the security-category
   install-time confirmation-gate UX, and the `mobile` profile layer.
2. **`docs/PLUGIN_SYSTEM.md`'s own separate Phase 2/3** (§6 of that
   doc): Phase 2 is CLI subcommands (`aphotic <plugin-name> ...`
   dispatch, needs `_aphotic_dispatch` to also check
   `~/.local/share/aphotic/plugins/*/commands/cmd_*.sh` plus a
   `"cli"` capability + `[commands]` manifest table). Phase 3 is
   third-party QML panes injected into Settings → Plugins — deferred
   deliberately until Phase 1/2 get more real-world mileage, since it
   needs a stable `qs.services`/`qs.components` subset and real
   trust/sandboxing decisions. Neither is built.
3. **Accent-slot open question** (`docs/PLUGIN_SYSTEM.md` §5): still
   genuinely open, not resolved by the shipped OpenRGB Sync plugin — it
   hardcodes the same color4-or-fallback heuristic the doc flags as not
   guaranteed to be correct for every theme.
4. **Open design decisions carried over from the old CLAUDE.md doc**,
   never resolved:
   - `on_agent_event` payload shape: redacted envelope vs. full
     payload + opt-in `full_payload = true` flag (leaning redacted by
     default).
   - Whether security-category plugins should live in the main
     `aphotic-plugins` index at all, vs. a fully separate opt-in index
     (mirrors the BlackArch precedent of an explicit trust step).

First-wave plugin candidates by category (dev/security/mobile/ai/
theming/productivity) that haven't been built yet are still listed in
git history on the old `CLAUDE.md` if useful as a starting shortlist —
not reproduced here since it was explicitly "not a commitment to build
all of these."

### Shell features (medium lift)
(From the old `CLAUDE_ROADMAP.md`, `feature/low-lift-shell-features`'s
medium/bigger-lift tier — none of this is started.)
- Screen recorder (`wf-recorder` + the areapicker's existing
  region-select).
- Notification grouping in `Notifs.qml`.
- Lock-screen media controls (surface the Players MPRIS service on
  `Lock.qml`).
- Plugin lockfile (`plugins.lock.json`) — blocked on plugin system
  Phase 2/3 above.
- Fingerprint/U2F auth — not near-term.

### Security baselines
(From the old `CLAUDE_ROADMAP.md`, `feature/exploit-sublayers-disclaimer`
— explicitly deferred, nothing implemented.) Two proposed profile
tiers:
- **`recommended`** — ufw/firewalld default-deny, unattended-upgrades,
  fail2ban, sysctl hardening.
- **`max`** — AppArmor/SELinux enforcing, ptrace restrictions,
  USBGuard, auditd.

Real unresolved conflict with the `exploit-*` layers: ptrace
restrictions break gdb/pwndbg for `exploit-reversing`, and strict
MAC/seccomp breaks nmap SYN scans and monitor-mode wireless tooling for
`exploit-recon`/`exploit-network`. Needs a real per-tool-exception
design — not attempted yet. Also: the BlackArch-repo approach is
Arch-specific; a hypothetical non-Arch port would need an equivalent
(e.g. Kali repos), out of scope for now since no other distro is
supported.

### `services/ai/` architecture
litellm-as-local-proxy (one endpoint fanning out to
Ollama/OpenRouter/Anthropic) is a candidate to eventually replace the
hand-rolled routing in `services/ai/`, flagged as worth revisiting —
not a decision, no plan yet either way.

---

## Working conventions worth keeping

Process notes, not feature items — carried over because they've
mattered in practice:

- **No comments by default.** Only add one when the *why* is
  non-obvious (a hidden constraint, a workaround for a specific bug,
  something that would surprise a reader) — never restate what the
  code already says.
- **Verify UI changes live**, not just via type-checking/tests — start
  the shell, exercise the golden path and edge cases, take a screenshot
  when in doubt.
- **Check the remote before trusting local disk.** Local branches can
  go stale relative to `origin` (a past session's local `test` branch
  pointer drifted from `origin/test` after a push that didn't update
  it locally) — diff against `origin/<branch>` before assuming local
  state is current.
- **Local-model handoff:** when a design decision affects both a local
  service (`services/ai/`, hardware detection) and a remote/CLI-driven
  path, check both call sites before declaring something fixed — they
  drift independently (e.g. `cmd_theme.sh` vs. `Settings.qml`'s own
  load-time reassertion).
