pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services
import qs.utils
import qs.modules.bar.components.status

Item {
    id: root

    required property ScreenState screenState
    readonly property var echoLabels: ({lockStatus:qsTr("Lock"),audio:qsTr("Audio"),microphone:qsTr("Microphone"),kbLayout:qsTr("Keyboard layout"),network:qsTr("Network"),bluetooth:qsTr("Bluetooth"),vpn:qsTr("VPN"),battery:qsTr("Battery"),resources:qsTr("Resources"),hostInfo:qsTr("Host information"),networkSpeed:qsTr("Network speed"),pomodoro:qsTr("Focus timer"),dnd:qsTr("Do not disturb"),notifCenter:qsTr("Notifications")})

    property color colour: Colours.inkMuted

    readonly property int spacing: Tokens.spacing.medium / 2
    // Real gap between pills, not a divider line inside one continuous
    // background: pills read as distinct groups.
    readonly property int groupSpacing: Tokens.spacing.small

    // Bar.qml's checkPopout reads this for group-aware hit-testing: find
    // which pill's own bounds contain the hover position first, then the
    // nearest icon within just that pill. checkPopout computes its own
    // match from its own pointer sample (via BarHit.nearestAlong against
    // `pill.icons`) and must not read `pill.hoveredEntry` below -- on
    // first entry into a pill, the outer hover handler's sample can fire
    // before this pill's MouseArea has updated `hoveredEntry` for that
    // position, reading stale state and failing to show a popout at all.
    // `hoveredEntry` only drives the HoverPill highlight.
    readonly property var groupContainers: {
        const result = [];
        for (let i = 0; i < groupRepeater.count; i++) {
            const pill = groupRepeater.itemAt(i);
            if (pill)
                result.push({ pill, icons: pill.icons });
        }
        return result;
    }

    // groupDivider entries only mark a split point between pills; the
    // pills' own gap does the visual job.
    readonly property var groups: {
        const values = Settings.barStatusIcons.filter(e => e.enabled);
        const out = [];
        let current = [];
        for (const v of values) {
            if (v.id === "groupDivider") {
                if (current.length > 0) {
                    out.push(current);
                    current = [];
                }
            } else {
                current.push(v);
            }
        }
        if (current.length > 0)
            out.push(current);
        return out;
    }

    // Cross-axis is a floor, not a cap. An entry that draws an icon beside
    // text (Bluetooth with a battery percentage, for one) is wider than it
    // is tall, so it overflows a vertical bar's thickness and the pill
    // below clips it. Taking the larger of the configured thickness and
    // what the content measures widens a side bar to fit instead of
    // truncating, and changes nothing when everything already fits.
    implicitWidth: Settings.barHorizontal ? groupLayout.implicitWidth : Math.max(Settings.barInnerWidth, groupLayout.implicitWidth)
    implicitHeight: Settings.barHorizontal ? Math.max(Settings.barInnerWidth, groupLayout.implicitHeight) : groupLayout.implicitHeight

    // At the root, not inside the kbLayout delegate: EntryWrapper's default
    // property is `Item item`, and this watch is a plain QtObject, so
    // nesting it there fails to compile. Here it also holds one steady
    // subscription for the component instead of one that comes and goes
    // with whichever entries the user's config enables.
    KeyboardStateWatch {}

    GridLayout {
        id: groupLayout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        flow: Settings.barHorizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom
        rowSpacing: root.groupSpacing
        columnSpacing: root.groupSpacing

        // Only `anchors.right` is active along-axis here (no opposing pair), so
        // QtQuick leaves `width` un-derived from anchors, and GridLayout does
        // not follow its own implicitWidth in that state: `width` stayed
        // frozen at a stale early value while the real content had long
        // since grown, so `anchors.right`'s position math placed the pill
        // short of where its content actually needed to start (reported
        // live as the rightmost status pill rendering outside the Dock
        // style's outer pill). Explicit `width: implicitWidth` keeps it
        // live-tracking. The default state doesn't need this: left and
        // right anchors together derive width correctly.
        states: State {
            name: "vertical"
            when: Settings.barHorizontal

            AnchorChanges {
                target: groupLayout
                anchors.left: undefined
                anchors.top: root.top
                anchors.bottom: root.bottom
                anchors.right: root.right
            }

            PropertyChanges {
                groupLayout.width: groupLayout.implicitWidth
            }
        }

        Repeater {
            id: groupRepeater

            model: root.groups

            StyledRect {
                id: pill

                required property var modelData
                readonly property alias icons: pillIcons
                property Item hoveredEntry: null

                color: "transparent"
                radius: Tokens.rounding.full
                clip: true

                // Same floor on the cross-axis as the root above, for the
                // same reason: this rect clips, so a pill pinned to the
                // configured thickness cuts any entry wider than it.
                Layout.preferredWidth: Settings.barHorizontal ? pillIcons.implicitWidth + Tokens.padding.medium * 2 : Math.max(Settings.barInnerWidth, pillIcons.implicitWidth + Tokens.padding.medium * 2)
                Layout.preferredHeight: Settings.barHorizontal ? Math.max(Settings.barInnerWidth, pillIcons.implicitHeight + Tokens.padding.medium * 2) : pillIcons.implicitHeight + Tokens.padding.medium * 2

                HoverPill {
                    container: pillIcons
                    hoveredEntry: pill.hoveredEntry
                    thickness: Settings.barHorizontal ? pill.height : pill.width
                }

                // Plain MouseArea, not HoverHandler -- see BarWrapper.qml's
                // hoverArea comment for the full reasoning. A HoverHandler
                // here can miss a fast or directional pointer entry into
                // this pill, leaving the hover highlight stuck or null
                // with no popout shown.
                MouseArea {
                    id: pillHover

                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    hoverEnabled: true

                    function updateHoveredEntry(x: real, y: real): void {
                        const local = pill.mapToItem(pillIcons, x, y);
                        pill.hoveredEntry = BarHit.nearestAt(pillIcons, local.x, local.y);
                    }

                    onPositionChanged: mouse => updateHoveredEntry(mouse.x, mouse.y)
                    onContainsMouseChanged: {
                        if (containsMouse)
                            updateHoveredEntry(mouseX, mouseY);
                        else
                            pill.hoveredEntry = null;
                    }
                }

                GridLayout {
                    id: pillIcons

                    anchors.centerIn: parent
                    flow: Settings.barHorizontal ? GridLayout.LeftToRight : GridLayout.TopToBottom
                    rowSpacing: root.spacing
                    columnSpacing: root.spacing

                    Repeater {
                        model: ScriptModel {
                            values: pill.modelData
                        }

                        DelegateChooser {
                            role: "id"

                            DelegateChoice {
                                roleValue: "lockStatus"
                                delegate: EntryWrapper {
                                    LockStatus {
                                        colour: root.colour
                                        parentSpacing: root.spacing
                                    }
                                }
                            }
                            DelegateChoice {
                                roleValue: "audio"
                                delegate: EntryWrapper {
                                    MaterialIcon {
                                        animate: true
                                        text: Icons.getVolumeIcon(Audio.volume, Audio.muted)
                                        color: root.colour
                                        fontStyle: Tokens.font.icon.medium
                                        fill: 1
                                    }
                                }
                            }
                            DelegateChoice {
                                roleValue: "microphone"
                                delegate: EntryWrapper {
                                    name: "audio" // Mic opens audio popout

                                    MaterialIcon {
                                        animate: true
                                        text: Icons.getMicVolumeIcon(Audio.sourceVolume, Audio.sourceMuted)
                                        color: root.colour
                                        fontStyle: Tokens.font.icon.medium
                                        fill: 1
                                    }
                                }
                            }
                            DelegateChoice {
                                roleValue: "kbLayout"
                                delegate: EntryWrapper {
                                    StyledText {
                                        animate: true
                                        text: Hypr.kbLayout
                                        color: root.colour
                                        font: Tokens.font.mono.medium
                                    }
                                }
                            }
                            DelegateChoice {
                                roleValue: "network"
                                delegate: EntryWrapper {
                                    MaterialIcon {
                                        animate: true
                                        text: Nmcli.activeEthernet ? "cable" : Nmcli.active ? Icons.getNetworkIcon(Nmcli.active.strength ?? 0) : "wifi_off"
                                        color: Settings.statusIconWifiColor.length > 0 ? Settings.statusIconWifiColor : root.colour

                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -Tokens.padding.small
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Quickshell.execDetached(["nm-connection-editor"])
                                        }
                                    }
                                }
                            }
                            DelegateChoice {
                                roleValue: "bluetooth"
                                delegate: EntryWrapper {
                                    BluetoothStatus {
                                        colour: Settings.statusIconBluetoothColor.length > 0 ? Settings.statusIconBluetoothColor : root.colour

                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -Tokens.padding.small
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Quickshell.execDetached(["blueman-manager"])
                                        }
                                    }
                                }
                            }
                            DelegateChoice {
                                roleValue: "vpn"
                                delegate: EntryWrapper {
                                    VpnStatus {
                                        colour: root.colour
                                    }
                                }
                            }
                            DelegateChoice {
                                roleValue: "battery"
                                delegate: EntryWrapper {
                                    BatteryStatus {
                                        colour: Settings.statusIconPowerProfileColor.length > 0 ? Settings.statusIconPowerProfileColor : root.colour
                                    }
                                }
                            }
                            DelegateChoice {
                                roleValue: "resources"
                                delegate: EntryWrapper {
                                    ResourcesStatus {
                                        colour: Settings.statusIconPerformanceColor.length > 0 ? Settings.statusIconPerformanceColor : root.colour
                                    }
                                }
                            }
                            DelegateChoice {
                                roleValue: "hostInfo"
                                delegate: EntryWrapper {
                                    HostInfoStatus {
                                        colour: Settings.statusIconHostInfoColor.length > 0 ? Settings.statusIconHostInfoColor : root.colour
                                    }
                                }
                            }
                            DelegateChoice {
                                roleValue: "networkSpeed"
                                delegate: EntryWrapper {
                                    NetworkSpeedStatus {
                                        colour: root.colour
                                    }
                                }
                            }
                            DelegateChoice {
                                roleValue: "pomodoro"
                                delegate: EntryWrapper {
                                    PomodoroStatus {
                                        colour: Settings.statusIconPomodoroColor.length > 0 ? Settings.statusIconPomodoroColor : root.colour
                                    }
                                }
                            }
                            DelegateChoice {
                                roleValue: "dnd"
                                delegate: EntryWrapper {
                                    DndStatus {
                                        colour: Settings.statusIconDndColor.length > 0 ? Settings.statusIconDndColor : root.colour
                                    }
                                }
                            }
                            DelegateChoice {
                                roleValue: "notifCenter"
                                delegate: EntryWrapper {
                                    NotifCenterStatus {
                                        colour: root.colour
                                        screenState: root.screenState
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Simple uniform spacing (pillIcons' own rowSpacing/columnSpacing)
    // replaces the old per-item gap machinery, which existed only to avoid
    // a phantom gap around a collapsed lockStatus within one pill. That
    // rare cosmetic case is accepted in exchange for real per-pill
    // grouping without threading first/last-present indices through every
    // delegate call site.
    component EntryWrapper: Item {
        id: statusEntry

        property QtObject _sonarTarget: Loader {
            active: Settings.sonarEnabled
            sourceComponent: EchoTarget {
                target: statusEntry.item
                targetId: "core:status/" + statusEntry.modelData.id
                label: root.echoLabels[statusEntry.modelData.id] || statusEntry.modelData.id
                action: ""
                bindDescription: ""
                plugin: ""
                eligible: true
            }
        }
        required property var modelData
        required property int index
        default property Item item
        property string name: modelData.id.toLowerCase()

        Layout.alignment: Settings.barHorizontal ? Qt.AlignVCenter : Qt.AlignHCenter

        implicitWidth: item?.implicitWidth ?? 0
        implicitHeight: item?.implicitHeight ?? 0

        children: item
    }
}
