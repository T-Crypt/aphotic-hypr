#!/usr/bin/env python

import json
import os
import random
import subprocess


def run_optional(cmd):
    try:
        subprocess.run(cmd)
    except FileNotFoundError:
        pass

# Directory-per-theme layout (see themes/THEME_SPEC.md): each subfolder of
# awww_dir is a theme, containing wallpapers + an optional theme.toml pin.
# State is shared with the Quickshell side (services/Themes.qml) via the
# same ~/.local/state/noctis/theme.json, so switching from either side
# keeps the other in sync instead of drifting.
awww_dir = os.path.expanduser("~/.config/awww")
state_path = os.path.expanduser("~/.local/state/noctis/theme.json")

IMAGE_EXTS = (".png", ".jpg", ".jpeg", ".gif", ".webp")


def list_themes():
    if not os.path.isdir(awww_dir):
        return []
    return sorted(
        d for d in os.listdir(awww_dir)
        if os.path.isdir(os.path.join(awww_dir, d))
    )


def list_wallpapers(theme):
    theme_dir = os.path.join(awww_dir, theme)
    if not os.path.isdir(theme_dir):
        return []
    return sorted(
        f for f in os.listdir(theme_dir)
        if f.lower().endswith(IMAGE_EXTS)
    )


def read_state():
    try:
        with open(state_path) as f:
            data = json.load(f)
            return data.get("theme", ""), data.get("wallpaper", "")
    except (FileNotFoundError, json.JSONDecodeError):
        return "", ""


def write_state(theme, wallpaper):
    os.makedirs(os.path.dirname(state_path), exist_ok=True)
    with open(state_path, "w") as f:
        json.dump({"theme": theme, "wallpaper": wallpaper}, f, indent=2)


def parse_engine_pin(theme):
    toml_path = os.path.join(awww_dir, theme, "theme.toml")
    backend = ""
    palette = ""
    colorscheme = ""
    style = ""
    papirus_color = ""
    if not os.path.isfile(toml_path):
        return backend, palette, colorscheme, style, papirus_color
    section = ""
    with open(toml_path) as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("[") and line.endswith("]"):
                section = line[1:-1]
                continue
            if "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip().strip('"')
            if section == "engine":
                if key == "backend":
                    backend = value
                elif key == "palette":
                    palette = value
                elif key == "colorscheme":
                    colorscheme = value
                elif key == "style":
                    style = value
            elif section == "icons" and key == "papirus_color":
                papirus_color = value
    return backend, palette, colorscheme, style, papirus_color


def notify(message):
    subprocess.run([
        "notify-send",
        "-h", "string:x-canonical-private-synchronous:hypr-cfg",
        "-u", "low",
        message,
    ])


def apply_wallpaper(theme, wallpaper):
    image_path = os.path.join(awww_dir, theme, wallpaper)

    subprocess.run(["awww", "img", "--transition-type", "wipe", "--transition-duration", "3", image_path])

    backend, palette, colorscheme, style, papirus_color = parse_engine_pin(theme)
    if colorscheme:
        # Fixed palette pin -- see cmd_theme.sh's _noctis_theme_apply for
        # why some themes (HackTheBox's real green/navy scheme) pin an
        # exact colorscheme file instead of deriving from the image.
        subprocess.run(["wallust", "cs", colorscheme, "--format", "pywal"])
    else:
        wallust_cmd = ["wallust", "run", image_path]
        if backend:
            wallust_cmd += ["-b", backend]
        if palette:
            wallust_cmd += ["-p", palette]
        if style:
            wallust_cmd += ["-S", style]
        subprocess.run(wallust_cmd)
    subprocess.run(["cp", image_path, os.path.join(awww_dir, "wallpaper.rofi")])

    if papirus_color:
        # Folder-icon accent pin -- see cmd_theme.sh's _noctis_theme_apply
        # for why this needs passwordless sudo and only no-ops silently
        # (same best-effort class as the sddm sync call below) rather
        # than blocking on a password prompt.
        run_optional(["sudo", "-n", "papirus-folders", "-C", papirus_color, "--theme", "Papirus-Dark", "-u"])

    # State is the source other tools (Quickshell's Themes.qml) read back,
    # so it's saved right after the actual wallpaper+color change lands --
    # ahead of the best-effort integration calls below, none of which
    # should be able to leave state stale just because e.g. pywalfox isn't
    # installed or `noctis` isn't on PATH in a given environment.
    write_state(theme, wallpaper)

    run_optional(["pywalfox", "update"])
    run_optional(["noctis", "reload"])
    run_optional(["noctis", "sddm", "sync"])
    notify(f"Wallpaper changed to {theme}/{wallpaper}")


def main():
    themes = list_themes()
    if not themes:
        notify("No theme folders found in ~/.config/awww")
        return

    current_theme, current_wallpaper = read_state()
    if current_theme not in themes:
        current_theme = themes[0]

    wallpapers = list_wallpapers(current_theme)
    if not wallpapers:
        notify(f"No wallpapers found in theme '{current_theme}'")
        return

    # Random pick within the current theme, excluding the current
    # wallpaper when there's more than one to choose from -- matches the
    # original script's "always changes to something new" behavior.
    choices = [w for w in wallpapers if w != current_wallpaper] or wallpapers
    next_wallpaper = random.choice(choices)

    apply_wallpaper(current_theme, next_wallpaper)


if __name__ == "__main__":
    main()
