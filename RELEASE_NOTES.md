# Release Notes

Short "what's new" blurbs, one per version. These are what `aphotic whatsnew`
reads from to show a Hyprland-native banner (`hyprctl notify`, the same
mechanism Hyprland itself uses for its own release announcements) the first
time you land on a new version — right after `install.sh`/`aphotic update`,
or on your next fresh Hyprland login if the version changed some other way.

This file is intentionally short and public-facing. Keep each entry to one
short sentence — `hyprctl notify` renders it as a single unwrapped line, and
anything longer just clips off-screen. For the full history see the
README's Roadmap section; for granular day-to-day change tracking see the
maintainer-local (gitignored) `docs/CHANGELOG.md`.

## 2.0.3

Aphotic now supports Omarchy, verified on a fresh Omarchy ISO install; EndeavourOS with Desktop Environment: None works too, the same as a minimal install.

## 2.0.2

A fifth bar style, the capsule, and a rebuilt notch that follows your bar to whichever edge it is docked on.

## 2.0.1

install.sh now detects AMD GPUs, installs their Mesa and RADV Vulkan drivers, and picks the Ollama GPU runner that matches your card (ollama-rocm on AMD, ollama-cuda on NVIDIA) so local models stop running on the CPU.

## 2.0.0

A modular plugin architecture — AI agent hooks (Claude Code/Codex/OpenCode) and Agent Graph are now opt-in plugins, not automatic: run `aphotic plugin install claude-hooks` (or codex-hooks/opencode-hooks/agent-graph) to keep them. See the README's Install section for details.

## 1.2.0

A live Agent Graph tab for Claude Code sessions, plus Hyprland-native
release banners like this one. See the README's Roadmap for the full list.

## 1.1.0

Swappable bar styles and an opt-in local Aphotic Assistant. See the
README's Roadmap for the full list.
