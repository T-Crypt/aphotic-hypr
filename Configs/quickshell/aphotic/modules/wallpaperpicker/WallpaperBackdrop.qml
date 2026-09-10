pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.components
import qs.services

Item {
    id: root

    required property string source
    required property int bandHeight
    required property int fadeExtent
    property bool active: false

    // Full-bleed, full-resolution, unblurred: the wallpaper itself is the
    // preview. The coverflow deliberately does the opposite -- a blurred
    // 640x360 band that reads as depth behind the strip and costs almost
    // nothing -- so this is opt-in per layout rather than a replacement.
    property bool lossless: false

    // sourceSize 0 means "decode at native resolution" to Image, which is
    // exactly what lossless mode wants.
    readonly property int decodeWidth: root.lossless ? 0 : 640
    readonly property int decodeHeight: root.lossless ? 0 : 360

    readonly property int effectiveBandHeight: root.lossless ? root.height : root.bandHeight

    readonly property string bandSource: root.active ? root.source : ""
    readonly property real fadeStop: root.lossless ? 0 : (root.bandHeight > 0 ? root.fadeExtent / root.bandHeight : 0)

    // The band cross-fades by loading into whichever of the two images is
    // not on screen and swapping to it once it is ready. Scrolling back to a
    // wallpaper the spare still holds assigns it the path it already has,
    // which raises no status change to swap on, so that case swaps directly.
    // Without it the band kept showing the previous wallpaper whenever the
    // strip moved back and forth between two.
    function _show(path: string): void {
        if (path.length === 0 || bleed.current.path === path)
            return;
        const spare = bleed.current === one ? two : one;
        if (spare.path === path) {
            if (spare.status === Image.Ready)
                bleed.current = spare;
            return;
        }
        spare.path = path;
    }

    onBandSourceChanged: root._show(root.bandSource)

    Item {
        id: band

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: root.effectiveBandHeight
        visible: root.bandSource.length > 0

        // No mask in lossless mode: the band is the whole screen, so there
        // are no edges to feather, and skipping the layer keeps the
        // full-resolution image off a render-target round trip.
        layer.enabled: !root.lossless
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: fade
            autoPaddingEnabled: false
        }

        Item {
            id: bleed

            property Img current: one

            width: root.width
            height: root.height
            y: -band.y

            layer.enabled: DepthFx.enabled && !root.lossless
            layer.effect: MultiEffect {
                saturation: -0.08
                brightness: -0.02
                blurEnabled: true
                blur: 1
                blurMax: DepthFx.full ? 64 : 40
                autoPaddingEnabled: false
            }

            Img {
                id: one
            }

            Img {
                id: two
            }
        }

        Rectangle {
            anchors.fill: parent
            visible: !root.lossless
            color: Colours.palette.m3surfaceContainer
            opacity: 0.15

            Behavior on color {
                CAnim {}
            }
        }

        DepthLayer {
            anchors.fill: parent
            visible: !root.lossless
            opacityScale: 1
        }
    }

    Rectangle {
        id: fade

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: root.effectiveBandHeight
        visible: false
        layer.enabled: true

        gradient: Gradient {
            GradientStop {
                position: 0
                color: "#00ffffff"
            }
            GradientStop {
                position: root.fadeStop
                color: "#ffffffff"
            }
            GradientStop {
                position: 1 - root.fadeStop
                color: "#ffffffff"
            }
            GradientStop {
                position: 1
                color: "#00ffffff"
            }
        }
    }

    component Img: Image {
        id: img

        property string path

        anchors.fill: parent
        source: img.path
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true
        sourceSize.width: root.decodeWidth
        sourceSize.height: root.decodeHeight
        opacity: bleed.current === img ? 1 : 0

        onStatusChanged: {
            if (img.status === Image.Ready && img.path === root.bandSource)
                bleed.current = img;
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }
}
