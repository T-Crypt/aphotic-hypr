pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "MessagePolicy.js" as Policy

// The SMS side of the phone stack, behind Settings.phoneMessages. It owns
// the in-memory thread store only: one list of entries per device id, each
// entry carrying address, body, timestamp, and direction. Sends go through
// the guarded kdeconnect-cli below, one at a time, and receive arrives
// through addIncoming, which the daemon listener will call once its signal
// is observed on paired hardware. No Timer and no polling.
Singleton {
    id: root

    readonly property bool enabled: Settings.phoneMessages
    // The bridge owns reachability, so a message surface cannot appear
    // where the device list does not.
    readonly property bool available: root.enabled && Phone.available

    property var threads: ({})
    property bool toolPresent: false
    property string lastError: ""
    property int spawns: 0

    property var _queue: []

    function threadsFor(deviceId: string): var {
        return root.threads[deviceId] ?? [];
    }

    function _append(entry: var): void {
        const list = root.threads[entry.deviceId] ?? [];
        const next = {};
        for (const key in root.threads)
            next[key] = root.threads[key];
        next[entry.deviceId] = [...list, entry];
        root.threads = next;
    }

    // The daemon listener's way in. Rejects anything short of a full
    // triple, so an unobserved payload shape can only add nothing, never
    // a half entry.
    function addIncoming(deviceId: string, address: string, body: string, timestamp: real): var {
        const entry = Policy.parseIncoming({ deviceId, address, body, timestamp });
        if (!entry)
            return null;
        root._append(entry);
        return entry;
    }

    function sendSms(deviceId: string, destination: string, body: string): void {
        // The flag gate, checked before any argv or queue work, so a
        // send with the surface off spawns nothing and stores nothing.
        // Reachability stays out of this check on purpose: the bridge
        // scan settles async, and a send with both flags on must still
        // run so its exit code can surface through lastError below.
        if (!root.enabled || !Phone.enabled)
            return;
        const args = Policy.buildSendArgs(deviceId, destination, body);
        if (args.length === 0)
            return;
        const d = String(deviceId ?? "").trim();
        const to = String(destination ?? "").trim();
        const text = String(body ?? "").trim();
        root._queue = [...root._queue, { deviceId: d, destination: to, body: text }];
        root._kick();
    }

    function _kick(): void {
        if (sender.running || root._queue.length === 0)
            return;
        const head = root._queue[0];
        const args = Policy.buildSendArgs(head.deviceId, head.destination, head.body);
        root.spawns += 1;
        // `command -v` before the launch, so a machine without KDE Connect
        // exits 127 instead of failing to start. That is what keeps the
        // package out of both base profiles: tests/test_profiles_shell_deps.py
        // treats a binary behind its own guard as optional by design. The
        // braces keep the guard's own exit code out of that same scan, which
        // reads the first word of every shell segment as a binary name.
        // "$@" carries the argv past the shell with no quoting, so a body
        // containing quotes cannot break the command.
        sender.exec(["sh", "-c", "command -v kdeconnect-cli >/dev/null 2>&1 || { exit 127; }; exec kdeconnect-cli \"$@\"", "sh"].concat(args));
    }

    Process {
        id: sender

        onExited: (code, status) => {
            const head = root._queue.length > 0 ? root._queue[0] : null;
            root._queue = root._queue.slice(1);
            root.toolPresent = code !== 127;
            root.lastError = code === 0 ? "" : String(code);
            if (code === 0 && head) {
                root._append({
                    deviceId: head.deviceId,
                    address: head.destination,
                    body: head.body,
                    timestamp: Date.now(),
                    direction: "out"
                });
            }
            root._kick();
        }
    }
}
