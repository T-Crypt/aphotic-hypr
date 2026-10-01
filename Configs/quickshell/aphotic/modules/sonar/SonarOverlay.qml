// SonarOverlay.qml -- one output's slice of the shared ping composition.
// The ring is one circle in logical desktop coordinates; this window
// draws the part of it that crosses its output. Targets answer as the
// ring reaches the nearest point of their rectangle.
pragma ComponentBehavior: Bound

import qs.components
import qs.config
import qs.services
import Quickshell
import QtQuick
import "../../services/SonarPolicy.js" as Policy
import "../../services/SonarTargets.js" as LayoutRules

Item {
    id: root

    required property ShellScreen screen
    property bool focused: false
    focus: root.focused

    // Global logical origin, mapped into this window.
    readonly property var localOrigin: Sonar.origin ? ({
        x: Sonar.origin.x - screen.x,
        y: Sonar.origin.y - screen.y
    }) : null

    readonly property real radius: Sonar.origin
        ? (Sonar.reduced ? Tokens.spacing.large * 2 : Policy.radiusFraction(Sonar.progress, false) * Sonar.maxRadius) : 0

    opacity: Policy.opacityAt(Sonar.progress, Sonar.reduced)

    readonly property var outputTargets: Sonar.visibleTargets.filter(t => t.output === root.screen.name).map(t => Object.assign({}, t, {
        labelWidth: 260, labelHeight: t.ghost ? (t.reason ? 118 : 94) : 56
    }))
    readonly property var labelLayout: LayoutRules.placeLabels(root.outputTargets, root.width, root.height, Tokens.spacing.small)
    readonly property var answered: root.outputTargets.filter(t => root.reached(t))

    function reached(target: var): bool {
        if (!Sonar.origin) return false;
        return Sonar.reduced || Policy.reached(Sonar.origin, {
            x:root.screen.x + target.rect.x, y:root.screen.y + target.rect.y,
            width:target.rect.width, height:target.rect.height
        }, root.radius);
    }

    // Any key and any click dismiss and are consumed, so nothing behind
    // the composition receives them. The invocation key's release and
    // repeats belong to an exec bind the compositor runs once per press,
    // so nothing of the sort reaches this surface.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: event => {
            event.accepted = true;
            Sonar.dismiss();
        }
    }

    Keys.onPressed: event => {
        event.accepted = true;
        if (Policy.dismissKey(event.key, event.isAutoRepeat))
            Sonar.dismiss();
    }

    Canvas {
        id: ring

        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            if (!root.localOrigin)
                return;
            // Surface-colored under-stroke keeps the accent readable on
            // dark and light wallpaper alike. Palette roles only; the
            // released appearance keeps its tokens.
            ctx.strokeStyle = Colours.palette.m3surfaceContainer;
            ctx.lineWidth = 10;
            ctx.globalAlpha = 0.85;
            ctx.beginPath();
            ctx.arc(root.localOrigin.x, root.localOrigin.y, root.radius + 3, 0, Math.PI * 2);
            ctx.stroke();
            ctx.globalAlpha = 1;
            ctx.strokeStyle = Colours.palette.m3primary;
            ctx.lineWidth = 3;
            ctx.beginPath();
            ctx.arc(root.localOrigin.x, root.localOrigin.y, root.radius, 0, Math.PI * 2);
            ctx.stroke();
        }

        Connections {
            target: root
            function onRadiusChanged(): void {
                ring.requestPaint();
            }
            function onLocalOriginChanged(): void {
                ring.requestPaint();
            }
        }

        Component.onCompleted: ring.requestPaint()
    }

    Repeater {
        model: root.outputTargets
        delegate: Item {
            id: outline
            required property var modelData
            readonly property var plate: root.labelLayout.labels.find(p => p.id === modelData.id) ?? null
            readonly property real distance: {
                if (!Sonar.origin) return 0;
                const r = modelData.rect;
                const x = root.screen.x + r.x, y = root.screen.y + r.y;
                const dx = Math.max(x - Sonar.origin.x, 0, Sonar.origin.x - x - r.width);
                const dy = Math.max(y - Sonar.origin.y, 0, Sonar.origin.y - y - r.height);
                return Math.hypot(dx, dy);
            }
            opacity: Sonar.reduced ? 1 : Math.max(0, Math.min(1, (root.radius - distance) / (Tokens.spacing.large * 2)))
            visible: root.reached(modelData)
            x: modelData.rect.x
            y: modelData.rect.y
            width: modelData.rect.width
            height: modelData.rect.height

            Rectangle {
                anchors.fill: parent
                visible: !outline.modelData.disabled
                color: "transparent"
                radius: Tokens.rounding.small
                border.width: 2
                border.color: Colours.palette.m3primary
            }
            Canvas {
                id: dashed
                anchors.fill: parent
                visible: !!outline.modelData.disabled
                opacity: 0.55
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    ctx.strokeStyle = Colours.palette.m3primary;
                    ctx.lineWidth = 2;
                    ctx.setLineDash([6,4]);
                    ctx.strokeRect(1,1,width-2,height-2);
                }
                Component.onCompleted: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
            }
            Rectangle {
                visible: outline.plate !== null
                x: (outline.plate?.x ?? 0) - outline.x
                y: (outline.plate?.y ?? 0) - outline.y
                width: outline.plate?.width ?? 0
                height: outline.plate?.height ?? 0
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainer

                StyledText {
                    x: Tokens.padding.small; y: Tokens.spacing.small
                    width: parent.width - Tokens.padding.small * 2
                    text: outline.modelData.label + "\n" + outline.modelData.shortcut
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    font: Tokens.font.label.medium
                }
                StyledText {
                    visible: !!outline.modelData.reason
                    x: Tokens.padding.small; y: 44
                    width: parent.width - Tokens.padding.small * 2
                    text: outline.modelData.reason || ""
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    font: Tokens.font.label.small
                }
                Rectangle {
                    visible: !!outline.modelData.ghost
                    x: Tokens.padding.small
                    y: parent.height - height - Tokens.spacing.small
                    width: Math.min(110, parent.width - Tokens.padding.small * 2)
                    height: 28
                    radius: Tokens.rounding.small
                    color: Colours.palette.m3primary
                    StyledText {
                        anchors.centerIn: parent
                        text: outline.modelData.route === "plugin-settings" ? qsTr("Settings") : outline.modelData.disabled ? qsTr("Enable") : qsTr("Open")
                        color: Colours.palette.m3onPrimary
                        font: Tokens.font.label.medium
                    }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.AllButtons
                        onPressed: event => {
                            event.accepted = true;
                            if (event.button === Qt.LeftButton) Sonar.activateGhost(outline.modelData);
                            else Sonar.dismiss();
                        }
                    }
                }
            }
        }
    }
    Rectangle {
        visible: root.labelLayout.grouped.length > 0
        x: Tokens.spacing.small; y: Tokens.spacing.small
        width: Math.min(root.width - Tokens.spacing.small * 2, groupLabel.implicitWidth + Tokens.padding.small * 2)
        height: 28
        radius: Tokens.rounding.small
        color: Colours.palette.m3surfaceContainer
        StyledText {
            id: groupLabel
            anchors.centerIn: parent
            width: Math.max(0, parent.width - Tokens.padding.small * 2)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: qsTr("%1 more labels · Settings").arg(root.labelLayout.grouped.length)
            font: Tokens.font.label.small
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: event => {
                event.accepted = true;
                const state = SonarDiscovery.stateFor(root.screen.name);
                Sonar.dismiss();
                if (event.button === Qt.LeftButton && state) {
                    state.settingsCategory = "sonar";
                    state.settings = true;
                }
            }
        }
    }
}
