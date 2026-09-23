// Wallpaper.qml
pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.components
import qs.services

Item {
    id: root

    property string source: Wallpapers.current
    property Image current: one
    property bool completed

    onSourceChanged: {
        if (!source)
            current = null;
        else if (current === one)
            two.update();
        else
            one.update();
    }

    Component.onCompleted: {
        if (source)
            Qt.callLater(() => one.update());
        completed = true;
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
            if (path === root.source)
                root.current = this;
            else
                path = root.source;
        }

        property string path
        source: path
        cache: true
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        // Decode at screen size, not file size: a bundled 7680x4320 wallpaper
        // is 127 MiB of VRAM per image uncapped and 25 MiB capped, and there
        // are two images per screen for the crossfade.
        sourceSize: root.width > 0 && root.height > 0
            ? Qt.size(Math.ceil(root.width * Screen.devicePixelRatio), Math.ceil(root.height * Screen.devicePixelRatio))
            : undefined

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
