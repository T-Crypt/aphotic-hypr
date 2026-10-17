pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.services

// The machine's terrain: CPU history as a filled ridge, memory as a fill
// rising from the floor, network as a thin bright line scaled to the
// session's own peak.
//
// The trail exists only while a surface above this mounts the watches:
// samples land when the services themselves change, so this canvas keeps
// no sampler and repaints only when a sample or a size lands. Closed
// dashboard means no samples, no paints, no cost.
Canvas {
    id: root

    readonly property int capacity: 48
    property var cpuTrail: []
    property var netTrail: []

    onCpuTrailChanged: root.requestPaint()
    onNetTrailChanged: root.requestPaint()
    onWidthChanged: root.requestPaint()
    onHeightChanged: root.requestPaint()
    onMemPercChanged: root.requestPaint()

    // Memory is instantaneous, not a trail: one fill line bound to the
    // service value.
    readonly property real memPerc: SystemUsage.memPerc

    function pushCpu(value: real): void {
        const next = root.cpuTrail.concat([Math.max(0, Math.min(1, value))]);
        root.cpuTrail = next.length > root.capacity ? next.slice(next.length - root.capacity) : next;
    }

    function pushNet(value: real): void {
        const next = root.netTrail.concat([Math.max(0, value)]);
        root.netTrail = next.length > root.capacity ? next.slice(next.length - root.capacity) : next;
    }

    // The probe seeds the trails with a waveform so a render does not
    // need minutes of polling first. Nothing in the live surface calls
    // this; the real trails fill from the services alone.
    function seed(cpu: var, net: var): void {
        root.cpuTrail = cpu;
        root.netTrail = net;
    }

    Connections {
        target: SystemUsage

        function onCpuPercChanged(): void {
            root.pushCpu(SystemUsage.cpuPerc);
        }
    }

    Connections {
        target: NetworkUsage

        function onDownloadSpeedChanged(): void {
            root.pushNet(NetworkUsage.downloadSpeed);
        }
    }

    onPaint: {
        const ctx = root.getContext("2d");
        ctx.clearRect(0, 0, root.width, root.height);

        const memH = root.height * root.memPerc;
        if (memH > 0) {
            ctx.fillStyle = Qt.alpha(Colours.signalTertiary, 0.16);
            ctx.fillRect(0, root.height - memH, root.width, memH);
        }

        const crest = 0.9;
        const count = root.cpuTrail.length;
        if (count > 0) {
            const step = root.width / root.capacity;

            ctx.beginPath();
            ctx.moveTo(0, root.height);
            for (let i = 0; i < count; i++)
                ctx.lineTo(i * step, root.height - root.cpuTrail[i] * root.height * crest);
            ctx.lineTo((count - 1) * step, root.height);
            ctx.closePath();
            ctx.fillStyle = Qt.alpha(Colours.signalStyle.accentLine, 0.28);
            ctx.fill();

            ctx.beginPath();
            for (let i = 0; i < count; i++) {
                const x = i * step;
                const y = root.height - root.cpuTrail[i] * root.height * crest;
                if (i === 0)
                    ctx.moveTo(x, y);
                else
                    ctx.lineTo(x, y);
            }
            ctx.strokeStyle = Qt.alpha(Colours.signalStyle.accentLine, 0.85);
            ctx.lineWidth = 2;
            ctx.stroke();
        }

        const netCount = root.netTrail.length;
        if (netCount > 1) {
            let peak = 1;
            for (let i = 0; i < netCount; i++)
                peak = Math.max(peak, root.netTrail[i]);

            const step = root.width / root.capacity;
            ctx.beginPath();
            for (let i = 0; i < netCount; i++) {
                const x = i * step;
                const y = root.height - (root.netTrail[i] / peak) * root.height * 0.5;
                if (i === 0)
                    ctx.moveTo(x, y);
                else
                    ctx.lineTo(x, y);
            }
            ctx.strokeStyle = Qt.alpha(Colours.signalSecondary, 0.75);
            ctx.lineWidth = 1.5;
            ctx.stroke();
        }
    }
}
