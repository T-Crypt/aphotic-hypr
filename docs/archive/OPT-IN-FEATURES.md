> **Archived 2026-08-30.** Superseded by [`docs/APHOTIC_UNIFIED_VISION.md`](../APHOTIC_UNIFIED_VISION.md)'s Modular Plugin Architecture section, which replaces this doc's domain-level opt-in framing with a finer-grained per-capability plugin model per direct user instruction. The Resource Engine design and per-domain (Gaming/Dev/Security) novelty content here is still accurate and is absorbed into the unified doc's Per-Domain Status section — kept here in full as the original design proposal.

# Aphotic Opt-In Intelligence Layers
### Gaming, Dev, and Security — Architecture & Design Proposal

**Status:** Draft for review
**Target location:** `docs/APHOTIC_OPT_IN_INTELLIGENCE_LAYERS.md`
**Related branches:** `feature/resource-engine-core`, `feature/gaming-opt-in`, `feature/dev-opt-in`, `feature/security-opt-in`
**Precedent:** AI opt-in (shipped) — Agent Graph, provider adapters, `on_theme_change` hooks

---

## 0. Why this document exists

The AI opt-in proved a pattern: Aphotic doesn't just *install tools*, it gives the desktop **awareness** of a domain (AI agents) and lets the shell **react** to it — the Agent Graph makes agent activity observable, not just present.

This document extends that pattern to three more opt-in domains — **Gaming**, **Dev**, and **Security** — and, more importantly, defines the **shared substrate** all four domains (AI, Gaming, Dev, Security) sit on top of, so we build one good primitive instead of four bespoke ones.

> **Aphotic = an adaptive Linux desktop runtime.**
> Opt-in profiles give it domain awareness. The Resource Engine lets those domains negotiate instead of collide.

---

## 1. Core Concept: Opt-In Intelligence Profiles

Each domain (AI, Gaming, Dev, Security) becomes a **Profile** — a first-class object with the same lifecycle shape, so the shell, the plugin system, and the Resource Engine only need to understand one contract.

```
DETECT
  ↓
LOAD PROFILE (config + learned state)
  ↓
NEGOTIATE RESOURCES (Resource Engine, if contention)
  ↓
APPLY STATE (desktop, GPU/CPU, workspace, theme, tools)
  ↓
MONITOR (lightweight, event-driven telemetry)
  ↓
DETECT ANOMALY → surface, don't auto-fix
  ↓
EXIT DETECTED
  ↓
RESTORE PREVIOUS STATE
```

Every profile (AI, Gaming, Dev, Security) implements this same state machine. This is the reusable core — **not** a gaming-specific or dev-specific concept. Building it once in core, and letting each opt-in domain be a plugin that plugs into it, is the highest-leverage architectural decision in this document.

### 1.1 What lives in core vs. what's a plugin

| Layer | Lives in | Why |
|---|---|---|
| Profile state machine (above) | **Core** | Identical shape across all domains; duplicating it per-domain is the exact mistake we avoided with `on_agent_event`. |
| Resource Engine (arbitration, negotiation UI contract) | **Core** | Cross-domain by definition — AI vs. Gaming vs. Dev vs. Security all need the same conflict-resolution primitive. |
| Event bus (compositor/window/process events → profile triggers) | **Core** | Already exists in spirit via Hyprland/Quickshell IPC; extend, don't rebuild. |
| State snapshot/restore (desktop state capture) | **Core** | Theme, workspace layout, monitor config, notification state — same restore mechanism regardless of who triggered the transition. |
| Game detection, per-game profiles, gaming telemetry, flight recorder | **Plugin** (`gaming/`) | Domain-specific logic, opt-in, zero cost when disabled. |
| Project/language detection, dev telemetry, session continuity | **Plugin** (`dev/`) | Same reasoning. |
| Engagement mode, scope guardian, tool orchestration | **Plugin** (`security/`) | Same reasoning. |
| Domain-specific UI (bar widgets, popouts) | **Plugin-owned QML modules**, loaded conditionally by core when the plugin is enabled | Keeps base install light; matches existing plugin taxonomy. |

