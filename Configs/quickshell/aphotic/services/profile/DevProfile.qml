pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import qs.services.profile

// The Dev profile, Phase 1: identity tracking only. It runs the real
// ProfileEngine lifecycle so the notch tile and any future claim have
// live state to bind to, and it changes no desktop state at all -- no
// onApply/onExit/onRestore/gracefulStop, because there is nothing
// honest for them to do yet.
//
// A singleton, and still core: Dev's detection is the `dev` layer's own
// baseline, and the launcher calls projectOpened() on it directly. The
// Gaming profile went the other way (PLG-03) -- it is a `profile`-
// capability plugin now, mounted from the registry by shell.qml, because
// it needs GpuVramSource injected and has a real install/remove story.
// Dev needs no injected dependency, so it stays importable straight from
// qs.services.profile.
//
// DETECT is the launcher's existing project-open action and nothing
// else -- no cwd polling, no git-root watch, no new daemon.
Singleton {
    id: root

    readonly property string profileId: "dev"
    readonly property bool enabled: InstallProfile.devEnabled

    readonly property string activeProjectPath: root._activeProjectPath
    readonly property string activeProjectName: {
        const path = root._activeProjectPath.replace(/\/+$/, "");
        if (!path)
            return "";
        return path.split("/").pop() ?? "";
    }
    readonly property bool active: root._activeProjectPath.length > 0

    // The seam the NEGOTIATE phase will attach to once there is something
    // real to measure. Deliberately unwired: registering a claim with a
    // guessed amount would feed fabricated data into arbitration that
    // answers with real suspensions.
    function registerWorkloadClaim(resourceKey: string, amount: real): var {
        if (!root.enabled || !resourceKey || !(amount > 0))
            return null;
        return ResourceEngine.register({
            id: `dev-workload-${resourceKey}`,
            owner: root.profileId,
            resource: resourceKey,
            amount: amount,
            priority: "background"
        });
    }

    function projectOpened(path: string): void {
        if (!root.enabled || !path || path === root._activeProjectPath)
            return;

        if (root._activeProjectPath.length > 0)
            ProfileEngine.deactivate(root.profileId, "project-switch");

        root._activeProjectPath = path;
        ProfileEngine.activate(root.profileId, "project-open");
    }

    property string _activeProjectPath: ""
    property bool _registered: false

    function _register(): void {
        if (root._registered || !root.enabled)
            return;
        root._registered = true;
        ProfileEngine.register({
            id: root.profileId,
            label: qsTr("Dev"),
            // Not [] -- StateSnapshot.capture() reads an empty array as
            // "unspecified" and falls through to allParts, which would
            // capture theme/workspace/monitors/notifications for a
            // profile that touches none of them. A non-empty list of
            // nothing real filters down to genuinely empty instead, which
            // is how this system spells "capture nothing".
            snapshot: ["none"],
            claims: []
        });
    }

    onEnabledChanged: {
        root._register();
        if (!root.enabled && root._activeProjectPath.length > 0) {
            ProfileEngine.deactivate(root.profileId, "layer-disabled");
            root._activeProjectPath = "";
        }
    }

    Component.onCompleted: root._register()
}
