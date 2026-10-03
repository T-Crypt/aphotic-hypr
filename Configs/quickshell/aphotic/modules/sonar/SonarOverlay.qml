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
    clip: true

    // Global logical origin, mapped into this window.
    readonly property var localOrigin: Sonar.origin ? ({
        x: Sonar.origin.x - screen.x,
        y: Sonar.origin.y - screen.y
    }) : null

    readonly property real sweep: Policy.radiusFraction(Sonar.progress, false)
    readonly property real radius: Sonar.origin
        ? (Sonar.reduced ? Tokens.spacing.large * 2 : root.sweep * root.sweep * (3 - 2 * root.sweep) * Sonar.maxRadius) : 0

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

    Repeater {
        model: Sonar.reduced ? 1 : 3
        delegate: Rectangle {
            required property int index
            readonly property real waveRadius: Math.max(0, root.radius - index * Tokens.spacing.extraLarge * 2)
            x: (root.localOrigin?.x ?? 0) - waveRadius
            y: (root.localOrigin?.y ?? 0) - waveRadius
            width: waveRadius * 2
            height: width
            radius: width / 2
            color: "transparent"
            border.width: index === 0 ? 1.5 : 1
            border.color: Colours.palette.m3primary
            opacity: (index === 0 ? 0.5 : index === 1 ? 0.16 : 0.07)
                * Math.min(1, waveRadius / Tokens.spacing.extraLarge)
            visible: root.localOrigin !== null && waveRadius > 0
            antialiasing: true
        }
    }

    Repeater {
        model: root.outputTargets
        delegate: Item {
            id: outline
            required property var modelData
            readonly property var plate: root.labelLayout.labels.find(p => p.id === modelData.id) ?? null
            readonly property bool shelf: (modelData.id ?? "").startsWith("core:shelf/")
            property real reveal: root.reached(modelData) ? 1 : 0
            opacity: reveal
            visible: reveal > 0
            Behavior on reveal {
                enabled: !Sonar.reduced
                NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
            }
            x: modelData.rect.x
            y: modelData.rect.y
            width: modelData.rect.width
            height: modelData.rect.height

            Repeater {
                model: Sonar.reduced ? 0 : outline.shelf ? 2 : 1
                delegate: Rectangle {
                    required property int index
                    readonly property real bloom: Math.min(1, outline.reveal * (index === 0 ? 1.3 : 1))
                    anchors.fill: parent
                    anchors.margins: -Tokens.spacing.extraSmall - Tokens.spacing.medium * bloom
                    radius: Tokens.rounding.large + Tokens.spacing.medium * bloom
                    color: Qt.alpha(Colours.palette.m3primary, 0.035 * (1 - bloom))
                    border.width: 1
                    border.color: Colours.palette.m3primary
                    opacity: (outline.shelf ? 0.3 : 0.2) * (1 - bloom)
                    antialiasing: true
                }
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: -Tokens.spacing.extraSmall / 2
                color: Qt.alpha(Colours.palette.m3primary, outline.modelData.disabled ? 0.035 : 0.07)
                radius: Tokens.rounding.large
                border.width: outline.modelData.disabled ? 0 : 1
                border.color: Qt.alpha(Colours.palette.m3primary, 0.55)
                antialiasing: true
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
                    ctx.lineWidth = 1;
                    ctx.setLineDash([4,5]);
                    ctx.beginPath();
                    const r = Math.max(0, Math.min(Tokens.rounding.large, (width-2)/2, (height-2)/2));
                    ctx.moveTo(1+r,1);
                    ctx.arcTo(width-1,1,width-1,height-1,r);
                    ctx.arcTo(width-1,height-1,1,height-1,r);
                    ctx.arcTo(1,height-1,1,1,r);
                    ctx.arcTo(1,1,width-1,1,r);
                    ctx.closePath();
                    ctx.stroke();
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
                radius: Tokens.rounding.medium
                color: Qt.alpha(Colours.palette.m3surfaceContainerHigh, 0.97)
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3onSurface, 0.1)
                antialiasing: true

                Rectangle {
                    x: Tokens.padding.small; y: 15
                    width: 4; height: 4; radius: 2
                    color: Colours.palette.m3primary
                    opacity: outline.modelData.disabled ? 0.5 : 1
                }
                StyledText {
                    x: Tokens.padding.large; y: Tokens.spacing.small
                    width: parent.width - Tokens.padding.large - Tokens.padding.small
                    text: outline.modelData.label
                    elide: Text.ElideRight
                    font: Tokens.font.label.medium
                }
                StyledText {
                    x: Tokens.padding.large; y: 29
                    width: parent.width - Tokens.padding.large - Tokens.padding.small
                    text: outline.modelData.shortcut
                    color: Colours.palette.m3onSurfaceVariant
                    elide: Text.ElideRight
                    font: Tokens.font.label.small
                }
                StyledText {
                    visible: !!outline.modelData.reason
                    x: Tokens.padding.small; y: 48
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
