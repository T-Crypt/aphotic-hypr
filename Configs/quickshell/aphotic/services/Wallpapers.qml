pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

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
    function setWallpaper(path: string, backend: var, palette: var, colorscheme: var, style: var, papirusColor: var): void {
        Quickshell.execDetached(["awww", "img", path, "--transition-type", "wipe", "--transition-angle", "30", "--transition-step", "90"]);
        Quickshell.execDetached(["cp", path, root.path]);

        if (colorscheme) {
            Quickshell.execDetached(["wallust", "cs", colorscheme, "--format", "pywal"]);
        } else {
            const cmd = ["wallust", "run", path];
            if (backend)
                cmd.push("-b", backend);
            if (palette)
                cmd.push("-p", palette);
            if (style)
                cmd.push("-S", style);
            Quickshell.execDetached(cmd);
        }

        // Folder-icon accent pin -- see cmd_theme.sh's _aphotic_theme_apply
        // for why this needs sudo and only no-ops silently (same class of
        // best-effort call as sddm sync below) rather than blocking.
        if (papirusColor)
            Quickshell.execDetached(["sudo", "-n", "papirus-folders", "-C", papirusColor, "--theme", "Papirus-Dark", "-u"]);

        // Best-effort — see cmd_sddm.sh; no-ops without passwordless sudo.
        Quickshell.execDetached(["aphotic", "sddm", "sync"]);
    }
}
