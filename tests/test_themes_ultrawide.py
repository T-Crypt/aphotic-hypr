"""An ultrawide screen gets a theme's ultrawide wallpapers first.

The probe runs the real Themes singleton offscreen over a throwaway awww
folder whose `.wallpapers.json` marks one image as 21:9. Qt's offscreen
platform takes a screen size from a config file, so the same theme is
read once on a 16:9 screen and once on a 3440x1440 one.
"""
import json
import shutil

import pytest
from test_sonar_session import run_probe

PROBE = """import QtQuick
import Quickshell
import qs.services
ShellRoot {
    id: root
    property int ticks: 0
    Timer { interval: 100; running: true; repeat: true; onTriggered: {
        root.ticks++;
        const info = Themes.themeInfo("nordic");
        if (!info && root.ticks < 40)
            return;
        console.log("ULTRAWIDE " + JSON.stringify({
            screen: Themes.ultrawideScreen,
            ultrawide: info ? info.ultrawide : null,
            first: Themes._preferredFirst(info),
            pool: Themes._preferredPool(info)
        }));
        Qt.quit();
    } }
}
"""


def _seed(tmp_path):
    theme = tmp_path / "home/.config/awww/nordic"
    theme.mkdir(parents=True)
    (theme / "theme.toml").write_text('[theme]\ndisplay_name = "Nordic"\n\n[wallpaper]\ndefault = "a.png"')
    for name in ("a.png", "b.png", "wide.png"):
        (theme / name).write_bytes(b"")
    (theme / ".wallpapers.json").write_text(json.dumps(
        {"schemaVersion": 1, "sizes": {"a.png": [1920, 1080], "b.png": [2560, 1440], "wide.png": [3440, 1440]}}))


@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
def test_a_16_9_screen_keeps_the_plain_order(tmp_path):
    _seed(tmp_path)
    out = run_probe(tmp_path, PROBE, marker="ULTRAWIDE", prefix="_ultrawide_")

    assert out["ultrawide"] == ["wide.png"], out
    assert out["screen"] is False
    assert out["first"] == ["a.png", "b.png", "wide.png"]
    assert out["pool"] == ["a.png", "b.png", "wide.png"]


@pytest.mark.skipif(shutil.which("qs") is None, reason="Quickshell unavailable")
def test_an_ultrawide_screen_puts_ultrawide_images_first(tmp_path):
    _seed(tmp_path)
    screens = tmp_path / "screens.json"
    screens.write_text(json.dumps({"screens": [{"name": "UW", "x": 0, "y": 0, "width": 3440, "height": 1440,
                                                "logicalDpi": 96, "logicalBaseDpi": 96, "dpr": 1}]}))
    out = run_probe(tmp_path, PROBE, extra_env={"QT_QPA_PLATFORM": f"offscreen:configfile={screens}"},
                    marker="ULTRAWIDE", prefix="_ultrawide_")

    assert out["screen"] is True, out
    assert out["first"] == ["wide.png", "a.png", "b.png"]
    assert out["pool"] == ["wide.png"]
