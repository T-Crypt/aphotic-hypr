pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.services
import qs.modules.bar.popouts as BarPopouts

Item {
    id: root

    required property ShellScreen screen
    required property ScreenState screenState
    required property BarPopouts.Wrapper popouts
    required property bool fullscreen
    required property real thickness

    function closeTray(): void {
        loader.item?.closeTray?.();
    }

    function checkPopout(pos: real): void {
        loader.item?.checkPopout?.(pos);
    }

    function handleWheel(pos: real, angleDelta: point): void {
        loader.item?.handleWheel?.(pos, angleDelta);
    }

    Loader {
        id: loader
        anchors.fill: parent

        sourceComponent: {
            switch (Settings.barStyle) {
            case "taskbar":
                return taskbarComp;
            case "minimal":
                return minimalComp;
            default:
                return fullComp;
            }
        }
    }

    Component {
        id: fullComp
        Bar {
            screen: root.screen
            screenState: root.screenState
            popouts: root.popouts
            fullscreen: root.fullscreen
            thickness: root.thickness
        }
    }

    Component {
        id: taskbarComp
        TaskbarBar {
            screen: root.screen
            screenState: root.screenState
            popouts: root.popouts
            fullscreen: root.fullscreen
            thickness: root.thickness
        }
    }

    Component {
        id: minimalComp
        MinimalBar {
            screen: root.screen
            screenState: root.screenState
            popouts: root.popouts
            fullscreen: root.fullscreen
            thickness: root.thickness
        }
    }
}
