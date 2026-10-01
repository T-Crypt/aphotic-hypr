pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.services
import "SonarTargets.js" as Rules

Singleton {
    id: root

    function bounds(output: var, surface: string, metadata: var): var {
        let w = Math.min(output.width - 32, surface === "workspace" ? output.width - 32 : 900);
        let h = Math.min(output.height - 64, surface === "workspace" ? output.height - 64 : 620);
        let x = (output.width-w)/2, y = (output.height-h)/2;
        if (surface === "shelf") {
            w = Math.min(output.width, Settings.barInnerWidth + Tokens.padding.medium * 2);
            h = Math.max(1,Math.min(640,output.height - Tokens.padding.large * 2));
            x = metadata?.edge === "right" ? output.width-w-Tokens.padding.small : Tokens.padding.small;
            y = (output.height-h)/2;
        } else if (surface === "bar" || surface === "notch") {
            w = surface === "notch" ? 240 : 160; h = surface === "notch" ? 48 : 32;
            if (Settings.barHorizontal) {
                x = (output.width-w)/2; y = Settings.barPositionBottom ? output.height-h-8 : 8;
            } else {
                const swap = w; w = h; h = swap;
                x = Settings.barPositionRight ? output.width-w-8 : 8; y = (output.height-h)/2;
            }
        } else if (surface === "overlay" && metadata) {
            w = Math.min(output.width-16,metadata.width); h = Math.min(output.height-16,metadata.height);
            x = metadata.anchor === "left" ? 8 : metadata.anchor === "right" ? output.width-w-8 : (output.width-w)/2;
            y = metadata.anchor === "top" ? 8 : metadata.anchor === "bottom" ? output.height-h-8 : (output.height-h)/2;
        } else if (surface === "desktopClock") {
            w = Math.min(300,output.width-32); h = Math.min(140,output.height-32);
            const position = Config.background.desktopClock.position;
            x = /left/i.test(position) ? 16 : /right/i.test(position) ? output.width-w-16 : (output.width-w)/2;
            y = /top/i.test(position) ? 16 : /bottom/i.test(position) ? output.height-h-16 : (output.height-h)/2;
        }
        return {x:Math.max(0,x),y:Math.max(0,y),width:Math.max(1,Math.min(w,output.width)),height:Math.max(1,Math.min(h,output.height))};
    }

    function stateFor(output: string): var {
        return Array.from(Sonar.screenStates).find(s => s.modelData?.name === output)
            ?? (output === Sonar.focusOutput ? Sonar.sessionScreen : null);
    }

    function snapshot(outputs: var, live: var): var {
        const result = [];
        function put(output, id, label, surface, route, extra) {
            if (live.some(t => t.output === output.name && t.id === id)) return;
            result.push(Object.assign({id:id,output:output.name,label:label,rect:root.bounds(output,surface),
                ghost:true,disabled:false,route:route,surface:surface,shortcut:"Click"},extra || {}));
        }
        for (const o of outputs) {
            const state = root.stateFor(o.name);
            if (!state) continue;
            for (const panel of [{id:"dashboard",label:qsTr("Command Center"),bind:"Toggle Command Center"},
                {id:"settings",label:qsTr("Settings"),bind:"Toggle Settings"},
                {id:"notificationCenter",label:qsTr("Notifications"),bind:"Toggle Notification Center"},
                {id:"launcher",label:qsTr("App launcher"),bind:"Toggle app launcher"}]) {
                if (state[panel.id]) continue;
                put(o,"core:"+panel.id,panel.label,panel.id,"core-open",{shortcut:Rules.shortcut(HyprKeybinds.entries,panel.bind)});
            }
            for (const edge of ["left","right"]) {
                if (Shelves.isOpen(o.name,edge)) continue;
                const enabled = Shelves.config(o.name)[edge].enabled;
                if (!enabled && !Settings.sonarGhosts) continue;
                put(o,"core:shelf/"+edge,edge === "left" ? qsTr("Left shelf") : qsTr("Right shelf"),"shelf",
                    enabled ? "shelf-open" : "shelf-enable",{edge:edge,disabled:!enabled,
                    rect:root.bounds(o,"shelf",{edge:edge}),shortcut:edge === "left" ? "Super + [" : "Super + ]"});
            }
            if (!state.dashboard) {
                const panel = root.bounds(o,"dashboard");
                const tabs = CommandCenterTabs.list.filter(t => t.id !== "aiChat" || InstallProfile.aiEnabled);
                tabs.forEach((tab,i) => put(o,"core:dashboard/tab-"+tab.id,tab.label,"dashboard","core-open",{
                    tab:tab.id,rect:{x:panel.x + 8 + i * Math.min(130,(panel.width-16)/tabs.length),y:panel.y+8,
                        width:Math.min(122,(panel.width-16)/tabs.length-8),height:40}}));
            }
            if (!state.workspace && PluginRegistry.surfacesFor("workspace").length > 0)
                put(o,"core:workspace",qsTr("Workspace"),"workspace","core-open",{shortcut:Rules.shortcut(HyprKeybinds.entries,"Toggle plugin workspace")});
            if (Settings.sonarGhosts && !Settings.desktopClockEnabled)
                put(o,"core:desktop-clock",qsTr("Desktop clock"),"desktopClock","core-enable",{disabled:true});
            for (const surface of PluginRegistry.discoverySurfaces) {
                const disabled = surface.action !== "open";
                if (disabled && !Settings.sonarGhosts) continue;
                if (!disabled && ((surface.surface === "dashboard" && state.dashboard) || (surface.surface === "workspace" && state.workspace))) continue;
                const known = ["dashboard","workspace","settings"].includes(surface.surface);
                const route = surface.action === "enable" ? "plugin-enable" : surface.action === "settings" || !known ? "plugin-settings" : "plugin-open";
                put(o,"discovery:"+surface.plugin+"/"+surface.surface+"/"+surface.id,surface.label,surface.surface,route,
                    {plugin:surface.plugin,local:surface.id,disabled:disabled,reason:surface.reason,rect:root.bounds(o,surface.surface,surface)});
            }
        }
        return result;
    }

    function current(target: var): bool {
        if (!target || !root.stateFor(target.output)) return false;
        if (target.surface === "shelf") {
            const enabled = Shelves.config(target.output)[target.edge]?.enabled === true;
            return !Shelves.isOpen(target.output,target.edge) && (target.route === "shelf-open" ? enabled : !enabled && Settings.sonarGhosts);
        }
        if (target.plugin) {
            const now = PluginRegistry.discoveryOf(target.plugin,target.surface,target.local);
            if (!now || (now.action !== "open" && !Settings.sonarGhosts)) return false;
            if (target.route === "plugin-enable") return now.action === "enable";
            if (target.route === "plugin-open") return now.action === "open";
            return true;
        }
        if (target.route === "core-enable") return Settings.sonarGhosts && !Settings.desktopClockEnabled;
        if (target.tab === "aiChat" && !InstallProfile.aiEnabled) return false;
        return target.surface !== "workspace" || PluginRegistry.surfacesFor("workspace").length > 0;
    }

    function activate(target: var, state: var): bool {
        if (!state) return false;
        if (target.surface === "shelf") {
            if (!root.current(target)) return false;
            if (target.route === "shelf-enable" && !Shelves.update(target.output,target.edge,{enabled:true})) return false;
            return Shelves.toggle(target.output,target.edge);
        }
        if (target.plugin) {
            const now = PluginRegistry.discoveryOf(target.plugin,target.surface,target.local);
            if (!now || (target.route === "plugin-enable" && now.action !== "enable")) return false;
        }
        if (target.route === "core-enable" && (!Settings.sonarGhosts || Settings.desktopClockEnabled)) return false;
        if (target.route === "plugin-enable") {
            if (enabler.running) return false;
            enabler.plugin = target.plugin;
            enabler.command = ["aphotic","plugin","enable",target.plugin];
            enabler.running = true;
        } else if (target.route === "plugin-settings") {
            state.settingsCategory = "plugins";
            state.settings = true;
        } else if (target.route === "plugin-open") {
            if (target.surface === "dashboard") {
                state.dashboardTabRequest = target.local;
                state.dashboard = true;
            } else if (target.surface === "workspace") state.workspace = true;
            else {
                const section = SettingsCategories.pluginSections.find(s => s.plugin === target.plugin && s.id === target.local);
                state.settingsCategory = section ? section.parentId + "/" + section.id : "plugins";
                state.settings = true;
            }
        } else if (target.route === "core-enable") {
            Settings.desktopClockEnabled = true;
        } else if (target.route === "core-open") {
            if (target.surface === "dashboard") {
                state.dashboardTabRequest = target.tab || "dashboard";
                state.dashboard = true;
            } else if (target.surface === "settings") state.settings = true;
            else if (target.surface === "notificationCenter") state.notificationCenter = true;
            else if (target.surface === "launcher") state.launcher = true;
            else if (target.surface === "workspace") state.workspace = true;
            else return false;
        } else return false;
        return true;
    }

    Process {
        id: enabler
        property string plugin: ""
        onExited: (code, status) => {
            if (code !== 0)
                Notifs.notify(qsTr("Could not enable plugin"), qsTr("Open Plugins in Settings to review %1.").arg(enabler.plugin), [], "Aphotic");
        }
    }
}