Nothing gaming/dev/security-specific ships in the base install. The base install gains: the state machine contract, the Resource Engine, and the snapshot/restore mechanism — all of which the AI opt-in *already needed* and partially built ad hoc. This is a refactor-forward, not scope creep.

---

## 2. The Aphotic Resource Engine (core, shared)

This is the single highest-priority piece. Without it, Gaming/Dev/Security/AI each reinvent "who gets the GPU right now" independently.

```
                    APHOTIC
                       │
          ┌────────────┼─────────────┬────────────┐
          │            │              │            │
         AI          GAMING          DEV        SECURITY
          │            │              │            │
          └────────────┴──────────────┴────────────┘
                             │
                     RESOURCE ENGINE
                             │
              ┌──────────────┼──────────────┐
              │               │              │
          GPU / CPU        Desktop        Process
          Memory           State           Registry
          Power            Theme           (who owns what)
```

### 2.1 Responsibilities

- **Track claims, not just usage.** Each active profile registers a lightweight *claim* ("Ollama: 17.8GB VRAM, background priority", "Cyberpunk 2077: GPU, foreground priority"). The engine doesn't poll continuously — it reacts to claim registration/deregistration events.
- **Detect contention, not performance.** The Resource Engine's job is conflict *detection and arbitration UI*, not being an APM tool. Actual telemetry (FPS, VRAM%, build times) belongs to each domain plugin.
- **Never auto-kill.** The engine always surfaces a choice. The only fully automatic behavior is *restoring prior state on exit*, because that's non-destructive by construction (it's a rollback).
- **One negotiation contract, reused everywhere:**

```
{domain} Resource Conflict

{claimant} is currently using {amount} {resource}.
{requestor} is requesting {resource} at {priority}.

[Suspend {claimant}]   [Keep Running]   [Ignore]
```

This exact shape handles "Ollama vs. Cyberpunk," "BloodHound's Neo4j vs. a Dev container build," "a full test suite vs. an active Claude Code agent," etc. One UI, one Quickshell popout, four consumers.

### 2.2 Arbitration model (Phase 1)

- Priority is **declared per-profile, not computed**. Gaming defaults to foreground-priority when a game has input focus. AI/Dev default to background-priority. Security engagements default to foreground-priority for network/proxy tools, background for passive tools (BloodHound ingestion).
- Conflict = two claims on the same constrained resource (GPU VRAM, GPU compute, high CPU core count) where combined claims exceed a configurable safety margin.
- No automatic suspension in Phase 1 — only detection + prompt. Automatic "suspend and auto-restore" (as in the original gaming spec) is a **Phase 2** feature, gated behind an explicit opt-in setting per profile pair (e.g., "always suspend AI for gaming, don't ask").

### 2.3 Safety boundaries

- Resource Engine never touches kernel/sysctl.
- Resource Engine never terminates a process directly — it asks the *owning profile plugin* to pause/suspend via that plugin's own graceful-stop hook (Ollama: unload model; Dev: pause container; Security: pause scan). This keeps destructive capability scoped to the plugin that understands the workload, not a generic kill switch in core.
- All arbitration decisions are logged locally (for the eventual per-domain flight recorders) but never phoned home.

### 2.4 Dependencies & performance

- Built on existing event sources: Hyprland IPC (window/workspace events), process exec/exit events (via existing process-watching used for Agent Graph), GPU query via existing `nvidia-smi`/`rocm-smi`-style polling **only when a profile with GPU claims is active** — zero idle cost when no opt-in profiles are enabled.
- No new always-running daemon. The engine is a QML/Go-backed singleton that's dormant (no polling, no timers) until a plugin registers a claim.

---

## 3. Gaming Opt-In — "Aphotic Gaming Intelligence" (Gaming Autopilot)

### 3.1 What's genuinely novel here (not "Steam + MangoHud + GameMode")

1. **AI ↔ Gaming resource negotiation** (Section 2) — the standout differentiator from the original brainstorm. No other Linux gaming setup negotiates GPU claims against a running local LLM.
2. **Gaming Flight Recorder** — a ring-buffer black-box for Linux gaming. Nobody else does this at the desktop-shell level.
3. **Game → Theme Integration** — the desktop visually becomes part of the game, using the *exact same* wallust/palette pipeline the AI opt-in and theming system already use. Zero new theming code, just a new trigger source.
4. **Performance Regression Detection against a learned per-game baseline** — not just "show me FPS" (MangoHud already does that), but "this run is 27% below your own historical baseline for this game."

