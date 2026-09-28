---
layout: default
title: Gallery
description: Screenshots of existing Aphotic desktop surfaces.
shots:
  - file: signal
    caption: The Signal line skin in Tokyo Night
  - file: command-center
    caption: Command Center
  - file: flow
    caption: Flow, every workload and what it holds
  - file: agents-popout
    caption: Agents popout
  - file: processes-popout
    caption: Processes popout
  - file: settings-appearance
    caption: Settings, themes and wallpapers
  - file: settings-plugins
    caption: Settings, plugins
  - file: wallpaper-carousel
    caption: Wallpaper picker
  - file: workspace-plane
    caption: Workspace plane replaying an agent run
  - file: pet-lumen
    caption: Lumen desktop pet
  - file: pet-cipher
    caption: Cipher desktop pet
  - file: pet-kozumi
    caption: Kozumi desktop pet
---
<section class="page hero"><p class="eyebrow">Gallery</p><h1>The desktop, in use.</h1><p class="lede">Screenshots from a live 2.0.7 desktop in the Signal line skin, plus the plugins that add to it.</p></section><section class="page gallery">{% for shot in page.shots %}<figure><img src="{{ '/assets/gallery/' | append: shot.file | append: '.png' | relative_url }}" alt="{{ shot.caption }}"><figcaption>{{ shot.caption }}</figcaption></figure>{% endfor %}</section>
