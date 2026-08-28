#!/usr/bin/env python

import json
import os
import random
import re
import subprocess
import sys


def run_optional(cmd, check=True):
    """Run command optionally with error handling."""
    try:
        if check:
            subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        else:
            subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (FileNotFoundError, subprocess.CalledProcessError):
        pass


# Directory-per-theme layout (see themes/THEME_SPEC.md): each subfolder of
# awww_dir is a theme, containing wallpapers + an optional theme.toml pin.
# State is shared with the Quickshell side (services/Themes.qml) via the
# same ~/.local/state/aphotic/theme.json, so switching from either side
# keeps the other in sync instead of drifting.
awww_dir = os.path.expanduser("~/.config/awww")
state_path = os.path.expanduser("~/.local/state/aphotic/theme.json")

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
    icon_theme = ""
    cursor_theme = ""
    gtk_theme = ""
    engine_name = ""
    if not os.path.isfile(toml_path):
        return backend, palette, colorscheme, style, papirus_color, icon_theme, cursor_theme, gtk_theme, engine_name
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
                elif key == "name":
                    engine_name = value
            elif section == "icons":
                if key == "papirus_color":
                    papirus_color = value
                elif key == "icon_theme":
                    icon_theme = value
                elif key == "cursor_theme":
                    cursor_theme = value
            elif section == "gtk" and key == "theme":
                gtk_theme = value
    return backend, palette, colorscheme, style, papirus_color, icon_theme, cursor_theme, gtk_theme, engine_name


settings_path = os.path.expanduser("~/.local/state/aphotic/settings.json")
qtct_paths = (
    os.path.expanduser("~/.config/qt5ct/qt5ct.conf"),
    os.path.expanduser("~/.config/qt6ct/qt6ct.conf"),
)


# Mirrors cmd_theme.sh's _aphotic_theme_apply icon/cursor/gtk-theme pin
# block -- see that function's comment for why this patches settings.json
# directly (Quickshell's own state, watchChanges: true picks it up live if
# the shell is running) as well as calling gsettings/hyprctl/sed directly
# (so it still takes effect even if the shell isn't running at all). Only
# applies while the matching Settings.qml *UserSet flag is still false.
def apply_theme_pins(icon_theme, cursor_theme, gtk_theme):
    if not (icon_theme or cursor_theme or gtk_theme):
        return
    try:
        with open(settings_path) as f:
            settings = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        settings = {}

    changed = False

    if icon_theme and not settings.get("iconThemeUserSet", False):
        settings["iconTheme"] = icon_theme
        changed = True
        # Run these in background to reduce lag - they're not critical for wallpaper change
        run_optional(["gsettings", "set", "org.gnome.desktop.interface", "icon-theme", icon_theme], check=False)
        for qtct_path in qtct_paths:
            if os.path.isfile(qtct_path):
                try:
                    with open(qtct_path) as f:
                        text = f.read()
                    text = re.sub(r"(?m)^icon_theme=.*$", f"icon_theme={icon_theme}", text)
                    with open(qtct_path, "w") as f:
                        f.write(text)
                except (IOError, OSError):
                    pass

    if cursor_theme and not settings.get("cursorThemeUserSet", False):
        settings["cursorTheme"] = cursor_theme
        changed = True
        # Run these in background to reduce lag - they're not critical for wallpaper change
        run_optional(["hyprctl", "setcursor", cursor_theme, str(settings.get("cursorSize", 24))], check=False)
        run_optional(["gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", cursor_theme], check=False)

    if gtk_theme and not settings.get("gtkThemeUserSet", False):
        settings["gtkTheme"] = gtk_theme
        changed = True
        # Run these in background to reduce lag - they're not critical for wallpaper change
        run_optional(["gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", gtk_theme], check=False)

    if changed:
        os.makedirs(os.path.dirname(settings_path), exist_ok=True)
        try:
            with open(settings_path, "w") as f:
                json.dump(settings, f, indent=2)
        except (IOError, OSError):
            pass


