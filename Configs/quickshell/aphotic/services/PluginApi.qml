pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services
import "PluginApiCore.js" as Core

// The supported way for a plugin to reach the running shell. A plugin
// declares what it needs in its manifest:
//
//   [api]
//   version = 1
//   uses = ["context.observe", "resource.observe"]
//
// and asks for its handle by name:
//
//   readonly property var api: PluginApi.handle("my-plugin")
//
// The handle carries a namespace per granted call and nothing else, so an
// undeclared call is simply absent. `api.has("context.request")` asks
// without touching it. Every call re-checks the grant, so disabling or
// removing the plugin revokes the handle it already holds, and the
// surfaces it declared are dropped at the same moment. `handle()` returns
// null while the plugin is not enabled; reading it in a binding makes that
// reactive.
//
// QML cannot sandbox imports, so a plugin can still reach services
// directly. That is not a supported contract and can break between
// releases; this is, and it is versioned (`aphotic plugin api`).
Singleton {
    id: root

    readonly property int version: Core.VERSION
    readonly property var uses: Core.USES

    property var _surfaces: ({})
    property var _closeHandlers: ({})
    property var _lastRequest: ({})

    function grantsFor(plugin: string): var {
        return Core.grants(PluginRegistry.apiOf(plugin), PluginRegistry.isEnabled(plugin));
    }

    function granted(plugin: string, use: string): bool {
        return root.grantsFor(plugin).includes(use);
    }

    function handle(plugin: string): var {
        const grants = root.grantsFor(plugin);
        if (!PluginRegistry.isEnabled(plugin))
            return null;

        const live = use => {
            if (root.granted(plugin, use))
                return true;
            console.warn(`PluginApi: ${plugin} called ${use} without a grant (declare it in [api].uses, or the plugin is disabled)`);
            return false;
        };

        const h = {
            version: Core.VERSION,
            plugin: plugin,
            granted: grants,
            has: use => root.granted(plugin, use)
        };

        if (grants.includes("context.observe"))
            h.context = {
                current: () => live("context.observe") ? RuntimeContext.current : "",
                policy: () => live("context.observe") ? RuntimeContext.policy : null,
                contexts: () => live("context.observe") ? RuntimeContext.contexts : []
            };

        if (grants.includes("context.request")) {
            h.context = h.context ?? {};
            h.context.request = (name, reason) => live("context.request") && root._request(plugin, name, reason);
        }

        if (grants.includes("resource.observe"))
            h.resources = {
                level: () => live("resource.observe") ? ResourcePosture.level : "quiet",
                surfaced: () => live("resource.observe") && ResourcePosture.surfaced,
                resource: () => live("resource.observe") ? ResourcePosture.resource : null,
                headline: () => live("resource.observe") ? ResourcePosture.headline : ""
            };

        if (grants.includes("surface.declare"))
            h.surfaces = {
                declare: (local, role) => live("surface.declare") && root._declare(plugin, local, role),
                track: (screenState, local, open) => {
                    const name = Core.surfaceName(plugin, local);
                    if (live("surface.declare") && name && root._owns(plugin, name))
                        Surfaces.track(screenState, name, open);
                },
                onCloseRequested: fn => {
                    if (live("surface.declare") && typeof fn === "function")
                        root._addCloseHandler(plugin, fn);
                }
            };

        if (grants.includes("notifications.publish"))
            h.notify = (summary, body) => {
                if (live("notifications.publish"))
                    Notifs.notify(String(summary ?? ""), String(body ?? ""), [], PluginRegistry.displayNameOf(plugin));
            };

        return h;
    }

    function _owns(plugin: string, name: string): bool {
        return (root._surfaces[plugin] ?? []).includes(name);
    }

    function _declare(plugin: string, local: string, role: string): bool {
        const name = Core.surfaceName(plugin, local);
        if (!name || !Surfaces.declare(name, role))
            return false;
        const next = Object.assign({}, root._surfaces);
        next[plugin] = (next[plugin] ?? []).filter(n => n !== name).concat([name]);
        root._surfaces = next;
        return true;
    }

    function _addCloseHandler(plugin: string, fn: var): void {
        const next = Object.assign({}, root._closeHandlers);
        next[plugin] = (next[plugin] ?? []).concat([fn]);
        root._closeHandlers = next;
    }

    // Never switches. The user gets a notification naming the plugin and
    // its reason, and switches from its action -- or doesn't.
    function _request(plugin: string, name: string, reason: string): bool {
        if (!RuntimeContext.has(name))
            return false;
        if (name === RuntimeContext.current)
            return true;
        const now = Date.now();
        if (!Core.mayRequest(root._lastRequest[plugin] ?? 0, now))
            return false;
        const next = Object.assign({}, root._lastRequest);
        next[plugin] = now;
        root._lastRequest = next;

        const target = RuntimeContext.contexts.find(c => c.id === name);
        const who = PluginRegistry.displayNameOf(plugin);
        Notifs.notify(qsTr("%1 suggests %2").arg(who).arg(target.label), reason ? String(reason) : target.description, [
            {
                identifier: "switch",
                text: qsTr("Switch to %1").arg(target.label),
                icon: target.icon,
                invoke: () => RuntimeContext.set(name)
            }
        ], who);
        return true;
    }

    // A plugin that stops being enabled takes its surfaces and callbacks
    // with it, the same tick. Its handle stays in the plugin's hands but
    // every call on it now refuses.
    function _revoke(plugin: string): void {
        for (const name of root._surfaces[plugin] ?? [])
            Surfaces.undeclare(name);
        const surfaces = Object.assign({}, root._surfaces);
        delete surfaces[plugin];
        root._surfaces = surfaces;
        const handlers = Object.assign({}, root._closeHandlers);
        delete handlers[plugin];
        root._closeHandlers = handlers;
    }

    Connections {
        target: PluginRegistry

        function onEnabledPluginsChanged(): void {
            const enabled = PluginRegistry.enabledPlugins;
            const known = Object.keys(root._surfaces).concat(Object.keys(root._closeHandlers));
            for (const plugin of known) {
                if (!enabled.includes(plugin))
                    root._revoke(plugin);
            }
        }
    }

    Connections {
        target: Surfaces

        function onCloseRequested(screenState: var, name: string): void {
            const owner = Core.parseSurface(name);
            if (!owner)
                return;
            for (const fn of root._closeHandlers[owner.plugin] ?? []) {
                try {
                    fn(screenState, owner.local);
                } catch (e) {
                    console.warn(`PluginApi: ${owner.plugin}'s close handler threw: ${e}`);
                }
            }
        }
    }
}
