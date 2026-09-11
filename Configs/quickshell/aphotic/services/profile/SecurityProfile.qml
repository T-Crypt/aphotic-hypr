// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.services.profile

// The Security profile, Phase 1: the ProfileEngine registrant and nothing
// else. DND on APPLY, the release on RESTORE, and the identity/theme
// revert every registrant gets for free the moment its snapshot exists --
// no dashboard tab, no widget, no tool integration. Those attach to this
// substrate later rather than arriving with it.
//
// A singleton, the same call DevProfile made: Vpn is itself a singleton,
// so there is no injected dependency to receive and no reason to mount
// this from shell.qml the way the Gaming plugin has to.
//
// DETECT is Vpn.connected -- the `aphotic vpn` daemon's own state, which
// Vpn.qml already polls every 5s. This reacts to that signal and starts
// no timer, no dbus monitor and no process of its own.
Singleton {
    id: root

    readonly property string profileId: "security"
    readonly property bool enabled: InstallProfile.securityEnabled

    // The seam NEGOTIATE attaches to once an engagement has a footprint
    // worth arbitrating. Unwired on purpose: BloodHound/Neo4j's resident
    // memory and an active scan's cost are both real numbers nobody has
    // measured yet, and a guessed one would feed fabricated data into
    // arbitration that answers with real suspensions. Foreground, like
    // Gaming and unlike Dev, because an engagement in progress is the
    // side that raises a negotiation, not the side that answers one.
    function registerEngagementClaim(resourceKey: string, amount: real): var {
        if (!root.enabled || !resourceKey || !(amount > 0))
            return null;
        return ResourceEngine.register({
            id: `security-engagement-${resourceKey}`,
            owner: root.profileId,
            resource: resourceKey,
            amount: amount,
            priority: "foreground"
        });
    }

    // The Security plane's workload passports. A VPN session is one
    // passport keyed on the session, and an explicit lab engagement opens
    // its own. Both are owner-driven: nothing here scans for VMs.
    function engagementStarted(label: string, kind: string): string {
        if (!root.enabled || !label)
            return "";
        return WorkloadPassports.open({
            plane: "security",
            owner: root.profileId,
            label: label,
            trigger: kind || "engagement-start",
            workloadId: "security-engagement",
            sessionId: `engagement:${kind || "lab"}:${label}`,
            sourceAt: Date.now()
        });
    }

    function engagementEnded(token: string, reason: string): bool {
        return WorkloadPassports.close(token, reason || "engagement-end");
    }

    property bool _registered: false
    property string _vpnToken: ""
    property string _dndReceipt: ""

    // DND is an action with a receipt, not a phase. The request is filed
    // before the toggle and settled after it, so Flow can say whether the
    // desktop actually went quiet and, on the way out, whether the value
    // was still the one Aphotic set.
    function _applyDnd(): void {
        const before = Settings.dndEnabled;
        root._dndReceipt = ActionReceipts.request({
            profileId: root.profileId,
            kind: "dnd",
            before: before,
            reason: "engagement in progress"
        });
        DoNotDisturb.setSecurityActive(true);
        if (Settings.dndEnabled)
            ActionReceipts.applied(root._dndReceipt, Settings.dndEnabled);
        else
            ActionReceipts.failed(root._dndReceipt, "do not disturb did not take");
    }

    function _restoreDnd(): void {
        if (!root._dndReceipt) {
            DoNotDisturb.setSecurityActive(false);
            return;
        }
        const action = ActionReceipts.restore(root._dndReceipt, Settings.dndEnabled);
        root._dndReceipt = "";
        if (action === "preserve")
            return;
        DoNotDisturb.setSecurityActive(false);
    }

    // snapshot is the "notifications" part only, which StateSnapshot
    // defines as exactly {dnd: Settings.dndEnabled} -- the one thing this
    // profile changes. Naming it explicitly matters: an empty array is
    // NOT "capture nothing", StateSnapshot.capture() falls back to
    // allParts when the list is empty, which would snapshot and restore
    // theme/workspace/monitors this profile never touches.
    //
    // No gracefulStop: an active engagement has no pause primitive to
    // call, so a hook here would be a fake one and canSuspend("security")
    // correctly stays false.
    function _register(): void {
        if (root._registered || !root.enabled)
            return;
        root._registered = true;
        ProfileEngine.register({
            id: root.profileId,
            label: qsTr("Security"),
            snapshot: ["notifications"],
            claims: [],
            onApply: () => root._applyDnd(),
            onRestore: () => root._restoreDnd()
        });
    }

    // Unregisters rather than only deactivating, which is where this
    // parts ways with DevProfile. InstallProfile reports `enabled` before
    // it has read aphotic.toml (unknown means enabled, so a git clone
    // sees the shell it cloned), and shell.qml arms this at startup --
    // so on an install without the exploit layers this registers first
    // and learns it should not have a moment later. Deactivating would
    // leave `security` sitting in ProfileEngine.profiles forever on
    // every machine that never asked for it. The Gaming plugin gets the
    // same effect from Component.onDestruction; a singleton is never
    // destroyed, so it has to happen here.
    onEnabledChanged: {
        if (root.enabled) {
            root._register();
            return;
        }
        if (!root._registered)
            return;
        root._registered = false;
        root._vpnToken = "";
        WorkloadPassports.closeOwner(root.profileId, "layer-disabled");
        ProfileEngine.unregister(root.profileId);
    }

    // The target is guarded rather than bound straight to Vpn so an
    // install without the exploit layers never touches that singleton at
    // all: Vpn is demand-created today (the Network settings pane is its
    // only other reader) and constructing it starts its 5s pgrep poll.
    Connections {
        target: root.enabled ? Vpn : null

        function onConnectedChanged(): void {
            if (Vpn.connected) {
                if (!ProfileEngine.isActive(root.profileId))
                    ProfileEngine.activate(root.profileId, "vpn-connect");
                root._vpnToken = WorkloadPassports.open({
                    plane: "security",
                    owner: root.profileId,
                    label: qsTr("VPN session"),
                    trigger: "vpn-connect",
                    workloadId: "security-vpn",
                    sessionId: "vpn",
                    sourceAt: Date.now()
                });
            } else {
                if (ProfileEngine.isActive(root.profileId))
                    ProfileEngine.deactivate(root.profileId, "vpn-disconnect");
                if (root._vpnToken) {
                    WorkloadPassports.close(root._vpnToken, "vpn-disconnect");
                    root._vpnToken = "";
                }
            }
        }
    }

    Component.onCompleted: root._register()
}
