pragma Singleton

import QtQuick
import Quickshell
import "LocalInferenceCore.js" as Core

Singleton {
    id: root

    readonly property var backends: root._backends
    readonly property var activeModels: Core.activeModels(root._backends)

    property var _backends: ({})

    function report(owner: string, label: string, models: var): void {
        root._backends = Core.report(root._backends, owner, label, models, Date.now());
    }
}