### 3.2 Architecture

**Core dependency:** Profile state machine + Resource Engine (Section 1–2). No gaming-specific code in core.

**Plugin: `aphotic-plugins/gaming/`**

| Sub-plugin | Responsibility | Phase |
|---|---|---|
| `game-discovery` | Unified detection: Steam, Heroic, Lutris, Bottles, Wine/Proton prefixes, RetroArch, PCSX2, Dolphin, native binaries. Process-exec-event driven, not polling. | 1 |
| `game-mode` | Enter/exit gaming state on detection: notification suppression, compositor tweaks, GameMode/MangoHud invocation. Implements the profile state machine. | 1 |
| `game-profiles` | Per-game config (GPU/CPU/env/launch opts/workspace/monitor/audio/theme). Learned incrementally — first run captures defaults, user/agent can tune. | 1 |
| `game-theme` | Wallpaper/palette swap on game launch, reusing existing `on_theme_change` hook and wallust pipeline. | 1 |
| `game-resource-manager` | Registers GPU/CPU claims with the Resource Engine; implements the AI↔Gaming negotiation prompt. | 1 |
| `game-telemetry` | FPS/frametime/1%-lows/GPU/VRAM/temp collection, local-only, event-sampled not continuously polled. | 2 |
| `game-optimizer` | Baseline learning + regression detection ("27% below baseline"). Suggests, never auto-applies. | 2 |
| `game-flight-recorder` | Ring buffer of recent telemetry (~60s), dumped to disk on crash-signal detection. | 2 |
| `proton-tools`, `rgb-sync`, `discord-presence` | Convenience integrations. | Later, community-contributable |

### 3.3 Event flow (Phase 1 happy path)

```
process exec event (Hyprland/Quickshell watcher)
  → game-discovery matches known launcher/binary pattern
  → game-mode: LOAD PROFILE
  → game-resource-manager: register GPU claim
      → Resource Engine: contention check
          → if AI workload active + VRAM tight → negotiation prompt
  → APPLY STATE: theme swap, workspace layout, notification suppress, GameMode/MangoHud launch
  → game exits (process exit event)
  → game-resource-manager: deregister claim
  → RESTORE previous desktop state
```

### 3.4 Telemetry & safety

- Local-first, opt-in, no cloud. Flight recorder writes to `~/.local/share/aphotic/gaming/sessions/`.
- No automatic driver/kernel/sysctl changes — "hardware-aware optimization" (item 8 in the original brainstorm) is *recommendation only* in Phase 1.

### 3.5 Phase 1 vs. later

- **Phase 1:** discovery, mode transition, per-game profile storage, theme integration, resource negotiation with AI.
- **Phase 2:** telemetry, regression detection, flight recorder.
- **Later / community:** RGB sync, Discord presence, unified launcher UI, per-game auto-tuned kernel-adjacent settings (with explicit consent gate, same pattern as the exploit-profile disclaimer gate).

---

## 4. Dev Opt-In — "Aphotic Dev Intelligence" (Project Autopilot)

The Dev domain has the same shape problem as Gaming: focus/workload switches (here: **project switches**, not game launches) that should transition desktop + resource state, and workloads (builds, containers, agents) that compete for the same GPU/CPU/VRAM the AI and Gaming layers care about. The genuinely novel piece is treating **project context switches** as first-class state transitions, the same way Gaming treats game launches — and feeding that context directly into the Agent Graph instead of leaving it siloed.

### 4.1 What's genuinely novel here

