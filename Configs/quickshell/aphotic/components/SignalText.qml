// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import qs.config

// A line of text resolved out of noise by shaders/signal.frag, coloured
// entirely from whatever palette the caller hands it.
//
// Nothing here animates. `progress` and `time` are plain properties a
// caller steps from its own low-rate clock, because a QML animation ticks
// once per frame and would hold the window at the display rate for as
// long as it ran -- the regression DepthFx.qml and the pet's own clock
// were both written to avoid.
//
// The text being sampled lives inside an invisible wrapper, and the
// fallback is a SEPARATE Text item. That split is not tidiness. Marking
// the ShaderEffectSource `visible: false` releases its `hideSource`, so
// the sampled Text goes on painting at full brightness underneath the
// shader and the whole effect reads as plain white letters on black --
// measured, not guessed. A source parked in an invisible wrapper is still
// captured into the texture and never drawn.
//
// The shader is built to .qsb at install time. An install that predates
// that step, or a machine with no qt6-shadertools, leaves the .qsb
// missing and the ShaderEffect reports Error -- so `fallback` becomes
// visible instead and the caller still gets legible text. `status` is not
// Compiled until the item has rendered once, so never read `shaded` in
// Component.onCompleted.
Item {
    id: root

    property real progress: 1
    property real time: 0
    property real grain: 1
    property real bloom: 0
    property color ink: "#ffffff"
    property color glow: "#ffffff"
    property string text: ""
    property string family: Tokens.font.mono.large.family
    property int pixelSize: 96
    property int weight: 500
    property real letterSpacing: 18

    readonly property bool shaded: fx.status === ShaderEffect.Compiled

    implicitWidth: fallback.implicitWidth
    implicitHeight: fallback.implicitHeight

    Item {
        id: source

        anchors.fill: parent
        visible: false

        Text {
            anchors.centerIn: parent
            // Sampled as a plain alpha mask -- the shader supplies every
            // colour, so this is rendered white and tinted there.
            color: "white"
            text: root.text
            font.family: root.family
            font.pixelSize: root.pixelSize
            font.weight: root.weight
            font.letterSpacing: root.letterSpacing
        }
    }

    ShaderEffectSource {
        id: mask

        anchors.fill: parent
        sourceItem: source
        live: true
        visible: false
    }

    ShaderEffect {
        id: fx

        anchors.fill: parent
        visible: root.shaded
        blending: true
        fragmentShader: Qt.resolvedUrl("../shaders/signal.frag.qsb")

        readonly property var source: mask
        readonly property real progress: root.progress
        readonly property real time: root.time
        readonly property real aspect: root.height > 0 ? root.width / root.height : 1
        readonly property real grain: root.grain
        readonly property real bloom: root.bloom
        readonly property color inkColour: root.ink
        readonly property color glowColour: root.glow
    }

    Text {
        id: fallback

        anchors.centerIn: parent
        visible: !root.shaded
        color: root.ink
        opacity: root.progress
        text: root.text
        font.family: root.family
        font.pixelSize: root.pixelSize
        font.weight: root.weight
        font.letterSpacing: root.letterSpacing
    }
}
