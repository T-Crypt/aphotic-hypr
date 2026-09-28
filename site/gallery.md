---
layout: default
title: Gallery
description: Screenshots of existing Aphotic desktop surfaces.
---
<section class="page hero"><p class="eyebrow">Gallery</p><h1>The desktop, in use.</h1><p class="lede">Screenshots from a live 2.0.7 desktop: the Signal style across the shell, plus the plugins that add to it.</p></section><section class="page gallery">{% assign shots = 'signal:The Signal overhaul in Tokyo Night, command-center:Command Center, flow:Flow, every workload and what it holds, agents-popout:Agents popout, processes-popout:Processes popout, settings-appearance:Settings, themes and wallpapers, settings-plugins:Settings, plugins, wallpaper-carousel:Wallpaper picker, workspace-plane:Workspace plane replaying an agent run, pet-lumen:Lumen desktop pet, pet-cipher:Cipher desktop pet, pet-kozumi:Kozumi desktop pet' | split: ', ' %}{% for shot in shots %}{% assign parts = shot | split: ':' %}<figure><img src="{{ '/assets/gallery/' | append: parts[0] | append: '.png' | relative_url }}" alt="{{ parts[1] }}"><figcaption>{{ parts[1] }}</figcaption></figure>{% endfor %}</section>
