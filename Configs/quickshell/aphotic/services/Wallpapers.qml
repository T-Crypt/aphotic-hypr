pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

// Real convention already used by every wallpaper-setting script in this
// repo (rofi-wallpaper.sh, thunar_wall.py, wallswitcher.py): they all copy
// the chosen image to ~/.config/awww/wallpaper.rofi as the "current
// wallpaper" marker -- not a text file, an actual copy of the image
// itself.
Singleton {
    id: root

    readonly property string path: `${Quickshell.env("HOME")}/.config/awww/wallpaper.rofi`
    // Query-string cache-bust: an Image with a `source` URL that never
    // changes won't notice the file's bytes changed underneath it
    // (wallpaper.rofi is the same path every time, just re-copied).
    // Bumping this on every FileView change forces a real reload.
    property int generation: 0
    readonly property string current: generation >= 0 ? `file://${path}?g=${generation}` : ""

    FileView {
        path: root.path
        watchChanges: true
        onFileChanged: root.generation++
    }

    // Bumped on every setWallpaper() call, and stamped onto wallustProc
    // right before each exec() -- see the onExited guard below for why.
    property int _generation: 0

    // backend/palette let a theme's theme.toml pin a specific wallust
    // engine mode (see themes/THEME_SPEC.md) for wallpapers that need
    // something other than Configs/wallust/wallust.toml's own defaults --
    // both are optional, an empty string means "let wallust use its own
    // configured default" rather than forcing a value. colorscheme is a
    // different engine mode entirely: a fixed palette read from
    // Configs/wallust/colorschemes/<name>.json instead of derived from
    // the wallpaper image, for themes with a real brand palette (e.g.
    // HackTheBox) that shouldn't drift with whatever art the default
    // wallpaper happens to contain -- when set, backend/palette (image-
    // generation-only knobs) are ignored, mirroring cmd_theme.sh's
    // _aphotic_theme_apply so the CLI and this QML path stay in sync.
    //
    // Picking themes in quick succession (the Appearance pane's grid has
    // no per-click cooldown, by design -- clicking should always feel
    // instant) used to launch a fresh, independent `awww img` transition
    // and a fresh, independent `wallust run` on every single click via
    // Quickshell.execDetached, with no way to cancel the previous one.
    // Two wallust runs racing meant two processes writing the same
    // Colours.qml/Kvantum/GTK/cava/swaylock output files concurrently --
    // whichever finished last "won" per file, so a fast double-pick could
    // land on a torn mix of both themes' colors (the actual "glitchy"
    // symptom) -- and two `awww img` calls raced two wipe transitions on
    // screen at once. Routing both through a real Process + exec() fixes
    // this for free: exec() on an already-running Process kills it and
    // launches the new command immediately (same convention already
    // relied on by Settings.qml's cursorApplyProc), so only the
    // most-recently-clicked theme's processes ever survive to write
    // anything or animate anything.
    function setWallpaper(path: string, backend: var, palette: var, colorscheme: var, style: var, papirusColor: var, iconTheme: var, cursorTheme: var, gtkTheme: var, engineName: var): void {
        root._generation++;

        // [engine].name is documented (themes/THEME_SPEC.md) as accepting
        // "wallust" | "matugen", but nothing here (or in cmd_theme.sh/
        // wallswitcher.py) has ever actually read it -- every apply path
        // always runs wallust regardless, so a theme pinning matugen
        // silently got wallust instead with zero indication anything was
        // ignored. Not implementing matugen here -- just making the
        // mismatch loud instead of silent, via a real notification
        // (Toaster.qml's toast() is a dead no-op stub left over from an
        // earlier unfinished pass, not what real toasts render through).
        if (engineName && engineName !== "wallust")
            Quickshell.execDetached(["notify-send", "-u", "low", "Aphotic", `theme pins engine '${engineName}', but only wallust is wired up — using wallust`]);

        awwwProc.exec(["awww", "img", path, "--transition-type", "wipe", "--transition-angle", "30", "--transition-step", "90"]);
        cpProc.exec(["cp", path, root.path]);

        let wallustCmd;
        if (colorscheme) {
            wallustCmd = ["wallust", "cs", colorscheme, "--format", "pywal"];
        } else {
            wallustCmd = ["wallust", "run", path];
            if (backend)
                wallustCmd.push("-b", backend);
            if (palette)
                wallustCmd.push("-p", palette);
            if (style)
                wallustCmd.push("-S", style);
        }
        wallustProc.taggedGeneration = root._generation;
        wallustProc.exec(wallustCmd);

        // Folder-icon accent pin -- see cmd_theme.sh's _aphotic_theme_apply
        // for why this needs sudo and only no-ops silently (same class of
        // best-effort call as sddm sync below) rather than blocking.
        if (papirusColor)
            Quickshell.execDetached(["sudo", "-n", "papirus-folders", "-C", papirusColor, "--theme", "Papirus-Dark", "-u"]);

        // Theme's own icon/cursor/gtk-theme pin (theme.toml's [icons]/
        // [gtk] tables) -- only applies while the user hasn't manually
        // picked one in Personalization (see Settings.qml's *UserSet
        // properties). Routed through Settings' own setters rather than
        // gsettings/sed calls here directly, so onXChanged's existing
        // _applyX() chain fires for free -- no duplicate apply logic.
        if (iconTheme && !Settings.iconThemeUserSet)
            Settings.iconTheme = iconTheme;
        if (cursorTheme && !Settings.cursorThemeUserSet)
            Settings.cursorTheme = cursorTheme;
        if (gtkTheme && !Settings.gtkThemeUserSet)
            Settings.gtkTheme = gtkTheme;

        // Best-effort — see cmd_sddm.sh; no-ops without passwordless sudo.
        Quickshell.execDetached(["aphotic", "sddm", "sync"]);
    }

    Process {
        id: awwwProc
    }

    Process {
        id: cpProc
    }

    // Only the theme-hook run (and, transitively, anything reading
    // palette.json) needs to wait for wallust to actually finish -- that
    // used to be `&&`-chained into one shell command specifically because
    // execDetached has no completion signal at all. A real Process does,
    // so this now runs off onExited instead, with the generation tag
    // guarding against a stale (superseded-and-killed) run's onExited
    // firing after a newer pick's process object has already moved on --
    // if _generation has advanced past what this run was tagged with,
    // a later exec() already preempted it and that later run's own
    // onExited will fire the hooks once *it* actually finishes.
    Process {
        id: wallustProc

        property int taggedGeneration: 0

        onExited: exitCode => {
            if (wallustProc.taggedGeneration !== root._generation)
                return;
            if (exitCode === 0)
                Quickshell.execDetached(["aphotic", "plugin", "run-theme-hooks"]);
        }
    }
}
