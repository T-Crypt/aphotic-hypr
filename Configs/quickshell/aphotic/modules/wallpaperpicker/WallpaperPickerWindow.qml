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
        bandHeight: filmstripMetrics.bandHeight
        fadeExtent: filmstripMetrics.bandFade
    }

    // The band geometry is the coverflow's, and the backdrop needs it before
    // the layout that defines it necessarily exists.
    QtObject {
        id: filmstripMetrics

        readonly property int bandHeight: Math.max(320, Math.round(root.height * 0.63))
        readonly property int bandFade: Math.round(bandHeight * 0.15)
    }

    MouseArea {
        anchors.fill: parent
        onClicked: pickerModel.revertAndClose()
    }

    Loader {
        id: layoutLoader

        anchors.fill: parent
        // Only built once the picker is actually opened, and torn down with
        // it: three layouts kept resident would each hold a view over every
        // wallpaper for the whole session.
        active: root.screenState.wallpaperPicker
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
