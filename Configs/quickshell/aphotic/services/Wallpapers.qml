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

    // Bumped on every setWallpaper() call, and stamped onto engineProc
    // right before each exec() -- see the onExited guard below for why.
    property int _generation: 0

    // theme.toml's [palette] table for the run currently in flight, or
    // null when this theme doesn't opt into clamping -- see _startClamp.
    property var _pendingClamp: null

    // engineName picks which colour engine renders the palette; the rest
    // of these are that engine's own knobs (scheme/contrast are matugen's,
    // backend/palette/colorscheme are wallust's) -- see
    // themes/THEME_SPEC.md.
    //
    // backend/palette let a theme's theme.toml pin a specific wallust
    // engine mode for wallpapers that need something other than
    // Configs/wallust/wallust.toml's own defaults --
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
    // paletteClamp is theme.toml's [palette] table, or null/undefined when
    // the theme doesn't opt in: { theme, anchor, maxHueShift, maxSatShift,
    // maxLightShift }. Passed as one object rather than five more
    // positional arguments purely because this signature is already long.
    function setWallpaper(path: string, backend: var, palette: var, colorscheme: var, style: var, papirusColor: var, iconTheme: var, cursorTheme: var, gtkTheme: var, engineName: var, scheme: var, contrast: var, paletteClamp: var): void {
        root._generation++;

        // Toaster.qml's toast() is a dead no-op stub left over from an
        // earlier unfinished pass, not what real toasts render through.
        if (engineName && engineName !== "wallust" && engineName !== "matugen")
            Quickshell.execDetached(["notify-send", "-u", "low", "Aphotic", `theme pins unknown engine '${engineName}' — using wallust`]);

        awwwProc.exec(["awww", "img", path, "--transition-type", "wipe", "--transition-angle", "30", "--transition-step", "90"]);
        cpProc.exec(["cp", path, root.path]);

        // Only the image-derived wallust path has a raw palette to clamp:
        // [engine].colorscheme is already a fixed palette, and matugen
        // would need its seed colour clamped pre-generation instead (see
        // themes/THEME_SPEC.md).
        root._pendingClamp = null;
        if (paletteClamp && paletteClamp.anchor && engineName !== "matugen") {
            if (colorscheme)
                Quickshell.execDetached(["notify-send", "-u", "low", "Aphotic", "theme sets both [engine].colorscheme and [palette].anchor — using the fixed colorscheme"]);
            else
                root._pendingClamp = paletteClamp;
        }

        let engineCmd;
        if (engineName === "matugen") {
            // --prefer is not optional: matugen refuses to choose between
            // an image's candidate source colours without a terminal to
            // prompt on.
            engineCmd = ["matugen", "image", path, "--prefer", "saturation", "-q"];
            if (scheme)
                engineCmd.push("-t", scheme);
            if (style)
                engineCmd.push("-m", style);
            if (contrast)
                engineCmd.push("--contrast", contrast);
        } else if (colorscheme) {
            engineCmd = ["wallust", "cs", colorscheme, "--format", "pywal"];
        } else {
            engineCmd = ["wallust", "run", path];
            if (backend)
                engineCmd.push("-b", backend);
            if (palette)
                engineCmd.push("-p", palette);
            if (style)
                engineCmd.push("-S", style);
        }
        engineProc.taggedGeneration = root._generation;
        engineProc.exec(engineCmd);

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
    // palette.json) needs to wait for the colour engine to actually
    // finish -- that
    // used to be `&&`-chained into one shell command specifically because
    // execDetached has no completion signal at all. A real Process does,
    // so this now runs off onExited instead, with the generation tag
    // guarding against a stale (superseded-and-killed) run's onExited
    // firing after a newer pick's process object has already moved on --
    // if _generation has advanced past what this run was tagged with,
    // a later exec() already preempted it and that later run's own
    // onExited will fire the hooks once *it* actually finishes.
    Process {
        id: engineProc

        property int taggedGeneration: 0

        onExited: exitCode => {
            if (engineProc.taggedGeneration !== root._generation)
                return;
            if (exitCode !== 0)
                return;
            if (root._pendingClamp)
                root._startClamp(root._pendingClamp);
            else
                Quickshell.execDetached(["aphotic", "plugin", "run-theme-hooks"]);
        }
    }

    // Palette clamp (theme.toml's [palette] table -- see
    // themes/THEME_SPEC.md). Mirrors cmd_theme.sh's
    // _aphotic_theme_clamp_palette: rewrite the raw image-derived palette
    // wallust just cached into a clamped colorscheme file, then re-run
    // every template from it with `wallust cs`, the same path
    // [engine].colorscheme already takes.
    //
    // Two more Processes chained off engineProc's onExited rather than one
    // `sh -c` line, for the same reason engineProc itself exists: each step
    // carries the generation tag, so a theme picked mid-clamp preempts this
    // one instead of racing it into the shared template output files. The
    // theme hooks stay the last link in the chain either way -- a failed
    // clamp leaves the unclamped palette applied, which is still a
    // complete, valid palette for the hooks to read.
    function _startClamp(clamp: var): void {
        const home = Quickshell.env("HOME");
        // The CLI's lib/ lives in the dots checkout, not under ~/.local
        // (install.sh only symlinks ~/.local/bin/aphotic) -- same env-var-
        // with-default resolution AboutPane.qml uses to read VERSION.
        const dotsDir = Quickshell.env("APHOTIC_DOTS_DIR") || `${home}/Aphotic-Hypr`;
        const cmd = [
            "python3", `${dotsDir}/Configs/.local/lib/aphotic/palette_clamp.py`,
            `${home}/.cache/wal/colors.json`,
            `${home}/.config/wallust/colorschemes/${clamp.anchor}.json`,
            "-o", `${home}/.config/wallust/colorschemes/${clamp.theme}-live.json`
        ];
        if (clamp.maxHueShift)
            cmd.push("--max-hue-shift", `${clamp.maxHueShift}`);
        if (clamp.maxSatShift)
            cmd.push("--max-sat-shift", `${clamp.maxSatShift}`);
        if (clamp.maxLightShift)
            cmd.push("--max-light-shift", `${clamp.maxLightShift}`);

        clampProc.liveScheme = `${clamp.theme}-live`;
        clampProc.taggedGeneration = root._generation;
        clampProc.exec(cmd);
    }

    Process {
        id: clampProc

        property int taggedGeneration: 0
        property string liveScheme: ""

        onExited: exitCode => {
            if (clampProc.taggedGeneration !== root._generation)
                return;
            if (exitCode !== 0) {
                Quickshell.execDetached(["aphotic", "plugin", "run-theme-hooks"]);
                return;
            }
            csProc.taggedGeneration = root._generation;
            csProc.exec(["wallust", "cs", clampProc.liveScheme, "--format", "pywal"]);
        }
    }

    Process {
        id: csProc

        property int taggedGeneration: 0

        onExited: {
            if (csProc.taggedGeneration !== root._generation)
                return;
            Quickshell.execDetached(["aphotic", "plugin", "run-theme-hooks"]);
        }
    }
}
