pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.services

// The machine's terrain: CPU history as a ridge and network as a low band
// along the floor. Memory stays a readout; as a line it read as a stray
// rule across the screen. The newest sample sits at the
// right edge and history runs off to the left.
//
// Samples land only while a surface above mounts the watches, so this
// canvas keeps no sampler and repaints only when a sample or a size lands.
Canvas {
    id: root

    readonly property int capacity: 48
    // Below this rate the network band stays flat, so idle chatter does
    // not draw a hill.
    readonly property real netFloor: 64 * 1024
    property var cpuTrail: []
    property var netTrail: []

    onCpuTrailChanged: root.requestPaint()
    onNetTrailChanged: root.requestPaint()
    onWidthChanged: root.requestPaint()
    onHeightChanged: root.requestPaint()

    function pushCpu(value: real): void {
        const next = root.cpuTrail.concat([Math.max(0, Math.min(1, value))]);
        root.cpuTrail = next.length > root.capacity ? next.slice(next.length - root.capacity) : next;
    }

    function pushNet(value: real): void {
        const next = root.netTrail.concat([Math.max(0, value)]);
        root.netTrail = next.length > root.capacity ? next.slice(next.length - root.capacity) : next;
    }

    // The probe seeds both trails so a render does not need minutes of
    // polling first. The live surface never calls this.
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

    function _xAt(i: int, count: int): real {
        const step = root.width / (root.capacity - 1);
        return root.width - (count - 1 - i) * step;
    }

    onPaint: {
        const ctx = root.getContext("2d");
        const h = root.height;
        ctx.clearRect(0, 0, root.width, h);

        const net = root.netTrail;
        if (net.length > 1) {
            let peak = root.netFloor;
            for (let i = 0; i < net.length; i++)
                peak = Math.max(peak, net[i]);
            const bandH = h * 0.28;

            ctx.beginPath();
            ctx.moveTo(root._xAt(0, net.length), h);
            for (let i = 0; i < net.length; i++)
                ctx.lineTo(root._xAt(i, net.length), h - (net[i] / peak) * bandH);
            ctx.lineTo(root.width, h);
            ctx.closePath();
            ctx.fillStyle = Qt.alpha(Colours.signalSecondary, 0.09);
            ctx.fill();
        }

        const cpu = root.cpuTrail;
        if (cpu.length > 1) {
            const crest = 0.92;
            const yAt = i => h - cpu[i] * h * crest;

            const fill = ctx.createLinearGradient(0, 0, 0, h);
            fill.addColorStop(0, Qt.alpha(Colours.signalStyle.accentLine, 0.26));
            fill.addColorStop(1, Qt.alpha(Colours.signalStyle.accentLine, 0));

            ctx.beginPath();
            ctx.moveTo(root._xAt(0, cpu.length), h);
            for (let i = 0; i < cpu.length; i++)
                ctx.lineTo(root._xAt(i, cpu.length), yAt(i));
            ctx.lineTo(root.width, h);
            ctx.closePath();
            ctx.fillStyle = fill;
            ctx.fill();

            ctx.beginPath();
            for (let i = 0; i < cpu.length; i++) {
                if (i === 0)
                    ctx.moveTo(root._xAt(i, cpu.length), yAt(i));
                else
                    ctx.lineTo(root._xAt(i, cpu.length), yAt(i));
            }
            ctx.strokeStyle = Qt.alpha(Colours.signalStyle.accentLine, 0.9);
            ctx.lineWidth = 1.5;
            ctx.lineJoin = "round";
            ctx.stroke();
        }
    }
}