1. **Project-as-Profile.** Opening a project directory (detected via `cd`/terminal cwd + editor workspace root + git repo root) triggers the same DETECT → LOAD → APPLY → MONITOR → RESTORE cycle as a game launch. Workspace layout, `mise` runtime versions, container state, and **which Claude Code agent context is active** all switch together.
2. **Agent Context Handoff.** When you switch projects, currently-running Claude Code / Agent Graph sessions for the *previous* project don't get orphaned or confused with the new one — the Dev profile pauses/backgrounds them in the Agent Graph (visually, not by killing them) and primes the new project's context (CLAUDE.md, open tickets/issues if a tracker plugin is connected) automatically. This is the dev-domain equivalent of Gaming's state restore, but for **agent sessions**, which nothing else on Linux does.
3. **Environment Drift Detection.** Compares the active `mise` runtime versions / container image tags / lockfile hashes against what's declared in the repo (`.mise.toml`, `Containerfile`, lockfiles) and flags drift *before* you debug a phantom bug caused by a stale toolchain — passive, informational, never auto-corrects.
4. **Build/Test Regression Detection.** Same pattern as Gaming's FPS baseline: learns a baseline build time / test-suite run time per project, flags "this build is 40% slower than your baseline" — often catches a cache invalidation or a runaway background process (frequently: an AI agent or a game left running).
5. **Dev Flight Recorder.** Ring buffer of recent terminal/log output across active panes; on a detected crash/panic/non-zero exit from a long-running process, preserves the preceding window automatically. Directly reuses the Gaming Flight Recorder's storage/ring-buffer mechanism from `core` (see 4.2) rather than reimplementing it.
6. **Dev ↔ AI/Gaming Resource Negotiation.** A full local build, a container-based test matrix, or a heavy language-server (rust-analyzer, tsserver) can starve an active Ollama session or a game just as easily as the reverse. This flows through the same Resource Engine and negotiation prompt as Section 2 — no new UI.

### 4.2 Architecture note: shared flight recorder

Because both Gaming (3.2) and Dev (4.1.5) want a ring-buffer + crash-triggered dump, **the ring buffer mechanism itself should live in core** (generic: "record last N seconds of {stream}, dump on {trigger}"), with Gaming and Dev plugins only supplying *what stream* (telemetry samples vs. terminal/log output) and *what trigger* (crash-signal vs. non-zero exit / panic pattern match). This avoids a third reimplementation when Security wants the same primitive (Section 5.1.4).

### 4.3 Plugin: `aphotic-plugins/dev/`

| Sub-plugin | Responsibility | Phase |
|---|---|---|
| `project-discovery` | Detects active project via terminal cwd + editor root + git root; debounced, event-driven. | 1 |
| `project-mode` | LOAD/APPLY/RESTORE profile: workspace layout, `mise` env activation, container up/down (rootless Podman). | 1 |
| `agent-context-handoff` | Pauses/backgrounds prior project's Agent Graph sessions visually; primes new project's context (CLAUDE.md, tracker issues if connected). Shares wire format with `on_agent_event`. | 1 |
| `dev-resource-manager` | Registers CPU/GPU/container claims with the Resource Engine. | 1 |
| `env-drift-detector` | Compares active toolchain/container versions vs. repo-declared versions; passive warning only. | 2 |
| `build-telemetry` | Learns build/test baseline durations per project; flags regressions. | 2 |
| `dev-flight-recorder` | Consumes core ring-buffer primitive; captures terminal/log output around crashes. | 2 |
| `port-radar` | Extends the already-planned host-info port-visibility popout into a full per-project port/service map. | 2 (already partially scoped) |

### 4.4 Event flow (Phase 1 happy path)

```
terminal cwd change / editor workspace open (event, not poll)
  → project-discovery: match against known project roots
  → project-mode: LOAD PROFILE
  → dev-resource-manager: register claims (container CPU/mem reservation if declared)
      → Resource Engine: contention check against active AI/Gaming claims
  → APPLY STATE: workspace layout, mise env, container up
  → agent-context-handoff: background prior project's agent sessions, prime new project's context
  → project changes / terminal closes / editor workspace switches
  → RESTORE previous state (container down if configured, workspace revert)
```

### 4.5 Phase 1 vs. later

- **Phase 1:** project detection, mode transition, agent context handoff, resource negotiation.
- **Phase 2:** drift detection, build/test regression detection, flight recorder, port radar expansion.
- **Later:** cross-project dependency graph visualization (which projects share containers/ports), auto-generated project profiles from repo inspection (language, framework, container config) rather than manual setup.

