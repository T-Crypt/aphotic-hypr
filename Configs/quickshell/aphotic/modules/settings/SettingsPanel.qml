import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

RowLayout {
    id: root

    required property ScreenState screenState
    property string currentCategory: "appearance"

    // Wallpaper auto-cycle (services/WallpaperCycle.qml) pauses while this
    // is true -- centralized here rather than on the panes themselves,
    // since paneLoader (below) has no `active:` guard and stays mounted
    // on whatever category was last shown even after the Settings window
    // itself closes, so a pane's own Component.onCompleted/onDestruction
    // would only fire on category switches, not on the window actually
    // closing while still on Appearance/Theme Creator.
    readonly property bool _showingWallpaperPane: root.currentCategory === "appearance" || root.currentCategory === "themeCreator"

    Binding {
        target: UiPickerState
        property: "active"
        value: root.screenState.settings && root._showingWallpaperPane
    }

    // Hoisted to config/SettingsCategories.qml so the launcher's "?"
    // settings-search mode can search the same list without a second,
    // driftable copy.
    readonly property var categories: SettingsCategories.list

    // Non-null when the selected category is a plugin's own pane. The
    // panel knows that plugin panes exist; it does not know that any
    // particular plugin does.
    readonly property var _pluginCategory: root.categories.find(c => c.id === root.currentCategory && c.componentUrl) ?? null

    onCategoriesChanged: {
        if (!root.categories.some(c => c.id === root.currentCategory))
            root.currentCategory = "appearance";
    }

    // Was 980x560 -- fixed since this panel first shipped with 5-6
    // categories; 14 exist now (SettingsCategories.list) and several
    // panes (AI, Network, Personalization) have grown dense enough that
    // the old size left everything visibly cramped. Bumped, still a
    // fixed size rather than screen-relative -- comfortably fits inside
    // even this repo's smallest documented target (1920x1080) with
    // margin, without needing per-screen sizing logic.
    width: 1180
    height: 720
    spacing: 0

    StyledRect {
        id: rail

        Layout.fillHeight: true
        Layout.preferredWidth: 300
        radius: Tokens.rounding.extraLarge
        color: Colours.tPalette.m3surfaceContainer

        DepthLayer {
            anchors.fill: parent
            opacityScale: 0.5
        }

        DepthGradient {
            anchors.fill: parent
            radius: rail.radius
            baseColour: rail.color
        }

        CategoryRail {
            anchors.fill: parent
            anchors.margins: Tokens.padding.extraLarge
            currentCategory: root.currentCategory
            categories: root.categories
            onCategorySelected: id => root.currentCategory = id
        }
    }

    StyledRect {
        id: paneSurface

        Layout.fillHeight: true
        Layout.fillWidth: true
        Layout.leftMargin: Tokens.spacing.medium
        radius: Tokens.rounding.extraLarge
        color: Colours.tPalette.m3surfaceContainer
        clip: true

        property int _prevCategoryIndex: 0

        // Shared by both pane loaders. paneLoader.sourceComponent goes
        // null for every plugin category, so switching between two
        // plugin panes never changes it and would otherwise skip the
        // slide entirely.
        function beginSlide(): void {
            const newIndex = root.categories.findIndex(c => c.id === root.currentCategory);
            const direction = newIndex >= paneSurface._prevCategoryIndex ? 1 : -1;
            paneSurface._prevCategoryIndex = newIndex;

            paneLoader.opacity = 0;
            paneLoader.x = direction * 24;
            paneFlick.contentY = 0;
            slideInTimer.restart();
        }

        DepthGradient {
            anchors.fill: parent
            radius: paneSurface.radius
            baseColour: paneSurface.color
        }

        Flickable {
            id: paneFlick

            anchors.fill: parent
            anchors.margins: Tokens.padding.extraLarge
            contentWidth: width
            contentHeight: paneFlick.activePane.height
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            // The active pane, whichever loader built it -- core panes
            // come from the switch below, a plugin's pane from a
            // file:// URL out of the registry. Height and the slide
            // animation read this rather than either loader, so a
            // plugin pane behaves exactly like a core one.
            readonly property Item activePane: root._pluginCategory ? pluginPaneLoader : paneLoader

            Loader {
                id: pluginPaneLoader

                width: paneFlick.width
                height: Math.max(paneFlick.height, pluginPaneLoader.item ? pluginPaneLoader.item.implicitHeight : 0)
                active: root._pluginCategory !== null
                asynchronous: true
                visible: pluginPaneLoader.active
                opacity: paneLoader.opacity
                x: paneLoader.x
                source: root._pluginCategory?.componentUrl ?? ""

                onSourceChanged: {
                    if (pluginPaneLoader.source != "")
                        paneSurface.beginSlide();
                }
            }

            Loader {
                id: paneLoader

                width: paneFlick.width
                height: Math.max(paneFlick.height, paneLoader.item ? paneLoader.item.implicitHeight : 0)
                visible: root._pluginCategory === null
                opacity: 1

                Behavior on opacity {
                    Anim { type: Anim.DefaultEffects }
                }
                Behavior on x {
                    Anim { type: Anim.Emphasized }
                }

                sourceComponent: {
                    if (root._pluginCategory)
                        return null;
                    switch (root.currentCategory) {
                    case "themeCreator":
                        return themeCreatorComp;
                    case "personalization":
                        return personalizationComp;
                    case "language":
                        return languageComp;
                    case "bar":
                        return barComp;
                    case "launcher":
                        return launcherComp;
                    case "displays":
                        return displaysComp;
                    case "clock":
                        return clockComp;
                    case "osd":
                        return osdComp;
                    case "ai":
                        return aiComp;
                    case "power":
                        return powerComp;
                    case "network":
                        return networkComp;
                    case "workspaceProfiles":
                        return workspaceProfilesComp;
                    case "plugins":
                        return pluginsComp;
                    case "system":
                        return systemComp;
                    case "advanced":
                        return advancedComp;
                    case "about":
                        return aboutComp;
                    default:
                        return appearanceComp;
                    }
                }

                onSourceComponentChanged: paneSurface.beginSlide()

                Timer {
                    id: slideInTimer
                    interval: 1
                    onTriggered: {
                        paneLoader.opacity = 1;
                        paneLoader.x = 0;
                    }
                }
            }
        }

        StyledRect {
            id: scrollThumb

            // Was 4px with no MouseArea at all -- just a scroll-position
            // indicator, not actually grabbable. Widened to a real click
            // target and made draggable (real ask: "hard to grab... and
            // use it without my scroll wheel"). Drag math sets
            // paneFlick.contentY directly from the mouse delta rather
            // than binding drag.target to this item -- QML's drag
            // mechanics overwrite a bound `y` with a plain value on
            // press, which would have permanently broken the one-way
            // binding below after the first drag.
            visible: paneFlick.contentHeight > paneFlick.height
            x: paneFlick.x + paneFlick.width - width
            y: paneFlick.y + paneFlick.visibleArea.yPosition * paneFlick.height
            width: 8
            height: Math.max(24, paneFlick.visibleArea.heightRatio * paneFlick.height)
            radius: Tokens.rounding.full
            color: Colours.palette.m3onSurfaceVariant
            opacity: dragArea.pressed ? 0.7 : dragArea.containsMouse ? 0.55 : 0.35

            Behavior on opacity {
                Anim { type: Anim.StandardSmall }
            }

            MouseArea {
                id: dragArea

                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                preventStealing: true

                property real pressY: 0
                property real pressContentY: 0

                onPressed: mouse => {
                    pressY = mapToItem(paneFlick, mouse.x, mouse.y).y;
                    pressContentY = paneFlick.contentY;
                }
                onPositionChanged: mouse => {
                    if (!pressed)
                        return;
                    const trackHeight = paneFlick.height - scrollThumb.height;
                    if (trackHeight <= 0)
                        return;
                    const scrollable = paneFlick.contentHeight - paneFlick.height;
                    const deltaY = mapToItem(paneFlick, mouse.x, mouse.y).y - pressY;
                    const deltaContent = deltaY / trackHeight * scrollable;
                    paneFlick.contentY = Math.max(0, Math.min(scrollable, pressContentY + deltaContent));
                }
            }
        }
    }

    Component {
        id: appearanceComp
        AppearancePane {}
    }
    Component {
        id: themeCreatorComp
        ThemeCreatorPane {}
    }

    Component {
        id: personalizationComp
        PersonalizationPane {}
    }
    Component {
        id: languageComp
        LanguagePane {}
    }
    Component {
        id: barComp
        BarPane {}
    }
    Component {
        id: launcherComp
        LauncherPane {}
    }
    Component {
        id: displaysComp
        DisplaysPane {}
    }
    Component {
        id: clockComp
        ClockPane {}
    }
    Component {
        id: osdComp
        OsdPane {}
    }
    Component {
        id: aiComp
        AiPane {}
    }
    Component {
        id: powerComp
        PowerSecurityPane {}
    }
    Component {
        id: networkComp
        NetworkPane {}
    }
    Component {
        id: workspaceProfilesComp
        WorkspaceProfilesPane {}
    }
    Component {
        id: pluginsComp
        PluginsPane {}
    }
    Component {
        id: systemComp
        SystemPane {}
    }
    Component {
        id: advancedComp
        AdvancedPane {}
    }
    Component {
        id: aboutComp
        AboutPane {}
    }
}
