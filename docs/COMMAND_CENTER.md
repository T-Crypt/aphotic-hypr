# Command Center — Design Doc

Status: **draft, not implemented.** Per the brief this responds to: nothing in
Steps 2–5 gets built until this doc is reviewed and the open conflicts below
are resolved one way or the other.

**Resolved since first draft:**
- Open Conflict #1 (Command Center vs. Dashboard) — **confirmed
  replace-in-place / upgrade of the current Dashboard.** §0/§1 below already
  assumed this; no rewrite needed.
- Open Conflict #4 (what "Claude" means) — **corrected twice.** First pass
  (env-var preset theory) was superseded after live-testing the actual
  Ollama host — see the rewritten §4 below for the final, verified shape.
- Open Conflict #2 (Workspaces tab scope) — **resolved, see the rewritten
  §2 below.** A workspace overview: every Hyprland workspace with its open
  windows, click to focus, built on the existing `Hypr.qml` service.
- Open Conflict #3 (clock-click behavior) — **resolved: always opens to
  the Dashboard tab**, no new hover-preview surface. Matches current
  click-to-open-Dashboard muscle memory; can revisit if that's missed in
  practice.
- Open Conflict #6 (API key storage location) — **resolved: separate
  `~/.config/aphotic/ai-keys.json`, `chmod 600`**, per §4's recommendation.
  Not folded into `shell.json`.

