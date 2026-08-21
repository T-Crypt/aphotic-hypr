# Command Center — Design Doc

Status: **draft, not implemented.** Per the brief this responds to: nothing in
Steps 2–5 gets built until this doc is reviewed and the open conflicts below
are resolved one way or the other.

## 0. The one finding that reframes everything else

Before window strategy or tabs: **a large fraction of what's being asked for
already exists**, under the `Dashboard` name, and the roadmap doc undersells
how much of it is built. Concretely:

- `modules/dashboard/DashboardWindow.qml` is *already* a full-screen,
  transparent, `WlrLayer.Overlay` `PanelWindow` with click-outside-to-dismiss
  and an Escape handler, with its content (`DashboardContent`) simply
  `anchors.centerIn: parent`. This **is** "the layer-shell/panel technique
  caelestia uses for its dashboard" the brief asks for — it's not something
  to go build, it's the file this whole feature should probably extend
  in place.
- `modules/dashboard/Dashboard.qml` is 1018 lines and already contains a full
  performance section — `HeroCard`/`GaugeCard`/`StorageGaugeCard`/
  `NetworkCard` components backed by the real `SystemUsage`/`NetworkUsage`
  services, covering CPU, GPU (when present), memory, per-disk storage, and
  network throughput with live history graphs. `CLAUDE_ROADMAP.md`'s
  "Feature updates" list still describes this as unbuilt ("Dashboard v2...
  needs a real Cpu/Memory/Storage service — no vendored equivalent exists
  yet, this is new work"). That line is stale. The service and most of the
  proposed "Performance" tab's content already ship today, just flattened
  into one continuous view rather than tab-separated.
- `modules/bar/components/Clock.qml` already toggles the Dashboard on click
  (`onClicked: root.screenState.dashboard = !root.screenState.dashboard`).
  There is no separate hover-popout on the clock the way Battery/Network/etc
  have — clicking it already opens the *entire* current Dashboard (clock +
  calendar + media), not a lightweight preview. So "click the calendar bar
  module instead of the current date/time popout" describes a conflict that
  doesn't quite exist in the form stated: there's nothing narrower to
  preserve or replace here, just one click handler to point at a bigger
  surface.
- The global hotkey path is `qs -c noctis ipc call dashboard toggle`
  (documented in `README.md`), which flips the same `screenState.dashboard`
  boolean `Clock.qml`'s click handler does. One flag, two triggers, already
  true today.

**What genuinely doesn't exist**: tab chrome (no `TabBar`/`SwipeView`/
`currentTab` anywhere in `modules/dashboard/`), a "Workspaces" tab of any
kind, the AI Chat tab, and the provider abstraction underneath it.

Given this, the real Step-1 decision isn't "how do I build a new floating
window" — it's:

> **Does "Command Center" replace/rename Dashboard in place, or does it live
> alongside it as a second surface?**

