#!/usr/bin/env python

import json
import os
import random
import re
import shutil
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


def run_detached(cmd):
    """Fire-and-forget a command with no wait -- for integration calls
    (reload, sddm sync, pywalfox, plugin hooks, desktop-pin gsettings/
    hyprctl calls, papirus-folders) that are genuinely best-effort and
    don't gate anything later in apply_wallpaper. Comments used to claim
    several of these "run in background", but they were still plain
    subprocess.run() calls underneath -- actually blocking, sequentially,
    on however long each one took (including a `sudo -n` call and a
    pywalfox native-messaging round trip, both of which can stall).
    start_new_session detaches fully so the child outlives this
    short-lived script cleanly instead of depending on it staying alive
    to be reaped.
    """
    try:
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL, start_new_session=True)
    except FileNotFoundError:
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
    """Return a sorted list of theme directory names in the awww directory.

    Each theme is represented by a subdirectory under `awww_dir`. Returns
    an empty list if the awww directory does not exist.
    """
    if not os.path.isdir(awww_dir):
        return []
    return sorted(
        d for d in os.listdir(awww_dir)
        if os.path.isdir(os.path.join(awww_dir, d))
    )


def list_wallpapers(theme):
    """List image files for `theme` in the awww directory.

    Returns a sorted list of filenames that match IMAGE_EXTS. If the
    specified theme directory does not exist, an empty list is returned.
    """
    theme_dir = os.path.join(awww_dir, theme)
    if not os.path.isdir(theme_dir):
        return []
    return sorted(
        f for f in os.listdir(theme_dir)
        if f.lower().endswith(IMAGE_EXTS)
    )


def read_state():
    """Read the persisted theme state JSON and return (theme, wallpaper).

    If the state file is missing or malformed, returns the empty pair
    ("", "") to indicate no valid current state.
    """
    try:
        with open(state_path) as f:
            data = json.load(f)
            return data.get("theme", ""), data.get("wallpaper", "")
    except (FileNotFoundError, json.JSONDecodeError):
        return "", ""


def write_state(theme, wallpaper):
    """Atomically persist the chosen theme and wallpaper to state_path.

    The function writes to a per-process temporary file and renames it over
    the real path to avoid leaving a partial file that concurrent readers
    (like Themes.qml) might try to parse.
    """
    # Atomic write: a plain open(state_path, "w") truncates the file
    # before writing the new content, so any read landing in that window
    # (Themes.qml watching the file, or this same script fired again by
    # key-repeat on the wallswitcher keybind before this call returns)
    # sees an empty file, fails JSON decoding, and read_state() falls
    # back to ("", "") -- which main() then resolves to themes[0], i.e.
    # whichever theme sorts first alphabetically (gruvbox), regardless
    # of the theme actually in use. Writing to a per-process temp file
    # and rename()-ing over the real path is atomic at the filesystem
    # level: a concurrent reader always sees either the old, fully-formed
    # state or the new one, never a partial/empty file.
    os.makedirs(os.path.dirname(state_path), exist_ok=True)
    tmp_path = f"{state_path}.{os.getpid()}.tmp"
    with open(tmp_path, "w") as f:
        json.dump({"theme": theme, "wallpaper": wallpaper}, f, indent=2)
    os.replace(tmp_path, state_path)


def parse_engine_pin(theme):
    """Parse a theme's theme.toml and return engine/icon/gtk pins.

    Reads the theme's theme.toml and extracts known keys from the
    [engine], [icons], and [gtk] sections. Returns a tuple with
    (backend, palette, colorscheme, style, papirus_color, icon_theme,
    cursor_theme, gtk_theme, engine_name, scheme, contrast). Missing
    fields are empty strings.
    """
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
    scheme = ""
    contrast = ""
    if not os.path.isfile(toml_path):
        return backend, palette, colorscheme, style, papirus_color, icon_theme, cursor_theme, gtk_theme, engine_name, scheme, contrast
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
                elif key == "scheme":
                    scheme = value
                elif key == "contrast":
                    contrast = value
            elif section == "icons":
                if key == "papirus_color":
                    papirus_color = value
                elif key == "icon_theme":
                    icon_theme = value
                elif key == "cursor_theme":
                    cursor_theme = value
            elif section == "gtk" and key == "theme":
                gtk_theme = value
    return backend, palette, colorscheme, style, papirus_color, icon_theme, cursor_theme, gtk_theme, engine_name, scheme, contrast


