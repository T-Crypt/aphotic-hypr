pragma ComponentBehavior: Bound

import QtQuick
import qs.config
import qs.services

Canvas {
    id: root

    readonly property int capacity: 48
    readonly property real netFlatBelow: 64 * 1024
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

    function seedForProbe(cpu: var, net: var): void {
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
            let peak = root.netFlatBelow;
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
