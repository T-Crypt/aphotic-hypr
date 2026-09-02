#!/usr/bin/env python3
"""Clamp a wallpaper-derived pywal palette to a theme's own anchor palette.

`wallust run <image>` derives every ANSI slot purely from the image's
pixels, so a wallpaper that happens to contain an off-palette colour can
push a theme's accent well outside what that theme is supposed to look
like (a pink sign in a photo turning Gruvbox neon-pink). This reads the
raw derived palette and the theme's anchor palette -- both pywal JSON --
and pulls each slot back toward the anchor only as far as the declared
per-theme ceilings, so every wallpaper still generates its own distinct
palette within a bounded neighbourhood of the theme's look.

Opted into per theme via theme.toml's [palette] table; see
themes/THEME_SPEC.md. The clamped result is written back out as pywal
JSON so `wallust cs <name> --format pywal` can re-run every template
from it -- the exact path [engine].colorscheme already uses.
"""

import argparse
import colorsys
import json
import sys

# Slots whose lightness carries wallust's check_contrast guarantees --
# background/foreground separation and readable dim-grey `ls` output.
# Clamping their lightness toward an anchor would fight that check on a
# very dark or very light wallpaper, so only their saturation is bounded.
LIGHTNESS_EXEMPT = frozenset({
    "background", "foreground", "cursor",
    "color0", "color7", "color8", "color15",
})

DEFAULT_MAX_HUE_SHIFT = 20.0
DEFAULT_MAX_SAT_SHIFT = 15.0
DEFAULT_MAX_LIGHT_SHIFT = 12.0

SPECIAL_KEYS = ("background", "foreground", "cursor")
COLOR_KEYS = tuple(f"color{i}" for i in range(16))


def hex_to_hls(value):
    """#rrggbb -> (hue degrees 0-360, lightness 0-100, saturation 0-100)."""
    text = value.strip().lstrip("#")
    if len(text) != 6:
        raise ValueError(f"not a #rrggbb colour: {value!r}")
    r, g, b = (int(text[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    return h * 360.0, l * 100.0, s * 100.0


def hls_to_hex(h, l, s):
    r, g, b = colorsys.hls_to_rgb((h % 360.0) / 360.0, l / 100.0, s / 100.0)
    return "#{:02x}{:02x}{:02x}".format(
        round(max(0.0, min(1.0, r)) * 255),
        round(max(0.0, min(1.0, g)) * 255),
        round(max(0.0, min(1.0, b)) * 255),
    )


def clamp_hue(raw, anchor, limit):
    """Rotate `raw` toward `anchor` by at most `limit` degrees.

    Rotating to the limit rather than snapping to the anchor is the whole
    point: a wallpaper past the ceiling still keeps its own direction of
    drift, it just stops at the theme's margin.
    """
    delta = ((raw - anchor + 180.0) % 360.0) - 180.0
    if abs(delta) <= limit:
        return raw % 360.0
    return (anchor + (limit if delta > 0 else -limit)) % 360.0


def clamp_linear(raw, anchor, limit):
    return max(0.0, min(100.0, max(anchor - limit, min(anchor + limit, raw))))


def clamp_color(raw_hex, anchor_hex, key, max_hue, max_sat, max_light):
    raw_h, raw_l, raw_s = hex_to_hls(raw_hex)
    anchor_h, anchor_l, anchor_s = hex_to_hls(anchor_hex)

    sat = clamp_linear(raw_s, anchor_s, max_sat)
    if key in LIGHTNESS_EXEMPT:
        return hls_to_hex(raw_h, raw_l, sat)

    hue = clamp_hue(raw_h, anchor_h, max_hue)
    light = clamp_linear(raw_l, anchor_l, max_light)
    return hls_to_hex(hue, light, sat)


def clamp_palette(raw, anchor,
                  max_hue=DEFAULT_MAX_HUE_SHIFT,
                  max_sat=DEFAULT_MAX_SAT_SHIFT,
                  max_light=DEFAULT_MAX_LIGHT_SHIFT):
    """Return a copy of `raw` with every slot clamped against `anchor`.

    The raw palette's exact key structure is preserved (including any keys
    the anchor doesn't carry, which pass through untouched) so the result
    stays a valid pywal colorscheme for `wallust cs --format pywal`.
    """
    out = json.loads(json.dumps(raw))
    for section, keys in (("special", SPECIAL_KEYS), ("colors", COLOR_KEYS)):
        raw_section = raw.get(section) or {}
        anchor_section = anchor.get(section) or {}
        for key in keys:
            if key not in raw_section or key not in anchor_section:
                continue
            out[section][key] = clamp_color(
                raw_section[key], anchor_section[key], key,
                max_hue, max_sat, max_light,
            )
    return out


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("raw", help="path to the wallust-derived pywal JSON (~/.cache/wal/colors.json)")
    parser.add_argument("anchor", help="path to the theme's anchor pywal JSON")
    parser.add_argument("-o", "--output", help="write here instead of stdout")
    parser.add_argument("--max-hue-shift", type=float, default=DEFAULT_MAX_HUE_SHIFT)
    parser.add_argument("--max-sat-shift", type=float, default=DEFAULT_MAX_SAT_SHIFT)
    parser.add_argument("--max-light-shift", type=float, default=DEFAULT_MAX_LIGHT_SHIFT)
    args = parser.parse_args(argv)

    try:
        with open(args.raw) as f:
            raw = json.load(f)
        with open(args.anchor) as f:
            anchor = json.load(f)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"palette_clamp: {exc}", file=sys.stderr)
        return 1

    try:
        clamped = clamp_palette(raw, anchor,
                                args.max_hue_shift, args.max_sat_shift, args.max_light_shift)
    except ValueError as exc:
        print(f"palette_clamp: {exc}", file=sys.stderr)
        return 1

    text = json.dumps(clamped, indent=2) + "\n"
    if args.output:
        try:
            with open(args.output, "w") as f:
                f.write(text)
        except OSError as exc:
            print(f"palette_clamp: {exc}", file=sys.stderr)
            return 1
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
