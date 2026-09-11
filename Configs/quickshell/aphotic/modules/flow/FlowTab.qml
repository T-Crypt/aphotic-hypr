pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Services.UPower
import qs.services
import qs.services.profile
import qs.components
import "FlowModel.js" as Model

Item {
    id: root
    implicitWidth: 940
    implicitHeight: 620
    readonly property bool presented: visible && opacity > 0 && !!Window.window && Window.window.visible
    property bool motion: true

    // Which planes this install actually carries. A plane the user never
    // installed reads as "not installed" rather than an idle one that
    // will never wake.
    readonly property var layers: ({
        ai: InstallProfile.aiEnabled,
        gaming: InstallProfile.gamingEnabled,
        security: InstallProfile.securityEnabled,
        dev: InstallProfile.devEnabled
    })

    Text {
        id: recoveryNotice
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width
        wrapMode: Text.Wrap
        color: Colours.palette.m3error
        visible: Handover.recovery.length > 0 || Handover.error.length > 0
        text: (Handover.error || "Host handover needs recovery: " + Handover.recovery.map(l => l.id).join(", "))
            + "\nFrom a terminal: aphotic handover status; aphotic handover recover <lease-id>"
    }

    Loader {
        anchors.fill: parent
        anchors.topMargin: recoveryNotice.visible ? recoveryNotice.implicitHeight + 8 : 0
        active: root.presented
        sourceComponent: FlowScene {
            id: scene
            background: Colours.palette.m3surfaceContainer
            surface: Colours.palette.m3surfaceContainerHigh
            accent: Colours.palette.m3primary
            secondary: Colours.palette.m3tertiary
            ink: Colours.palette.m3onSurface
            muted: Colours.palette.m3onSurfaceVariant
            motion: root.motion
            onMotionChanged: root.motion = motion
            flow: Model.build(ResourceEngine.claims, ResourceEngine.resources, ProfileEngine.states, ProfileEngine.profiles, root.layers, WorkloadPassports.live, ActionReceipts.all, ({
                enabled: Settings.flowShellActivity,
                ready: ShellUsage.ready,
                cpuPerc: ShellUsage.cpuPerc,
                cores: ShellUsage.cores,
                memoryMib: ShellUsage.memoryMib,
                gpuNote: ShellUsage.gpuNote
            }))
            shellActivity: Settings.flowShellActivity
            onShellActivityToggled: {
                Settings.flowShellActivity = !Settings.flowShellActivity;
                scene.record(Settings.flowShellActivity ? "shell activity shown" : "shell activity hidden");
            }
            pending: ResourceEngine.pending
            projection: Model.projection(ResourceEngine.pending, ResourceEngine.claims)
            metrics: [
                {label:"CPU", value:Math.round(SystemUsage.cpuPerc*100)+"%"},
                {label:"GPU", value:SystemUsage.gpuStatsAvailable ? Math.round(SystemUsage.gpuPerc*100)+"%" : "Unavailable"},
                {label:"VRAM CLAIMS", value:vramClaimed()},
                {label:"MEMORY", value:Math.round(SystemUsage.memPerc*100)+"%"},
                {label:"CPU TEMP", value:SystemUsage.cpuTemp > 0 ? Math.round(SystemUsage.cpuTemp)+"°C" : "Unavailable"},
                {label:"BATTERY", value:UPower.displayDevice.isLaptopBattery ? Math.round(UPower.displayDevice.percentage*100)+"%" : "AC / no battery"},
                {label:"NET ↓ / ↑ B/s", value:rate(NetworkUsage.downloadSpeed)+" / "+rate(NetworkUsage.uploadSpeed)}
            ]
            function vramClaimed(): string {
                const spec = ResourceEngine.resources["gpu-vram"];
                const claims = ResourceEngine.claims.filter(c => c.resource === "gpu-vram");
                return spec ? Model.amount(claims.reduce((sum,c) => sum+c.amount,0), spec.unit) : "Undeclared";
            }
            function rate(bytes: real): string {
                return bytes >= 1048576 ? (bytes/1048576).toFixed(1)+"M" : Math.round(bytes/1024)+"K";
            }
            function record(message: string): void {
                events = [Qt.formatTime(new Date(),"hh:mm:ss") + " · " + message].concat(events).slice(0,12);
            }
            // Export is an explicit user action and writes nothing on its
            // own: the text goes to the clipboard, so the user decides
            // where it lands.
            onExportReceipts: {
                Quickshell.clipboardText = ActionReceipts.exportText();
                scene.record("receipts copied to clipboard");
            }
            onDecide: (negotiationId, decision) => {
                if (ResourceEngine.pending && ResourceEngine.pending.id === negotiationId)
                    ResourceEngine.resolve(decision);
            }
            // Inside the visibility-gated loader, so it stops with the
            // view. Passport staleness only matters to something looking
            // at it.
            Timer {
                running: WorkloadPassports.liveCount > 0
                interval: 15000
                repeat: true
                onTriggered: WorkloadPassports.refresh()
            }
            // Aphotic only measures itself while the layer is on and the
            // view is up. Off by default, and torn down with the loader.
            LazyLoader {
                active: Settings.flowShellActivity

                QtObject {
                    Component.onCompleted: ShellUsage.acquire()
                    Component.onDestruction: ShellUsage.release()
                }
            }
            SystemUsageWatch {}
            NetworkUsageWatch {}
            Connections {
                target: ProfileEngine
                function onPhaseChanged(id: string, from: string, to: string): void {
                    scene.record(id + " · " + from + " → " + to);
                }
            }
            Connections {
                target: ActionReceipts
                function onSettled(receipt: var): void {
                    scene.record(receipt.profileId + " · " + receipt.kind + " · " + ActionReceipts.label(receipt));
                }
            }
            Connections {
                target: WorkloadPassports
                function onStaled(passport: var): void {
                    scene.record(passport.label + " · source went quiet");
                }
            }
            Connections {
                target: ResourceEngine
                function onNegotiationResolved(negotiation: var, decision: string): void {
                    scene.record(negotiation.resourceLabel + " · " + (decision === "suspend" ? "graceful stop requested" : decision));
                }
            }
        }
    }
}
