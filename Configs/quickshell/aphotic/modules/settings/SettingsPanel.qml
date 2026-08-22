import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

RowLayout {
    id: root

    required property ScreenState screenState
    property string currentCategory: "appearance"

    readonly property var categories: [
        { id: "appearance", icon: "palette", label: qsTr("Appearance"), description: qsTr("Theme, wallpaper, colors") },
        { id: "themeCreator", icon: "format_paint", label: qsTr("Theme Creator"), description: qsTr("Build a static custom theme") },
        { id: "personalization", icon: "face", label: qsTr("Personalization"), description: qsTr("Accent, cursor, icons") },
        { id: "bar", icon: "dock_to_bottom", label: qsTr("Bar"), description: qsTr("Position, density") },
        { id: "displays", icon: "monitor", label: qsTr("Displays"), description: qsTr("Resolution, refresh rate") },
        { id: "clock", icon: "schedule", label: qsTr("Clock / Date"), description: qsTr("Format, desktop clock") },
        { id: "osd", icon: "notifications", label: qsTr("OSD / Notifications"), description: qsTr("Sliders, timeouts") },
        { id: "ai", icon: "smart_toy", label: qsTr("AI"), description: qsTr("Provider, API keys") },
        { id: "power", icon: "shield", label: qsTr("Power & Security"), description: qsTr("Profile, idle, lock") },
        { id: "workspaceProfiles", icon: "workspaces", label: qsTr("Workspace Profiles"), description: qsTr("Named one-key launch groups") },
        { id: "system", icon: "monitor_heart", label: qsTr("System"), description: qsTr("Doctor, dependencies") },
        { id: "about", icon: "info", label: qsTr("About"), description: qsTr("Version, credits") }
    ]

    width: 980
    height: 560
    spacing: 0

    StyledRect {
        Layout.fillHeight: true
        Layout.preferredWidth: 300
        radius: Tokens.rounding.extraLarge
        color: Colours.tPalette.m3surfaceContainer

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

        Flickable {
            id: paneFlick

            anchors.fill: parent
            anchors.margins: Tokens.padding.extraLarge
            contentWidth: width
            contentHeight: paneLoader.height
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Loader {
                id: paneLoader

                width: paneFlick.width
                height: Math.max(paneFlick.height, paneLoader.item ? paneLoader.item.implicitHeight : 0)
                opacity: 1

                Behavior on opacity {
                    Anim { type: Anim.DefaultEffects }
                }
                Behavior on x {
                    Anim { type: Anim.Emphasized }
                }

                sourceComponent: {
                    switch (root.currentCategory) {
                    case "themeCreator":
                        return themeCreatorComp;
                    case "personalization":
                        return personalizationComp;
                    case "bar":
                        return barComp;
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
                    case "workspaceProfiles":
                        return workspaceProfilesComp;
                    case "system":
                        return systemComp;
                    case "about":
                        return aboutComp;
                    default:
                        return appearanceComp;
                    }
                }

                onSourceComponentChanged: {
                    const newIndex = root.categories.findIndex(c => c.id === root.currentCategory);
                    const direction = newIndex >= paneSurface._prevCategoryIndex ? 1 : -1;
                    paneSurface._prevCategoryIndex = newIndex;

                    opacity = 0;
                    x = direction * 24;
                    paneFlick.contentY = 0;
                    slideInTimer.restart();
                }

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

            visible: paneFlick.contentHeight > paneFlick.height
            x: paneFlick.x + paneFlick.width - width
            y: paneFlick.y + paneFlick.visibleArea.yPosition * paneFlick.height
            width: 4
            height: Math.max(24, paneFlick.visibleArea.heightRatio * paneFlick.height)
            radius: Tokens.rounding.full
            color: Colours.palette.m3onSurfaceVariant
            opacity: 0.35
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
        id: barComp
        BarPane {}
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
        id: workspaceProfilesComp
        WorkspaceProfilesPane {}
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
