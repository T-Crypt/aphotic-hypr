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
        { id: "appearance", icon: "palette", label: qsTr("Appearance") },
        { id: "bar", icon: "dock_to_bottom", label: qsTr("Bar") },
        { id: "clock", icon: "schedule", label: qsTr("Clock / Date") },
        { id: "osd", icon: "notifications", label: qsTr("OSD / Notifications") },
        { id: "system", icon: "monitor_heart", label: qsTr("System") },
        { id: "about", icon: "info", label: qsTr("About") }
    ]

    width: 720
    height: 480
    spacing: 0

    StyledRect {
        Layout.fillHeight: true
        Layout.preferredWidth: 200
        radius: Tokens.rounding.extraLarge
        color: Colours.tPalette.m3surfaceContainer

        CategoryRail {
            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            currentCategory: root.currentCategory
            categories: root.categories
            onCategorySelected: id => root.currentCategory = id
        }
    }

    StyledRect {
        Layout.fillHeight: true
        Layout.fillWidth: true
        Layout.leftMargin: Tokens.spacing.medium
        radius: Tokens.rounding.extraLarge
        color: Colours.tPalette.m3surfaceContainer

        Loader {
            id: paneLoader

            anchors.fill: parent
            anchors.margins: Tokens.padding.large
            opacity: 1

            Behavior on opacity {
                Anim { type: Anim.DefaultEffects }
            }

            sourceComponent: {
                switch (root.currentCategory) {
                case "bar":
                    return barComp;
                case "clock":
                    return clockComp;
                case "osd":
                    return osdComp;
                case "system":
                    return systemComp;
                case "about":
                    return aboutComp;
                default:
                    return appearanceComp;
                }
            }

            onSourceComponentChanged: {
                opacity = 0;
                fadeInTimer.restart();
            }

            Timer {
                id: fadeInTimer
                interval: 1
                onTriggered: paneLoader.opacity = 1
            }
        }
    }

    Component {
        id: appearanceComp
        AppearancePane {}
    }
    Component {
        id: barComp
        BarPane {}
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
        id: systemComp
        SystemPane {}
    }
    Component {
        id: aboutComp
        AboutPane {}
    }
}
