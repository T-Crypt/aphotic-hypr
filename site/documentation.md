---
layout: docs
title: Documentation
description: Public documentation for Aphotic.
---
# Documentation

The public Wiki is rendered here as native documentation. Start with [Getting Started]({{ '/docs/getting-started/' | relative_url }}) or use the index to explore installation, themes, plugins, and troubleshooting.

[Sonar and Shelves]({{ '/docs/sonar-and-shelves/' | relative_url }}) covers the opt-in
feature under review: output settings, shortcuts, dismissal and plugin tabs.

## Install

`./install-tui.sh` is the keyboard-driven installer over `install.sh`. It opens
on facts about the machine, then walks release channel, profile, layers and
theme, then the assistant, login screen, NVIDIA driver, conflicts and backups.
Arrows or `j` and `k` move, space toggles, Enter confirms, ESC steps back and
never quits. A Review screen shows the exact `install.sh` command your choices
built, and nothing runs before you accept it. On a plain terminal, `NO_COLOR`
or `TERM=dumb`, the same screens fall back to a numbered menu.

The scripted path stays `./install.sh` with flags, for CI and unattended
installs. The flag reference lives in
[Installation]({{ '/docs/installation/' | relative_url }}).

## Notifications and OSD

Toasts, history entries, the notification center card and the OSD slider draw
from one shared skin. Urgency reads on the signal line: a normal entry sits at
idle, a critical one at warn.

## The bar

The notch joins the bar edge in every bar style. The edge line opens across the
notch and the surface border leaves that edge bare, so no seam shows where the
two meet.
