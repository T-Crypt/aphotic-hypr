// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import qs.services.ai

QtObject {
    id: root

    property var events: []
    property real speed: 1
    property bool playing: false

    readonly property int cursor: root._cursor
    readonly property var sessions: root._sessions
    readonly property bool loaded: root.events.length > 0
    readonly property real positionMs: root._clockMs
    readonly property real durationMs: root._stamps.length > 0 ? root._stamps[root._stamps.length - 1] : 0
    readonly property real progress: root.durationMs > 0 ? Math.min(1, root._clockMs / root.durationMs) : 0
    readonly property var stamps: root._stamps
    readonly property bool finished: root.loaded && root._cursor >= root.events.length

    property int _cursor: 0
    property var _sessions: []
    property real _clockMs: 0
    property var _stamps: []

    readonly property int maxGapMs: 1200

    onEventsChanged: root.reset()

    function reset(): void {
        const stamps = [];
        let clock = 0;
        for (let i = 0; i < root.events.length; i++) {
            if (i > 0) {
                const gap = (root.events[i].t ?? 0) - (root.events[i - 1].t ?? 0);
                clock += Math.max(0, Math.min(root.maxGapMs, gap));
            }
            stamps.push(clock);
        }
        root._stamps = stamps;
        root._clockMs = 0;
        root._cursor = 0;
        root._sessions = [];
        root.playing = false;
    }

    function play(): void {
        if (!root.loaded)
            return;
        if (root.finished)
            root.seekTo(0);
        root.playing = true;
    }

    function pause(): void {
        root.playing = false;
    }

    function toggle(): void {
        if (root.playing)
            root.pause();
        else
            root.play();
    }

    function step(delta: int): void {
        root.playing = false;
        const next = Math.max(0, Math.min(root.events.length, root._cursor + delta));
        root._clockMs = next === 0 ? 0 : root._stamps[next - 1];
        root._advanceTo(next);
    }

    function seekTo(ms: real): void {
        root._clockMs = Math.max(0, Math.min(root.durationMs, ms));
        let target = 0;
        while (target < root._stamps.length && root._stamps[target] <= root._clockMs)
            target++;
        root._advanceTo(target);
    }

    function seekToIndex(index: int): void {
        root.playing = false;
        const clamped = Math.max(0, Math.min(root.events.length, index + 1));
        root._clockMs = clamped === 0 ? 0 : root._stamps[clamped - 1];
        root._advanceTo(clamped);
    }

    function _advanceTo(target: int): void {
        if (target === root._cursor)
            return;
        if (target < root._cursor) {
            root._sessions = AgentGraphService.foldEvents(root.events, target);
            root._cursor = target;
            return;
        }
        let sessions = root._sessions;
        for (let i = root._cursor; i < target; i++)
            sessions = AgentGraphService.applyTo(sessions, root.events[i]);
        root._sessions = sessions;
        root._cursor = target;
    }

    property Timer _tick: Timer {
        interval: 33
        repeat: true
        running: root.playing && root.loaded
        onTriggered: {
            root._clockMs += 33 * root.speed;
            let target = root._cursor;
            while (target < root._stamps.length && root._stamps[target] <= root._clockMs)
                target++;
            root._advanceTo(target);
            if (root._cursor >= root.events.length)
                root.playing = false;
        }
    }
}
