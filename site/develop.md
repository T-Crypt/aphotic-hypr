---
layout: docs
title: Develop
description: Build, test, and ship changes to Aphotic.
---
# Develop

The [Developer SDK]({{ '/docs/developer-sdk/' | relative_url }}) is the hub for
working on Aphotic: one page that points at each subsystem's guide. The most
used pages:

- [Contributor Workflow]({{ '/docs/contributor-workflow/' | relative_url }}) —
  what runs on your daily machine, what runs in the dev VM, what CI runs on
  the PR
- [Dev VM]({{ '/docs/dev-vm/' | relative_url }}) — build a disposable test
  machine on libvirt or Proxmox, and hand the setup to your own agent
- [Build a Plugin]({{ '/docs/build-a-plugin/' | relative_url }}), with the
  [plugin SDK guide](https://raw.githubusercontent.com/T-Crypt/aphotic-plugins/main/WRITING-PLUGINS.md)
  in the plugins repo
- [CLI Reference]({{ '/docs/cli-reference/' | relative_url }}) — every
  `aphotic` command

The loop on a checkout: `tools/ci/local.sh` before every push, and a
windowless `QT_QPA_PLATFORM=offscreen qs -p <component.qml>` probe for QML
changes — never `qs -p .` on a live desktop, it maps a second bar.
