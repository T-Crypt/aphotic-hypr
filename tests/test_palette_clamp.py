import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Configs" / ".local" / "lib" / "aphotic"))
from palette_clamp import clamp_hue, clamp_palette, hex_to_hls


def palette(**colors):
    """Build a pywal palette, defaulting every unset slot to mid grey."""
    base = {
        "special": {"background": "#101010", "foreground": "#e0e0e0", "cursor": "#e0e0e0"},
        "colors": {f"color{i}": "#808080" for i in range(16)},
    }
    for key, value in colors.items():
        if key in base["special"]:
            base["special"][key] = value
        else:
            base["colors"][key] = value
    return base


def test_hue_within_bound_passes_through():
    # anchor 30 deg (orange), raw ~40 deg -- inside a 20 deg ceiling, so
    # the wallpaper's own hue must survive untouched.
    raw = palette(color1="#cc8833")
    anchor = palette(color1="#cc6633")
    raw_h, _, _ = hex_to_hls(raw["colors"]["color1"])

    out = clamp_palette(raw, anchor, max_hue=20, max_sat=100, max_light=100)
    out_h, _, _ = hex_to_hls(out["colors"]["color1"])

    assert abs(out_h - raw_h) < 1.0


def test_hue_past_bound_rotates_to_limit_not_to_anchor():
    # Gruvbox-orange anchor vs. a neon-pink wallpaper accent: the result
    # must land exactly max_hue_shift away from the anchor, still on the
    # raw colour's side, rather than snapping onto the anchor itself.
    raw = palette(color1="#ff33aa")
    anchor = palette(color1="#cc6633")
    anchor_h, _, _ = hex_to_hls(anchor["colors"]["color1"])
    raw_h, _, _ = hex_to_hls(raw["colors"]["color1"])

    out = clamp_palette(raw, anchor, max_hue=20, max_sat=100, max_light=100)
    out_h, _, _ = hex_to_hls(out["colors"]["color1"])

    delta = ((out_h - anchor_h + 180) % 360) - 180
    raw_delta = ((raw_h - anchor_h + 180) % 360) - 180
    assert abs(abs(delta) - 20) < 0.5
    assert (delta > 0) == (raw_delta > 0)
    assert abs(out_h - anchor_h) > 1.0


def test_clamp_hue_takes_the_short_way_around_the_wheel():
    assert abs(clamp_hue(350, 10, 5) - 5) < 1e-9
    assert abs(clamp_hue(10, 350, 5) - 355) < 1e-9


def test_exempt_slots_keep_their_lightness():
    # background/foreground/cursor/color0/7/8/15 carry wallust's
    # check_contrast guarantees -- a very dark or very light wallpaper
    # must never have those pulled back toward the anchor's lightness.
    exempt = {
        "background": "#000000",
        "foreground": "#ffffff",
        "cursor": "#ffffff",
        "color0": "#050505",
        "color7": "#fafafa",
        "color8": "#0a0a0a",
        "color15": "#ffffff",
    }
    raw = palette(**exempt)
    anchor = palette(**{k: "#808080" for k in exempt})

    out = clamp_palette(raw, anchor, max_hue=20, max_sat=15, max_light=12)

    for key, value in exempt.items():
        got = out["special"].get(key) or out["colors"][key]
        _, raw_l, _ = hex_to_hls(value)
        _, out_l, _ = hex_to_hls(got)
        assert abs(out_l - raw_l) < 0.5, f"{key} lightness was clamped"


def test_non_exempt_slot_lightness_is_clamped():
    raw = palette(color3="#ffffff")
    anchor = palette(color3="#808080")

    out = clamp_palette(raw, anchor, max_hue=20, max_sat=15, max_light=12)
    _, out_l, _ = hex_to_hls(out["colors"]["color3"])
    _, anchor_l, _ = hex_to_hls(anchor["colors"]["color3"])

    assert abs(out_l - (anchor_l + 12)) < 0.5


def test_saturation_is_clamped_on_exempt_slots_too():
    raw = palette(background="#4b0082")
    anchor = palette(background="#101010")

    out = clamp_palette(raw, anchor, max_hue=20, max_sat=15, max_light=12)
    _, _, out_s = hex_to_hls(out["special"]["background"])
    _, _, anchor_s = hex_to_hls(anchor["special"]["background"])

    assert out_s <= anchor_s + 15 + 0.5


def test_key_structure_is_preserved():
    raw = palette()
    raw["alpha"] = "100"
    out = clamp_palette(raw, palette())

    assert set(out) == {"special", "colors", "alpha"}
    assert set(out["special"]) == {"background", "foreground", "cursor"}
    assert set(out["colors"]) == {f"color{i}" for i in range(16)}
