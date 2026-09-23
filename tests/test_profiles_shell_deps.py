"""Hard rule 8: whatever the shell launches ships in both base profiles.

A fresh minimal install drew every icon as its ligature name because the
icon font was missing, and later audits found dead volume keys, a Super+M
bound to a program no profile installed, and bar buttons that opened
nothing. Each case was a binary or asset used on one machine and never
added to a profile. These tests fail the moment that happens again.
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib" / "toml"))
from merge import merge_packages

ROOT = Path(__file__).resolve().parents[1]

# Binary the shell or its Hyprland config runs -> the package that ships it.
SHELL_BINARIES = {
    "pamixer": "pamixer",
    "brightnessctl": "brightnessctl",
    "awww-daemon": "awww",
    "kitty": "kitty",
    "nm-applet": "network-manager-applet",
    "nm-connection-editor": "network-manager-applet",
    "blueman-applet": "blueman",
    "blueman-manager": "blueman",
    "papirus-folders": "papirus-folders",
    "gsettings": "glib2",
    "matugen": "matugen",
}

# Apps a keybind launches that only the full profile promises. Minimal
# tells the user to install their own programs.
FULL_ONLY_APPS = {"firefox", "thunar", "code"}

# Launchers and system tools that are not profile packages.
NOT_PACKAGES = {"qs", "aphotic", "systemctl", "dbus-update-activation-environment"}

# Settings.qml default -> package that provides it.
DEFAULT_THEMES = {
    "iconTheme": ("Papirus-Dark", "papirus-icon-theme"),
    "cursorTheme": ("Bibata-Modern-Ice", "bibata-cursor-theme"),
    "gtkTheme": ("adw-gtk3-dark", "adw-gtk-theme"),
}


def _packages(profile):
    merged = merge_packages(str(ROOT / f"profiles/base/{profile}.toml"), [])
    return set(merged["main"]) | set(merged.get("prep", []))


def _hypr_commands():
    words = set()
    for name in ("keybinds.lua", "startup.lua"):
        text = (ROOT / "Configs/hypr" / name).read_text()
        for cmd in re.findall(r'exec_cmd\(\s*"([^"]+)"', text):
            for part in re.split(r"&&|\|\||;|\|", cmd):
                w = part.strip().split()
                while w and (w[0] in ("sleep", "command", "-v") or re.fullmatch(r"[0-9.]+", w[0])):
                    w = w[1:]
                if w and not w[0].startswith(("/", "~")):
                    words.add(w[0])
    return words


def test_shell_binaries_ship_in_both_profiles():
    for profile in ("full", "minimal"):
        packages = _packages(profile)
        for binary, package in SHELL_BINARIES.items():
            assert package in packages, f"{binary} needs {package}, missing from {profile}"


def test_hypr_config_launches_only_shipped_programs():
    unknown = _hypr_commands() - set(SHELL_BINARIES) - FULL_ONLY_APPS - NOT_PACKAGES
    assert not unknown, f"Hyprland config launches {sorted(unknown)}; map each to a profile package"


def test_full_only_apps_ship_in_full():
    full = _packages("full")
    for app in FULL_ONLY_APPS:
        package = "visual-studio-code-bin" if app == "code" else app
        assert package in full, f"{app} is bound to a key but missing from full"


def test_settings_default_themes_ship_in_both_profiles():
    settings = (ROOT / "Configs/quickshell/aphotic/services/Settings.qml").read_text()
    for prop, (value, package) in DEFAULT_THEMES.items():
        match = re.search(rf'property string {prop}: "([^"]*)"', settings)
        assert match, f"Settings.qml no longer declares {prop}"
        assert match.group(1) == value, f"{prop} default changed to {match.group(1)}; update DEFAULT_THEMES and the profiles"
        for profile in ("full", "minimal"):
            assert package in _packages(profile), f"default {prop} {value} needs {package}, missing from {profile}"


def test_gtk_monospace_font_ships_in_both_profiles():
    startup = (ROOT / "Configs/hypr/startup.lua").read_text()
    match = re.search(r"monospace-font-name '([^']+?) \d+'", startup)
    assert match and match.group(1) == "JetBrainsMono Nerd Font Mono"
    for profile in ("full", "minimal"):
        assert "ttf-jetbrains-mono-nerd" in _packages(profile)
