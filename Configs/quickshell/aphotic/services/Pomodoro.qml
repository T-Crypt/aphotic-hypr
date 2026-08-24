pragma Singleton

import QtQuick
import Quickshell

// Simple work/break countdown, shared by the bar's PomodoroStatus icon,
// its popout, and the Dashboard's DashPomodoro card -- same "one service,
// several readers" shape as every other status entry.
Singleton {
    id: root

    readonly property int workSeconds: 25 * 60
    readonly property int breakSeconds: 5 * 60

    property bool running: false
    property bool isBreak: false
    property int remaining: workSeconds

    function toggle(): void {
        running = !running;
    }

    function reset(): void {
        running = false;
        isBreak = false;
        remaining = workSeconds;
    }

    function skip(): void {
        isBreak = !isBreak;
        remaining = isBreak ? breakSeconds : workSeconds;
    }

    function formatTime(seconds: int): string {
        const m = Math.floor(seconds / 60);
        const s = seconds % 60;
        return `${m}:${s < 10 ? "0" : ""}${s}`;
    }

    Timer {
        interval: 1000
        running: root.running
        repeat: true
        onTriggered: {
            if (root.remaining > 0) {
                root.remaining--;
                return;
            }
            const finishedBreak = root.isBreak;
            root.isBreak = !root.isBreak;
            root.remaining = root.isBreak ? root.breakSeconds : root.workSeconds;
            Quickshell.execDetached(["notify-send", "-a", "aphotic", finishedBreak ? qsTr("Break's over") : qsTr("Time for a break"), finishedBreak ? qsTr("Back to work") : qsTr("Step away for %1 minutes").arg(root.breakSeconds / 60)]);
        }
    }
}
