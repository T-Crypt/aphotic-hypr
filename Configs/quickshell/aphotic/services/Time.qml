pragma Singleton

import QtQuick
import Quickshell
import qs.config

Singleton {
    property alias enabled: secondsClock.enabled
    readonly property date date: secondsClock.date
    readonly property int hours: minuteClock.hours
    readonly property int minutes: minuteClock.minutes
    readonly property int seconds: secondsClock.seconds

    readonly property string timeStr: format(Settings.twelveHourClock ? "hh:mm:A" : "hh:mm")
    readonly property list<string> timeComponents: timeStr.split(":")
    readonly property string hourStr: timeComponents[0] ?? ""
    readonly property string minuteStr: timeComponents[1] ?? ""
    readonly property string amPmStr: timeComponents[2] ?? ""

    function format(fmt: string): string {
        return Qt.formatDateTime(fmt.includes("s") ? secondsClock.date : minuteClock.date, fmt);
    }

    SystemClock {
        id: secondsClock

        precision: SystemClock.Seconds
    }

    SystemClock {
        id: minuteClock

        enabled: secondsClock.enabled
        precision: SystemClock.Minutes
    }
}