Everything below assumes **replace-in-place** (rename `Dashboard` →
`CommandCenter` conceptually, restructure its one long scroll into four
tabs, keep `DashboardWindow.qml`'s window as-is) because building a second
full-screen overlay window that duplicates clock/calendar/media/performance
content the first one already renders would be real, avoidable duplication.
This is flagged as **Open Conflict #1** below — it's a real product decision,
not a technical one, and should be confirmed before Step 2 starts.

## 1. Window / surface strategy

**Recommendation: no new window.** Extend `DashboardWindow.qml` in place.

- It's already a fullscreen transparent `PanelWindow` on `WlrLayer.Overlay`
  with `ExclusionMode.Ignore` — nothing reserves screen space, it draws over
  everything, and it's dismissed by click-outside or Escape. This is
  standard practice for a "floating-looking" surface built on layer-shell
  rather than a real Hyprland toplevel, and it's the same trick caelestia's
  own dashboard uses (per the brief's own description) — Noctis already
  has it, doesn't need to import it.
- **No Hyprland `windowrulev2` float/center rule is needed.** Real floating
  toplevel rules (see `Configs/hypr/windows.lua`'s existing
  `float-lutris`/`center-lutris` pair, `move = "50% 50%"`) only matter for
  windows Hyprland itself tiles — a layer-shell surface on the overlay layer
  was never a tiled toplevel to begin with, so there's nothing for Hyprland
  to float or center. If a real toplevel path is chosen instead (see the
  fallback below), *that's* when a windowrule becomes necessary.
- **Centering**: already solved — `DashboardContent { anchors.centerIn:
  parent }`. A tabbed version keeps the same centering; only the content
  inside grows a tab bar and swaps its body per tab.

**Fallback (not recommended)**: if Command Center is deliberately meant to
be a *different kind* of surface than Dashboard — e.g., something that
needs real Hyprland floating-window semantics (resizable by the user,
draggable, appears in `hyprctl clients`, alt-tabbable) rather than an
overlay a click anywhere dismisses — that's a real toplevel, which
Quickshell can produce as a plain `Window` (not `PanelWindow`) rendered
through XWayland/native Wayland toplevel, matched by a new
`windowrulev2` in `windows.lua` (`float = true`, `move = "50% 50%"`, plus a
`size` rule) keyed on whatever window class Quickshell assigns it. This is
more moving parts for a capability nothing in the brief's actual feature
list (tabs, AI chat) requires, so it's called out here only so the tradeoff
is explicit, not because it's the recommended path.

## 2. Tab structure

Proposed tabs, mapped against what already exists:

| Tab | Status | Source |
|---|---|---|
| **Dashboard** | Exists today, needs no new content | `DashDateTime`, `DashCalendar`, `DashMedia` — currently the top `RowLayout` in `DashboardContent.qml` |
| **Performance** | Exists today, needs extraction from the flat layout | `Dashboard.qml`'s `HeroCard`/`GaugeCard`/`StorageGaugeCard`/`NetworkCard` (CPU/GPU/memory/storage/network), already reading `SystemUsage`/`NetworkUsage` |
| **Workspaces** | New | Nothing exists. Scope needs defining — see Open Conflict #2. |
| **AI Chat** | New | See §3/§4 below |

Mechanically: replace `DashboardContent.qml`'s `ColumnLayout` (currently:
top row of 3 cards, then a `Loader` for the big `Dashboard` performance
block) with a caelestia-style tab row (icon + label per tab, matching the
brief's reference) driving a `StackLayout` or a `Loader`-per-tab swap. Given
this codebase's existing preference for `Loader { active: ...; source
Component: ... }` over `StackLayout` elsewhere (see `BarWrapper.qml`,
`popouts/Wrapper.qml`), a `Loader`-based tab switch keyed on a
`currentTab: string` property is the more idiomatic fit here than
introducing `StackLayout` as a new pattern.

Reuse `Anim.Emphasized`/`Tokens.anim` for the tab-switch content transition
(cross-fade, matching the bar popout morph work — see §5), not a new
animation curve.

## 3. Trigger wiring

- `Clock.qml`'s existing `onClicked: root.screenState.dashboard =
  !root.screenState.dashboard` stays exactly as-is — it already does what's
  being asked (open the surface from the calendar bar module).
- The global hotkey (`qs -c noctis ipc call dashboard toggle`) also stays
  as-is — same flag, already a second trigger path, nothing to add.
- New: which tab opens by default. Two reasonable options: always open to
  "Dashboard" (simplest, matches current click-to-open-dashboard muscle
  memory), or remember the last-viewed tab in `ScreenState` (richer, but
  another piece of state to keep in sync). Recommend starting with "always
  Dashboard tab" and only adding memory if it's actually missed in use —
  matches this repo's general bias toward not building state-tracking that
  isn't clearly needed yet.

**Open Conflict #3** (see checklist): the brief asks to flag whether the
click should open Command Center "instead of, or in addition to" the
current date/time popout. As established in §0, there is no existing
separate date/time popout to preserve — so this reduces to: should clicking
the clock open straight to a specific tab (e.g. jump straight to
"Dashboard" tab, which already shows date/time), or should there be a
*new*, narrower hover-preview on the clock (matching the Battery/Network/
Bluetooth status-icon pattern) as a quick-glance layer *in front of*
opening the full Command Center? That would be new scope not currently
implied by anything else in the brief.

## 4. AI provider abstraction

### What already exists

`Configs/.local/lib/noctis/commands/cmd_ai.sh` is real, not a stub:
`noctis ai status` checks both the `claude` CLI and `ollama` reachability
(with loaded-model listing for Ollama), and `noctis ai profile <name>`
writes to `shell.json` via `noctis_json_set "ai.activeProfile" "$name"`
(the same jq-wrapped config convention — `NOCTIS_CONFIG_FILE`,
`noctis_json_get`/`noctis_json_set` in `globalcontrol.sh` — the brief asks
to follow). Profile *definitions* are an explicit `TODO` in that file
today. This is the right foundation to build the QML-side provider
abstraction against, not a parallel system.

### Open Conflict #4 — "Claude" means two different things here

The brief lists providers as "Ollama, Claude, Gemini, ChatGPT (all via API
key)". But `cmd_ai.sh` already treats **Claude Code** (the `claude` CLI —
what this assistant *is*, run via subprocess, authenticated through the
user's existing Claude Code login/subscription, agentic and stateful) as a
first-class citizen alongside Ollama, explicitly distinct from a raw API-key
integration. A "Claude" entry in the AI Chat tab's provider list could mean
either:

- **Shell out to the `claude` CLI** — no API key needed, reuses the user's
  existing Claude Code auth, but is a CLI-subprocess integration (spawn,
  parse output, no true token-level streaming the way an SDK stream gives
  you) rather than a clean HTTP chat-completions call.
- **A real Anthropic API call** with a separately-configured API key,
  architecturally identical to the Gemini/ChatGPT entries.

These aren't the same feature, and conflating them under one "Claude"
pill would misrepresent which one the user is actually talking to (and
which billing/auth path is in play). This needs an explicit decision
before §4 code exists — not something to default silently. Given the
project's own stated identity ("Claude Code + Ollama as first-class
citizens", `cmd_ai.sh` already codifying that split), the more consistent
reading is: **Ollama and Claude Code are the two first-class, no-separate-
API-key providers** (Ollama via local HTTP, Claude Code via CLI
subprocess), and Anthropic API / Gemini / ChatGPT are the optional,
API-key-gated tier — i.e. four visible entries, but two different
integration shapes underneath, not four uniform HTTP clients.

### Proposed shape

New `services/ai/` singleton layer (mirrors the `services/` convention
already used for `Audio`, `Players`, `SystemUsage`, etc. — a QML singleton
per concern, not a monolith):

- `services/ai/AiProviders.qml` — the pluggable-backend registry. Each
  provider exposes a uniform QML-facing interface (`sendMessage(text)`,
  `streamingResponse` signal/property, `available: bool`,
  `requiresApiKey: bool`) regardless of what it does underneath.
- Backend implementations as `Process`-based QML (matching how
  `SystemUsage.qml`/`Wallpapers.qml` already shell out via
  `Quickshell.Io.Process`/`execDetached`), not a native plugin:
  - **Ollama**: local HTTP against `localhost:11434`'s
    `/api/chat` (streaming NDJSON), no key. First-class, default-selected
    provider per project identity.
  - **Claude Code**: subprocess (`claude -p "<prompt>" --output-format
    stream-json` or equivalent), parsed incrementally. First-class,
    no key (reuses existing CLI auth).
  - **Anthropic API / Gemini / ChatGPT**: real HTTP clients, each gated on
    an API key. Greyed out in the provider pill row when no key is
    configured, exactly as the brief asks.

### API key storage — a real decision, not a detail

The brief says "using jq-wrapped config like the rest of the project" —
meaning `shell.json` via `noctis_json_set`. That file is general shell
state (theme, bar settings, AI profile *name*), read and rewritten
casually by CLI commands, the QML shell, and theme-switch scripts, with no
special file permissions. Putting live API keys in the same file as
"is the bar persistent" is a real credential-hygiene smell — anything with
read access to `~/.config/noctis/shell.json` (any user process, any future
`noctis` subcommand that does a broad `jq` dump for debugging) gets the
keys too.

**Recommendation**: keys live in their own file,
`~/.config/noctis/ai-keys.json`, created `chmod 600`, read only by
`cmd_ai.sh`/the QML AI service — not folded into `shell.json`. Still
jq-wrapped (same `noctis_json_get`/`set`-style helpers, just pointed at a
different, tightly-permissioned file) so it doesn't introduce a second
config *format*, just a second config *file* for the one category of data
that actually needs isolation. This should be confirmed before
implementation, not assumed.

### UI

Two-pill row per the brief's end-4 reference: **Provider** (Ollama /
Claude Code / Claude API / Gemini / ChatGPT) and, conditionally, a second
pill for **Ollama model** (only shown when Ollama is the active provider,
populated from `ollama list` — `cmd_ai.sh`'s `status` subcommand already
knows how to enumerate these). Disabled/greyed provider entries for
anything API-key-gated with no key configured, per the brief.

## 5. Theme consistency

No new work needed beyond following existing convention: every color in
the new tabs/chat UI reads from `Colours.palette.*` (never a hardcoded
hex), text contrast follows the `contrastOn`/`mutedOn`/`legibleAccent`
helpers already in `Colours.qml` (the WCAG-based fixes from this session,
not the old brightness-guess approach), and rounding uses `Tokens.rounding.*`
tokens (per this session's bar rounding audit — `Tokens.rounding.full` for
any pill/circle shape, no ad-hoc `height/2` math). The chat message
bubbles, model-pill row, and tab bar should be built as `StyledRect`/
`StyledText`-based components (the shared base components used everywhere
else in this shell) rather than raw `Rectangle`/`Text`, so they
automatically inherit the theme-reactive color/behavior wiring instead of
needing it re-derived.

## 6. Animation reuse

The brief asks to reuse "whatever Behavior/easing values were tuned for
the bar popouts". The concrete, current answer (not a Task-N reference —
see Open Conflict #5 on why that numbering doesn't resolve cleanly): this
session's `popouts/Wrapper.qml` rework added real `Behavior on
x/y/width/height/radius/opacity`, all on `Anim { type: Anim.Emphasized }`
— `Tokens.anim.emphasized`, a compound no-overshoot bezier
(`durations.normal` = 400ms by default for the plain `Emphasized` enum
value). Tab-switch content cross-fades and any Command-Center-specific
open/close motion should reuse that same `Anim.Emphasized` token rather
than tuning a new curve — the whole point of centralizing it in `Tokens.qml`
was so future motion work doesn't reinvent it per-surface.

## Open conflicts checklist (resolve before Step 2)

1. **Command Center vs. Dashboard**: replace-in-place (this doc's working
   assumption) or a genuinely separate second surface? If separate, most of
   §0/§1's "reuse what exists" reasoning doesn't apply and this doc needs a
   rewrite of those sections.
2. **Workspaces tab scope**: completely undefined by the brief beyond the
   caelestia reference naming it. Workspace switcher? Per-workspace window
   list? Something else? Needs a concrete spec before it can be built —
   right now it's a label with no content plan.
3. **Clock-click behavior**: jump straight into a specific Command Center
   tab, or add a new narrower hover-preview on the clock in front of it
   (new scope, not currently implied elsewhere)?
4. **"Claude" the provider**: Claude Code CLI (no key, first-class) vs.
   Anthropic API (key-gated, same tier as Gemini/ChatGPT) — these need to
   both exist as distinct entries, not be conflated into one.
5. **Phase/versioning mismatch**: the brief references "Phase 3.6 Task 8"
   for the popout animation work to reuse. The current `CLAUDE_ROADMAP.md`
   (v4) doesn't use phase/task numbering at all anymore — it's organized as
   "Immediate goal" + "Quality debt" + "Feature updates" lists, a framing
   change from whatever earlier version (v2/v3) used numbered
   phases/tasks (some of that older numbering survives only as inline code
   comments, e.g. `Colours.qml`'s "Task 8"/"Task 2" references). Practical
   answer given in §6: reuse `Anim.Emphasized` by name, since that's the
   actual current identifier for the tuned values — but the roadmap doc
   itself needs a decision on where Command Center fits: it doesn't cleanly
   match "Quality debt" (nothing here is fixing existing breakage) or the
   existing "Feature updates" list (which doesn't mention it at all,
   including under Dashboard v2, which arguably should have been the entry
   this grows from). Recommend adding it as a new named entry under
   Feature updates once scope is settled, rather than trying to retrofit
   phase numbering that the current doc has already moved past.
6. **API key storage location**: `shell.json` (as literally stated in the
   brief) vs. a separate `600`-permissioned `ai-keys.json` (this doc's
   recommendation, §4). Real security tradeoff, not a style choice.
7. **`CLAUDE_ROADMAP.md` accuracy**: independent of Command Center, the
   roadmap's "Dashboard v2" feature-update entry is stale (describes
   `SystemUsage`/performance cards as unbuilt when they exist and are
   fairly complete). Worth a separate small pass to correct that entry
   regardless of what happens with Command Center, so the next reader
   doesn't re-discover this the hard way.
