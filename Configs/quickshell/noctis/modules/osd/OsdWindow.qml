pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.config
import qs.components
import qs.services
import qs.utils

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    readonly property Brightness.Monitor monitor: Brightness.getMonitorForScreen(root.screen)
    property bool shown: false

    function show(): void {
        if (!Config.osd.enabled)
            return;
        shown = true;
        hideTimer.restart();
    }

    WlrLayershell.namespace: "noctis-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors.top: true
    anchors.bottom: true
    anchors.right: true

    implicitWidth: Tokens.sizes.osd.sliderWidth + Tokens.padding.large * 2
    implicitHeight: screen.height

    visible: shown

    Timer {
        id: hideTimer
        interval: Config.osd.hideDelay
        onTriggered: root.shown = false
    }

    Connections {
        target: Audio

        function onVolumeChanged(): void {
            root.show();
        }
        function onMutedChanged(): void {
            root.show();
        }
        function onSourceVolumeChanged(): void {
            root.show();
        }
        function onSourceMutedChanged(): void {
            root.show();
        }
    }

    Connections {
        target: root.monitor

        function onBrightnessChanged(): void {
            root.show();
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: Tokens.spacing.medium

        OsdSlider {
            icon: Icons.getVolumeIcon(Audio.volume, Audio.muted)
            value: Audio.volume
            to: GlobalConfig.services.maxVolume
            onMoved: value => Audio.setVolume(value)
            onWheelUp: Audio.incrementVolume()
            onWheelDown: Audio.decrementVolume()
        }

        OsdSlider {
            visible: Config.osd.enableMicrophone
            height: visible ? implicitHeight : 0

            icon: Icons.getMicVolumeIcon(Audio.sourceVolume, Audio.sourceMuted)
            value: Audio.sourceVolume
            to: GlobalConfig.services.maxVolume
            onMoved: value => Audio.setSourceVolume(value)
            onWheelUp: Audio.incrementSourceVolume()
            onWheelDown: Audio.decrementSourceVolume()
        }

        OsdSlider {
            visible: Config.osd.enableBrightness
            height: visible ? implicitHeight : 0

            icon: `brightness_${Math.round((root.monitor?.brightness ?? 0) * 6) + 1}`
            value: root.monitor?.brightness ?? 0
            to: 1
            onMoved: value => root.monitor?.setBrightness(value)
            onWheelUp: root.monitor?.setBrightness((root.monitor?.brightness ?? 0) + GlobalConfig.services.brightnessIncrement)
            onWheelDown: root.monitor?.setBrightness((root.monitor?.brightness ?? 0) - GlobalConfig.services.brightnessIncrement)
        }
    }
}
