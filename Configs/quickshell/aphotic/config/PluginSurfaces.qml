pragma Singleton
import QtQuick
import qs.config

QtObject {
    id: root

    readonly property var kinds: [
        { id: "dashboard", icon: "dashboard", description: qsTr("Adds a Dashboard tab: %1") },
        { id: "notch", icon: "expand_more", description: qsTr("Adds a notch tile: %1") },
        { id: "settings", icon: "tune", description: qsTr("Adds a Settings section: %1") },
        { id: "overlay", icon: "layers", description: qsTr("Adds an overlay: %1") },
        { id: "fullscreen-overlay", icon: "fullscreen", description: qsTr("Adds a fullscreen overlay: %1") }
    ]

    function kind(surface: string): var {
        return root.kinds.find(k => k.id === surface) ?? root.kinds[0];
    }

    function iconFor(surface: string): string {
        return root.kind(surface).icon;
    }

    function describe(surface: string, label: string): string {
        return root.kind(surface).description.arg(label);
    }

    function jumpsFor(plugin: string): var {
        return SettingsCategories.pluginSections.filter(s => s.plugin === plugin).map(s => ({
            surface: "settings",
            icon: "settings",
            label: s.label,
            address: `${s.parentId}/${s.id}`
        }));
    }

    function navigate(screenState: var, jump: var): void {
        if (jump.surface === "settings")
            screenState.settingsCategory = jump.address;
    }
}
