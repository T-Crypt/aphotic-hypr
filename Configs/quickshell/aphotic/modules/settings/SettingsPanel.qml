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
    // on a plugin's section arrives as "<category>/<section>", a hit on a
    // setting row as "<category>/<section>/<row>" (the section empty for a
    // core pane row), which is also the id searchIndex hands the launcher,
    // so the same string survives the ScreenState.settingsCategory handoff
    // untouched.
    readonly property string currentCategoryId: root.currentCategory.split("/")[0]
    property string requestedSection: ""
    property string requestedRow: ""
    property var _highlightedRow: null
    property int _rowAttempts: 0

    readonly property var sections: SettingsCategories.sectionsFor(root.currentCategoryId)

    onCurrentCategoryChanged: {
        const parts = root.currentCategory.split("/");
        root.requestedSection = parts.length > 1 ? parts[1] : "";
        root.requestedRow = parts.length > 2 ? parts[2] : "";
        root._clearHighlight();
        root._rowAttempts = 0;
        if (root.requestedSection !== "" || root.requestedRow !== "")
            revealTimer.restart();
    }

    // A search hit can name a row instead of a section. The row components
    // carry the address as `searchId` (components/SettingsRow.qml), so the
    // pane is found by walking the loaded tree rather than every pane
    // wiring its own registry. A row inside a collapsed inline section has
    // no instance yet; opening the sections and retrying is the one case
    // that needs a second pass.
    function _findRow(item: var, rowId: string): var {
        if (!item || !item.children)
            return null;
        for (const child of item.children) {
            if (child.searchId !== undefined && child.searchId === rowId)
                return child;
            const found = root._findRow(child, rowId);
            if (found)
                return found;
        }
        return null;
    }

    function _expandSections(item: var): void {
        if (!item || !item.children)
            return;
        for (const child of item.children) {
            if (typeof child.expanded === "boolean" && child.content !== undefined && !child.expanded)
                child.expanded = true;
            root._expandSections(child);
        }
    }

    // The panel owns the one mark a search hit leaves. Clearing it here,
    // before the reference drops, keeps a row from a previous hit marked
    // when the next hit lands in the same category (whose address change
    // never rebuilds the pane, so the old row survives to be seen).
    function _clearHighlight(): void {
        if (root._highlightedRow && root._highlightedRow.highlighted !== undefined)
            root._highlightedRow.highlighted = false;
        root._highlightedRow = null;
    }

    function _revealRow(): void {
        root._clearHighlight();
        if (root.requestedRow === "" || !paneLoader.item)
            return;
        const row = root._findRow(paneLoader.item, root.requestedRow);
        if (!row) {
            if (root._rowAttempts < 2) {
                root._rowAttempts += 1;
                root._expandSections(paneLoader.item);
                rowRetryTimer.restart();
            }
            return;
        }
        root._highlightedRow = row;
        row.highlighted = true;
        paneFlick.revealItem(row);
    }

    onCategoriesChanged: {
        if (!root.categories.some(c => c.id === root.currentCategoryId))
            root.currentCategory = "appearance";
    }

    // Fixed size, not screen-relative: 14 categories and several dense
    // panes need the room, and it still fits the smallest supported
    // target (1920x1080) with margin.
    width: 1180
    height: 720
    spacing: 0

    StyledRect {
        id: rail

        Layout.fillHeight: true
        Layout.preferredWidth: 300
        radius: Tokens.rounding.large
        color: Colours.signalStyle.base

        Elevation {
            target: parent
            level: 2
        }

        DepthLayer {
            anchors.fill: parent
            opacityScale: 0.5
        }

        DepthGradient {
            anchors.fill: parent
            visible: false
            radius: rail.radius
            baseColour: rail.color
        }

        GradedOutline {
            radius: rail.radius
            level: 0
        }

        CategoryRail {
            anchors.fill: parent
            anchors.margins: Tokens.padding.extraLarge
            currentCategory: root.currentCategoryId
            categories: root.categories
            searchIndex: SettingsCategories.searchIndex
            onCategorySelected: (id, sectionId, rowId) => {
                const parts = [id];
                if (sectionId.length > 0 || rowId.length > 0)
                    parts.push(sectionId);
                if (rowId.length > 0)
                    parts.push(rowId);
                root.currentCategory = parts.join("/");
            }
        }
    }

    StyledRect {
        id: paneSurface

        Layout.fillHeight: true
        Layout.fillWidth: true
        Layout.leftMargin: Tokens.spacing.medium
        radius: Tokens.rounding.large
        color: Colours.signalStyle.surface
        // The Flickable inside already clips the sliding content; the
        // Signal skin needs the shadow to fall outside the pane.
        clip: false

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
            visible: false
            radius: paneSurface.radius
            baseColour: paneSurface.color
        }

        Elevation {
            target: parent
            level: 2
        }

        GradedOutline {
            radius: paneSurface.radius
            level: 0
        }

        // Accent glow falling from the top of the pane, behind its header.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 1
            height: 200
            topLeftRadius: paneSurface.radius
            topRightRadius: paneSurface.radius
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.alpha(Colours.signal, 0.1)
                }
                GradientStop {
                    position: 1
                    color: Qt.alpha(Colours.signal, 0)
                }
            }
        }

        Flickable {
            id: paneFlick

            anchors.fill: parent
            anchors.margins: Tokens.padding.extraLarge
            contentWidth: width
            contentHeight: paneColumn.height
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            function revealItem(item: Item): void {
                const limit = Math.max(0, paneFlick.contentHeight - paneFlick.height);
                paneFlick.contentY = Math.min(limit, Math.max(0, item.mapToItem(paneColumn, 0, 0).y));
            }

            function revealSection(sectionId: string): void {
                for (let i = 0; i < sectionRepeater.count; i++) {
                    const item = sectionRepeater.itemAt(i);
                    if (item?.modelData?.id !== sectionId)
                        continue;
                    paneFlick.revealItem(item);
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

                    // A ColumnLayout taller than its content spreads the
                    // slack between its children, which scattered short
                    // panes down the viewport. Only a pane that holds a
                    // list sized to the viewport opts in with fillViewport.
                    readonly property bool fills: paneLoader.item?.fillViewport ?? false

                    Layout.fillWidth: true
                    Layout.fillHeight: paneLoader.fills
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
                        case "sonar":
                            return sonarComp;
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
                    color: Colours.inkMuted
                    font: Tokens.font.label.builders.medium.weight(Font.DemiBold).build()
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

                Item {
                    Layout.fillHeight: !paneLoader.fills
                }
            }
        }

        // Shade under the top edge once content has scrolled beneath it.
        Rectangle {
            anchors.left: paneFlick.left
            anchors.right: paneFlick.right
            anchors.top: paneFlick.top
            height: 14
            opacity: paneFlick.contentY > 1 ? 1 : 0
            gradient: Gradient {
                GradientStop {
                    position: 0
                    color: Qt.alpha(Colours.shadow, 0.35)
                }
                GradientStop {
                    position: 1
                    color: Qt.alpha(Colours.shadow, 0)
                }
            }

            Behavior on opacity {
                Anim { type: Anim.DefaultEffects }
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
            onTriggered: {
                paneFlick.revealSection(root.requestedSection);
                root._revealRow();
            }
        }

        Timer {
            id: rowRetryTimer

            interval: 32
            onTriggered: root._revealRow()
        }

        StyledRect {
            id: scrollThumb

            // Drag math sets paneFlick.contentY directly from the mouse
            // delta rather than binding drag.target to this item -- QML's
            // drag mechanics overwrite a bound `y` with a plain value on
            // press, which would have permanently broken the one-way
            // binding below after the first drag.
            visible: paneFlick.contentHeight > paneFlick.height
            x: paneFlick.x + paneFlick.width - width
            y: paneFlick.y + paneFlick.visibleArea.yPosition * paneFlick.height
            width: 8
            height: Math.max(24, paneFlick.visibleArea.heightRatio * paneFlick.height)
            radius: Tokens.rounding.full
            color: Colours.inkMuted
            opacity: dragArea.pressed ? 0.7 : dragArea.containsMouse ? 0.55 : 0.35

            Behavior on opacity {
                Anim { type: Anim.StandardSmall }
            }

            MouseArea {
                id: dragArea

                anchors.fill: parent
                anchors.margins: -Tokens.padding.extraSmall
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
        BarPane {
            screenState: root.screenState
        }
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
        id: sonarComp
        SonarPane {
            screenState: root.screenState
        }
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
