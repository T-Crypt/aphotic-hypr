pragma Singleton

import QtQuick

// Mirrors modules/lock/Lock.qml's WlSessionLock.locked, kept in a real
// singleton so other services (the wallpaper auto-cycle timer) can react
// to it without needing a direct reference to that Scope's instance.
// Lock.qml maintains this via a plain Binding to lock.locked -- a
// Connections/onLockedChanged handler reading lock.locked back out
// intermittently observed a stale value at fire time (real signal-
// ordering quirk in WlSessionLock, not a typo); a direct binding sidesteps
// that entirely since it just always reflects the current value.
QtObject {
    property bool locked: false
}
