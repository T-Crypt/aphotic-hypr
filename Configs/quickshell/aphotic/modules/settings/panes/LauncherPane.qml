import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

ColumnLayout {
    id: root

    spacing: Tokens.spacing.largeIncreased

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
}
