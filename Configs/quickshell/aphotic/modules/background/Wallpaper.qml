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
            Qt.callLater(() => {
                one.update();
                completed = true;
            });
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
                        text: qsTr("Pick one with SUPER+SHIFT+W")
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

        transitions: Transition {
            Anim {
                target: img
                properties: "opacity,scale"
            }
        }
    }
}
