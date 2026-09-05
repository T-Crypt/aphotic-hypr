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
    readonly property bool _showingWallpaperPane: root.currentCategoryId === "appearance" || root.currentCategoryId === "themeCreator"

    Binding {
        target: UiPickerState
        property: "active"
        value: root.screenState.settings && root._showingWallpaperPane
    }

    // Hoisted to config/SettingsCategories.qml so the rail's search box
    // and the launcher's "?" settings-search mode can index the same pane
    // set without a second, driftable copy.
    readonly property var categories: SettingsCategories.list

    // currentCategory is an address, not just a category id: a search hit
    // on a plugin's section arrives as "<category>/<section>", which is
    // also the id searchIndex hands the launcher, so the same string
    // survives the ScreenState.settingsCategory handoff untouched.
    readonly property string currentCategoryId: root.currentCategory.split("/")[0]
    property string requestedSection: ""

    readonly property var sections: SettingsCategories.sectionsFor(root.currentCategoryId)

    onCurrentCategoryChanged: {
        const parts = root.currentCategory.split("/");
        root.requestedSection = parts.length > 1 ? parts[1] : "";
        if (root.requestedSection !== "")
            revealTimer.restart();
    }

    onCategoriesChanged: {
        if (!root.categories.some(c => c.id === root.currentCategoryId))
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
            currentCategory: root.currentCategoryId
            categories: root.categories
            searchIndex: SettingsCategories.searchIndex
            onCategorySelected: (id, sectionId) => root.currentCategory = sectionId.length > 0 ? `${id}/${sectionId}` : id
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

        function beginSlide(): void {
            const newIndex = root.categories.findIndex(c => c.id === root.currentCategoryId);
            const direction = newIndex >= paneSurface._prevCategoryIndex ? 1 : -1;
            paneSurface._prevCategoryIndex = newIndex;

            paneColumn.opacity = 0;
            paneColumn.x = direction * 24;
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
            contentHeight: paneColumn.height
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            function revealSection(sectionId: string): void {
                for (let i = 0; i < sectionRepeater.count; i++) {
                    const item = sectionRepeater.itemAt(i);
                    if (item?.modelData?.id !== sectionId)
                        continue;
                    const limit = Math.max(0, paneFlick.contentHeight - paneFlick.height);
                    paneFlick.contentY = Math.min(limit, Math.max(0, item.mapToItem(paneColumn, 0, 0).y));
                    return;
                }
            }

            ColumnLayout {
                id: paneColumn

                width: paneFlick.width
                // Takes the viewport's slack itself and lets paneLoader
                // absorb it, so a self-centring pane keeps working when
                // its category gains a plugin section. Reads its own
                // implicitHeight, which is derived from children's
                // implicit sizes and not from this height, so there is no
                // cycle here.
                height: Math.max(implicitHeight, paneFlick.height)
                spacing: Tokens.spacing.small
                opacity: 1

                Behavior on opacity {
                    Anim { type: Anim.DefaultEffects }
                }
                Behavior on x {
                    Anim { type: Anim.Emphasized }
                }

                Loader {
                    id: paneLoader

                    Layout.fillWidth: true
                    // The only fillHeight child, so it takes whatever the
                    // sections below leave -- About, Launcher and
                    // Appearance distribute that slack with their own
                    // fillHeight spacers. Stretching the pane to the whole
                    // viewport instead would push the first section header
                    // a screen down; giving it only its natural height
                    // collapsed those panes' centring the moment a plugin
                    // docked a section into their category.
                    Layout.fillHeight: true
                    Layout.preferredHeight: paneLoader.item?.implicitHeight ?? 0

                    sourceComponent: {
                        switch (root.currentCategoryId) {
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
                        case "about":
                            return aboutComp;
                        default:
                            return appearanceComp;
                        }
                    }

                    onSourceComponentChanged: paneSurface.beginSlide()
                }

                StyledText {
                    visible: root.sections.length > 0
                    Layout.topMargin: Tokens.spacing.large
                    Layout.leftMargin: Tokens.padding.small
                    text: qsTr("Plugins")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.medium
                }

                Repeater {
                    id: sectionRepeater

                    model: root.sections

                    SettingsSection {
                        id: section

                        required property var modelData

                        readonly property bool matched: root.requestedSection === section.modelData.id

                        Layout.fillWidth: true
                        icon: section.modelData.icon
                        label: section.modelData.label
                        description: section.modelData.description
                        source: section.modelData.componentUrl
                        highlighted: section.matched

                        onMatchedChanged: {
                            if (section.matched)
                                section.expanded = true;
                        }

                        Component.onCompleted: {
                            if (section.matched)
                                section.expanded = true;
                        }
                    }
                }
            }
        }

        Timer {
            id: slideInTimer

            interval: 1
            onTriggered: {
                paneColumn.opacity = 1;
                paneColumn.x = 0;
            }
        }

        // Runs after the category switch has rebuilt the pane and the
        // section rows, since the target row has no position until then.
        Timer {
            id: revealTimer

            interval: 32
            onTriggered: paneFlick.revealSection(root.requestedSection)
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
        PluginsPane {
            screenState: root.screenState
        }
    }
    Component {
        id: systemComp
        SystemPane {}
    }
    Component {
        id: aboutComp
        AboutPane {}
    }
}
