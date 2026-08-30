# Aphotic — Unified Vision & Project State

**This is the single source of truth for what Aphotic is, what's shipped,
what's in progress, and what's planned.** It consolidates every planning,
architecture, and idea document previously scattered across `docs/` into
one navigable structure, organized by domain rather than by source file.

Consolidated 2026-08-30 from `docs/ROADMAP.md`, `docs/OPT-IN-FEATURES.md`,
`docs/PLUGIN_SYSTEM.md`, `docs/FRONTIER-UNIFIED.md`, `docs/BACKLOG.md`,
`docs/AGENT_TRACKING.md`, `docs/FEATURES.md`, `docs/IN_FLIGHT.md`,
`docs/LEDGER.md`, and `docs/wiki-pending/COMMAND_CENTER.md`. **Nothing was
deleted** — superseded docs live in `docs/archive/` with a pointer back
here; still-live reference docs (`docs/BACKLOG.md`, `docs/PLUGIN_SYSTEM.md`,
`docs/AGENT_TRACKING.md`, `docs/LEDGER.md`, root `CONTRIBUTING.md`) stay
where they are and are cross-referenced throughout, not duplicated.

**How to use this doc:**
- Root `CLAUDE.md` is the short orientation anchor — read that first.
- This doc is the full picture: architecture, the plugin system rewrite,
  per-domain status, known issues, backlog, and history.
- `docs/BACKLOG.md` stays the *operational pick list* (ID-based: `AGP-01`,
  `E3-02`, etc.) — this doc doesn't reproduce every ID, it gives the
  narrative and links out to it.
- `docs/LEDGER.md` stays the append-only session log of what actually
  shipped/broke/got fixed, day by day — this doc doesn't duplicate it.

---

## Table of contents

