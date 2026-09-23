// Wallpaper.qml
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.config
import qs.components
import qs.services

Item {
    id: root

    property string source: Wallpapers.current
    property Image current: one
    property bool completed
    property size _nativeSize: Qt.size(0, 0)
    property string _probeSource: ""

    onSourceChanged: {
        if (!source)
            current = null;
        else
            root._probe();
    }

    Component.onCompleted: {
        if (source)
            Qt.callLater(root._probe);
        completed = true;
    }

    // Qt upscales to sourceSize as readily as it downscales, so the cap
    // needs the file's real size first. A header read is cheap; a failed
    // one leaves the size unknown and the screen cap applies.
    function _probe(): void {
        // Startup reaches here twice for one source. A second exec kills the
        // first run, and acting on that empty result loaded an upscaled
        // texture whose peak the driver never gave back.
        if (sizeProc.running && root._probeSource === root.source)
            return;
        root._probeSource = root.source;
        sizeProc.exec(["python3", "-c", "import sys\nfrom PIL import Image\nprint(*Image.open(sys.argv[1]).size)", root.source.replace(/^file:\/\//, "").replace(/\?.*$/, "")]);
    }

    function _advance(): void {
        if (root.current === one)
            two.update();
        else
            one.update();
    }

    // Decode at screen size only when the file is larger than the screen
    // needs; a smaller file decodes at its own size and the GPU scales it.
    function _capFor(native: size): var {
        const sw = Math.ceil(root.width * Screen.devicePixelRatio);
        const sh = Math.ceil(root.height * Screen.devicePixelRatio);
        if (sw <= 0 || sh <= 0)
            return undefined;
        if (native.width > 0 && native.height > 0 && Math.max(sw / native.width, sh / native.height) >= 1)
            return undefined;
        return Qt.size(sw, sh);
    }

    Process {
        id: sizeProc
        property string out: ""
        stdout: StdioCollector {
            onStreamFinished: sizeProc.out = text
        }
        // A run killed by a newer probe exits abnormally; only a finished
        // run advances the crossfade.
        onExited: (exitCode, exitStatus) => {
            if (exitStatus !== 0 || root._probeSource !== root.source)
                return;
            const dims = exitCode === 0 ? sizeProc.out.trim().split(" ").map(Number) : [];
            root._nativeSize = dims.length === 2 && dims[0] > 0 ? Qt.size(dims[0], dims[1]) : Qt.size(0, 0);
            root._advance();
        }
    }

    Loader {
        asynchronous: true
        anchors.fill: parent

        active: root.completed && !root.source

        sourceComponent: StyledRect {
            color: Colours.palette.m3surfaceContainer

            Row {
                anchors.centerIn: parent
                spacing: Tokens.spacing.large

                MaterialIcon {
                    text: "sentiment_stressed"
                    color: Colours.palette.m3onSurfaceVariant
                    font.pointSize: Tokens.fontSize.extraLarge * 2
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: qsTr("No wallpaper set")
                        color: Colours.palette.m3onSurfaceVariant
                        font.pointSize: Tokens.fontSize.extraLarge
                        font.bold: true
                    }

                    StyledText {
                        text: qsTr("Pick one with SUPER+W")
                        color: Colours.palette.m3onSurfaceVariant
                        font.pointSize: Tokens.fontSize.normal
                    }
                }
            }
        }
    }

    Img {
        id: one
    }

    Img {
        id: two
    }

    component Img: Image {
        id: img

        function update(): void {
            if (path === root.source) {
                root.current = this;
                return;
            }
            img.cap = root._capFor(root._nativeSize);
            path = root.source;
        }

        property string path
        property var cap
        source: path
        cache: true
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        // Fixed when the image loads, so probing the next wallpaper never
        // reloads the one on screen. A 7680x4320 file is 127 MiB of VRAM
        // uncapped and 25 MiB capped at 3440x1440.
        sourceSize: img.cap

        anchors.fill: parent

        opacity: 0
        scale: 1

        onStatusChanged: {
            if (status === Image.Ready)
                root.current = this;
        }

        states: State {
            name: "visible"
            when: root.current === img

            PropertyChanges {
                img.opacity: 1
                img.scale: 1
            }
        }

        // The image that faded out drops its texture; only the visible
        // wallpaper stays resident.
        transitions: Transition {
            SequentialAnimation {
                Anim {
                    target: img
                    properties: "opacity,scale"
                }
                ScriptAction {
                    script: {
                        if (root.current !== img)
                            img.path = "";
                    }
                }
            }
        }
    }
}
