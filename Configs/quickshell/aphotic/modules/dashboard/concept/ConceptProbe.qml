pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.components
import qs.services
import "modules/dashboard/concept" as Concept

// Offscreen render probe for the dashboard concept. Never maps a window
// on a live desktop: run it with QT_QPA_PLATFORM=offscreen, e.g.
//
//   QT_QPA_PLATFORM=offscreen \
//     CONCEPT_W=1920 CONCEPT_H=1080 CONCEPT_MS=14000 \
//     CONCEPT_OUT=/tmp/opencode/concept-1920x1080.png \
//     qs -p ConceptProbeRun.qml
//
// qs resolves `qs.*` imports only from the config root, so a wrapper
// copies this file to the root (as ConceptProbeRun.qml) before running
// and deletes it afterwards. See README.md in this directory.
ShellRoot {
    id: probe

    readonly property int outW: Number(Quickshell.env("CONCEPT_W") || 1920)
    readonly property int outH: Number(Quickshell.env("CONCEPT_H") || 1080)
    // How long the surface stays open before the grab. The CPU ridge
    // grows one sample per service poll while it is open, so a longer
    // run draws more terrain.
    readonly property int runMs: Number(Quickshell.env("CONCEPT_MS") || 14000)
    readonly property string outFile: Quickshell.env("CONCEPT_OUT") || "/tmp/opencode/concept.png"

    Component.onCompleted: console.log("PROBE size", probe.outW, "x", probe.outH, "run", probe.runMs, "ms")

    FloatingWindow {
        implicitWidth: probe.outW
        implicitHeight: probe.outH
        visible: true
        color: Colours.shadow

        SystemUsageWatch {}
        NetworkUsageWatch {}

        Concept.ConceptPulse {
            id: surface

            anchors.fill: parent
        }

        // Seeded terrain: a gentle load waveform with one spike, drawn
        // at the exact capacity the surface holds, so the render shows a
        // filled ridge without minutes of polling first. The readouts
        // and the clock still show the live service values.
        Timer {
            interval: 50
            running: true

            onTriggered: {
                const count = 48;
                const cpu = [];
                const net = [];
                for (let i = 0; i < count; i++) {
                    const wave = 0.18 + 0.16 * Math.sin(i / 4.5) + 0.08 * Math.sin(i / 1.7);
                    const spike = (i >= 20 && i <= 23) ? 0.5 : 0;
                    cpu.push(Math.min(1, Math.max(0.04, wave + spike)));
                    net.push(Math.max(0, 0.3 + 0.25 * Math.sin(i / 3.1) + (i >= 33 && i <= 35 ? 0.4 : 0)));
                }
                surface.terrain.seed(cpu, net);
                console.log("PROBE seeded terrain");
            }
        }

        Timer {
            interval: probe.runMs
            running: true

            onTriggered: surface.grabToImage(result => {
                console.log("PROBE saved", probe.outFile, result.saveToFile(probe.outFile));
                Qt.quit();
            })
        }
    }
}
