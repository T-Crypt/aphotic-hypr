pragma Singleton
import QtQuick
import Quickshell
import qs.services
import "EchoPolicy.js" as Policy
import "PluginApiCore.js" as Api

Singleton {
    id: root
    property var records: ({})
    property var anchors: []
    readonly property var eligiblePlugins: PluginRegistry.enabledPlugins.filter(p => Api.grants(PluginRegistry.apiOf(p), true).includes("sonar.register"))

    function register(plugin: string, local: string, descriptor: var): bool {
        if (!root.eligiblePlugins.includes(plugin))
            return false;
        const value = Policy.normalize(plugin, local, descriptor);
        if (!value)
            return false;
        // "Resolves action ownership": a target's action must name a
        // surface this plugin actually declared, not an id it invented.
        if (value.action && !PluginApi.ownsSurface(plugin, value.action))
            return false;
        const next = Policy.put(root.records, value);
        if (!next)
            return false;
        root.records = next;
        return true;
    }

    function update(plugin: string, local: string, descriptor: var): bool {
        return !!root.records[`plugin:${plugin}/${local}`] && root.register(plugin, local, descriptor);
    }

    function unregister(plugin: string, local: string): void {
        const next = Object.assign({}, root.records);
        delete next[`plugin:${plugin}/${local}`];
        root.records = next;
    }

    function removePlugin(plugin: string): void {
        root.records = Policy.removePlugin(root.records, plugin);
    }

    function attach(anchor: var): void {
        if (!root.anchors.includes(anchor))
            root.anchors = root.anchors.concat([anchor]);
    }

    function detach(anchor: var): void {
        root.anchors = root.anchors.filter(a => a !== anchor);
    }

    function snapshot(): var {
        const targets = Object.values(root.records).filter(r =>
            root.eligiblePlugins.includes(r.plugin)
            // A surface undeclared between registration and this ping
            // leaves its target without an owner; drop it here too.
            && (!r.action || PluginApi.ownsSurface(r.plugin, r.action)));
        for (const anchor of root.anchors) {
            const target = anchor.snapshot();
            if (target)
                targets.push(target);
        }
        return targets;
    }

    onEligiblePluginsChanged: {
        for (const plugin of [...new Set(Object.values(root.records).map(r => r.plugin))]) {
            if (!root.eligiblePlugins.includes(plugin))
                root.removePlugin(plugin);
        }
    }
}
