<p align="center">
  <img src="assets/aphotic-banner.svg" alt="Aphotic — Hyprland dotfiles, after dark" width="900">
</p>

<p align="center">
  <img src="https://img.shields.io/github/stars/T-Crypt/Aphotic-Hypr?style=for-the-badge&color=7DCFFF&labelColor=0b0d12">
  <img src="https://img.shields.io/github/issues/T-Crypt/Aphotic-Hypr?style=for-the-badge&color=E0AF68&labelColor=0b0d12">
  <img src="https://img.shields.io/github/forks/T-Crypt/Aphotic-Hypr?style=for-the-badge&color=F7768E&labelColor=0b0d12">
  <img alt="GitHub last commit" src="https://img.shields.io/github/last-commit/T-Crypt/Aphotic-Hypr?style=for-the-badge&color=AD8EE6&labelColor=0b0d12">
  <img alt="License" src="https://img.shields.io/github/license/T-Crypt/Aphotic-Hypr?style=for-the-badge&color=7DCFFF&labelColor=0b0d12">
  <img alt="Status: Beta" src="https://img.shields.io/badge/status-beta-E0AF68?style=for-the-badge&labelColor=0b0d12">
</p>

## Overview

Aphotic is a modular Hyprland environment using a single Quickshell
shell for the desktop UI.

It provides four optional profiles:

-   Developer
-   Gaming
-   AI
-   Security

Features are layered rather than enabled as one large desktop stack.
Inactive features should add little to no runtime overhead.

## Preview

One shell, reskinned live from a wallpaper — no rebuild, no relogin. Shown
over **Tokyo Night**, **Lofi**, and **Gruvbox**, three of the eight themes
that ship out of the box:

<p align="center">
  <img src="./assets/preview.png" width="900">
</p>

Agentic workflow, live render: every Bash and Read call landing on the graph
as the agent makes it, with replay scrubbing and zoom.

https://github.com/user-attachments/assets/a9a2ff29-4c57-4e1f-b4e9-e3a93e995c2a

## Gallery

<details>
<summary><b>Desktop &amp; bar</b></summary>
<br>

<table>
<tr>
<td width="50%"><p align="center"><img src="./assets/screenshots/bar-full.png" width="440"><br><sub>Bar: Full style</sub></p></td>
<td width="50%"><p align="center"><img src="./assets/screenshots/bar-dock.png" width="440"><br><sub>Bar: Dock style</sub></p></td>
</tr>
<tr>
<td width="50%"><p align="center"><img src="./assets/screenshots/workspaces.png" width="440"><br><sub>Workspaces</sub></p></td>
<td width="50%"><p align="center"><img src="./assets/screenshots/launcher.png" width="440"><br><sub>Launcher</sub></p></td>
</tr>
</table>

</details>

<details>
<summary><b>Command Center</b></summary>
<br>

<table>
<tr>
<td width="50%"><p align="center"><img src="./assets/screenshots/dashboard.png" width="440"><br><sub>Dashboard</sub></p></td>
<td width="50%"><p align="center"><img src="./assets/screenshots/performance.png" width="440"><br><sub>Performance</sub></p></td>
</tr>
<tr>
<td width="50%"><p align="center"><img src="./assets/screenshots/workspace-profiles.png" width="440"><br><sub>Workspace Profiles</sub></p></td>
<td width="50%"></td>
</tr>
</table>

</details>

<details>
<summary><b>AI</b></summary>
<br>

<table>
<tr>
<td width="50%"><p align="center"><img src="./assets/screenshots/ai-chat.png" width="440"><br><sub>AI Chat</sub></p></td>
<td width="50%"><p align="center"><img src="./assets/screenshots/ai-settings.png" width="440"><br><sub>AI Settings &amp; Hardware Advisor</sub></p></td>
</tr>
<tr>
<td width="50%"><p align="center"><img src="./assets/screenshots/intelligence-assistant.png" width="440"><br><sub>Aphotic Assistant</sub></p></td>
<td width="50%"></td>
</tr>
</table>

</details>

<details>
<summary><b>Theming &amp; settings</b></summary>
<br>

<table>
<tr>
<td width="50%"><p align="center"><img src="./assets/screenshots/wallpaper-picker.png" width="440"><br><sub>Wallpaper Picker</sub></p></td>
<td width="50%"><p align="center"><img src="./assets/screenshots/theme-creator.png" width="440"><br><sub>Theme Creator</sub></p></td>
</tr>
<tr>
<td width="50%"><p align="center"><img src="./assets/screenshots/personalization.png" width="440"><br><sub>Personalization</sub></p></td>
<td width="50%"><p align="center"><img src="./assets/screenshots/plugins.png" width="440"><br><sub>Plugins</sub></p></td>
</tr>
</table>