1. [Current architecture & principles](#1-current-architecture--principles)
2. [Modular plugin architecture (top priority)](#2-modular-plugin-architecture-top-priority)
3. [Per-domain status: AI, Gaming, Dev, Security](#3-per-domain-status-ai-gaming-dev-security)
4. [Known bugs / active issues](#4-known-bugs--active-issues)
5. [Backlog — captured, unscoped ideas](#5-backlog--captured-unscoped-ideas)
6. [Historical / superseded record](#6-historical--superseded-record)

---

## 1. Current architecture & principles

### 1.1 What Aphotic is

An Arch/Hyprland desktop rice built on Quickshell, with a real installer
(`install.sh`), a CLI (`aphotic`), a plugin system, and — the newest
addition — an opt-in AI-agent-aware layer (Agent Graph, provider tracking).
The base shell is theming/rice/Settings/core Quickshell modules; everything
domain-specific (AI, Gaming, Dev, Security) is opt-in on top of that base.

### 1.2 The overarching engineering rule

> **Compositor-First, GPU-When-Justified** — minimize RAM, CPU, IPC,
> allocations, polling, redraws and GPU utilization. GPU/RHI/QSG techniques
> are used because they reduce overhead or enable something otherwise
> impossible, never because GPU rendering looks impressive.

(From `docs/archive/FRONTIER-UNIFIED.md`, adopted project-wide via
`docs/BACKLOG.md`.) This is the yardstick the [GPU/polling debloat
backlog items](#41-refactors) are measured against, and the same
discipline the Agent Graph pipeline (§3.1) was built to demonstrate.

### 1.3 Hard architectural rules (non-negotiable)

Full rationale for each lives in `CONTRIBUTING.md` (QML/CLI/installer
conventions) and §10 of `docs/archive/OPT-IN-FEATURES.md`; the short list:

- Static `PanelWindow` geometry, `offsetScale` content-transform animation
  only — no exceptions for any new overlay, including gaming/security/dev
  visual indicators.
- No explanatory comments by default in QML/shell — only for a genuinely
  non-obvious workaround or safety warning.
- Singleton/component split — state lives in a singleton, components
  consume it.
- Flyout/popout chrome is shared (`PanelWindow` + open/close transition +
  hover-dismiss `HoverHandler`), never reinvented per-surface.
- Feature-branch-only development; nothing merges to `test` or `main`
  unattended; separable, independently revertible commits.
- No destructive automatic action anywhere, except the one documented
  exception: Security's post-engagement sanitization (§3.4) clearing
  scrollback/agent-context on exit, because *not* doing that automatically
  is the more dangerous default.
- Local-first telemetry, no cloud requirement, in any domain, ever.
- Every optimization/suggestion is reversible and requires explicit user
  action to apply — the Resource Engine (§2 of
  `docs/archive/OPT-IN-FEATURES.md`) never auto-kills, it always prompts.
- Every binary dependency the shell shells out to must be declared in
  **both** `profiles/base/full.toml` and `profiles/base/minimal.toml` —
  the Quickshell shell always loads in full regardless of install profile,
  so a missing dep in `minimal` is a silent runtime gap. (This exact rule
  is why the OpenVPN bug in §4.1 is a base-layer issue, not a full-tier
  one — see the decision recorded there.)

### 1.4 The three eras this repo has been through

1. **Rice + Settings** — the original shell, theming pipeline, Settings
   Control Center. Substantially complete (`docs/archive/ROADMAP.md`
   §Shipped).
2. **Plugin system Phase 1** — `on_theme_change` hooks, the OpenRGB
   reference plugin, then a manifest-v2 expansion (`project-hook`,
   `workspace-hook`, category rail, security index). Shipped; contract
   doc is `docs/PLUGIN_SYSTEM.md`.
3. **AI opt-in** — provider tracking, then the Agent Graph (a full
   zero-polling event pipeline + declarative graph renderer). Shipped at
   v1.2.0. This era is what taught the project the DETECT → APPLY →
   MONITOR → RESTORE shape now being generalized to Gaming/Dev/Security
   in §2–3.

---

## 2. Modular plugin architecture (top priority)

> This section is written fresh from first principles, per direct user
> instruction — it does **not** just carry over
> `docs/archive/OPT-IN-FEATURES.md`'s framing. That doc scoped Gaming/Dev/
> Security as **domain-level** opt-ins (pick "gaming," get everything
> gaming has). The real requirement is finer-grained than that, and this
> supersedes the domain-level framing as current direction.

### 2.1 Core principle

**Aphotic base = shell + rice/theming + Settings + core Quickshell modules
only.** Every domain (AI, Gaming, Dev, Security) *and every individual
capability within a domain* (Agent Graph, telemetry, flight recorder, a
specific gaming sub-plugin, etc.) is **independently installable and
independently removable**, with no partial or orphaned state left behind
in either direction.

Concretely, this means:

- Enabling "ai" → "harness" role support does **not** pull in the Agent
  Graph. A user can enable AI harness support and *separately* install or
  uninstall the Agent Graph as its own plugin on top of that, without
  pulling in anything else AI-related they didn't ask for.
- A user can install a handful of individual Gaming sub-plugins (e.g.
  `game-theme` + `game-mode`, see §3.2's sub-plugin table) without
  installing `game-telemetry` or `game-flight-recorder`, and later remove
  just one of those cleanly.
- This applies to every domain identically — Dev's `agent-context-handoff`
  vs. `env-drift-detector`, Security's `engagement-mode` vs.
  `recon-graph`, etc. (sub-plugin tables in §3.2–3.4) are all independent
  install units, not a package deal.

### 2.2 What "clean removal" means

Install and removal of a plugin must be symmetric and complete:

- **Config changes** made by enabling a plugin are reverted.
- **Files** the plugin added are removed.
- **Any dashboard tab / UI surface** it contributed disappears — no
  leftover config drift, no dead UI entries, no orphaned files.

This implies each plugin needs a **manifest of exactly what it touches**
— files written, config keys set, UI surfaces registered — so install and
remove can be derived from the same manifest rather than each being
hand-written and inevitably drifting apart. `docs/PLUGIN_SYSTEM.md`'s
existing `plugin.toml` (§3 of that doc) is the right foundation to extend,
not replace — it already has `[hooks]` and `capabilities`; what's missing
is the "what does this plugin own" declaration this requirement needs.

**Explicitly out of scope for this document:** the exact manifest field
names, the registry schema, and how install/remove diff against the
manifest. That's implementation work for a future prompt scoping directly
off this requirement — see the backlog item in §5.

### 2.3 Opt-in/opt-out is not install-time-only

The mechanism must work **outside `install.sh` entirely** — a user should
be able to opt in or out of any plugin at any point after initial install,
not just during first setup. `install.sh` remains the *suggested, default*
route for convenience (e.g. `install.sh --opt-in` presenting a modular
selection menu), but it cannot be the *only* route.

The underlying install/remove mechanism needs to be callable standalone:

- as a CLI command (extends `docs/PLUGIN_SYSTEM.md`'s existing
  `aphotic plugin install|enable|disable|remove` verbs — those already
  exist for the theme-hook-plugin case and are the natural home for this),
  and/or
- via a Settings.qml plugin-manager UI (Settings already has a "Plugins"
  category per `docs/PLUGIN_SYSTEM.md` §7 — this would be a real
  extension of it, not a new surface).

**Open decision, not settled here:** whether the mechanism is CLI-only,
UI-only, or both from day one. Flagged for the implementation prompt.

### 2.4 Agent Graph is the forcing example

Agent Graph must be **fully extracted into its own opt-in plugin** — not
part of the base install under any circumstance, and not bundled with the
"ai" opt-in by default. This directly supersedes the framing in
`docs/archive/OPT-IN-FEATURES.md`'s closing notes, which treated Agent
Graph as something that "will eventually" move to `aphotic-plugins/`; this
document makes that a formal requirement, not an aspiration.

Concrete rule: Agent Graph should only install/activate when **both**:
1. the "ai" profile is enabled, **and**
2. at least one **"harness"**-role entry is configured, per the
   harness/provider role field in `services/ai/AgentRoles.qml`
   (`docs/AGENT_TRACKING.md` is the contract doc for what a harness is —
   Claude Code, Codex, OpenCode; a bare Ollama provider has nothing for
   the graph to render).

This is also the leading candidate explanation for the black-screen-on-
restart bug (§4.1) — see that entry for why it's flagged as "worth
checking, not assumed."

### 2.5 install.sh needs a full refactor, not a patch

Cross-referencing this against the already-partially-implemented
`lib/install/` process: `install.sh` needs a genuine redesign around
"everything is an independently toggleable plugin," not incremental
patches on top of its current profile/layer model. This is recorded as a
formal backlog item (§5.2), not decided here — the scope of that refactor
depends on the manifest/registry design from §2.2, which is itself
deferred to implementation.

### 2.6 What this section deliberately does not decide

- The manifest/registry schema (§2.2).
- CLI vs. UI vs. both for the standalone mechanism (§2.3).
- The exact shape of `install.sh --opt-in`'s selection menu.

All three are real requirements captured clearly enough that a future
prompt can scope implementation directly from this section — that is the
intended handoff, not a gap.

---

## 3. Per-domain status: AI, Gaming, Dev, Security

### 3.1 AI — shipped, with the plugin-extraction requirement above

**Shipped:** provider/harness tracking (`docs/AGENT_TRACKING.md`), the
Agent Graph (radial call-tree renderer, replay, hardware-tiered
degradation — full technical detail in `docs/archive/FEATURES.md`,
condensed permanent summary in `docs/archive/ROADMAP.md`'s "Agent graph —
shipped architecture" section), harness hooks for Claude Code, Codex, and
OpenCode (all three documented in `docs/AGENT_TRACKING.md` §3 and its
per-harness subsections). Zero-polling was fully achieved as of
2026-08-30 (`AGF-07`/`AGF-08`, see `docs/LEDGER.md`'s final entry) —
`AgentProviders.qml` now tails the same event log the graph does, with
`pgrep` demoted to a 60s hookless-machine-only reconcile.

**In progress / open:**
- Agent Graph plugin extraction (§2.4) — formal requirement, not started.
- Harness-vs-provider audit for AI chat surfaces — see §4.1 (Codex
  incorrectly selectable as a chat provider).
- UI polish backlog (`AGP-*` in `docs/BACKLOG.md` §A1) and functional
  gaps (`AGF-*` in §A2) — see that doc for the full ID list.
- GPU rendering track (G1 shader materials → G2 window-peek → G3
  GPU-native graph) — sequenced, not started; full spec in
  `docs/archive/FEATURES.md`, backlog IDs `D-01`–`D-03`.

**Planned (Dev-pillar AI crossover):** Agent Context Handoff — pausing/
backgrounding a project's agent sessions on project switch and priming
the new project's context — is scoped under Dev (§3.3) since the trigger
is a project switch, not an AI event, but it's an `ai`-category plugin
capability. Explicitly flagged as a prompt-injection-shaped risk if
tracker data is untrusted (auto-injecting context vs. surfacing it) — no
decision made yet, default to surfacing only.

### 3.2 Gaming — planned, Phase 0/1 not started

**What's genuinely novel** (not "Steam + MangoHud + GameMode," from
`docs/archive/OPT-IN-FEATURES.md` §3.1):
1. AI ↔ Gaming resource negotiation via the shared Resource Engine (§3.5
   below) — no other Linux gaming setup negotiates GPU claims against a
   running local LLM.
2. Gaming Flight Recorder — a ring-buffer black-box for Linux gaming.
3. Game → Theme integration, reusing the exact existing wallust/palette
   pipeline and `on_theme_change` hook — zero new theming code.
4. Performance regression detection against a *learned per-game baseline*
   (not just showing FPS — MangoHud does that already).

**Sub-plugins** (each independently installable per §2.1):

| Sub-plugin | Responsibility | Phase |
|---|---|---|
| `game-discovery` | Steam/Heroic/Lutris/Bottles/Wine/RetroArch/PCSX2/Dolphin detection, event-driven | 1 |
| `game-mode` | Enter/exit gaming state: notification suppression, compositor tweaks, GameMode/MangoHud | 1 |
| `game-profiles` | Per-game config, learned incrementally | 1 |
| `game-theme` | Wallpaper/palette swap on launch via existing `on_theme_change` | 1 |
| `game-resource-manager` | Registers GPU/CPU claims with the Resource Engine | 1 |
| `game-telemetry` | FPS/frametime/VRAM/temp, event-sampled not polled | 2 |
| `game-optimizer` | Baseline learning + regression detection, suggests only | 2 |
| `game-flight-recorder` | ~60s ring buffer, dumped on crash-signal | 2 |
| `proton-tools`, `rgb-sync`, `discord-presence` | Convenience integrations | Later, community |

**Status: none of this is built.** The one directly-requested piece
(gaming-mode VRAM release, killing local Ollama models before a
Steam/Proton launch) is tracked as its own backlog item, §5.1 —
explicitly **not started**, and per explicit user instruction must not be
implemented piecemeal across sessions once picked up (own feature branch,
full PR/CI/merge cycle, README mention only once actually working).

### 3.3 Dev — planned, Phase 0/1 not started

**What's genuinely novel** (`docs/archive/OPT-IN-FEATURES.md` §4.1):
1. **Project-as-Profile** — opening a project directory triggers the same
   DETECT → LOAD → APPLY → MONITOR → RESTORE cycle as a game launch.
2. **Agent Context Handoff** — switching projects backgrounds the
   previous project's Agent Graph sessions (visually, not killed) and
   primes the new project's context. Nothing else on Linux does this.
   Carries the prompt-injection caveat noted in §3.1.
3. **Environment drift detection** — `mise`/container/lockfile versions
   vs. what the repo declares, passive/informational only.
4. **Build/test regression detection** — same baseline-learning pattern
   as Gaming's FPS regression detection.
5. **Dev Flight Recorder** — reuses the *same* core ring-buffer primitive
   Gaming's flight recorder needs (see §3.5 — this sharing is why the
   ring buffer belongs in core, not duplicated per-domain).
6. **Dev ↔ AI/Gaming resource negotiation** — same Resource Engine, no
   new UI.

**Sub-plugins:**

| Sub-plugin | Responsibility | Phase |
|---|---|---|
| `project-discovery` | Terminal cwd + editor root + git root, event-driven | 1 |
| `project-mode` | LOAD/APPLY/RESTORE: workspace layout, `mise` env, container up/down | 1 |
| `agent-context-handoff` | Background prior project's agent sessions, prime new context | 1 |
| `dev-resource-manager` | Registers CPU/GPU/container claims | 1 |
| `env-drift-detector` | Passive toolchain/container drift warning | 2 |
| `build-telemetry` | Per-project baseline build/test duration, flags regressions | 2 |
| `dev-flight-recorder` | Consumes core ring-buffer primitive for terminal/log capture | 2 |
| `port-radar` | Per-project port/service map, extends the already-planned host-info popout | 2 |

**Dashboard crossover:** `docs/archive/wiki-pending/COMMAND_CENTER.md`'s
tab design for the Dashboard is largely already shipped —
`modules/dashboard/DashboardContent.qml` already has the five tabs and
Loader-per-tab cross-fade that doc specified (confirmed in
`docs/LEDGER.md`'s "Queued/open" section). Any further Dashboard
reorganization work should check current state before assuming the old
design doc's gap list is still accurate.

**Status: none of the Dev opt-in plugins are built.**

### 3.4 Security — planned, Phase 0/1 not started

**Not** a "harden my desktop" tier (that's the separate, also-deferred
"Security baselines" backlog item, §5.2). This is a profile for security
research / pentest workstation use. **What's genuinely novel**
(`docs/archive/OPT-IN-FEATURES.md` §5.1):

1. **Engagement Mode with unmissable visual state** — VPN connect /
   engagement start triggers a desktop-wide visual signal (bar accent,
   border, wallpaper tint via the existing theme pipeline), directly
   targeting the "ran a command against the wrong target because I forgot
   which VPN I'm on" mistake.
2. **Scope Guardian** — passive, advisory-only outbound-target checking
   against a declared scope list. Never blocks, never intercepts.
3. **Evidence Chain Recorder** — reuses the same core ring-buffer
   primitive as Gaming/Dev, with "always-on for session duration" as the
   trigger instead of crash-only.
4. **Recon Graph** — the Agent Graph pattern, repurposed to visualize
   live attack-surface discovery (BloodHound/Caido/Nmap) in real time,
   reusing the same QML graph-rendering module.
5. **Post-Engagement Sanitization** — the one place in the whole system
   where "automatic on exit" is *stricter* than elsewhere (§1.3's one
   documented exception to "no destructive automation").
6. **AI-Assisted Triage With a Hard Guardrail** — no AI-suggested command
   executes without explicit user action, ever, during an engagement.
7. Security ↔ AI/Gaming/Dev resource negotiation — same Resource Engine.

**Sub-plugins:**

| Sub-plugin | Responsibility | Phase |
|---|---|---|
| `engagement-mode` | DETECT → APPLY visual state + workspace → RESTORE | 1 |
| `scope-guardian` | Passive advisory scope-check | 1 |
| `security-resource-manager` | Registers claims (BloodHound/Neo4j, scans) | 1 |
| `post-engagement-sanitizer` | Agent backgrounding, scrollback clear, identity revert | 1 (safety-critical) |
| `ai-triage-guardrail` | Enforces explicit-approval-before-execution | 1 |
| `evidence-recorder` | Session-duration capture via core ring-buffer | 2 |
| `recon-graph` | Live attack-surface graph, reuses Agent Graph's renderer | 2 |
| BloodHound CE / Caido / libimobiledevice / scrcpy integrations | Tool-specific | Later |

**Safety boundaries (stricter than any other domain):** Aphotic never
executes an offensive action itself. Scope Guardian and the AI triage
guardrail are advisory/blocking-of-automation only. Evidence capture is
local-only, never uploaded, user-prompted before anything persists.

**Status: none of this is built.**

### 3.5 The shared substrate all four domains sit on

The highest-leverage piece, and why §2's plugin architecture matters more
than any single domain: AI, Gaming, Dev, and Security all implement the
*same* profile state machine (DETECT → LOAD PROFILE → NEGOTIATE RESOURCES
→ APPLY STATE → MONITOR → DETECT ANOMALY → EXIT → RESTORE), and all four
would otherwise reinvent "who gets the GPU right now" independently.

| Layer | Lives in | Why |
|---|---|---|
| Profile state machine | **Core** | Identical shape across all domains |
| Resource Engine (claims, arbitration, one negotiation-prompt UI contract) | **Core** | Cross-domain by definition |
| Event bus (compositor/window/process → profile triggers) | **Core** | Extends existing Hyprland/Quickshell IPC |
| State snapshot/restore | **Core** | Same mechanism regardless of trigger |
| Ring-buffer primitive (flight recorders) | **Core** | Gaming, Dev, and Security all want "record last N seconds of {stream}, dump on {trigger}" — building it once avoids a third reimplementation |
| Domain-specific detection/telemetry/UI | **Plugin**, per §2 | Opt-in, zero cost when disabled |

**Resource Engine specifics** (`docs/archive/OPT-IN-FEATURES.md` §2):
tracks *claims*, not continuous usage polling (reacts to
registration/deregistration events); detects contention, doesn't do APM;
never auto-kills — always surfaces the same one negotiation-prompt shape
(`[Suspend] [Keep Running] [Ignore]`) regardless of which two domains are
colliding; never touches kernel/sysctl; never terminates a process
directly, only asks the *owning plugin* to pause via its own graceful-stop
hook. No new always-running daemon — dormant until a plugin registers a
claim.

**Status: Phase 0 (the core substrate itself) has not been started.**
Nothing in §3.2–3.4 can ship its "genuinely novel" pieces until this
lands — this is the correct thing to scope and build first among the four
domains.

**Open questions carried forward, unresolved:**
- Static vs. dynamic claim declaration (Phase 1 can start static).
- Where the ring-buffer primitive lives precisely — Quickshell singleton
  vs. small Go-core component (touches the QML/Go boundary, needs a
  deliberate call).
- Engagement-mode's visual signal needs a real design pass, not a
  placeholder, given how safety-critical "always know your VPN state" is.

---

## 4. Known bugs / active issues

### 4.1 Bugs

**Settings.qml custom OpenVPN function is broken.**
Needs investigation and a real fix — not attempted in this consolidation
pass. Three linked causes to capture, not just the UI symptom:
- The UI-level bug itself (unspecified root cause yet — needs
  investigation).
- NetworkManager's OpenVPN plugin was not auto-installed as a dependency.
- Manual permission changes were required to let OpenVPN open a tunnel on
  `localhost:1337`.

*Open decision, resolved here (2026-08-30):* **the `openvpn` package
belongs in the base tier, i.e. both `profiles/base/full.toml` and
`profiles/base/minimal.toml`** — not gated to a "full-tier-only" opt-in.
Reasoning: `CONTRIBUTING.md`'s own installer convention already states
that any binary dependency the shell shells out to must be declared in
**both** profile files, because the Quickshell shell always loads in
full regardless of install profile (`services/Vpn.qml` and
`modules/settings/panes/NetworkPane.qml` are core shell components, not
gated behind an opt-in layer) — a missing dep in `minimal` is a silent
runtime gap, not a smaller install, per that same rule (§1.3). As of this
writing there is an **uncommitted, in-progress change** on this branch's
starting tree that adds `openvpn` to `profiles/base/full.toml`'s package
list but not yet to `minimal.toml` — noted here as supporting evidence
for the decision (the fix is already headed the right direction, just
incomplete), not something this consolidation pass touches or completes.
The eventual bug fix should finish that: add `openvpn` to `minimal.toml`
too, then resolve the permissions issue for the `localhost:1337` tunnel.

**Bar.qml: bioluminescent glow behind the active-workspace-summary block
has hard/square edges.**
The glow highlights the rectangle's corners rather than sitting cleanly
behind a rounded shape. Needs the glow geometry corrected to match rounded
edges. Not investigated further here.

**Black-screen-on-restart.**
Restarting the Aphotic shell service produces a black screen with no
wallpaper; bar icons and volume OSD sliders take roughly a minute to
become visible. Appears to be a rendering-buffer issue, suspected related
to Agent Graph initialization — already partially troubleshot in an
earlier session (reference not locatable in current `docs/LEDGER.md`;
flag for whoever picks this up to search prior session transcripts if
available). **Cross-reference, not an assumption:** worth checking
whether this resolves once Agent Graph is extracted to its own opt-in
plugin (§2.4) and stops loading by default — but that has not been
verified, and the bug should be treated as open regardless of the
plugin-extraction timeline.

**AI chat harness-vs-provider audit needed.**
Confirmed issue: Codex is a **harness**, not a **provider**
(`docs/AGENT_TRACKING.md`'s role classification, sourced from
`services/ai/AgentRoles.qml`), and should not appear as a selectable chat
provider the way Claude currently does. The audit needs to cover **every**
current chat entry point (AI Chat dashboard tab, Quick Intelligence
popout) against the role field, not just the Codex case — there may be
other harness/provider mismatches not yet found.

### 4.2 Refactors

- **GPU/resource debloat.** Idle GPU utilization sits around 20% at rest
  — too high, needs a full pass to trim active consumption and leave
  headroom for real compute workloads. Likely intersects with the polling
  and lazy-instantiation items below rather than being one isolated fix.
- **Agent Graph plugin extraction** — see §2.4. Formal requirement now,
  supersedes the old "bundled with AI opt-in" framing.
- **`install.sh` full refactor/modernization** — see §2.5. Not a patch
  job; a redesign around "everything is an independently toggleable
  plugin," built on the existing half-implemented `lib/install/` process.
- **Polling audit.** Every current polling interval needs review for
  conversion to event-driven / "sleeping until seen." Explicitly called
  out: no reason to monitor every GPU simultaneously when the UI only
  ever displays one — monitor only what's actually visible/active. The
  Agent Graph's own `AgentProviders.qml` fix (§3.1, `AGF-07`/`AGF-08`) is
  the reference example of what this looks like done correctly.
- **Lazy surface instantiation.** Expensive UI surfaces (Agent Graph,
  detail panels, anything non-trivial to construct) should not be
  instantiated until actually opened, not built eagerly at shell startup.

**These three — debloat, polling, and lazy-surface instantiation — are
the same underlying discipline** already documented as acceptance
criteria in the Resource Engine core section (§3.5 above,
`docs/archive/OPT-IN-FEATURES.md` §2.4's "Dependencies & performance").
Treat them as one coordinated pass when picked up, not three unrelated
backlog entries — see `docs/BACKLOG.md`'s own framing of this same point
under "How the agent graph measures against it."

---

## 5. Backlog — captured, unscoped ideas

This section captures newly reported items at consolidation time (2026-08-30)
plus pointers to where the larger, ID-based backlog lives. **Nothing here is
scoped or designed** — that happens when an item is picked up, matching
`docs/BACKLOG.md`'s own "pick an ID, then scope it" convention.

### 5.1 Community-facing asks (still open as of 2026-08-30)

- **Gaming-mode VRAM release** (kill/unload local Ollama models before a
  Steam/Proton launch) — **not started**. Full requested shape (systemd
  oneshot or `cmd_gaming.sh`, Steam launch-wrapper trigger, `SUPER+SHIFT+G`
  keybind) is recorded in `docs/LEDGER.md`'s "Community / needs dedicated
  testers" section. Per explicit standing user instruction: this does not
  get implemented piecemeal across sessions — own feature branch, full
  branch → PR → CI → merge cycle, README mention only once working
  end-to-end.
- **AMD GPU tester needed** — all Ollama/AI-assistant GPU support and
  verification so far is NVIDIA-only. Needs someone with real AMD
  hardware to validate ROCm-path GPU acceleration and drive the
  already-queued `install.sh` AMD support work.

### 5.2 The larger ID-based backlog

`docs/BACKLOG.md` remains canonical for everything else — its own
sections cover: Agent system polish/functional-gaps/held-decisions
(`AGP-*`/`AGF-*`/`AGH-*`), small/medium ready-to-pick items (`B-*`/`C-*`),
the GPU rendering track (`D-*`), the long-range frontier
(`E1`–`E6`: compositor-native core, performance discipline, dev flavours,
Gaming, Security, the overarching GPU-native-observability vision), and
tooling/meta (`F-*`, including "un-gitignore `docs/`" — **done as part of
this consolidation**, see the PR description). This document's Modular
Plugin Architecture requirement (§2) and the `install.sh` refactor (§4.2)
are new entries that should be added to `docs/BACKLOG.md`'s own list
(section D or a new section) the next time that file is touched — not
duplicated here as IDs, since ID assignment belongs to that doc's own
convention.

### 5.3 Frontier ideas not yet plugin-shaped

`docs/archive/FRONTIER-UNIFIED.md` (archived, absorbed here) already did
the work of sorting ~50 long-range ideas into "core architecture" vs.
"plugin-shaped" — see `docs/BACKLOG.md` §E for the full ID list. Its one
actionable conclusion not yet reflected in `docs/PLUGIN_SYSTEM.md`: two
new capability tags worth adding when Phase 1a's manifest work happens —
`game-hook` (fire on game process exec/exit) and `security-hook` (fire on
a security-relevant event) — following the exact shape of the shipped
`theme-hook`/`project-hook`/`workspace-hook` tags.

---

## 6. Historical / superseded record

Superseded documents live in `docs/archive/`, each with a one-line pointer
back to where its content now lives in this document. Nothing was deleted.

| Archived doc | What it was | Superseded by |
|---|---|---|
| `docs/archive/ROADMAP.md` | Shipped/open summary, long-form context | §1, §3, §4 above; `docs/BACKLOG.md` stays live for open-work IDs |
| `docs/archive/FEATURES.md` | Agent Graph's own phase-by-phase spec | §3.1's AI domain summary |
| `docs/archive/OPT-IN-FEATURES.md` | Domain-level Gaming/Dev/Security opt-in proposal | §2 (finer-grained plugin model) + §3 (domain novelty content absorbed as-is) |
| `docs/archive/FRONTIER-UNIFIED.md` | Frontier-idea-to-plugin-shape analysis | §5.3's capability-tag conclusion; `docs/BACKLOG.md` §E for the raw ID list |
| `docs/archive/IN_FLIGHT.md` | Older per-batch working notes | Already superseded by `docs/LEDGER.md`; noted here for completeness |
| `docs/archive/wiki-pending/COMMAND_CENTER.md` | Dashboard tabs design proposal | §3.3's Dashboard crossover note (mostly already shipped) |
| `docs/archive/superpowers/plans/2026-08-19-quickshell-bar.md` | Implementation plan for the (now-shipped) Quickshell bar | The bar itself, shipped; kept as historical record only |
| `docs/archive/superpowers/specs/2026-08-19-quickshell-bar-design.md` | Design spec for the same | Same |

**Docs that stayed in place** (still actively useful as standalone
references, cross-referenced throughout this document rather than
absorbed or moved):

- `docs/BACKLOG.md` — the live, ID-based operational pick list.
- `docs/PLUGIN_SYSTEM.md` — the plugin system's contract doc (Phase 1
  shipped, manifest v2 shipped; §2 of this document extends it, doesn't
  replace it).
- `docs/AGENT_TRACKING.md` — the agent event pipeline's contract doc.
- `docs/LEDGER.md` — the append-only session-by-session log of what
  shipped, broke, and got fixed. Continues to be appended to; not
  restructured by this consolidation.
- `docs/CHANGELOG.md` — user-facing version changelog.
- `docs/wiki-pending/*.md` (`bar-styles.md`, `cli.md`, `exploit-layer.md`,
  `terminal_games.md`) — reference material pending Wiki publication, not
  planning docs; out of scope for this consolidation.
- Root `CONTRIBUTING.md`, `README.md`, `CODE_OF_CONDUCT.md`,
  `SECURITY.md`, `RELEASE_NOTES.md` — user-facing/contributor docs,
  untouched, cross-referenced from §1.3 and elsewhere above.
