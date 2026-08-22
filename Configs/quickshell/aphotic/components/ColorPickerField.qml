import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.config
import qs.services

// Reusable accent-color picker: a swatch+chevron trigger that opens a
// popup with a row of common presets plus a full HSV wheel for anything
// else. `value` is a hex string; "" means "unset" when `allowUnset` is
// true, which every current caller relies on to mean "fall back to the
// theme default" without this component knowing anything about theming.
Item {
    id: root

    property string value: ""
    property bool allowUnset: true
    property color unsetPreviewColour: Colours.palette.m3primary
    property var presets: ["#4A5A52", "#669B04", "#3B82F6", "#EF4444", "#F59E0B", "#8B5CF6", "#EC4899", "#14B8A6"]

    implicitWidth: trigger.implicitWidth
    implicitHeight: trigger.implicitHeight

    function _toHex(c: color): string {
        function ch(v: real): string {
            const s = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16);
            return s.length < 2 ? "0" + s : s;
        }
        return "#" + ch(c.r) + ch(c.g) + ch(c.b);
    }

    StyledRect {
        id: trigger

        implicitWidth: 72
        implicitHeight: 32
        radius: Tokens.rounding.small
        color: Colours.tPalette.m3surfaceContainer

        RowLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.extraSmall
            spacing: Tokens.spacing.extraSmall

            Rectangle {
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                radius: 10
                color: root.value.length > 0 ? root.value : "transparent"
                border.width: root.value.length > 0 ? 0 : 2
                border.color: Colours.palette.m3onSurfaceVariant

                MaterialIcon {
                    anchors.centerIn: parent
                    visible: root.value.length === 0
                    text: "palette"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.builders.small.scale(0.7).build()
                }
            }

            MaterialIcon {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                text: "expand_more"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
            }
        }

        StateLayer {
            anchors.fill: parent
            radius: parent.radius
            onClicked: popup.visible ? popup.close() : popup.open()
        }

        Popup {
            id: popup

            y: trigger.height + Tokens.spacing.small
            padding: Tokens.padding.medium
            width: 224

            background: StyledRect {
                radius: Tokens.rounding.medium
                color: Colours.tPalette.m3surfaceContainer
                border.width: 1
                border.color: Colours.palette.m3outlineVariant
            }

            contentItem: ColumnLayout {
                spacing: Tokens.spacing.medium

                StyledText {
                    text: qsTr("Common")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.medium
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledRect {
                        visible: root.allowUnset
                        implicitWidth: 32
                        implicitHeight: 32
                        radius: Tokens.rounding.full
                        color: Colours.tPalette.m3surfaceContainerHigh
                        border.width: root.value.length === 0 ? 3 : 1
                        border.color: root.value.length === 0 ? Colours.palette.m3onSurface : Colours.palette.m3outlineVariant

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "palette"
                            color: Colours.palette.m3onSurfaceVariant
                            fontStyle: Tokens.font.icon.small
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.value = ""
                        }
                    }

                    Repeater {
                        model: root.presets

                        StyledRect {
                            id: swatch

                            required property string modelData

                            implicitWidth: 32
                            implicitHeight: 32
                            radius: Tokens.rounding.full
                            color: swatch.modelData
                            border.width: root.value.toLowerCase() === swatch.modelData.toLowerCase() ? 3 : 1
                            border.color: root.value.toLowerCase() === swatch.modelData.toLowerCase() ? Colours.palette.m3onSurface : Colours.palette.m3outlineVariant

                            MaterialIcon {
                                anchors.centerIn: parent
                                visible: root.value.toLowerCase() === swatch.modelData.toLowerCase()
                                text: "check"
                                color: Colours.contrastOn(swatch.modelData)
                                fontStyle: Tokens.font.icon.small
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.value = swatch.modelData
                            }
                        }
                    }
                }

                StyledText {
                    Layout.topMargin: Tokens.spacing.small
                    text: qsTr("Custom")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.medium
                }

                ColumnLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Tokens.spacing.small

                    ColorWheel {
                        id: wheel

                        Layout.alignment: Qt.AlignHCenter
                        value: brightnessTrack.fraction
                        onPicked: c => root.value = root._toHex(c)
                    }

                    Item {
                        id: brightnessTrack

                        readonly property real fraction: Math.min(1, Math.max(0, x_ / width))
                        property real x_: width

                        Layout.fillWidth: true
                        implicitHeight: 14

                        StyledRect {
                            anchors.fill: parent
                            radius: height / 2
                            color: Colours.tPalette.m3surfaceContainerHigh
                        }

                        StyledRect {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            radius: parent.height / 2
                            width: Math.max(height, parent.width * brightnessTrack.fraction)
                            color: Qt.hsva(wheel.hue, wheel.saturation, 1, 1)
                        }

                        MouseArea {
                            anchors.fill: parent

                            function setFromX(x: real): void {
                                brightnessTrack.x_ = x;
                                root.value = root._toHex(Qt.hsva(wheel.hue, wheel.saturation, brightnessTrack.fraction, 1));
                            }

                            onPressed: mouse => setFromX(mouse.x)
                            onPositionChanged: mouse => {
                                if (pressed)
                                    setFromX(mouse.x);
                            }
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.value.length > 0 ? root.value : qsTr("theme default")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.mono.small
                    }
                }
            }
        }
    }
}
