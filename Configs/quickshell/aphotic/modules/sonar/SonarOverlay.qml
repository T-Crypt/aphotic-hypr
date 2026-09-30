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
        ? Policy.radiusFraction(Sonar.progress, Sonar.reduced) * Sonar.maxRadius : 0

    opacity: Policy.opacityAt(Sonar.progress, Sonar.reduced)

    // Targets registered to this output that the ring has reached so
    // far. Plugin records carry output-local rects; the answer test runs
    // in the shared global plane so one ring answers everywhere.
    readonly property var answered: {
        if (!Sonar.origin)
            return [];
        const r = root.radius;
        return Sonar.targets.filter(t => {
            if (t.output !== screen.name)
                return false;
            return Policy.reached(Sonar.origin, {
                x: screen.x + t.rect.x,
                y: screen.y + t.rect.y,
                width: t.rect.width,
                height: t.rect.height
            }, r);
        });
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
        model: root.answered

        delegate: Item {
            id: outline

            required property var modelData

            x: modelData.rect.x
            y: modelData.rect.y
            width: modelData.rect.width
            height: modelData.rect.height

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                radius: Tokens.rounding.small
                border.width: 2
                border.color: Colours.palette.m3primary
            }

            // Name and actual shortcut, on the surface color so it reads
            // over any wallpaper. Below the outline when there is room,
            // above when there is not, clamped into the output.
            readonly property bool below: modelData.rect.y + modelData.rect.height + 32 < screen.height
            readonly property real plateY: below
                ? Math.min(modelData.rect.height + Tokens.spacing.small, screen.height - height)
                : Math.max(-height - Tokens.spacing.small, 0)
            readonly property real plateX: Math.max(0, Math.min(
                (modelData.rect.width - label.implicitWidth - Tokens.padding.medium * 2) / 2,
                screen.width - label.implicitWidth - Tokens.padding.medium * 2))

            Rectangle {
                x: outline.plateX
                y: outline.plateY
                implicitWidth: label.implicitWidth + Tokens.padding.medium * 2
                implicitHeight: label.implicitHeight + Tokens.spacing.small * 2
                radius: Tokens.rounding.small
                color: Colours.palette.m3surfaceContainer

                StyledText {
                    id: label

                    anchors.centerIn: parent
                    text: outline.modelData.label
                        + (outline.modelData.shortcut ? "  " + outline.modelData.shortcut : "")
                    color: Colours.palette.m3onSurface
                    font: Tokens.font.label.medium
                }
            }
        }
    }
}
