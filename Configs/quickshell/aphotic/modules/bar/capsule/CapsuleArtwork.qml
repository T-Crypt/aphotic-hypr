pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.components
import qs.components.effects
import qs.services

Item {
    id: root

    property string source: ""
    property bool shaped: false
    property int artSize: 64
    property int cornerRadius: Tokens.rounding.medium

    // The blob is the only shader this style adds, so it follows the same
    // switch as every other capsule transition: off means a plain rounded
    // tile with no mask and no Shape geometry at all.
    readonly property bool shapedActive: root.shaped && Settings.capsuleAnimations

    // Re-rolled per track so consecutive songs never land on the same
    // silhouette. amplitude runs 0 -> target once per change, which is the
    // only time the outline is rebuilt.
    property int lobes: 6
    property real amplitude: 0.09
    property real phase: 0

    function reshape(): void {
        const pool = [4, 5, 6, 7, 9];
        root.lobes = pool[Math.floor(Math.random() * pool.length)];
        root.phase = Math.random() * Math.PI * 2;

        morph.stop();
        root.amplitude = 0;
        morph.to = 0.06 + Math.random() * 0.05;
        morph.restart();
    }

    implicitWidth: root.artSize
    implicitHeight: root.artSize

    // Aphotic's established mask idiom -- see
    // modules/bar/components/workspaces/SpecialWorkspaces.qml: the item
    // layers itself and an invisible sibling supplies the alpha.
    layer.enabled: root.shapedActive
    layer.effect: Mask {
        maskSource: blob.item
    }

    onSourceChanged: {
        if (root.shapedActive)
            root.reshape();
    }

    Component.onCompleted: {
        if (root.shapedActive)
            root.reshape();
    }

    Anim {
        id: morph

        target: root
        property: "amplitude"
        to: 0.09
        type: Anim.SlowSpatial
    }

    StyledClippingRect {
        anchors.fill: parent
        // The blob already defines the silhouette when it is masking, so a
        // second rounded-rect clip underneath would only cut the petals off.
        radius: root.shapedActive ? 0 : root.cornerRadius
        color: Colours.palette.m3surfaceContainerHigh

        Image {
            id: art

            anchors.fill: parent
            source: root.source
            // Pinned to the declared artSize, never to the item's own
            // width: that width animates, and a bound sourceSize re-decodes
            // the image on every frame of an expand.
            sourceSize.width: root.artSize
            sourceSize.height: root.artSize
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            visible: root.source.length > 0 && status === Image.Ready
            opacity: visible ? 1 : 0

            Behavior on opacity {
                enabled: Settings.capsuleAnimations
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        MaterialIcon {
            anchors.centerIn: parent
            visible: !art.visible
            text: "music_note"
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: root.artSize >= 56 ? Tokens.font.icon.large : Tokens.font.icon.small
        }
    }

    Loader {
        id: blob

        anchors.fill: parent
        active: root.shapedActive

        sourceComponent: BlobShape {
            visible: false
            layer.enabled: true
            lobes: root.lobes
            amplitude: root.amplitude
            phase: root.phase
        }
    }
}
