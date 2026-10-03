pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import "../services/SonarTargets.js" as Rules

QtObject {
    id: root

    required property Item target
    required property string targetId
    required property string label
    property string action: ""
    property string bindDescription: ""
    property string plugin: ""
    property bool eligible: true

    readonly property bool available: {
        if (!root.eligible || !root.target || !root.target.visible || !root.target.QsWindow.window?.visible)
            return false;
        for (let item = root.target; item; item = item.parent)
            if (!item.visible || item.opacity <= 0)
                return false;
        return !root.plugin || PluginRegistry.isEnabled(root.plugin);
    }

    function usable(): bool { return root.available; }

    function snapshot(): var {
        if (!root.usable()) return null;
        const screen = root.target.QsWindow.window.screen;
        const points = [[0,0],[root.target.width,0],[0,root.target.height],[root.target.width,root.target.height]]
            .map(p => root.target.mapToGlobal(p[0],p[1]));
        const xs = points.map(p => p.x), ys = points.map(p => p.y);
        let rect = Rules.clipRect({x:Math.min(...xs),y:Math.min(...ys),width:Math.max(...xs)-Math.min(...xs),height:Math.max(...ys)-Math.min(...ys)},
            {x:screen.x,y:screen.y,width:screen.width,height:screen.height});
        for (let item = root.target.parent; rect && item; item = item.parent) {
            if (!item.clip) continue;
            const a = item.mapToGlobal(0,0), b = item.mapToGlobal(item.width,item.height);
            rect = Rules.clipRect(rect,{x:a.x,y:a.y,width:b.x-a.x,height:b.y-a.y});
        }
        if (!rect) return null;
        rect.x -= screen.x; rect.y -= screen.y;
        return {id:root.targetId, output:screen.name, label:root.label, action:root.action, rect:rect,
            shortcut:Rules.shortcut(HyprKeybinds.entries, root.bindDescription), anchor:root};
    }

    Component.onCompleted: EchoRegistry.attach(root)
    Component.onDestruction: EchoRegistry.detach(root)
}
