pragma Singleton

import QtQuick
import Quickshell
import qs.config

// Runtime-only user-toggleable settings -- session-scoped, not persisted
// (this repo has no settings-persistence layer yet, matching the same
// limitation already noted for the launcher's style options). Distinct
// from config/Config.qml, which holds compile-time-ish static defaults;
// these are the subset a user can actually flip live from the bar's
// settings popout.
Singleton {
    id: root

    property bool twelveHourClock: GlobalConfig.services.useTwelveHourClock
    property bool showClockDate: Config.bar.clock.showDate
    property bool barPersistent: Config.bar.persistent
    property bool desktopClockEnabled: Config.background.desktopClock.enabled
}
