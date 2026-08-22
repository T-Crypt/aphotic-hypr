import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

SettingsRow {
    id: root

    required property var presets // [{ value, label }]
    required property var value

    signal selected(value: var)

    RowLayout {
        spacing: Tokens.spacing.small

        Repeater {
            model: root.presets

            StyledRect {
                id: presetPill

                required property var modelData
                readonly property bool active: presetPill.modelData.value === root.value

                Layout.preferredHeight: 28
                Layout.preferredWidth: presetLabel.implicitWidth + Tokens.padding.medium * 2
                radius: Tokens.rounding.full
                color: presetPill.active ? Colours.palette.m3primary : Colours.layer(Colours.tPalette.m3surfaceContainer, 2)

                Behavior on color {
                    CAnim {}
                }

                StyledText {
                    id: presetLabel
                    anchors.centerIn: parent
                    text: presetPill.modelData.label
                    color: presetPill.active ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.selected(presetPill.modelData.value)
                }
            }
        }
    }
}
