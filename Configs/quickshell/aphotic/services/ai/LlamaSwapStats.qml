pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services.ai
import "InferenceCore.js" as Core

Singleton {
    id: root

    readonly property string model: root._model
    readonly property bool generating: root._generating
    readonly property real tokensPerSecond: root._tokensPerSecond
    readonly property int nDecoded: root._nDecoded
    readonly property int nCtx: root._nCtx
    readonly property real lastUpdated: root._lastUpdated

    property var _holders: ({})
    property var _samples: ({})
    property string _model: ""
    property bool _generating: false
    property real _tokensPerSecond: 0
    property int _nDecoded: 0
    property int _nCtx: 0
    property real _lastUpdated: 0

    readonly property bool _wanted: Object.keys(root._holders).length > 0
    readonly property var _runningModels: AiProviders.llamaSwapRunningModels
        .filter(entry => entry?.name && !entry.embedding)

    function hold(owner: string, on: bool): void {
        if (!owner || on === Object.prototype.hasOwnProperty.call(root._holders, owner))
            return;
        const next = Object.assign({}, root._holders);
        if (on)
            next[owner] = true;
        else
            delete next[owner];
        root._holders = next;
        if (Object.keys(next).length === 0)
            root._generating = false;
    }

    function _accept(name: string, text: string): void {
        let slots;
        try {
            slots = JSON.parse(text);
        } catch (e) {
            return;
        }
        if (!Array.isArray(slots))
            return;

        const now = Date.now();
        const update = Core.updateStats(root._samples, name, slots, now);
        root._samples = update.samples;
        const current = update.current;

        if (Core.acceptStatsModel(root._model, name, current.generating)) {
            root._model = name;
            root._generating = current.generating;
            root._nDecoded = current.nDecoded;
            root._nCtx = current.nCtx;
            root._lastUpdated = now;
            if (current.tokensPerSecond > 0)
                root._tokensPerSecond = current.tokensPerSecond;
        }
    }

    Instantiator {
        model: root._wanted ? root._runningModels : []

        delegate: QtObject {
            id: poller

            required property var modelData
            readonly property string name: poller.modelData.name ?? ""

            property Timer timer: Timer {
                interval: 1000
                repeat: true
                triggeredOnStart: true
                running: root._wanted && AiConfig.llamaSwapHostConfigured && poller.name.length > 0
                onTriggered: {
                    if (!slots.running)
                        slots.exec(["curl", "-s", "-m", "2", `${AiConfig.llamaSwapHost}/upstream/${encodeURIComponent(poller.name)}/slots`]);
                }
            }

            property Process slots: Process {
                stdout: StdioCollector {
                    onStreamFinished: root._accept(poller.name, text)
                }
            }
        }
    }

    Connections {
        target: AiProviders
        function onLlamaSwapRunningModelsChanged(): void {
            if (root._model && !root._runningModels.some(entry => entry.name === root._model))
                root._generating = false;
        }
    }
}