def parse_palette_pin(theme):
    """Return a theme's [palette] clamp pins as a dict of strings.

    Kept separate from parse_engine_pin's tuple because this table is
    optional and self-contained: an empty "anchor" means the theme never
    opted into clamping and the derived palette is used as-is.
    """
    toml_path = os.path.join(awww_dir, theme, "theme.toml")
    pins = {"anchor": "", "max_hue_shift": "", "max_sat_shift": "", "max_light_shift": ""}
    if not os.path.isfile(toml_path):
        return pins
    section = ""
    with open(toml_path) as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("[") and line.endswith("]"):
                section = line[1:-1]
                continue
            if section != "palette" or "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            if key in pins:
                pins[key] = value.strip().strip('"')
    return pins


# Mirrors cmd_theme.sh's _aphotic_theme_clamp_palette -- see that function
# and themes/THEME_SPEC.md's "Clamped palettes" section. Rewrites the raw
# image-derived palette wallust just cached into a clamped colorscheme
# file, then re-runs every template from it via `wallust cs`.
def apply_palette_clamp(theme, pins):
    """Clamp the freshly derived palette toward the theme's anchor."""
    if not pins["anchor"]:
        return
    schemes_dir = os.path.expanduser("~/.config/wallust/colorschemes")
    anchor_file = os.path.join(schemes_dir, f"{pins['anchor']}.json")
    raw_file = os.path.expanduser("~/.cache/wal/colors.json")
    if not os.path.isfile(anchor_file):
        print(f"theme '{theme}' pins [palette].anchor = '{pins['anchor']}' but {anchor_file} is missing — applying unclamped palette")
        return
    if not os.path.isfile(raw_file):
        return

    # The CLI's lib/ lives in the dots checkout, not under ~/.local --
    # install.sh only symlinks ~/.local/bin/aphotic.
    dots_dir = os.environ.get("APHOTIC_DOTS_DIR") or os.path.expanduser("~/Aphotic-Hypr")
    live = os.path.join(schemes_dir, f"{theme}-live.json")
    cmd = [
        "python3", os.path.join(dots_dir, "Configs/.local/lib/aphotic/palette_clamp.py"),
        raw_file, anchor_file, "-o", live,
    ]
    for flag, key in (("--max-hue-shift", "max_hue_shift"),
                      ("--max-sat-shift", "max_sat_shift"),
                      ("--max-light-shift", "max_light_shift")):
        if pins[key]:
            cmd += [flag, pins[key]]

    try:
        subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (FileNotFoundError, subprocess.CalledProcessError):
        print(f"palette clamp failed for '{theme}' — applying unclamped palette")
        return
    run_optional(["wallust", "cs", f"{theme}-live", "--format", "pywal"])


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
    """Apply pinned icon/cursor/GTK themes if the user hasn't overridden them.

    Only updates settings.json when the corresponding "UserSet" flag is
    not true. When applying a pin, also fire detached system commands to
    apply the change immediately where possible (gsettings, hyprctl), and
    update qt5ct/qt6ct configs when present. IO errors are ignored to
    keep the function robust in varied environments.
    """
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
        # Not critical for the wallpaper change itself -- genuinely
        # detached, not just blocking with output suppressed.
        run_detached(["gsettings", "set", "org.gnome.desktop.interface", "icon-theme", icon_theme])
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
        run_detached(["hyprctl", "setcursor", cursor_theme, str(settings.get("cursorSize", 24))])
        run_detached(["gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", cursor_theme])

    if gtk_theme and not settings.get("gtkThemeUserSet", False):
        settings["gtkTheme"] = gtk_theme
        changed = True
        run_detached(["gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", gtk_theme])

    if changed:
        os.makedirs(os.path.dirname(settings_path), exist_ok=True)
        try:
            with open(settings_path, "w") as f:
                json.dump(settings, f, indent=2)
        except (IOError, OSError):
            pass


