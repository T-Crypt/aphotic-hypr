pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.config
import qs.components
import qs.services
import qs.modules.bar
import qs.modules.bar.popouts as BarPopouts

Item {
    id: root

    required property string styleName
    required property string label

    readonly property bool selected: Settings.barStyle === root.styleName
    // Matches Tokens.sizes.bar.minimalInnerWidth vs innerWidth -- Minimal
    // is thinner than Full/Taskbar in the real bar, and the preview
    // needs to actually reflect that instead of rendering it at the same
    // virtual thickness as the other two.
    readonly property real previewThickness: root.styleName === "minimal" ? 28 : 48
    // Content-sized floating styles, drawn at their own implicit size and
    // centred, rather than stretched edge to edge like the full-width ones.
    readonly property bool floats: root.styleName === "dock" || root.styleName === "capsule"

    implicitWidth: 190
    implicitHeight: 120

    // Not one of the real per-screen instances (Variants{model:
    // Quickshell.screens} in shell.qml) -- a scratch instance so a
    // preview card's (non-interactive, see the MouseArea below) content
    // can't cross-contaminate real screenState flags like `settings` or
    // `launcher`. modelData: null still satisfies the required property
    // without adopting any real screen's identity/persistence key.
    ScreenState {
        id: previewScreenState
        modelData: null
    }

    BarPopouts.Wrapper {
        id: previewPopouts
        screen: Quickshell.screens[0] ?? null
        barWidth: 48
        windowWidth: 400
        windowHeight: 200
        screenState: previewScreenState
    }

    StyledRect {
        anchors.fill: parent
        radius: Tokens.rounding.large
        color: root.selected ? Colours.layer(Colours.tPalette.m3surfaceContainer, 2) : Colours.tPalette.m3surfaceContainer
        border.width: root.selected ? 2 : 0
        border.color: Colours.palette.m3primary

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.padding.small
            spacing: Tokens.spacing.small

            Item {
                id: previewFrame

                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                // Real components at true size, scaled down to ~32% --
                // not a mockup. Interaction is intentionally swallowed by
                // the MouseArea below rather than reaching this tiny
                // scaled-down content (clicking a preview selects the
                // style; it doesn't drive the miniature bar itself).
                //
                // The full-width styles (full/taskbar/minimal) put their
                // meaningful content at the LEFT and RIGHT edges of the
                // bar (start button/tasks vs. tray/clock), with an empty
                // fillWidth spacer in between -- centering a wide virtual
                // canvas inside this small a frame at a fixed scale would
                // only ever show that empty middle slice. Sizing the
                // virtual canvas to exactly `frame width / scale` and
                // anchoring top-left instead means the whole bar, edge to
                // edge, always fits the visible frame at the same 0.32
                // scale, regardless of card size.
                Item {
                    id: previewContent

                    readonly property real previewScale: 0.32

                    scale: previewScale
                    transformOrigin: Item.TopLeft
                    x: root.floats ? (previewFrame.width - width * previewScale) / 2 : 0
                    y: (previewFrame.height - height * previewScale) / 2
                    width: root.floats ? loader.item?.implicitWidth ?? 0 : previewFrame.width / previewScale
                    height: root.floats ? (loader.item?.implicitHeight ?? 0) : root.previewThickness

                    Loader {
                        id: loader
                        anchors.fill: root.floats ? undefined : parent

                        sourceComponent: {
                            switch (root.styleName) {
                            case "dock":
                                return dockComp;
                            case "capsule":
                                return capsuleComp;
                            case "taskbar":
                                return taskbarComp;
                            case "minimal":
                                return minimalComp;
                            default:
                                return fullComp;
                            }
                        }
                    }
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: root.label
                font: Tokens.font.label.medium
                color: root.selected ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: Settings.setBarStyle(root.styleName)
        }
    }

    Component {
        id: fullComp
        Bar {
            screen: Quickshell.screens[0] ?? null
            screenState: previewScreenState
            popouts: previewPopouts
            fullscreen: false
            thickness: root.previewThickness
        }
    }

    Component {
        id: taskbarComp
        TaskbarBar {
            screen: Quickshell.screens[0] ?? null
            screenState: previewScreenState
            popouts: previewPopouts
            fullscreen: false
            thickness: root.previewThickness
        }
    }

    Component {
        id: minimalComp
        MinimalBar {
            screen: Quickshell.screens[0] ?? null
            screenState: previewScreenState
            popouts: previewPopouts
            fullscreen: false
            thickness: root.previewThickness
        }
    }

    Component {
        id: dockComp
        DockBar {
            screen: Quickshell.screens[0] ?? null
            screenState: previewScreenState
        }
    }

    Component {
        id: capsuleComp
        CapsuleBar {
            screen: Quickshell.screens[0] ?? null
            screenState: previewScreenState
        }
    }
}
