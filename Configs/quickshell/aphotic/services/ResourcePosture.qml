pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.services.profile
import "Posture.js" as Posture

// The Resource Engine as ambient state. Flow stays the place to inspect
// claims; this is what lets the bar and the notch know something is
// happening without anyone opening Flow. services/Posture.js
// holds the rules.
//
// Derived entirely from ResourceEngine's own properties, so it costs one
// re-evaluation per claim or measurement change and nothing at rest. The
// only timer is the settle window after a negotiation is answered, and it
// runs once per answer.
Singleton {
    id: root

    readonly property var state: Posture.assess(ResourceEngine.claims, ResourceEngine.resources, ResourceEngine.pending, ResourceEngine.overBudget, root._settling)

    // quiet | settling | pressure | contention | negotiating
    readonly property string level: root.state.level
    readonly property var resource: root.state.resource
    readonly property string headline: Posture.headline(root.state)

    // Whether ambient surfaces should show it under the current runtime
    // context. Settling always shows: it is the tail of something that was
    // already on screen.
    readonly property bool surfaced: root.level === "settling" || (root.level !== "quiet" && Posture.atLeast(root.level, RuntimeContext.resourceThreshold))

    // The answered negotiations of this session, newest first.
    readonly property var history: root._history

    readonly property int historyLimit: 20
    readonly property int settleMs: 4000

    property bool _settling: false
    property var _history: []

    function atLeast(level: string, threshold: string): bool {
        return Posture.atLeast(level, threshold);
    }

    Connections {
        target: ResourceEngine

        function onNegotiationResolved(negotiation: var, decision: string): void {
            root._history = [{
                    at: Date.now(),
                    decision: decision,
                    resource: negotiation.resource,
                    label: negotiation.resourceLabel,
                    claimant: negotiation.claimant?.owner ?? "",
                    requestor: negotiation.requestor?.owner ?? ""
                }].concat(root._history).slice(0, root.historyLimit);
            root._settling = true;
            settle.restart();
        }
    }

    Timer {
        id: settle

        interval: root.settleMs
        onTriggered: root._settling = false
    }
}