def apply_wallpaper(theme, wallpaper):
    """Apply `wallpaper` from `theme`.

    This performs the full apply flow: tell awww to display the image,
    run the theme's pinned colour engine -- matugen, or wallust (or a
    fixed colorscheme) -- to generate palettes, copy the wallpaper for
    the launcher, run detached plugin hooks, apply any pinned
    icon/cursor/GTK themes, persist state, and fire best-effort
    integration commands (pywalfox, aphotic reload/sddm sync).
    """
    image_path = os.path.join(awww_dir, theme, wallpaper)

    # `awww img` only hands the image to the awww-daemon and returns --
    # the daemon animates the transition itself, in its own process, so
    # transition-duration costs this script nothing (measured: ~20ms
    # whether the transition is instant or several seconds long). The
    # previous "none"/instant transition here was chasing script latency
    # that was actually coming from the blocking integration calls below
    # -- it bought no real speed and just made every switch a hard,
    # jarring cut. A short fade is smooth without adding any wait.
    run_optional(["awww", "img", "--transition-type", "fade", "--transition-duration", "0.45", "--transition-fps", "60", image_path])

    backend, palette, colorscheme, style, papirus_color, icon_theme, cursor_theme, gtk_theme, engine_name, scheme, contrast = parse_engine_pin(theme)
    palette_pins = parse_palette_pin(theme)

    if engine_name and engine_name not in ("wallust", "matugen"):
        print(f"theme '{theme}' pins unknown engine '{engine_name}' — using wallust")
    if colorscheme and palette_pins["anchor"]:
        # A fixed colorscheme derives nothing from the image, so there's
        # no raw palette for the clamp to bound.
        print(f"theme '{theme}' sets both [engine].colorscheme and [palette].anchor — using the fixed colorscheme, skipping the clamp")

    if engine_name == "matugen":
        # --prefer is not optional: matugen refuses to choose between an
        # image's candidate source colours without a terminal to prompt on.
        matugen_cmd = ["matugen", "image", image_path, "--prefer", "saturation", "-q"]
        if scheme:
            matugen_cmd += ["-t", scheme]
        if style:
            matugen_cmd += ["-m", style]
        if contrast:
            matugen_cmd += ["--contrast", contrast]
        run_optional(matugen_cmd)
    elif colorscheme:
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
        apply_palette_clamp(theme, palette_pins)

    # In-process copy -- cheaper than spawning `cp` for what's just a
    # few-MB file, and nothing after this depends on it landing first.
    try:
        shutil.copyfile(image_path, os.path.join(awww_dir, "current-wallpaper"))
    except OSError:
        pass

    # Plugin theme-hooks: genuinely detached now. Ordering (wallust must
    # have already re-templated palette.json before hooks read it) only
    # ever depended on wallust's own call above having already returned
    # by the time this line runs -- not on this call itself blocking
    # until every hook finishes, which is what the old "blocks until
    # wallust finished" comment actually needed.
    run_detached(["aphotic", "plugin", "run-theme-hooks"])

    # Handle papirus-folders with no sudo prompt if possible
    if papirus_color:
        run_detached(["sudo", "-n", "papirus-folders", "-C", papirus_color, "--theme", "Papirus-Dark", "-u"])

    # Local file writes (settings.json, qt5ct/qt6ct configs) stay
    # synchronous here -- they're just fast disk I/O; only the
    # gsettings/hyprctl calls apply_theme_pins fires off are detached.
    apply_theme_pins(icon_theme, cursor_theme, gtk_theme)

    # State is the source other tools (Quickshell's Themes.qml) read back,
    # so it's saved right after the actual wallpaper+color change lands --
    # ahead of the best-effort integration calls below, none of which
    # should be able to leave state stale just because e.g. pywalfox isn't
    # installed or `aphotic` isn't on PATH in a given environment.
    write_state(theme, wallpaper)

    # Genuinely fire-and-forget: nothing downstream in this script waits
    # on any of these, so there's no reason to block on a full Quickshell
    # reload or a pywalfox native-messaging round trip before returning.
    run_detached(["pywalfox", "update"])
    run_detached(["aphotic", "reload"])
    run_detached(["aphotic", "sddm", "sync"])


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