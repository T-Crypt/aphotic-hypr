# Theme Spec

A Noctis theme directory contains all the configuration needed to define a complete visual identity, including wallpaper reference, color engine settings, and optional per-app overrides.

## Theme Directory Structure

Each theme is a directory under `themes/` with the following structure:

```
themes/
├── <theme-name>/
│   ├── wallpaper.jpg          # Reference wallpaper (required)
│   ├── wallust.toml           # Wallust configuration (optional, uses defaults if missing)
│   ├── scheme.json            # Color scheme specification (optional, uses default if missing)
│   ├── config.json            # Theme-specific overrides (optional)
│   └── apps/                  # Per-app configuration overrides (optional)
│       ├── kitty/
│       ├── rofi/
│       ├── firefox/
│       └── ...
```

## Wallpaper Reference

The `wallpaper.jpg` file is the primary reference for color generation. All color schemes and palettes are generated from this image using the configured engine.

## Wallust Configuration

The `wallust.toml` file in each theme directory allows overriding the default wallust settings for that specific theme:

```toml
[general]
backend = "kmeans"           # Options: kmeans, fast_resize, full_image, wal
colorspace = "lab"           # Options: hsl, lab, lch
contrast_aware = true        # Enable contrast-aware ordering
```

## Scheme Specification

The `scheme.json` file defines the color scheme to use for this theme:

```json
{
    "engine": "wallust",
    "backend": "kmeans",
    "colorspace": "lab",
    "scheme": "vibrant"
}
```

## Per-App Overrides

Optional directory structure for app-specific configurations. These are merged with the default templates during palette generation.

## Theme State Tracking

Themes are applied using symbolic links in `~/.local/share/noctis/active-theme` which points to the active theme directory. The system tracks:
- Current theme name
- Current wallpaper path
- Last used color scheme

This enables seamless cycling through themes and automatic palette regeneration when schemes change.