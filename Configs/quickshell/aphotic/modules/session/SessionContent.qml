pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

RowLayout {
    id: root

    required property var screenState
    property SurfaceReveal reveal: null

    spacing: Tokens.spacing.large

    // Lock still goes through the real, battle-tested swaylock here
    // (not our new Quickshell lock screen) -- deliberately not coupling
    // two brand-new experimental features together yet.
    SessionButton {
        reveal: root.reveal ? root.reveal.staggered(0) : 1
        icon: "lock"
        label: qsTr("Lock")
        command: ["swaylock"]
        onActivated: root.screenState.session = false

        Component.onCompleted: forceActiveFocus()
    }

    SessionButton {
        reveal: root.reveal ? root.reveal.staggered(1) : 1
        icon: "bedtime"
        label: qsTr("Suspend")
        command: ["systemctl", "suspend"]
        onActivated: root.screenState.session = false
    }

    SessionButton {
        reveal: root.reveal ? root.reveal.staggered(2) : 1
        icon: "logout"
        label: qsTr("Log out")
        command: ["hyprctl", "dispatch", "hl.dsp.exit()"]
        onActivated: root.screenState.session = false
    }

    SessionButton {
        reveal: root.reveal ? root.reveal.staggered(3) : 1
        icon: "ac_unit"
        label: qsTr("Hibernate")
        command: ["systemctl", "hibernate"]
        onActivated: root.screenState.session = false
    }

    SessionButton {
        reveal: root.reveal ? root.reveal.staggered(4) : 1
        icon: "restart_alt"
        label: qsTr("Reboot")
        command: ["systemctl", "reboot"]
        onActivated: root.screenState.session = false
    }

    SessionButton {
        reveal: root.reveal ? root.reveal.staggered(5) : 1
        icon: "power_settings_new"
        label: qsTr("Shut down")
        command: ["systemctl", "poweroff"]
        onActivated: root.screenState.session = false
    }
}
