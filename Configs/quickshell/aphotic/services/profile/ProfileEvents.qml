pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.services.profile

// The fan-out point between event sources the shell already has and
// whatever wants to react to them. Not a new event mechanism: the
// compositor half is fed by Hypr.qml's existing Connections on Hyprland's
// raw event stream (Hypr re-emits as `rawEvent`), and the substrate half
// is fed by ProfileEngine's and ResourceEngine's own signals. Nothing here
// opens a socket, spawns a process or runs a timer.
//
// A domain plugin that watches something core has no business knowing
// about (a game launcher, a container runtime, a harness hook's event log)
// owns that watcher itself and publish()es into this bus, so subscribers
// see one stream regardless of where an event came from.
//
// Zero-cost when unused is structural, not a promise: every Connections
// below is disabled while there are no subscribers, so with no opt-in
// profile installed this singleton is not connected to anything and the
// compositor's event stream reaches nothing.
Singleton {
    id: root

    readonly property var kinds: ["compositor.raw", "window.open", "window.close", "window.focus", "workspace.focus", "monitor.change", "profile.phase", "profile.anomaly", "resource.claim", "resource.negotiation"]

    readonly property int subscriberCount: root._subs.length
    readonly property bool idle: root._subs.length === 0
    readonly property var lastEvent: root._lastEvent

    signal event(kind: string, payload: var)

    property var _subs: []
    property var _lastEvent: null
    property int _nextToken: 1

    // wanted: array of kind strings, or [] / "*" for everything.
    function subscribe(owner: string, wanted: var, callback: var): int {
        if (typeof callback !== "function") {
            console.warn(`ProfileEvents: subscribe('${owner}') needs a callback`);
            return 0;
        }
        const token = root._nextToken;
        root._nextToken = token + 1;
        const selected = (wanted === "*" || !Array.isArray(wanted)) ? [] : wanted.slice();
        root._subs = root._subs.concat([{
            token: token,
            owner: String(owner),
            kinds: selected,
            callback: callback
        }]);
        return token;
    }

    function unsubscribe(token: int): void {
        root._subs = root._subs.filter(s => s.token !== token);
    }

    function unsubscribeOwner(owner: string): void {
        root._subs = root._subs.filter(s => s.owner !== owner);
    }

    function publish(kind: string, payload: var): void {
        if (root._subs.length === 0)
            return;

        const record = {
            kind: kind,
            at: Date.now(),
            payload: payload ?? ({})
        };
        root._lastEvent = record;

        for (const sub of root._subs) {
            if (sub.kinds.length > 0 && !sub.kinds.includes(kind))
                continue;
            try {
                sub.callback(record);
            } catch (e) {
                console.warn(`ProfileEvents: subscriber '${sub.owner}' threw on '${kind}': ${e}`);
            }
        }
    }

    readonly property var _rawEventKinds: ({
        openwindow: "window.open",
        closewindow: "window.close",
        activewindow: "window.focus",
        workspace: "workspace.focus",
        monitoradded: "monitor.change",
        monitorremoved: "monitor.change",
        focusedmon: "monitor.change"
    })

    Connections {
        target: Hypr
        enabled: !root.idle

        function onRawEvent(name: string, data: string): void {
            root.publish("compositor.raw", { name: name, data: data });
            const mapped = root._rawEventKinds[name];
            if (mapped)
                root.publish(mapped, { name: name, data: data });
        }
    }

    Connections {
        target: ProfileEngine
        enabled: !root.idle

        function onPhaseChanged(id: string, from: string, to: string): void {
            root.publish("profile.phase", { profile: id, from: from, to: to });
        }

        function onAnomalySurfaced(id: string, anomaly: var): void {
            root.publish("profile.anomaly", { profile: id, anomaly: anomaly });
        }
    }

    Connections {
        target: ResourceEngine
        enabled: !root.idle

        function onClaimRegistered(claim: var): void {
            root.publish("resource.claim", { action: "register", claim: claim });
        }

        function onClaimReleased(claim: var): void {
            root.publish("resource.claim", { action: "release", claim: claim });
        }

        function onNegotiationRaised(negotiation: var): void {
            root.publish("resource.negotiation", { action: "raised", negotiation: negotiation });
        }

        function onNegotiationResolved(negotiation: var, decision: string): void {
            root.publish("resource.negotiation", { action: "resolved", decision: decision, negotiation: negotiation });
        }
    }
}
