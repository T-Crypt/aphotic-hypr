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

    readonly property int decodeWidth: 640
    readonly property int decodeHeight: 360

    readonly property string bandSource: root.active ? root.source : ""
    readonly property real fadeStop: root.bandHeight > 0 ? root.fadeExtent / root.bandHeight : 0

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
        height: root.bandHeight
        visible: root.bandSource.length > 0

        layer.enabled: true
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

            layer.enabled: DepthFx.enabled
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
            color: Colours.palette.m3surfaceContainer
            opacity: 0.15

            Behavior on color {
                CAnim {}
            }
        }

        DepthLayer {
            anchors.fill: parent
            opacityScale: 1
        }
    }

    Rectangle {
        id: fade

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: root.bandHeight
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
