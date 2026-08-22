pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Wayland

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