def apply_wallpaper(theme, wallpaper):
    image_path = os.path.join(awww_dir, theme, wallpaper)

    # Apply wallpaper with minimal transition for speed
    run_optional(["awww", "img", "--transition-type", "none", "--transition-duration", "0", image_path])

    backend, palette, colorscheme, style, papirus_color, icon_theme, cursor_theme, gtk_theme, engine_name = parse_engine_pin(theme)

    # [engine].name is documented (themes/THEME_SPEC.md) as accepting
    # "wallust" | "matugen", but nothing here (or in cmd_theme.sh/
    # Wallpapers.qml) has ever actually read it -- every apply path always
    # runs wallust regardless, so a theme pinning matugen silently got
    # wallust instead with zero indication anything was ignored. Not
    # implementing matugen here -- just making the mismatch loud instead
    # of silent.
    if engine_name and engine_name != "wallust":
        print(f"theme '{theme}' pins engine '{engine_name}', but only wallust is wired up — using wallust")

    if colorscheme:
        # Fixed palette pin -- see cmd_theme.sh's _aphotic_theme_apply for
        # why some themes (HackTheBox's real green/navy scheme) pin an
        # exact colorscheme file instead of deriving from the image.
        run_optional(["wallust", "cs", colorscheme, "--format", "pywal"])
    else:
        wallust_cmd = ["wallust", "run", image_path]
        if backend:
            wallust_cmd += ["-b", backend]
        if palette:
            wallust_cmd += ["-p", palette]
        if style:
            wallust_cmd += ["-S", style]
        run_optional(wallust_cmd)
    
    # Copy to rofi wallpaper
    try:
        subprocess.run(["cp", image_path, os.path.join(awww_dir, "wallpaper.rofi")], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (FileNotFoundError, subprocess.CalledProcessError):
        pass

    # Plugin theme-hooks - run in background to reduce lag
    run_optional(["aphotic", "plugin", "run-theme-hooks"], check=False)

    # Handle papirus-folders with no sudo prompt if possible
    if papirus_color:
        # Run without blocking for better performance - use non-blocking sudo if available or skip if not
        try:
            subprocess.run(["sudo", "-n", "papirus-folders", "-C", papirus_color, "--theme", "Papirus-Dark", "-u"], 
                          check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except (FileNotFoundError, subprocess.CalledProcessError):
            pass

    # Apply theme pins in background to reduce lag
    apply_theme_pins(icon_theme, cursor_theme, gtk_theme)

    # State is the source other tools (Quickshell's Themes.qml) read back,
    # so it's saved right after the actual wallpaper+color change lands --
    # ahead of the best-effort integration calls below, none of which
    # should be able to leave state stale just because e.g. pywalfox isn't
    # installed or `aphotic` isn't on PATH in a given environment.
    write_state(theme, wallpaper)

    # Run these background processes without blocking for better performance
    run_optional(["pywalfox", "update"], check=False)
    run_optional(["aphotic", "reload"], check=False)
    run_optional(["aphotic", "sddm", "sync"], check=False)


def main():
    themes = list_themes()
    if not themes:
        print("No theme folders found in ~/.config/awww")
        return

    current_theme, current_wallpaper = read_state()
    if current_theme not in themes:
        current_theme = themes[0]

    wallpapers = list_wallpapers(current_theme)
    if not wallpapers:
        print(f"No wallpapers found in theme '{current_theme}'")
        return

    # --next used to just be an alias for random (themes shipped too few
    # wallpapers each for order to matter) -- now that every theme ships
    # several curated wallpapers, a real deterministic cycle is more
    # useful and matches what the flag's name actually promises. Default
    # (no flag, still what SUPER+W's keybind runs) stays random --
    # nothing asked to change that keybind's own feel.
    if "--next" in sys.argv[1:] and current_wallpaper in wallpapers:
        idx = wallpapers.index(current_wallpaper)
        next_wallpaper = wallpapers[(idx + 1) % len(wallpapers)]
    else:
        # Random pick within the current theme, excluding the current
        # wallpaper when there's more than one to choose from -- matches
        # the original script's "always changes to something new" behavior.
        choices = [w for w in wallpapers if w != current_wallpaper] or wallpapers
        next_wallpaper = random.choice(choices)

    apply_wallpaper(current_theme, next_wallpaper)


if __name__ == "__main__":
    main()