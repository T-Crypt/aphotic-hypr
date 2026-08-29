import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    spacing: Tokens.spacing.largeIncreased

    // This pane has only one setting -- top-anchoring it the way every
    // other (denser) pane does leaves a large dead zone below and reads
    // as misplaced rather than deliberate. Symmetric fillHeight spacers
    // center the title+group block in whatever height SettingsPanel.qml
    // hands the pane, without touching the top-anchored pattern every
    // other pane still relies on.
    Item {
        Layout.fillHeight: true
    }

    StyledText {
        text: qsTr("Launcher")
        font: Tokens.font.title.large
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsPresetRow {
            icon: "grid_view"
            label: qsTr("Results style")
            description: qsTr("App-search results only — clipboard, emoji, windows, themes, and projects always show as a list")
            presets: [{
                    value: "list",
                    label: qsTr("List")
                }, {
                    value: "grid",
                    label: qsTr("Grid")
                }]
            value: Settings.launcherStyle
            onSelected: value => Settings.launcherStyle = value
        }
    }

    Item {
        Layout.fillHeight: true
    }
}
