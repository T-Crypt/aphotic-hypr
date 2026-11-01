pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services
import qs.services.ai

// Which coding agents the shell shows, and in what order. The order is the
// whole setting: the first shown harness is the default the bar selects
// and the launcher opens projects in, so there is no separate default.
ColumnLayout {
    id: root

    spacing: Tokens.spacing.extraSmall

    function entries(): var {
        return Harnesses.ordered.map(o => ({ id: o.descriptor.id, enabled: o.enabled }));
    }

    function setEnabled(index: int, value: bool): void {
        Harnesses.setOrder(root.entries().map((e, i) => i === index ? { id: e.id, enabled: value } : e));
    }

    function move(from: int, to: int): void {
        const next = root.entries();
        if (to < 0 || to >= next.length || from === to)
            return;
        next.splice(to, 0, next.splice(from, 1)[0]);
        Harnesses.setOrder(next);
    }

    function sourceText(source: string): string {
        if (source.startsWith("plugin:"))
            return qsTr("From the %1 plugin").arg(source.slice(7));
        if (source.startsWith("drop-in:"))
            return qsTr("Drop-in %1").arg(source.slice(8));
        return source;
    }

    StyledText {
        Layout.leftMargin: Tokens.padding.small
        text: qsTr("Coding agents")
        color: Colours.inkMuted
        font: Tokens.font.label.medium
    }

    StyledText {
        Layout.fillWidth: true
        Layout.leftMargin: Tokens.padding.small
        text: Harnesses.ordered.length > 0
            ? qsTr("The first one shown is the default: the bar selects it and projects open in it.")
            : qsTr("No coding agent is set up. Enable a hook plugin, or add a file under ~/.config/aphotic/harnesses/.")
        wrapMode: Text.WordWrap
        color: Colours.inkMuted
        font: Tokens.font.label.small
    }

    SettingsGroup {
        Layout.fillWidth: true
        visible: Harnesses.ordered.length > 0

        Repeater {
            model: Harnesses.ordered

            SettingsToggleRow {
                id: harnessRow

                required property var modelData
                required property int index

                readonly property bool isDefault: Harnesses.visible.length > 0
                    && Harnesses.visible[0].id === harnessRow.modelData.descriptor.id

                icon: harnessRow.modelData.descriptor.icon
                label: harnessRow.modelData.descriptor.label
                description: !harnessRow.modelData.enabled ? qsTr("Hidden")
                    : harnessRow.isDefault ? qsTr("Default")
                    : root.sourceText(harnessRow.modelData.descriptor.source)
                checked: harnessRow.modelData.enabled
                opacity: harnessRow.modelData.enabled ? 1 : 0.6
                onToggled: state => root.setEnabled(harnessRow.index, state)

                Repeater {
                    model: [
                        { glyph: "↑", to: harnessRow.index - 1, tip: qsTr("Move up") },
                        { glyph: "↓", to: harnessRow.index + 1, tip: qsTr("Move down") }
                    ]

                    Item {
                        id: moveButton

                        required property var modelData

                        implicitWidth: 28
                        implicitHeight: 28
                        enabled: moveButton.modelData.to >= 0 && moveButton.modelData.to < Harnesses.ordered.length
                        opacity: moveButton.enabled ? 1 : 0.3

                        StyledText {
                            anchors.centerIn: parent
                            text: moveButton.modelData.glyph
                            color: Colours.inkMuted
                            font: Tokens.font.label.medium
                        }

                        Interact {
                            anchors.fill: parent
                            radius: Tokens.rounding.full
                            onClicked: root.move(harnessRow.index, moveButton.modelData.to)
                        }
                    }
                }
            }
        }
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsRow {
            searchId: "aiHarnesses"
            icon: "refresh"
            label: qsTr("Rescan agents")
            description: qsTr("Reads hook plugins and drop-in files again. Edits to a drop-in show up here after a rescan.")
            activatable: true
            onActivated: Quickshell.execDetached(["aphotic", "agent", "harnesses"])
        }
    }
}
