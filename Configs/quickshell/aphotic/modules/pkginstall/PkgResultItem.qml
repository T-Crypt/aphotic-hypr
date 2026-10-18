pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Item {
    id: root

    required property var modelData
    required property ScreenState screenState

    width: ListView.view?.width ?? 0
    implicitHeight: Tokens.sizes.launcher.itemHeight

    function execute(): void {
        PkgSearch.install(root.modelData.name);
        root.screenState.pkgInstall = false;
    }

    Interact {
        radius: Tokens.rounding.large
        onClicked: root.execute()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        spacing: Tokens.spacing.medium

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            RowLayout {
                spacing: Tokens.spacing.small

                StyledText {
                    text: root.modelData.name
                    font: Tokens.font.body.medium
                    color: Colours.ink
                    elide: Text.ElideRight
                }

                StyledRect {
                    Layout.preferredWidth: repoLabel.implicitWidth + Tokens.padding.small * 2
                    Layout.preferredHeight: repoLabel.implicitHeight + Tokens.padding.extraSmall
                    radius: Tokens.rounding.full
                    color: root.modelData.isAur ? Colours.signalTertiary : Colours.chip

                    StyledText {
                        id: repoLabel
                        anchors.centerIn: parent
                        text: root.modelData.isAur ? qsTr("AUR") : root.modelData.repo
                        font: Tokens.font.label.small
                        color: root.modelData.isAur ? Colours.contrastOn(Colours.signalTertiary) : Colours.chipInk
                    }
                }

                StyledText {
                    visible: root.modelData.installed
                    text: qsTr("Installed")
                    font: Tokens.font.label.small
                    color: Colours.signalSecondary
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: root.modelData.description
                font: Tokens.font.body.small
                color: Colours.inkMuted
                elide: Text.ElideRight
            }
        }
    }
}
