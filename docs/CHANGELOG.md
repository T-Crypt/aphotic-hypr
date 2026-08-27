# Changelog

Full shipped-item history, moved out of the README's Roadmap section to
keep that one scannable. Newest entries at the top of each block match
the order they were added to the README over time (not strictly
chronological release dates).

## v1.1.0

- **Swappable bar styles** — the bar's cosmetic pill/square/minimal skin
  choice is now a real structural style switcher: **Full** (the
  existing bar, unchanged), **Dock** (a floating macOS-style app dock —
  pinned + live running apps, auto-hide, icon-proximity hover-scale
  magnification), **Taskbar** (Windows-style grouped task list + start
  button), and **Minimal** (an Omarchy-style thin single-accent icon
  strip). Switch live from Settings → Bar (four real live-previewed
  cards, not screenshots), `aphotic bar style <name>` / `aphotic bar
  cycle`, or `SUPER+Ctrl+Shift+B`. See
  [`docs/bar-styles.md`](bar-styles.md). Note: `barSkin`'s old
  `"minimal"` value (a transparent-background outline treatment) is
  repurposed to mean the new structural Minimal style — a one-time
  behavior change for anyone with that value already saved.

- **Aphotic Assistant** — an opt-in local chatbot (NVIDIA-gated, installed via `install.sh --with-assistant` or the wizard prompt) with a fixed persona/system-prompt, model picked via `llmfit`'s hardware-aware recommendation at install time, a first-open welcome message, and reinstall/uninstall controls in Settings → AI. Not supported on AMD/ROCm or CPU-only yet — a real future gap, not attempted in that pass.
- **Low-lift shell QoL batch** — a weather Dashboard card (Open-Meteo, IP-based auto-location fallback), a single-click eyedropper (`SUPER+Shift+C`), a Do Not Disturb toggle (bar icon + `SUPER+Shift+D`, auto-engaged by Pomodoro focus), a wallpaper slideshow (Settings → Appearance), launcher app sorting by actual usage, and a Wi-Fi/Bluetooth/DND quick-toggles card on the Dashboard.
- **Intelligence quick-chat popout** — a right-docked overlay (`SUPER+Shift+A`) sharing the AI Chat tab's provider/key backend but with its own persisted, per-session conversation history — see [Intelligence](../README.md#quickshell-shell) in the README. Not streamed token-by-token yet (an explicit scope cut, not a stub) — that would need a per-provider rewrite (NDJSON for Ollama, SSE for Gemini/ChatGPT, `--output-format stream-json` for the Claude CLI) that didn't fit that pass.
- **`ai` layer workflow integration** — the layer was package-only (raw Ollama) until [llmfit](https://github.com/AlexsJones/llmfit) added real hardware-aware model recommendations: `aphotic ai fit` on the CLI (works standalone, no Quickshell needed), plus a Settings → AI "Hardware Advisor" card (button-triggered scan, top-3 recommendations, one-click Ollama pull via a best-effort name-to-tag guess, shown to the user rather than applied silently) and a "Model Storage" card (create/inspect/clean the Ollama and GGUF model directories). GPU-detection failures surface llmfit's own error output rather than falling back silently.
- **AI-native differentiators** — the bar's agent module covers three providers (Claude Code, Codex, Ollama — session count/token usage or loaded models, right-click launch, middle-click cycle), backed by real 15-min usage tracking and a Claude Code hook `install.sh` wires automatically (see [`docs/AGENT_TRACKING.md`](AGENT_TRACKING.md)), plus a launcher project switcher (`@` sigil — jump to a git repo with a terminal + `claude` + editor in one action). This module fully replaced the earlier, standalone count-only Claude Code status icon (removed, not left duplicated). Still open: surfacing the hook's live per-session data as real per-session status in the panel (the hook writes it, nothing reads it yet), AI chat context injection, and session handoff.
- **Workspace profiles** — named, one-key launch groups (Settings → Workspace Profiles) — not a live session snapshot, a saved replay list dispatched via `hyprctl`.
- **Plugin system, Phase 1** — theme-change hooks, the `aphotic plugin` CLI, a Settings → Plugins pane (browse/install/enable/disable), and a real first plugin (OpenRGB Sync) distributed via the separate [`aphotic-plugins`](https://github.com/T-Crypt/aphotic-plugins) repo. See [`docs/PLUGIN_SYSTEM.md`](PLUGIN_SYSTEM.md) for Phase 2/3 (CLI-triggered actions, real UI surfaces beyond theme hooks).
- **Small QoL wins** — a host-info bar icon (click-to-copy LAN IP, hover for hostname), a Pomodoro focus/break timer (bar icon + popout + Dashboard card), and a clipboard "pin" so frequently reused snippets/commands survive `cliphist`'s rolling history.
- **`ai` layer / AI settings pane** — Settings → AI covering active provider, Ollama host/model, and masked API-key entry for Claude/Gemini/ChatGPT.
- **Ollama model management** — Settings → AI's Ollama Models section (live VRAM per loaded model, delete, pull-by-name, set active model).
- **Theme-colors swatch view, expanded into a full Theme Creator** — build a static theme from a hand-picked palette (common-color presets or an HSV color wheel), writes a real theme + colorscheme + generated wallpaper into `~/.config/awww`.
- **Bar orientation** — a true vertical (left/right-docked) bar mode, plus three selectable bar styles (pill/square/minimal, Settings → Bar).
- **Theming architecture** — directory-per-theme wallpaper sets, tracked per-theme wallpaper state, and a wallpaper picker (Settings → Appearance) covering every theme in one grid.
- **Shell restart supervision** — a `systemd --user` unit (`aphotic-shell.service`) auto-restarts the Quickshell daemon on crash instead of requiring a manual `SUPER+B`.
- **Quickshell shell** — bar with real popouts + a live resource meter, launcher with app/clipboard/emoji/window/wallpaper modes, screenshot picker, notifications, OSD, lock, session menu, Command Center (tabbed dashboard + AI Chat), and a full Settings Control Center — see [Quickshell Shell](../README.md#quickshell-shell) and [Settings](../README.md#settings--control-center) in the README.
- **Identity** — a live bar-position toggle: Settings → Bar docks left/right and toggles compact density live.
