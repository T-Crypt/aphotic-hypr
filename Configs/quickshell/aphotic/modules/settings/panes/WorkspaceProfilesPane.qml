pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.config
import qs.components
import qs.services

// Named, one-key launch groups -- a deliberately honest scope-down of
// "session restore". Hyprland/X11 apps don't expose any way to snapshot
// their live internal state, so a profile is just a user-authored list of
// {command, workspace} pairs replayed via `hyprctl dispatch exec
// [workspace N] <command>`, not a capture of whatever happened to be open.
ColumnLayout {
    id: root

    property int newEntryWorkspace: 1
    property var newProfileEntries: []

    function addEntry(): void {
        const cmd = commandInput.text.trim();
        if (cmd.length === 0)
            return;
        root.newProfileEntries = [...root.newProfileEntries, { command: cmd, workspace: root.newEntryWorkspace }];
        commandInput.text = "";
        root.newEntryWorkspace = 1;
    }

    function removeEntry(index: int): void {
        root.newProfileEntries = root.newProfileEntries.filter((_, i) => i !== index);
    }

    function saveProfile(): void {
        const name = nameInput.text.trim();
        if (name.length === 0 || root.newProfileEntries.length === 0)
            return;
        Settings.workspaceProfiles = [...Settings.workspaceProfiles, { name: name, entries: root.newProfileEntries }];
        nameInput.text = "";
        root.newProfileEntries = [];
        root.newEntryWorkspace = 1;
    }

    function launchProfile(profile: var): void {
        for (const entry of profile.entries)
            launchProc.exec(["hyprctl", "dispatch", "exec", `[workspace ${entry.workspace}] ${entry.command}`]);
    }

    function deleteProfile(index: int): void {
        Settings.workspaceProfiles = Settings.workspaceProfiles.filter((_, i) => i !== index);
    }

    Process {
        id: launchProc
    }

    spacing: Tokens.spacing.largeIncreased

    StyledText {
        text: qsTr("Workspace Profiles")
        font: Tokens.font.title.large
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("A profile is a saved list of apps and the workspace each one should open on -- one click launches all of them via hyprctl. This replays a fixed list, it doesn't snapshot whatever windows happened to be open.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    StyledText {
        visible: Settings.workspaceProfiles.length === 0
        text: qsTr("No profiles yet -- build one below.")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.body.small
    }

    SettingsGroup {
        Layout.fillWidth: true
        visible: Settings.workspaceProfiles.length > 0

        Repeater {
            model: Settings.workspaceProfiles

            SettingsRow {
                id: profileRow

                required property var modelData
                required property int index

                icon: "workspaces"
                label: profileRow.modelData.name
                description: qsTr("%1 app(s)").arg(profileRow.modelData.entries.length)

                RowLayout {
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: "play_arrow"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small

                        StateLayer {
                            anchors.fill: parent
                            anchors.margins: -Tokens.padding.small
                            radius: Tokens.rounding.full
                            onClicked: root.launchProfile(profileRow.modelData)
                        }
                    }

                    MaterialIcon {
                        text: "delete"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small

                        StateLayer {
                            anchors.fill: parent
                            anchors.margins: -Tokens.padding.small
                            radius: Tokens.rounding.full
                            onClicked: root.deleteProfile(profileRow.index)
                        }
                    }
                }
            }
        }
    }

    StyledText {
        Layout.topMargin: Tokens.spacing.small
        text: qsTr("New profile")
        color: Colours.palette.m3onSurfaceVariant
        font: Tokens.font.label.medium
    }

    SettingsGroup {
        Layout.fillWidth: true

        SettingsRow {
            icon: "edit"
            label: qsTr("Profile name")

            StyledRect {
                implicitWidth: 220
                implicitHeight: 32
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerHigh

                TextInput {
                    id: nameInput
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurface
                    clip: true

                    StyledText {
                        visible: nameInput.text.length === 0
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: qsTr("Coding session")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                }
            }
        }

        SettingsRow {
            icon: "terminal"
            label: qsTr("Command")
            description: qsTr("Launched with hyprctl dispatch exec")

            StyledRect {
                implicitWidth: 220
                implicitHeight: 32
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainerHigh

                TextInput {
                    id: commandInput
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    font: Tokens.font.label.small
                    color: Colours.palette.m3onSurface
                    clip: true

                    StyledText {
                        visible: commandInput.text.length === 0
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: qsTr("kitty")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                }
            }
        }

        SettingsRow {
            icon: "dashboard"
            label: qsTr("Workspace")
            description: qsTr("Opens on workspace %1").arg(root.newEntryWorkspace)

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
                        onClicked: root.newEntryWorkspace = Math.max(1, root.newEntryWorkspace - 1)
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
                        onClicked: root.newEntryWorkspace = Math.min(20, root.newEntryWorkspace + 1)
                    }
                }
            }
        }
    }

    RowLayout {
        spacing: Tokens.spacing.medium

        StyledRect {
            implicitWidth: addEntryLabel.implicitWidth + Tokens.padding.large * 2
            implicitHeight: 36
            radius: Tokens.rounding.medium
            color: Colours.tPalette.m3surfaceContainer

            StyledText {
                id: addEntryLabel
                anchors.centerIn: parent
                text: qsTr("Add entry")
                color: Colours.palette.m3onSurface
                font: Tokens.font.body.medium
            }

            StateLayer {
                anchors.fill: parent
                radius: parent.radius
                onClicked: root.addEntry()
            }
        }
    }

    SettingsGroup {
        Layout.fillWidth: true
        visible: root.newProfileEntries.length > 0

        Repeater {
            model: root.newProfileEntries

            SettingsRow {
                id: entryRow

                required property var modelData
                required property int index

                icon: "terminal"
                label: entryRow.modelData.command
                description: qsTr("Workspace %1").arg(entryRow.modelData.workspace)

                MaterialIcon {
                    text: "close"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small

                    StateLayer {
                        anchors.fill: parent
                        anchors.margins: -Tokens.padding.small
                        radius: Tokens.rounding.full
                        onClicked: root.removeEntry(entryRow.index)
                    }
                }
            }
        }
    }

    RowLayout {
        Layout.topMargin: Tokens.spacing.medium
        Layout.bottomMargin: Tokens.spacing.medium
        spacing: Tokens.spacing.medium

        StyledRect {
            readonly property bool canSave: nameInput.text.trim().length > 0 && root.newProfileEntries.length > 0

            implicitWidth: saveLabel.implicitWidth + Tokens.padding.large * 2
            implicitHeight: 40
            radius: Tokens.rounding.medium
            color: canSave ? Colours.palette.m3primary : Colours.tPalette.m3surfaceContainer

            StyledText {
                id: saveLabel
                anchors.centerIn: parent
                text: qsTr("Save profile")
                color: parent.canSave ? Colours.contrastOn(Colours.palette.m3primary) : Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.medium
            }

            StateLayer {
                anchors.fill: parent
                radius: parent.radius
                disabled: !parent.canSave
                onClicked: root.saveProfile()
            }
        }
    }
}
