> **Archived 2026-08-30.** Superseded by [`docs/APHOTIC_UNIFIED_VISION.md`](../APHOTIC_UNIFIED_VISION.md) — its shipped/open summaries are folded into that doc's Architecture & Principles and Per-Domain Status sections. Kept here for full historical detail; `docs/BACKLOG.md` remains the live pick-list.

# Roadmap

> **Consolidated 2026-08-29.** Open work from this file now also appears in
> [`BACKLOG.md`](BACKLOG.md) — the single pick list used by "let's work on a
> feature" sessions (section B, C and D). Nothing here was deleted; this file keeps the
> long-form context behind those one-line entries.

> **Correction to the paragraph below:** this file is *not* tracked in git.
> `docs/` is gitignored, so everything in here is maintainer-local. Anything
> that must reach contributors belongs in `README.md` or `CONTRIBUTING.md`.

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

### Notifications
- **App-icon resolution doesn't cross-reference installed desktop
  entries.** Found 2026-08-29 (`docs/LEDGER.md`'s "Documented, not
  built" section A has the full writeup). Notifications now correctly
  render whatever icon a sending app's D-Bus payload actually included
  (a real bug fixed the same day — see LEDGER item 6), but for apps
  that send no icon hint at all, there's still no fallback to the same
  desktop-entry-based icon resolution the launcher already has. Real
  work: matching a notification's sender against an installed desktop
  entry (not a guaranteed 1:1 string match).
- **No Aphotic-branded template for system/shell-originated
  notifications.** Same LEDGER section — `assets/aphotic-mark-frame.svg`
  is already vendored and used by `components/AphoticMark.qml`
  elsewhere in the bar, but nothing wires a themed version of it into
  notifications specifically. Needs a real classification mechanism for
  "this is a system notification" (the existing `-a aphotic` app-name
  convention this codebase's own `notify-send` call sites already use
  is a plausible signal, not yet confirmed as the intended one) plus a
  distinct visual template, not just an icon swap.

### Launcher
- **Grid mode has no left/right keyboard navigation.** Confirmed
  2026-08-29 (`docs/LEDGER.md`'s "Documented, not built" section B):
  `Launcher.qml` wires `Keys.onDownPressed`/`onUpPressed` to
  `grid.moveCurrentIndexDown()`/`moveCurrentIndexUp()` but has no
  `onLeftPressed`/`onRightPressed` handlers at all, despite `GridView`
  already exposing the matching `moveCurrentIndexLeft()`/`Right()`
  methods. Narrow, low-lift fix when next picked up.
- **Grid mode hard-caps visible results with no pagination.**
  `appResults.slice(0, gridMaxShown)` (12 cells, 4×3) silently drops
  everything past the cap — no scroll, no "+N more." List mode has no
  such ceiling. This is the concrete mechanism behind "can't see every
  installed app the way Rofi's drun mode does."
- **General grid-mode polish (centering/margins) and a font-unification
  ask (browser vs. shell typography) were both raised 2026-08-29 but
  not yet investigated** — see `docs/LEDGER.md` for exactly what's
  still unclear about each before either is actionable.

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

### Agent graph — shipped architecture (condensed, 2026-08-29)

Permanent summary of the agent graph workstream, so this survives
`docs/FEATURES.md` (which stays as the historical log rather than being
deleted, per the append-and-strike-through rule).

**Pipeline.** `Configs/.local/lib/aphotic/agent_hook.sh` is a thin `exec`
wrapper around `agent_hook.py`, one process per Claude Code hook firing
(~23 ms, down from ~70 ms). It writes three sinks from one schema: a
rotating live stream (`agent-events.jsonl`), the bar's existing per-session
snapshot (`agent-sessions/<id>.json`, unchanged shape), and a durable
per-run archive (`agent-runs/<id>.jsonl`, 25 runs x 2 MB) that replay reads.
`services/ai/AgentGraphService.qml` tails the live stream with one
long-lived `tail -F` into a `SplitParser` — no polling — and every record is
idempotent by `(sessionId, event, toolId, t)`.

**Rendering.** Declarative, not native: `modules/agentgraph/GraphLayout.qml`
(radial call tree, concentric rings, fit clamped at 0.75x) and `GraphView.qml`
(edges grouped by status into three `ShapePath`s fed by `PathMultiline`,
nodes as pills, one shared `flowClock` driving every edge particle).
Surfaced as a Command Center tab; the renderer takes `sessions` as a plain
property and knows nothing about tabs. Replay reuses the same renderer with
a different clock via a shared reducer (`AgentGraphService.applyTo`).

**Tiering.** `AgentGraphService.tier` resolves from the detected GPU and
demotes one step while Ollama holds models resident. Tiers scale node
budget, particle density and event-buffer size — never the look.

**Measured.** JS force layout (rejected) 3.54 ms/frame at 150 nodes on a
software-rendered VM; radial ships instead and costs **0.00% CPU at rest
with 55 nodes**. ~10% CPU on that same VM while one call is in flight, which
is glow/particle rendering under llvmpipe, not layout.

**Known limitations.** Subagent parentage relies on the `Agent` call's
`PostToolUse.tool_response.agentId`; without it the fallback attaches calls
to the session root. Click-to-focus matches a terminal by `cwd` leaf against
window titles and fails silently. Replay position is view-local state. The
"shareable summary" half of run export was never built.

**Gating.** The whole stack follows the installer's `ai` layer through
`services/InstallProfile.qml` — absent, not idle, when off.

### GPU rendering track (G1 → G2 → G3)

Recorded 2026-08-29 as a first-class sequenced track, not parked ideas.
Technical scope in `docs/FEATURES.md`; ledger context in `docs/IDEAS.md`.
Kept here because it outlives both — `docs/FEATURES.md` gets deleted when
the agent graph ships, and G3 is a second pass over that same surface.

- **G1 — Shader-driven telemetry materials.** Live system/agent telemetry
  as shader uniforms on bar segments and chrome. The warm-up rung:
  establishes the `.qsb` pipeline and contributor build step, no C++ module
  and no install-time compile. Depends on nothing.
- **G2 — True window-peek thumbnails.** `wlr-screencopy` output bound to a
  live `QSGTexture` via a custom `QQuickItem`. Core difficulty is Wayland
  buffer handling (DMA-BUF import, format/modifier negotiation, frame sync
  and lifetime), not rendering. First compiled C++ module shipped to users;
  brings the install-time build story with it. Depends on G1.
- **G3 — GPU-native multi-agent execution graph.** The agent graph
  re-rendered with `QSGGeometryNode`/`QSGMaterial` and instanced geometry,
  layout relaxation moved to `QRhi` compute. Depends on G1, G2, and on the
  declarative graph being finished and useful — it replaces a renderer
  rather than creating one. Feasibility already proven (a
  `QSGGeometryNode`-emitting `QQuickItem` was built and imported into
  Quickshell 0.3.0 during agent-graph Phase 0); what's open is cost, not
  possibility.

Each rung pays for the next one's infrastructure, which is why the
expensive one is last. Hardware tiering applies across the whole track:
scale how much is simulated, never how it looks, and never compete with a
resident local model for VRAM.

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
