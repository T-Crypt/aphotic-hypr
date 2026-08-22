pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    readonly property var accentPresets: ["", "#4A5A52", "#669B04", "#3B82F6", "#EF4444", "#F59E0B", "#8B5CF6", "#EC4899", "#14B8A6"]

    property var cursorThemes: []
    property var iconThemes: []

    spacing: Tokens.spacing.largeIncreased

    Component.onCompleted: {
        cursorThemeProc.running = true;
        iconThemeProc.running = true;
    }

    // Cursor themes are marked by a `cursors/` subdirectory, not
    // index.theme (most cursor-only themes don't have one).
    Process {
        id: cursorThemeProc
        command: ["sh", "-c", `for d in /usr/share/icons/*/cursors ${Quickshell.env("HOME")}/.local/share/icons/*/cursors; do [ -d "$d" ] && basename "$(dirname "$d")"; done 2>/dev/null | sort -u`]
        stdout: StdioCollector {
            onStreamFinished: root.cursorThemes = text.split("\n").filter(s => s.length > 0)
        }
    }

    Process {
        id: iconThemeProc
        command: ["sh", "-c", `for f in /usr/share/icons/*/index.theme ${Quickshell.env("HOME")}/.local/share/icons/*/index.theme; do [ -f "$f" ] && basename "$(dirname "$f")"; done 2>/dev/null | sort -u`]
        stdout: StdioCollector {
            onStreamFinished: root.iconThemes = text.split("\n").filter(s => s.length > 0)
        }
    }

    StyledText {
        text: qsTr("Personalization")
        font: Tokens.font.title.large
    }

    StyledText {
        text: qsTr("Accent color")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    Flow {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        Repeater {
            model: ScriptModel {
                values: root.accentPresets
            }

            StyledRect {
                id: swatch

                required property string modelData
                readonly property bool isThemeDefault: swatch.modelData.length === 0
                readonly property bool active: Settings.accentColorOverride === swatch.modelData

                implicitWidth: 40
                implicitHeight: 40
                radius: Tokens.rounding.full
                color: swatch.isThemeDefault ? Colours.tPalette.m3surfaceContainer : swatch.modelData
                border.width: swatch.active ? 3 : 1
                border.color: swatch.active ? Colours.palette.m3onSurface : Colours.palette.m3outlineVariant

                MaterialIcon {
                    anchors.centerIn: parent
                    visible: swatch.isThemeDefault
                    text: "palette"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }

                MaterialIcon {
                    anchors.centerIn: parent
                    visible: swatch.active && !swatch.isThemeDefault
                    text: "check"
                    color: Colours.contrastOn(swatch.color)
                    fontStyle: Tokens.font.icon.small
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    showHoverBackground: !swatch.active
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Settings.accentColorOverride = swatch.modelData
                }
            }
        }
    }

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: qsTr("Cursor")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    Flow {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small
        visible: root.cursorThemes.length > 0

        Repeater {
            model: ScriptModel {
                values: root.cursorThemes
            }

            NamePill {
                required property string modelData
                label: modelData
                active: Settings.cursorTheme === modelData
                onClicked: Settings.cursorTheme = modelData
            }
        }
    }

    StyledText {
        visible: root.cursorThemes.length === 0
        text: qsTr("No cursor themes found under ~/.local/share/icons or /usr/share/icons")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    SettingsGroup {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.small

        SettingsRow {
            icon: "photo_size_select_small"
            label: qsTr("Cursor size")
            description: qsTr("%1px").arg(Settings.cursorSize)

            RowLayout {
                spacing: Tokens.spacing.small

                MaterialIcon {
                    text: "remove"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small

                    StateLayer {
                        anchors.fill: parent
                        anchors.margins: -Tokens.padding.small
                        radius: Tokens.rounding.full
                        onClicked: Settings.cursorSize = Math.max(16, Settings.cursorSize - 4)
                    }
                }

                MaterialIcon {
                    text: "add"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small

                    StateLayer {
                        anchors.fill: parent
                        anchors.margins: -Tokens.padding.small
                        radius: Tokens.rounding.full
                        onClicked: Settings.cursorSize = Math.min(48, Settings.cursorSize + 4)
                    }
                }
            }
        }
    }

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: qsTr("Icons")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    Flow {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small
        visible: root.iconThemes.length > 0

        Repeater {
            model: ScriptModel {
                values: root.iconThemes
            }

            NamePill {
                required property string modelData
                label: modelData
                active: Settings.iconTheme === modelData
                onClicked: Settings.iconTheme = modelData
            }
        }
    }

    StyledText {
        visible: root.iconThemes.length === 0
        text: qsTr("No icon themes found under ~/.local/share/icons or /usr/share/icons")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    component NamePill: StyledRect {
        id: pill

        required property string label
        required property bool active

        signal clicked

        // Plain implicit size, not Layout.preferredWidth/Height -- this
        // sits inside a Flow (a plain positioner), not a Layout, where
        // Layout.* attached properties are silently inert.
        implicitHeight: 32
        implicitWidth: pillLabel.implicitWidth + Tokens.padding.large * 2
        radius: Tokens.rounding.full
        color: pill.active ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainer

        StyledText {
            id: pillLabel
            anchors.centerIn: parent
            elide: Text.ElideMiddle
            text: pill.label
            color: pill.active ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }

        StateLayer {
            anchors.fill: parent
            radius: parent.radius
            showHoverBackground: !pill.active
        }

        MouseArea {
            anchors.fill: parent
            onClicked: pill.clicked()
        }
    }
}
