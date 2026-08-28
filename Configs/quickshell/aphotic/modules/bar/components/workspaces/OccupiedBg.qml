pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property Repeater workspaces
    required property var occupied
    required property int groupOffset

    property list<var> pills: []

    onOccupiedChanged: {
        if (!occupied)
            return;
        let count = 0;
        const start = groupOffset;
        const end = start + Math.max(1, workspaces.count);
        for (const [ws, occ] of Object.entries(occupied)) {
            if (ws > start && ws <= end && occ) {
                const isFirstInGroup = Number(ws) === start + 1;
                const isLastInGroup = Number(ws) === end;
                if (isFirstInGroup || !occupied[ws - 1]) {
                    if (pills[count])
                        pills[count].start = ws;
                    else
                        pills.push(pillComp.createObject(root, {
                            start: ws
                        }));
                    count++;
                }
                if ((isLastInGroup || !occupied[ws + 1]) && pills[count - 1])
                    pills[count - 1].end = ws;
            }
        }
        if (pills.length > count)
            pills.splice(count, pills.length - count).forEach(p => p.destroy());
    }

    Repeater {
        model: ScriptModel {
            values: root.pills.filter(p => p)
        }

        StyledRect {
            id: rect

            required property var modelData

            readonly property Workspace start: root.workspaces.count > 0 ? root.workspaces.itemAt(getWsIdx(modelData.start)) ?? null : null // qmllint disable incompatible-type
            readonly property Workspace end: root.workspaces.count > 0 ? root.workspaces.itemAt(getWsIdx(modelData.end)) ?? null : null // qmllint disable incompatible-type

            // See ActiveIndicator.qml's own note: wrap on the number of
            // cells actually rendered, not the configured maximum.
            function getWsIdx(ws: int): int {
                const shown = Math.max(1, root.workspaces.count);
                let i = ws - 1;
                while (i < 0)
                    i += shown;
                return i % shown;
            }

            anchors.horizontalCenter: root.horizontalCenter

            // Whichever anchor line above/below is actually active (see
            // states below) owns the cross axis and silently overrides
            // the corresponding x/y binding here -- so it's safe to just
            // always feed both from start's own position.
            x: (start?.x ?? 0) - 1
            y: (start?.y ?? 0) - 1
            implicitWidth: Settings.barHorizontal ? (start && end ? end.x + end.size - start.x + 2 : 0) : (Settings.barInnerWidth - Tokens.padding.small + 2)
            implicitHeight: Settings.barHorizontal ? (Settings.barInnerWidth - Tokens.padding.small + 2) : (start && end ? end.y + end.size - start.y + 2 : 0)

            color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 2)
            radius: Tokens.rounding.full

            scale: 0
            Component.onCompleted: scale = 1

            states: State {
                name: "vertical"
                when: Settings.barHorizontal

                AnchorChanges {
                    target: rect
                    anchors.horizontalCenter: undefined
                    anchors.verticalCenter: root.verticalCenter
                }
            }

            Behavior on scale {
                Anim {
                    easing: Tokens.anim.standardDecel
                }
            }

            Behavior on x {
                Anim {}
            }

            Behavior on y {
                Anim {}
            }

            Behavior on implicitWidth {
                Anim {}
            }

            Behavior on implicitHeight {
                Anim {}
            }
        }
    }

    Component {
        id: pillComp

        Pill {}
    }

    component Pill: QtObject {
        property int start
        property int end
    }
}
