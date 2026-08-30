# Aphotic-Hypr — orientation anchor

Aphotic is an Arch/Hyprland desktop rice built on Quickshell: a themed
shell, a real installer (`install.sh`), an `aphotic` CLI, a plugin system,
and an opt-in AI-agent-aware layer (Agent Graph, harness/provider
tracking). This file is a map, not the content — read
**[`docs/APHOTIC_UNIFIED_VISION.md`](docs/APHOTIC_UNIFIED_VISION.md)** for
architecture, the plugin-system rewrite, per-domain status, and known
issues. It is the canonical source of truth; don't duplicate its content
here.

## If you're picking this up cold

1. Read this file (you're doing that now).
2. Read `docs/APHOTIC_UNIFIED_VISION.md` §1 (architecture & principles)
   and §2 (modular plugin architecture — the current top priority).
3. For the specific domain/area you're touching, read that doc's §3
   (per-domain status) and §4 (known bugs) for that area.
4. Check `docs/BACKLOG.md` for the live, ID-based pick list of scoped-
   but-not-yet-picked work, and `docs/LEDGER.md` for the day-by-day log
   of what actually shipped most recently.

## Current state (2026-08-30)

- **Branches:** `main` (stable, released), `test` (integration branch
  holding everything shipped but not yet cut into a release), plus
  whatever short-lived `feature/*`/`fix/*` branch a given task is on.
  Nothing merges to `test` or `main` unattended.
- **Modular plugin architecture** (`APHOTIC_UNIFIED_VISION.md` §2) — the
  current top-priority initiative. Requirement captured, implementation
  not started: manifest/registry design, `install.sh` refactor, and
  Agent Graph's extraction into its own opt-in plugin are all still
  ahead of it.
- **Resource Engine core** (`APHOTIC_UNIFIED_VISION.md` §3.5) — the
  shared substrate Gaming/Dev/Security opt-ins all depend on. Not
  started. Nothing in those three domains can ship its novel pieces
  until this lands.
- **Gaming / Dev / Security opt-ins** (`APHOTIC_UNIFIED_VISION.md` §3.2–
  3.4) — fully planned, zero code. Blocked on the Resource Engine core
  above.
- **Agent-identification work** (harness vs. provider role field,
  `docs/AGENT_TRACKING.md`) — shipped for presence/usage/live-session
  tracking across Claude Code, Codex, and OpenCode. Open: an audit of
  every AI chat surface against the role field (Codex currently shows up
  as a selectable chat provider when it's a harness — see
  `APHOTIC_UNIFIED_VISION.md` §4.1).
- **Docs** are git-tracked again as of 2026-08-30 (previously gitignored)
  — `docs/` is the project's durable memory now, not maintainer-local.

## Hard rules that must never be violated

Full rationale lives in `CONTRIBUTING.md` and
`APHOTIC_UNIFIED_VISION.md` §1.3 — this is the short list:

- Static `PanelWindow` geometry, `offsetScale` content-transform
  animation only.
- No explanatory comments by default in QML/shell — only for a genuinely
  non-obvious workaround.
- Feature-branch-only; nothing merges to `test`/`main` unattended.
- No destructive automatic action anywhere, except Security's documented
  post-engagement sanitization exception.
- Local-first telemetry, no cloud requirement, ever.
- Every binary the shell shells out to goes in **both**
  `profiles/base/full.toml` and `profiles/base/minimal.toml` — the shell
  always loads in full regardless of install profile.
