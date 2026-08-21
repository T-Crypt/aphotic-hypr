pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Wayland
import qs.config
import qs.services

WlSessionLockSurface {
    id: root

    required property WlSessionLock lock
    required property var pam

    color: Colours.palette.m3surfaceContainer

    LockContent {
        anchors.centerIn: parent
        lock: root.lock
        pam: root.pam
    }
}
