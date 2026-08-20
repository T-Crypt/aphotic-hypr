import QtQuick
import qs.components
import qs.config
import qs.services

Item {
    id: root

    required property var screen
    required property int barWidth
    property bool hasCurrent: false
    property string currentName: ""
    property real currentCenter: 0
    property var currentTrayItem: null

    readonly property string category: currentName.startsWith("traymenu") ? "tray" : currentName

    StyledRect {
        id: flyout

        visible: root.hasCurrent && loader.item
        x: root.barWidth + Tokens.spacing.small
        y: Math.max(0, root.currentCenter - height / 2)
        width: loader.item ? loader.item.implicitWidth + Tokens.padding.medium * 2 : 0
        height: loader.item ? loader.item.implicitHeight + Tokens.padding.medium * 2 : 0
        radius: Tokens.rounding.medium
        color: Colours.palette.m3surfaceContainerHigh

        Loader {
            id: loader

            anchors.centerIn: parent
            active: root.hasCurrent

            sourceComponent: {
                switch (root.category) {
                case "audio":
                    return audioComp;
                case "network":
                    return networkComp;
                case "bluetooth":
                    return bluetoothComp;
                case "battery":
                    return batteryComp;
                case "activewindow":
                    return windowComp;
                case "kblayout":
                    return kbLayoutComp;
                case "lockstatus":
                    return lockStatusComp;
                case "tray":
                    return trayComp;
                default:
                    return null;
                }
            }
        }
    }

    Component {
        id: audioComp
        AudioPopout {}
    }
    Component {
        id: networkComp
        NetworkPopout {}
    }
    Component {
        id: bluetoothComp
        BluetoothPopout {}
    }
    Component {
        id: batteryComp
        BatteryPopout {}
    }
    Component {
        id: windowComp
        WindowPopout {}
    }
    Component {
        id: kbLayoutComp
        KbLayoutPopout {}
    }
    Component {
        id: lockStatusComp
        LockStatusPopout {}
    }
    Component {
        id: trayComp
        TrayPopout {
            trayItem: root.currentTrayItem
        }
    }
}
