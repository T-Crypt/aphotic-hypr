// EyedropperPicker.qml -- click-to-sample a single screen pixel via grim +
// Pillow, copies the hex to the clipboard and confirms with a notify-send
// toast carrying a generated swatch icon. No rendered chrome (just a
// crosshair cursor), so there's nothing to hide before grim shoots --
// unlike Picker.qml's selection overlay, which has to hide itself and wait
// for a ScreencopyView frame before capturing.
pragma ComponentBehavior: Bound

import qs.services
import Quickshell
import Quickshell.Io
import QtQuick

MouseArea {
    id: root

    required property var loader
    required property ShellScreen screen

    readonly property string _pixelScript: "import sys\nfrom PIL import Image\nshot, swatch = sys.argv[1], sys.argv[2]\nr, g, b = Image.open(shot).convert('RGB').getpixel((0, 0))\nImage.new('RGB', (64, 64), (r, g, b)).save(swatch)\nprint(f'{r:02x}{g:02x}{b:02x} {r} {g} {b}')\n"

    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.CrossCursor
    focus: true

    Keys.onEscapePressed: root.loader.active = false

    onClicked: mouse => {
        const gx = Math.round(root.screen.x + mouse.x);
        const gy = Math.round(root.screen.y + mouse.y);
        const ts = Date.now();
        captureProc.shotPath = `/tmp/aphotic-colorpicker-${ts}.png`;
        captureProc.swatchPath = `/tmp/aphotic-colorpicker-swatch-${ts}.png`;
        captureProc.command = ["grim", "-g", `${gx},${gy} 1x1`, captureProc.shotPath];
        captureProc.running = true;
        root.loader.active = false;
    }

    Process {
        id: captureProc

        property string shotPath
        property string swatchPath

        onExited: exitCode => {
            if (exitCode !== 0)
                return;
            readProc.swatchPath = captureProc.swatchPath;
            readProc.command = ["python3", "-c", root._pixelScript, captureProc.shotPath, captureProc.swatchPath];
            readProc.running = true;
        }
    }

    Process {
        id: readProc

        property string swatchPath

        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(" ");
                if (parts.length < 4)
                    return;
                const hex = `#${parts[0]}`;
                const rgb = `rgb(${parts[1]}, ${parts[2]}, ${parts[3]})`;
                Quickshell.execDetached(["wl-copy", hex]);
                Quickshell.execDetached(["notify-send", "-a", "aphotic", "-i", readProc.swatchPath, `Color picked: ${hex}`, rgb]);
            }
        }
    }
}