---

## 5. Security Opt-In — "Aphotic Security Intelligence" (Engagement Autopilot)

This is **not** a "harden my desktop" tier — that's intentionally deferred to `CLAUDE_ROADMAP.md` as its own track. This is a profile for **security research / pentest workstation use**, matching the already-planned plugin candidates (BloodHound CE, Caido, libimobiledevice, scrcpy). The genuinely novel angle: pentesters' actual daily pain isn't tool availability (every distro has that), it's **state discipline** — remembering what network you're on, not leaking scope-out-of-bounds traffic, and not leaving sensitive session state lying around after you're done. That's exactly the DETECT → APPLY → RESTORE shape this whole document is built around.

### 5.1 What's genuinely novel here

1. **Engagement Mode with unmissable visual state.** Connecting to an engagement VPN / launching Caido's proxy for a defined engagement triggers a *desktop-wide, hard-to-miss* visual signal (bar accent, border treatment, wallpaper tint — reusing the existing theme pipeline exactly like Gaming's theme integration) so it is never ambiguous which network context you're operating in. This directly targets the single most common, most embarrassing pentest mistake: running a command against the wrong target because you forgot which VPN/session you're in.
2. **Scope Guardian.** A *passive, advisory-only* watcher that checks outbound targets (from Caido traffic, Nmap invocations, etc.) against a user-defined scope list for the active engagement and warns — never blocks, never intercepts — if something falls outside scope. This is a desktop-shell-level safety net that doesn't exist anywhere else; it's not a firewall, it's a "did you mean to do that" nudge.
3. **Evidence Chain Recorder.** Auto-timestamped local log of commands run + terminal capture during an active engagement, structured for later report writing — a lightweight, local chain-of-custody aid, not a compliance product. Reuses the same ring-buffer/flight-recorder primitive from Section 4.2, just with "always-on for the session duration" as the trigger instead of crash-only.
4. **Recon Graph.** The Agent Graph pattern, repurposed: instead of visualizing AI agent activity, visualize *live attack-surface discovery* as BloodHound ingests data or Caido/Nmap scans complete — a real-time node graph of hosts/services/relationships as they're found, using the exact same QML graph-rendering module the Agent Graph already built. This is high-leverage reuse, not new visualization code.
5. **Post-Engagement Sanitization.** On exit: kill/background any AI agent sessions that had engagement-context loaded (so a later, unrelated Claude Code session never accidentally inherits client data in context), clear terminal scrollback for engagement panes, prompt to save or discard captured findings, revert theme/network identity. This is the Security domain's version of "restore previous state" — except restoration here is safety-critical, not just cosmetic.
6. **AI-Assisted Triage With a Hard Guardrail.** Ollama can help triage recon output (summarize a BloodHound path, explain a Caido finding) but the profile enforces that **no AI-suggested command executes without explicit user action** — this is a stricter version of the existing first-install disclaimer gate already built for the exploit-profile taxonomy, extended to any AI-in-the-loop suggestion during an engagement.
7. **Security ↔ AI/Gaming/Dev Resource Negotiation.** BloodHound's Neo4j backend and active large scans are genuinely resource-heavy; they flow through the same Resource Engine as everything else — no special case.

### 5.2 Plugin: `aphotic-plugins/security/`

| Sub-plugin | Responsibility | Phase |
|---|---|---|
| `engagement-mode` | DETECT (VPN connect / defined engagement start) → APPLY visual state + workspace → RESTORE on disconnect/exit. | 1 |
| `scope-guardian` | Passive advisory check of tool targets against declared scope list. | 1 |
| `security-resource-manager` | Registers claims (BloodHound/Neo4j, active scans) with Resource Engine. | 1 |
| `evidence-recorder` | Session-duration capture using core ring-buffer primitive; local-only. | 2 |
| `recon-graph` | Live attack-surface graph, reusing Agent Graph's QML rendering module. | 2 |
| `post-engagement-sanitizer` | Agent session backgrounding, scrollback clear, identity/theme revert. | 1 (safety-critical, ships with engagement-mode) |
| `ai-triage-guardrail` | Enforces explicit-approval-before-execution for any AI-suggested action during an engagement. | 1 |
| Tool integrations: BloodHound CE, Caido, libimobiledevice, scrcpy | Launch/state hooks into the above, per already-planned plugin candidates. | Later / as each tool integration matures |

