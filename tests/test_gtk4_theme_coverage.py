"""Every path that regenerates the palette must also deploy the GTK4 stylesheet.

The colour engines write ~/.local/state/aphotic/gtk4.css. Nothing reads
it until `aphotic theme refresh-gtk` stamps the live UI font in and
installs it over ~/.config/gtk-4.0/gtk.css, which is the only file
libadwaita looks at. A path that runs an engine and skips that step
leaves every GTK4 app on the previous theme's colours, and says nothing.

That is not one call site. Five separate places run an engine: the CLI's
theme apply and scheme set, Hyprland's two wallpaper scripts, and the
shell's own picker. The first cut of this feature covered one of them.

So this test has two halves. It pins the five known paths, and it fails
on a sixth appearing anywhere in the tree, which is the half that
actually catches the next one.
"""

import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent

# The deploy, named as each language spells it.
DEPLOY = re.compile(r"_aphotic_theme_refresh_gtk|refresh-gtk")

# An engine in command position, which is narrower than the engine being
# named. `wallust run`, `matugen image` and the list-head form
# ["wallust", "cs", ...] all launch one. Colours.qml's
# `engine === "matugen"` reads which one already ran and must not match,
# nor must a wallust.toml path or a `wallust_cmd` variable name.
ENGINE = re.compile(
    r"""wallust\s+(?:run|cs|pywal|theme)\b"""
    r"""|matugen\s+image\b"""
    r"""|["'](?:wallust|matugen)["']\s*,"""
    r"""|aphotic_matugen_run"""
)

# Files that name an engine without being a path a user can take to a new
# palette. Each is exempt for a stated reason, not because the pattern was
# inconvenient.
EXEMPT = {
    "Configs/.local/lib/aphotic/globalcontrol.sh":
        "defines aphotic_matugen_run; every caller is itself covered below",
    "scripts/generate-theme-anchors.sh":
        "runs wallust against a throwaway config dir, never the real targets",
    "Configs/.local/lib/aphotic/palette_clamp.py":
        "rewrites a cached palette file, runs no engine",
}

# The paths that must deploy. Listed rather than discovered, so deleting a
# call site fails here instead of quietly shrinking the covered set.
REQUIRED = [
    "Configs/.local/lib/aphotic/commands/cmd_theme.sh",
    "Configs/.local/lib/aphotic/commands/cmd_scheme.sh",
    "Configs/hypr/scripts/wallswitcher.py",
    "Configs/hypr/scripts/thunar_wall.py",
    "Configs/quickshell/aphotic/services/Wallpapers.qml",
]

SCANNED = (".sh", ".py", ".qml", ".lua")


def strip_comments(text, suffix):
    """A grep-shaped test fails on its own explanatory prose otherwise.

    Both halves below would match the comments this feature is documented
    in, so the comments come out first. Same reason
    test_singleton_reachability.py strips `//`.
    """
    marker = {".qml": "//", ".lua": "--"}.get(suffix, "#")
    return "\n".join(line.split(marker)[0] for line in text.splitlines())


def source_files():
    for path in ROOT.rglob("*"):
        if path.suffix not in SCANNED or not path.is_file():
            continue
        rel = path.relative_to(ROOT).as_posix()
        if rel.startswith(("tests/", "docs/", ".git/")):
            continue
        yield rel, path


@pytest.mark.parametrize("rel", REQUIRED)
def test_known_palette_path_deploys_gtk4_stylesheet(rel):
    path = ROOT / rel
    body = strip_comments(path.read_text(), path.suffix)
    assert ENGINE.search(body), f"{rel} no longer runs a colour engine; drop it from REQUIRED"
    assert DEPLOY.search(body), (
        f"{rel} regenerates the palette without deploying the GTK4 stylesheet, "
        "so every GTK4 app keeps the previous theme's colours"
    )


def test_no_unlisted_path_runs_a_colour_engine():
    missed = []
    for rel, path in source_files():
        if rel in REQUIRED or rel in EXEMPT:
            continue
        body = strip_comments(path.read_text(), path.suffix)
        if ENGINE.search(body):
            missed.append(rel)
    assert not missed, (
        "these run a colour engine and are neither a known deploy path nor "
        f"exempt: {missed}. Add the GTK4 deploy and list it in REQUIRED, or "
        "add it to EXEMPT with the reason it cannot reach a new palette"
    )
