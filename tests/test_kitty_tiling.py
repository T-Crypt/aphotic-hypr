"""kitty must not restore a maximized window on launch.

A maximized kitty wrote {"window-state": "maximized"} to
~/.cache/kitty/main.json, and every later kitty restored it, so each new
terminal opened maximized over the workspace. Toggling a group masked it,
which is why the auto_group fix did not end the reports. This test fails
the moment kitty.conf stops disabling the restore.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def active_option(path, name):
    for line in path.read_text().splitlines():
        stripped = line.strip()
        if stripped.startswith("#") or not stripped:
            continue
        key, _, value = stripped.partition(" ")
        if key == name:
            return value.strip()
    return None


def test_kitty_does_not_remember_window_size():
    conf = ROOT / "Configs" / "kitty" / "kitty.conf"
    assert active_option(conf, "remember_window_size") == "no"
