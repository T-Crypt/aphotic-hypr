// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.config
import qs.services

// ACT-01. One list of everything a user can ask the shell to do, and one
// way to ask for it.
//
// An action is a named, invokable thing -- not a surface. Core ships a
// static set every install has; a plugin declaring `[action]` in its
// manifest contributes more, present only while that plugin is installed,
// enabled and past its own gate. Both end up in `actions`, in one list
// rather than two beside each other, for the same reason AiProviders
// merges plugin pills into its own provider list: two lists would make
// every consumer choose which one it meant, and choose wrong somewhere.
//
// The palette notch tile is the first consumer. It is deliberately not
// the only shape this supports -- `invoke()` is callable from anything,
// including `qs ipc call aphotic action <id>` (shell.qml), which is what
// makes an action reachable from a keybind and the CLI without a second
// registration. A launcher mode, the dashboard and the assistant are the
// remaining consumers, and they add a call site here, not a list.
//
// Invocation takes a context rather than reaching for a window itself: a
// ScreenState is per-monitor, and an action fired from the palette should
// land on the monitor the palette is on, not on whichever screen
// enumerates first. A caller with no context (an IPC call arriving from a
// keybind) resolves the focused screen's state and passes that.
Singleton {
    id: root

    // Which Settings pane each `settings.*` action opens, derived from the
    // rail's own category list rather than restated here -- a category
    // added there is an action here with no edit, and the two cannot
    // drift into disagreeing about what a pane is called.
    readonly property var _settingsActions: SettingsCategories.list.map(c => ({
        id: `settings.${c.id}`,
        icon: c.icon,
        label: qsTr("Settings: %1").arg(c.label),
        plugin: ""
    }))

    readonly property var coreActions: [
        {
            id: "settings.open",
            icon: "settings",
            label: qsTr("Open Settings"),
            plugin: ""
        },
        {
            id: "keybinds.cheatsheet",
            icon: "keyboard",
            label: qsTr("Keyboard shortcuts"),
            plugin: ""
        },
        {
            id: "theme.cycle",
            icon: "palette",
            label: qsTr("Next theme"),
            plugin: ""
        }
    ].concat(root._settingsActions)

    readonly property var pluginActions: PluginRegistry.actionRegistrations.map(a => ({
        id: a.id,
        icon: a.icon,
        label: a.label,
        plugin: a.plugin,
        componentUrl: a.componentUrl
    }))

    // The one list every action surface reads.
    readonly property var actions: root.coreActions.concat(root.pluginActions)

    function find(id: string): var {
        return root.actions.find(a => a.id === id) ?? null;
    }

    // Whether an action id still resolves. A palette slot naming a plugin
    // action outlives the plugin being removed -- the slot stays in the
    // user's settings.json so re-installing the plugin brings it back
    // rather than silently dropping it -- so every consumer has to be able
    // to ask, and to render the gap rather than an empty row.
    function has(id: string): bool {
        return root.find(id) !== null;
    }

    function invoke(id: string, context: var): void {
        const action = root.find(id);
        if (!action) {
            console.warn(`aphotic action: unknown id '${id}'`);
            return;
        }

        if (action.plugin.length > 0) {
            root._runPluginAction(action);
            return;
        }

        const handler = root._coreHandlers[id] ?? (id.startsWith("settings.") ? root._openSettingsCategory : null);
        if (handler)
            handler(context ?? ({}), id);
    }

    // A plugin's action component is headless: it does its work in
    // `Component.onCompleted` and has nothing to show, so it is built,
    // allowed to run, and torn down in the same call. Same contract as a
    // pet_action's component (PetActionMenu.qml), built without a Loader
    // because this singleton has no visual tree to put one in -- and
    // because an action has to be invokable from IPC, where there is no
    // surface on screen at all.
    function _runPluginAction(action: var): void {
        const component = Qt.createComponent(action.componentUrl);
        if (component.status === Component.Error) {
            console.warn(`aphotic action: ${action.id} failed to load: ${component.errorString()}`);
            component.destroy();
            return;
        }

        const instance = component.createObject(null);
        if (instance)
            instance.destroy();
        else
            console.warn(`aphotic action: ${action.id} produced no object`);
        component.destroy();
    }

    readonly property var _coreHandlers: ({
        "settings.open": context => root._openSettings(context, ""),
        "keybinds.cheatsheet": context => {
            if (context.screenState)
                context.screenState.keybindsCheatsheet = true;
        },
        // Cycles the installed themes rather than opening a picker: the
        // palette is the place a thing happens, not a route to the place
        // it happens. Themes.setTheme picks the theme's own default
        // wallpaper when handed an empty one.
        "theme.cycle": () => {
            const themes = Themes.themes;
            if (themes.length < 2)
                return;
            const i = themes.findIndex(t => t.name === Themes.activeTheme);
            Themes.setTheme(themes[(i + 1) % themes.length].name, "");
        }
    })

    function _openSettingsCategory(context: var, id: string): void {
        root._openSettings(context, id.slice("settings.".length));
    }

    function _openSettings(context: var, category: string): void {
        if (!context.screenState)
            return;
        if (category.length > 0)
            context.screenState.settingsCategory = category;
        context.screenState.settings = true;
    }
}
