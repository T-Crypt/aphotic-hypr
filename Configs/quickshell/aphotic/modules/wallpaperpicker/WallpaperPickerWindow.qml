pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.services

PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    required property ScreenState screenState

    WlrLayershell.namespace: "aphotic-wallpaperpicker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    visible: screenState.wallpaperPicker
    implicitWidth: screen.width
    implicitHeight: screen.height

    readonly property string layout: Settings.wallpaperPickerLayout
    // The grid is the only layout that browses across themes: stepping
    // between themes in a coverflow or a dock would apply a whole theme
    // switch per scrolled-past card.
    readonly property bool browseAllThemes: root.layout === "grid"
    // The dock hands the whole screen to the wallpaper itself; the other
    // two keep the blurred band that reads as depth behind them.
    readonly property bool losslessBackdrop: root.layout === "dock"

    WallpaperPickerModel {
        id: pickerModel

        allThemes: root.browseAllThemes
        open: root.screenState.wallpaperPicker
        onCloseRequested: root.screenState.wallpaperPicker = false
    }

    Connections {
        target: root.screenState

        function onWallpaperPickerChanged(): void {
            if (!root.screenState.wallpaperPicker) {
                pickerModel.cancelPreview();
                return;
            }
            root.everOpened = true;
            // Nothing watches ~/.config/awww, so a wallpaper dropped in
            // since the shell started would otherwise not appear until a
            // restart. Opening the picker is the natural moment to look.
            Themes.rescan();
            pickerModel.begin();
            Qt.callLater(() => layoutLoader.item?.focusActive());
        }
    }

    WallpaperBackdrop {
        anchors.fill: parent
        active: root.screenState.wallpaperPicker
        source: layoutLoader.item?.backdropSource ?? ""
        lossless: root.losslessBackdrop
        // Each layout states the band it needs. Every layout used to be
        // handed the coverflow's (63% of the height, faded at the top),
        // which is right for a filmstrip sitting in the lower two thirds
        // and wrong for the grid, whose rows run the full height and so ran
        // off the bottom of the blur onto bare wallpaper.
        bandHeight: layoutLoader.item?.bandHeight ?? filmstripMetrics.bandHeight
        fadeExtent: layoutLoader.item?.bandFade ?? filmstripMetrics.bandFade
    }

    // The coverflow's geometry, kept as the fallback for the window between
    // the picker opening and its layout being built.
    QtObject {
        id: filmstripMetrics

        readonly property int bandHeight: Math.max(320, Math.round(root.height * 0.63))
        readonly property int bandFade: Math.round(bandHeight * 0.15)
    }

    MouseArea {
        anchors.fill: parent
        onClicked: pickerModel.revertAndClose()
    }

    // Built on first open and kept afterwards, so every later open is
    // immediate rather than reconstructing a view over the whole
    // wallpaper list. Nothing here runs while the window is hidden: the
    // PanelWindow is not visible, the model's preview timer is stopped on
    // close, and the layouts drive off the model rather than polling.
    // Switching layout in Settings swaps sourceComponent and the old one
    // goes, so at most one is ever resident.
    property bool everOpened: false

    onLayoutChanged: {
        if (!root.screenState.wallpaperPicker)
            root.everOpened = false;
    }

    Loader {
        id: layoutLoader

        anchors.fill: parent
        active: root.screenState.wallpaperPicker || root.everOpened
        sourceComponent: root.layout === "grid" ? gridComp : root.layout === "dock" ? dockComp : coverflowComp

        onLoaded: Qt.callLater(() => layoutLoader.item?.focusActive())
    }

    Component {
        id: coverflowComp

        WallpaperFilmstrip {
            model: pickerModel
        }
    }

    Component {
        id: gridComp

        WallpaperGrid {
            model: pickerModel
        }
    }

    Component {
        id: dockComp

        WallpaperDock {
            model: pickerModel
        }
    }
}
