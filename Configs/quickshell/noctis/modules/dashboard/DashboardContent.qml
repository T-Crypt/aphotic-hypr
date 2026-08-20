import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components
import qs.services

RowLayout {
    id: root

    spacing: Tokens.spacing.medium

    component Card: StyledRect {
        radius: Tokens.rounding.extraLarge
        color: Colours.tPalette.m3surfaceContainer
    }

    Card {
        Layout.preferredWidth: dateTime.implicitWidth
        Layout.preferredHeight: dateTime.implicitHeight

        DashDateTime {
            id: dateTime
        }
    }

    Card {
        Layout.preferredWidth: calendar.implicitWidth
        Layout.preferredHeight: calendar.implicitHeight

        DashCalendar {
            id: calendar
        }
    }

    Card {
        Layout.preferredWidth: media.implicitWidth
        Layout.preferredHeight: media.implicitHeight

        DashMedia {
            id: media
        }
    }
}
