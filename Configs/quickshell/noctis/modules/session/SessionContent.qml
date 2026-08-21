pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

RowLayout {
    id: root

    required property var screenState

    spacing: Tokens.spacing.large

    // Lock still goes through the real, battle-tested swaylock here
    // (not our new Quickshell lock screen) -- deliberately not coupling
    // two brand-new experimental features together yet.
    SessionButton {
        icon: "lock"
        label: qsTr("Lock")
        command: ["swaylock"]
        onActivated: root.screenState.session = false

        Component.onCompleted: forceActiveFocus()
    }

    SessionButton {
        icon: "bedtime"
        label: qsTr("Suspend")
        command: ["systemctl", "suspend"]
        onActivated: root.screenState.session = false
    }

    SessionButton {
        icon: "logout"
        label: qsTr("Log out")
        command: ["hyprctl", "dispatch", "hl.dsp.exit()"]
        onActivated: root.screenState.session = false
    }

    SessionButton {
        icon: "ac_unit"
        label: qsTr("Hibernate")
        command: ["systemctl", "hibernate"]
        onActivated: root.screenState.session = false
    }

    SessionButton {
        icon: "restart_alt"
        label: qsTr("Reboot")
        command: ["systemctl", "reboot"]
        onActivated: root.screenState.session = false
    }

    SessionButton {
        icon: "power_settings_new"
        label: qsTr("Shut down")
        command: ["systemctl", "poweroff"]
        onActivated: root.screenState.session = false
    }
}