### 5.3 Event flow (Phase 1 happy path)

```
engagement VPN connect / engagement-mode manually started
  → engagement-mode: LOAD PROFILE (scope list, engagement metadata)
  → security-resource-manager: register claims
      → Resource Engine: contention check
  → APPLY STATE: visual engagement indicator, dedicated workspace, notification suppress
  → scope-guardian + ai-triage-guardrail: active for session duration
  → engagement ends (VPN disconnect / manual stop)
  → post-engagement-sanitizer: background agent sessions with engagement context,
    clear scrollback, prompt save/discard evidence
  → RESTORE previous desktop state
```

### 5.4 Safety boundaries (security domain is the strictest)

- Scope Guardian and AI Triage Guardrail are **advisory/blocking-of-automation only** — Aphotic never executes an offensive action itself, ever. It suggests, warns, and requires explicit human action for anything execution-related. This is a harder line than Gaming or Dev, and should be documented as a non-negotiable design constraint.
- Evidence capture is local-only, never uploaded, and the user is always prompted before anything captured persists past the session.
- Post-engagement sanitization is the one place in this whole document where "automatic on exit" is *stricter* than elsewhere (clearing scrollback, backgrounding agent context) precisely because the cost of *not* doing it automatically (client data bleeding into an unrelated later session) is higher than the cost of doing it.

### 5.5 Phase 1 vs. later

- **Phase 1:** engagement-mode, scope-guardian, resource negotiation, AI triage guardrail, post-engagement sanitization.
- **Phase 2:** evidence recorder, recon graph.
- **Later:** deep per-tool integrations (BloodHound/Caido/libimobiledevice/scrcpy), network identity randomization per engagement.

---

## 6. Cross-Profile Interaction Matrix

All conflicts route through the same Resource Engine negotiation UI (Section 2.1). This table is illustrative of *why* a shared engine matters — these are all the same underlying mechanism.

| Conflict | Typical trigger | Resolution pattern |
|---|---|---|
| AI vs. Gaming | Ollama VRAM vs. game launch | Original spec's "Suspend AI / Keep Running" prompt |
| AI vs. Dev | Agent Graph session vs. heavy local build/container | Suspend/deprioritize agent, or let build wait |
| Dev vs. Gaming | Background container build vs. game launch | Same prompt pattern, container-aware pause |
| Security vs. AI | BloodHound/Neo4j vs. Ollama | Same prompt; AI triage guardrail already limits AI's footprint during engagements |
| Security vs. Dev/Gaming | Rare in practice (different usage sessions) | Still routed through engine for completeness, low priority to build first |

---

## 7. Combined Plugin Directory Structure

```
aphotic-plugins/
    gaming/
        game-mode
        game-discovery
        game-profiles
        game-theme
        game-resource-manager
        game-telemetry          (Phase 2)
        game-optimizer          (Phase 2)
        game-flight-recorder    (Phase 2)
        proton-tools            (Later)
        rgb-sync                (Later)
        discord-presence        (Later)
    dev/
        project-discovery
        project-mode
        agent-context-handoff
        dev-resource-manager
        env-drift-detector      (Phase 2)
        build-telemetry         (Phase 2)
        dev-flight-recorder     (Phase 2)
        port-radar               (Phase 2)
    security/
        engagement-mode
        scope-guardian
        security-resource-manager
        ai-triage-guardrail
        post-engagement-sanitizer
        evidence-recorder        (Phase 2)
        recon-graph              (Phase 2)
        bloodhound-integration   (Later)
        caido-integration        (Later)
        mobile-forensics         (Later — libimobiledevice, scrcpy)
```

---

## 8. Phase Roadmap (all three domains)

**Phase 0 — Core prerequisite (`feature/resource-engine-core`)**
Profile state machine, Resource Engine (claims/arbitration/negotiation UI contract), shared ring-buffer primitive, state snapshot/restore mechanism. Nothing user-facing ships without this; all three opt-ins depend on it.