Only #5 (phase/versioning, informational — already answered in practice:
reuse `Anim.Emphasized` by name) and #7 (roadmap accuracy, already fixed
independently) remain, neither of which blocks implementation. **All
implementation-blocking conflicts are now resolved.**

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
- The global hotkey path is `qs -c aphotic ipc call dashboard toggle`
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
  own dashboard uses (per the brief's own description) — Aphotic already
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
| **Workspaces** | New, scoped below | Built on the existing `Hypr.qml` service |
| **AI Chat** | New | See §3/§4 below |

### Workspaces tab (resolved scope)

A workspace overview, not a full window-thumbnail switcher (no live window
previews/screenshots — that's real added complexity this doesn't need for
a first cut): one card per entry in `Hypr.workspaces`, each listing the
windows on it (grouped from `Hypr.toplevels` by `workspace.id`, one row per
window with its app icon via `Icons.getAppCategoryIcon` — the same
resolution `ActiveWindow.qml` already uses — and title text), the
currently-focused workspace visually distinguished (reuse the bar's own
`Workspace.qml`/`ActiveIndicator.qml` active-state styling for consistency
rather than inventing a second "this one's active" treatment). Clicking a
workspace card or a specific window row calls `Hypr.dispatch("workspace
<id>")` (or the window-specific focus dispatch, matching what
`Workspaces.qml`'s own click handling already does in the bar) and closes
Command Center. No drag-to-move-window-between-workspaces in v1 — that's
real added interaction complexity (drag handling, drop targets, Hyprland
dispatch for window-to-workspace moves) worth deferring until the simple
read-and-jump version is in use.

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
- The global hotkey (`qs -c aphotic ipc call dashboard toggle`) also stays
  as-is — same flag, already a second trigger path, nothing to add.
- **Resolved**: always opens to the "Dashboard" tab, no last-viewed-tab
  memory and no new hover-preview surface on the clock. Matches current
  click-to-open-Dashboard muscle memory, and avoids adding state-tracking
  (`ScreenState` growing a `lastCommandCenterTab` field) before it's clear
  that's actually missed in practice.

## 4. AI provider abstraction

### What already exists

`Configs/.local/lib/aphotic/commands/cmd_ai.sh` is real, not a stub:
`aphotic ai status` checks both the `claude` CLI and `ollama` reachability
(with loaded-model listing for Ollama), and `aphotic ai profile <name>`
writes to `shell.json` via `aphotic_json_set "ai.activeProfile" "$name"`
(the same jq-wrapped config convention — `APHOTIC_CONFIG_FILE`,
`aphotic_json_get`/`aphotic_json_set` in `globalcontrol.sh` — the brief asks
to follow). Profile *definitions* are an explicit `TODO` in that file
today. This is the right foundation to build the QML-side provider
abstraction against, not a parallel system.

### Open Conflict #4 — resolved (superseding the first env-var-preset theory)

First draft of this doc treated "Claude Code CLI" and "Claude API" as two
separate integration shapes (subprocess vs. HTTP client) needing two
distinct code paths, then a second draft collapsed them into one: the
theory that `claude-ollama`/`claude-anthropic` shell functions just toggle
`ANTHROPIC_BASE_URL`/`ANTHROPIC_API_KEY` around one `claude` CLI subprocess,
with Ollama treated as an Anthropic-shaped backend the CLI could be pointed
at directly.

**That second theory is also wrong — verified by testing the real host,
not assumed.** The Ollama host is `http://10.0.0.200:11434`, live and
healthy (`/api/tags` lists 7 loaded models: `gpt-oss:20b`, `gemma4:26b`,
`qwen3-vl:30b`, `devstral-small-2:24b`, `qwen3-coder:30b`, `qwen3:30b`,
`qwen3.8:27b`). But probing its API surface directly:

- `POST /v1/messages` (the Anthropic Messages API shape `claude` CLI
  speaks) → **HTTP 405**. Ollama's server does not implement this endpoint.
- `POST /v1/chat/completions` (OpenAI-compatible shape) → **HTTP 200**,
  full valid completion.

So `ANTHROPIC_BASE_URL` pointed at raw Ollama cannot work — there's no
Anthropic-shaped endpoint on the other end for the `claude` CLI to talk to,
regardless of what the interactive shell functions' names suggest they do.
(Those functions may predate this Ollama install, point at a different
host that did proxy-translate, or the user's mental model of what they do
was approximate — moot either way now that the live target has been
checked directly.)

**Final resolved shape**: only **Claude (real Anthropic)** goes through the
`claude` CLI subprocess, with a real `ANTHROPIC_API_KEY` and no
`ANTHROPIC_BASE_URL` override. **Ollama, Gemini, and ChatGPT are all direct
HTTP clients** — Ollama hits `POST http://<configured-host>:11434/v1/chat/completions`
(OpenAI-compatible, no API key needed), Gemini/ChatGPT hit their own real
endpoints with their own keys. This is a bigger simplification than the
env-var-preset theory: `services/ai/AiProviders.qml` needs exactly one
subprocess-based backend (Claude) and three HTTP-based backends
(Ollama/Gemini/ChatGPT) behind the same uniform interface, not a
CLI-vs-HTTP split that cuts across providers unpredictably.

### Proposed shape

New `services/ai/` singleton layer (mirrors the `services/` convention
already used for `Audio`, `Players`, `SystemUsage`, etc. — a QML singleton
per concern, not a monolith):

- `services/ai/AiProviders.qml` — the pluggable-backend registry. Each
  provider exposes a uniform QML-facing interface (`sendMessage(text)`,
  `streamingResponse` signal/property, `available: bool`,
  `requiresApiKey: bool`) regardless of what it does underneath.
- **Claude (Anthropic)**: subprocess to `claude` (matching how
  `SystemUsage.qml`/`Wallpapers.qml` already shell out via
  `Quickshell.Io.Process`/`execDetached`), with a real `ANTHROPIC_API_KEY`
  passed through and no `ANTHROPIC_BASE_URL` override. The only
  CLI-subprocess-based provider.
- **Ollama**: direct HTTP client, `POST http://<configured-host>:11434/v1/chat/completions`
  (OpenAI-compatible; verified live against `10.0.0.200:11434`, see the
  resolved §4 conflict above), no API key needed. First-class,
  default-selected provider — no key required to use it, only a reachable
  host.
- **Gemini / ChatGPT**: real, separate HTTP clients, each gated on their
  own API key. Greyed out in the provider pill row when no key is
  configured, exactly as the brief asks.
- The Ollama-model sub-pill (which local model to request) reads from the
  same `/api/tags` endpoint already probed above (or `ollama list`-equivalent
  enumeration `cmd_ai.sh status` already does against the configured host).

### API key storage — a real decision, not a detail

The brief says "using jq-wrapped config like the rest of the project" —
meaning `shell.json` via `aphotic_json_set`. That file is general shell
state (theme, bar settings, AI profile *name*), read and rewritten
casually by CLI commands, the QML shell, and theme-switch scripts, with no
special file permissions. Putting live API keys in the same file as
"is the bar persistent" is a real credential-hygiene smell — anything with
read access to `~/.config/aphotic/shell.json` (any user process, any future
`aphotic` subcommand that does a broad `jq` dump for debugging) gets the
keys too.

**Recommendation**: real secrets — the Anthropic key used by the Claude
preset, plus Gemini/ChatGPT keys — live in their own file,
`~/.config/aphotic/ai-keys.json`, created `chmod 600`, read only by
`cmd_ai.sh`/the QML AI service — not folded into `shell.json`. Still
jq-wrapped (same `aphotic_json_get`/`set`-style helpers, just pointed at a
different, tightly-permissioned file) so it doesn't introduce a second
config *format*, just a second config *file* for the one category of data
that actually needs isolation. The Ollama host address is not a secret and
can stay in regular `shell.json` config alongside the active-provider
selection. This should be confirmed before implementation, not assumed.

### UI

Two-pill row per the brief's end-4 reference: **Provider** (Ollama /
Claude / Gemini / ChatGPT — four independent backends per the resolved §4
shape: one CLI subprocess, three HTTP clients) and, conditionally, a
second pill for **Ollama model** (only shown when Ollama is the active
provider, populated from its `/api/tags` endpoint against the configured
host). Disabled/greyed provider entries for anything API-key-gated with no
key configured: Claude greys out with no Anthropic key on file, Gemini/
ChatGPT grey out with no key on file each; Ollama greys out only if its
configured host is unreachable (no key gate, since it needs none).

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

1. ~~**Command Center vs. Dashboard**~~ — **RESOLVED**: confirmed
   replace-in-place / an upgrade of the current Dashboard. §0/§1's "reuse
   what exists" reasoning stands as written.
2. ~~**Workspaces tab scope**~~ — **RESOLVED**: a workspace overview (one
   card per `Hypr.workspaces` entry, windows grouped from `Hypr.toplevels`,
   click to jump via `Hypr.dispatch`), no live window thumbnails and no
   drag-to-move in v1. See the rewritten §2.
3. ~~**Clock-click behavior**~~ — **RESOLVED**: always opens straight to
   the Dashboard tab, no new hover-preview surface. See §3.
4. ~~**"Claude" the provider**~~ — **RESOLVED (final)**: verified live
   against the real Ollama host (`10.0.0.200:11434`) that it has no
   Anthropic-Messages-API-shaped endpoint (405 on `/v1/messages`, 200 on
   OpenAI-shaped `/v1/chat/completions`) — the earlier env-var-preset
   theory doesn't hold. Final shape: Claude is the only `claude`-CLI-
   subprocess provider (real `ANTHROPIC_API_KEY`, no `ANTHROPIC_BASE_URL`);
   Ollama/Gemini/ChatGPT are all direct HTTP clients. See the rewritten §4.
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
6. ~~**API key storage location**~~ — **RESOLVED**: separate
   `600`-permissioned `~/.config/aphotic/ai-keys.json`, not folded into
   `shell.json`. See §4.
7. **`CLAUDE_ROADMAP.md` accuracy**: independent of Command Center, the
   roadmap's "Dashboard v2" feature-update entry is stale (describes
   `SystemUsage`/performance cards as unbuilt when they exist and are
   fairly complete). Worth a separate small pass to correct that entry
   regardless of what happens with Command Center, so the next reader
   doesn't re-discover this the hard way.
