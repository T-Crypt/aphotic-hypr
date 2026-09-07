---
layout: default
title: Gallery
description: Screenshots of existing Aphotic desktop surfaces.
---
<section class="page hero"><p class="eyebrow">Gallery</p><h1>The desktop, in use.</h1><p class="lede">Existing project screenshots showing real Aphotic surfaces and plugins.</p></section><section class="page gallery">{% assign shots = 'bar-minimal:Minimal bar, dashboard:Command Center, plugins:Plugin management, theme:Theme controls, pet-lumen:Lumen desktop pet, pet-cipher:Cipher desktop pet, pet-kozumi:Kozumi desktop pet' | split: ', ' %}{% for shot in shots %}{% assign parts = shot | split: ':' %}<figure><img src="{{ '/assets/gallery/' | append: parts[0] | append: '.png' | relative_url }}" alt="{{ parts[1] }}"><figcaption>{{ parts[1] }}</figcaption></figure>{% endfor %}</section>
