import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

Item {
    id: root

    implicitWidth: Math.max(180, layout.implicitWidth + Tokens.padding.large * 2)
    implicitHeight: layout.implicitHeight + Tokens.padding.large * 2

    ColumnLayout {
        id: layout

        anchors.centerIn: parent
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Tokens.spacing.small

            MaterialIcon {
                text: Weather.conditionIcon
                color: Colours.palette.m3secondary
                fontStyle: Tokens.font.icon.large
            }

            StyledText {
                visible: Weather.hasData
                text: `${Math.round(Weather.currentTemp)}°${Settings.weatherUnits === "fahrenheit" ? "F" : "C"}`
                color: Colours.palette.m3onSurface
                font: Tokens.font.headline.builders.large.scale(1.1).weight(Font.DemiBold).build()
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            visible: !Weather.hasData
            text: Weather.errorText.length > 0 ? Weather.errorText : qsTr("Loading weather…")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            Layout.maximumWidth: 160
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            visible: Weather.hasData
            text: Weather.conditionText
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.medium
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            visible: Weather.hasData && Weather.resolvedLocationName.length > 0
            text: Weather.resolvedLocationName
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.label.small
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacing.small
            visible: Weather.hasData && Weather.forecast.length > 0
            spacing: Tokens.spacing.medium

            Repeater {
                model: Weather.forecast

                ColumnLayout {
                    required property var modelData

                    spacing: Tokens.spacing.extraSmall / 2

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Qt.formatDate(new Date(parent.modelData.day), "ddd")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: Weather._iconFor(parent.modelData.code)
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: `${Math.round(parent.modelData.high)}°/${Math.round(parent.modelData.low)}°`
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.small
                    }
                }
            }
        }
    }
}
