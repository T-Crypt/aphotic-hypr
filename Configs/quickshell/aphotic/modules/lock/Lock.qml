pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services

Scope {
    id: root

    property alias lock: lock

    WlSessionLock {
        id: lock

        LockSurface {
            lock: lock
            pam: pam
        }
    }

    // Polled rather than bound to lock.onLockedChanged/a live Binding --
    // both were tried and both stuck at the initial value: WlSessionLock's
    // change notification does not reliably fire for every path that sets
    // `locked` (verified live: a direct `isLocked()` read always returns
    // the correct current value, but neither a Connections handler nor a
    // Binding on the same property ever observed it changing). A real
    // Quickshell-side quirk, not fixable from here -- 500ms of staleness
    // is entirely fine for what this drives (pausing the wallpaper
    // auto-cycle timer), so polling sidesteps it rather than chasing a
    // native fix.
    Timer {
        interval: 500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: SessionLockState.locked = lock.locked
    }

    Pam {
        id: pam

        lock: lock
    }

    IpcHandler {
        target: "lock"

        function engage(): void {
            root.lock.locked = true;
        }

        function unlock(): void {
            root.lock.locked = false;
        }

        function isLocked(): bool {
            return root.lock.locked;
        }
    }
}