**Phase 1 — Per-domain MVP (`feature/gaming-opt-in`, `feature/dev-opt-in`, `feature/security-opt-in`)**
Detection, mode transition, per-domain resource-manager wired into the Resource Engine, theme/state integration where applicable. Ships one working DETECT→APPLY→RESTORE cycle per domain plus at least one real cross-domain negotiation (AI vs. Gaming, as originally specced, is the reference implementation).

**Phase 2 — Intelligence layer**
Telemetry, baseline learning, regression detection, flight recorders, Recon Graph, drift detection. This is where each domain's "genuinely unique" value compounds.

**Later / community-contributable**
Tool-specific integrations (proton-tools, RGB, Discord presence, BloodHound/Caido/mobile forensics), auto-generated profiles, cross-project/cross-engagement visualization.

---

## 9. Open Questions (resolve during implementation, document in PR description)

- Should Resource Engine claims be declared statically per-profile-config, or should plugins be able to register claims dynamically at runtime (e.g., a container declaring its own resource reservation from its Containerfile)? Phase 1 can start static; dynamic is a natural Phase 2 extension.
- Where does the shared ring-buffer primitive live precisely — as a Quickshell singleton service, or a small Go-core component invoked by any plugin? Leaning Go-core for consistency with the installer core's role as source of truth, but this touches the QML/Go boundary and should be a deliberate call, not a default.
- Engagement-mode's visual signal (bar accent/border/wallpaper tint) needs a concrete design pass — this is a Quickshell/theming task, not an architecture question, but should not be handwaved given how safety-critical the "always know you're in engagement mode" property is.
- Agent Context Handoff (4.1.2) needs to define exactly what "priming context" means for a Claude Code session — is this just surfacing CLAUDE.md + issues in the Agent Graph UI, or actually feeding it into a session's initial context automatically? The latter has real prompt-injection-shaped risk if tracker data is untrusted and should default to surfacing, not auto-injecting.

---

## 10. Constraints carried forward from existing Aphotic principles (non-negotiable across all three)

- Fully opt-in; zero cost to base install when disabled.
- Static `PanelWindow` geometry with `offsetScale` content-transform animation only — no exceptions for engagement-mode's visual indicator or any gaming/dev overlay.
- Single-sourced singletons for all new services (Resource Engine, ring-buffer, profile state machine).
- No comments in QML/shell, per `CONTRIBUTING.md`.
- Feature-branch-only development; separable, independently revertible commits.
- Nothing merges to `test` or `main` unattended.
- No destructive automatic action anywhere except post-engagement sanitization's scrollback/agent-context clearing (Section 5.4), which is the one deliberate, documented exception and must stay documented as such.
- Local-first telemetry, no cloud requirement, anywhere in any domain.
- Every optimization/suggestion is reversible and requires explicit user action to apply.

-- Base note: Current "AGENT GRAPH - LIVE RENDER GRAPH" will eventually be moved to aphotic-plugins and base 'AI' opt in ships with defaults in current 'TOML'
-- Current Base structure and feel: This should exist as the BASE layer of Aphotic minus the "Agent Graph" which will eventually be moved to aphotic-plugins/ai/ai-agent-graph and other related ground breaking related / aligned features with the AI profile TOML. Its inherently missing from this document as the basis of the structure is off the newest addition being the "agent graph" itself as an "Opt in" feature. 
-- Everything above can be refactored and organized as you see fit once you have reviewed THROUGHLY or documented any changes. This needs to be the truth of changes going forward. 

-- ALL other @docs/ need to align with this vision BUT still be ideas, inflight, and cross referenced to see relevance.
-- All Plugins are version stamped in their respective "plugin.toml" for future version changes or break/fix implementations
-- Lastly -- Create a aphotic-themes repository for community lead themes. It must follow the convention of everything else, but an option on the "Apperance" tab to install "Community Curated Themes" and then open a library browser or similar function to keep the current git repository themes and files relevant (could require the user to searh the repo and enter the exact name if that is easier but overall thats not the theme of this -- your call on this one boss)
