import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services

SettingsRow {
    id: root

    // `enabled` is optional and defaults true. A preset that sets it
    // false is drawn dimmed and does not take a click: the row still says
    // the choice exists without pretending it is ready.
    required property var presets // [{ value, label, enabled }]
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
                readonly property bool selectable: presetPill.modelData.enabled !== false

                Layout.preferredHeight: 28
                Layout.preferredWidth: presetLabel.implicitWidth + Tokens.padding.medium * 2
                radius: Tokens.rounding.full
                opacity: presetPill.selectable ? 1 : 0.45
                color: Settings.barSignal ? (presetPill.active ? Colours.signalStyle.raised : "transparent") : (presetPill.active ? Colours.palette.m3primary : Colours.layer(Colours.tPalette.m3surfaceContainer, 2))
                border.width: Settings.barSignal ? 1 : 0
                border.color: Settings.barSignal ? (presetPill.active ? Colours.signalStyle.accentLine : Colours.signalStyle.hairline) : "transparent"

                Behavior on color {
                    CAnim {}
                }

                StyledText {
                    id: presetLabel
                    anchors.centerIn: parent
                    text: presetPill.modelData.label
                    color: Settings.barSignal ? (presetPill.active ? Colours.palette.m3onSurface : Colours.palette.m3onSurfaceVariant) : (presetPill.active ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant)
                    font: Tokens.font.label.small
                }

                StateLayer {
                    anchors.fill: parent
                    radius: parent.radius
                    visible: presetPill.selectable
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: presetPill.selectable
                    cursorShape: presetPill.selectable ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.selected(presetPill.modelData.value)
                }
            }
        }
    }
}