</details>

## Features

-   Quickshell desktop shell
-   Live theme and wallpaper switching
-   Four bar styles
-   Launcher and application search
-   Notifications and OSD
-   Lock and session controls
-   Command Center
-   Settings and theme creator
-   Workspace profiles
-   Plugin system
-   AI provider integration
-   Local Ollama model management
-   Agent workflow graph
-   Resource arbitration
-   Gaming profile with GameMode integration
-   GPU process and VRAM accounting
-   Developer and security tooling

## Architecture

Aphotic separates the base desktop from optional profiles and plugins.

``` text
Aphotic
├── Quickshell
│   ├── Bar
│   ├── Launcher
│   ├── Notifications
│   ├── OSD
│   ├── Lock
│   ├── Command Center
│   └── Settings
│
├── Profiles
│   ├── Developer
│   ├── Gaming
│   ├── AI
│   └── Security
│
└── Plugins
    └── Optional extensions
```

Profiles can interact through the Resource Engine.

``` text
Workload
   ↓
Resource Claim
   ↓
Contention
   ↓
Negotiation
   ↓
Apply
   ↓
Monitor
   ↓
Restore
```

The engine is designed to remain dormant when there is nothing to
manage. Resource polling and process accounting are activated only where
required.

## Profiles

### Developer

Development tools, workspace behavior, terminal integration, and
project-oriented workflows.

### Gaming

GameMode-based gaming sessions with GPU process accounting and resource
negotiation.

Aphotic can detect GPU contention between a running game and other
workloads such as local AI models.

### AI

Optional AI integrations including:

-   Claude
-   Ollama
-   Gemini
-   ChatGPT
-   Aphotic Assistant

Local Ollama models can participate in the Resource Engine through GPU
VRAM claims.

### Security

Optional security-research tooling organized into dedicated layers.

## Plugin System

Optional functionality lives outside the base shell.

Plugins can be installed, enabled, disabled, and removed independently.

The core desktop does not require optional plugins to function.

Repository: [T-Crypt/aphotic-plugins](https://github.com/T-Crypt/aphotic-plugins)

## Themes

Aphotic ships with multiple themes and supports live wallpaper-driven
color generation.

Included themes currently include:

-   Gruvbox
-   Nordic
-   Rosé Pine
-   Tokyo Night
-   Catppuccin Latte
-   Lofi
-   HackTheBox
-   Windows 11

Theme commands:

``` bash
aphotic theme list
aphotic theme set <theme>
aphotic theme next
aphotic theme prev
aphotic wallpaper --random
```

## Installation

Clone the repository:

``` bash
git clone https://github.com/T-Crypt/Aphotic-Hypr.git
cd Aphotic-Hypr
```

Run the installer:

``` bash
./install.sh
```

The installer supports profiles and optional features without requiring
every component to be installed.

See the installation documentation for available options.

## Stack

| Component | Implementation |
| --- | --- |
| Compositor | Hyprland |
| Desktop shell | Quickshell |
| Terminal | Kitty |
| File manager | Thunar |
| Wallpaper | awww |
| Shell | ZSH / Starship |
| Audio visualizer | Cava |

## Performance

Aphotic is designed around a simple rule:

> Features that are not being used should not continuously consume
> resources.

The shell favors:

-   compositor-adjacent components
-   event-driven state where practical
-   conditional polling
-   optional profiles
-   optional plugins
-   minimal external daemons
-   graceful degradation when optional dependencies are unavailable

The Resource Engine extends this approach to active workloads instead of
treating system resources as static configuration.

## Documentation

-   [Installation](https://github.com/T-Crypt/Aphotic-Hypr/wiki)
-   [CLI
    Reference](https://github.com/T-Crypt/Aphotic-Hypr/wiki/CLI-Reference)
-   [Bar
    Styles](https://github.com/T-Crypt/Aphotic-Hypr/wiki/Bar-Styles)

## Project Status

Aphotic is currently in beta.

Core desktop functionality is stable and actively used. Profiles,
plugins, and runtime features continue to evolve.

Bug reports and hardware-specific issues are welcome.

## License

See [LICENSE](LICENSE).
