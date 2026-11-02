"""Every bar style fits inside its own strip at both orientations.

A side-docked bar is a strip one bar thick. A style that lays its entries
out in a single row overflows that strip, and the wrapper clips whatever
runs past it: icons vanish or get squeezed to nothing. The probe builds
each style offscreen, with three groups of status icons, at the strip
size the wrapper would give it. Each bar is built at the other
orientation and then flipped, the way the async settings load and the
edge switch in Settings both do it live. The probe then walks the item
tree for a visible child outside the bar, outside the nearest ancestor
that clips it, or squeezed below its own implicit size. The full style is
left out: its drop shadow and elided window title extend past the strip
on purpose.
"""
import shutil

import pytest
from test_sonar_session import run_probe

PROBE = r"""import QtQuick
import Quickshell
import qs.components
import qs.services
import qs.modules.bar
import qs.config

ShellRoot {
    id: shell
    property var results: []
    property int step: 0
    readonly property var cases: [
        ["minimal", true], ["minimal", false], ["taskbar", true], ["taskbar", false], ["capsule", true], ["capsule", false], ["dock", true], ["dock", false]
    ]
    readonly property var statusIcons: ["network", "bluetooth", "vpn", "hostInfo", "groupDivider", "lockStatus", "resources", "networkSpeed", "pomodoro", "battery", "groupDivider", "dnd", "notifCenter"].map(id => ({ id, enabled: true }))
    ScreenState { id: ss }

    FloatingWindow {
        id: win
        visible: true
        implicitWidth: 1920
        implicitHeight: 1080
        Item { id: host; anchors.fill: parent }
    }
    Component { id: minimalC; MinimalBar { screen: Quickshell.screens[0]; screenState: ss; popouts: null; fullscreen: false; thickness: shell.thick } }
    Component { id: taskbarC; TaskbarBar { screen: Quickshell.screens[0]; screenState: ss; popouts: null; fullscreen: false; thickness: shell.thick } }

    Component { id: fullC; Bar { screen: Quickshell.screens[0]; screenState: ss; popouts: null; fullscreen: false; thickness: shell.thick } }
    Component { id: capsuleC; CapsuleBar { screen: Quickshell.screens[0]; screenState: ss } }
    Component { id: dockC; DockBar { screen: Quickshell.screens[0]; screenState: ss } }
    property var bar: null
    property real thick: 44
    function check(name, horiz) {
        const issues = [];
        const lay = bar.children.find(c => c.objectName === "" && c.flow !== undefined) ;
        function clipper(c) {
            for (let p = c.parent; p && p !== bar; p = p.parent)
                if (p.clip)
                    return p;
            return bar;
        }
        function walk(item, depth) {
            for (const c of item.children) {
                if (!c.visible || c.width <= 0 && c.height <= 0) continue;
                if (c.item === null) continue;
                const box = clipper(c);
                const p = c.mapToItem(box, 0, 0);
                if (p.x < -1 || p.y < -1 || p.x + c.width > box.width + 1 || p.y + c.height > box.height + 1)
                    issues.push(`out ${c} in ${box} at ${Math.round(p.x)},${Math.round(p.y)} ${Math.round(c.width)}x${Math.round(c.height)}`);
                if (c.implicitWidth > 0 && c.width + 1 < c.implicitWidth && c.implicitWidth < 500 || c.implicitHeight > 0 && c.height + 1 < c.implicitHeight && c.implicitHeight < 500)
                    issues.push(`squeezed ${c} ${Math.round(c.width)}x${Math.round(c.height)} < ${Math.round(c.implicitWidth)}x${Math.round(c.implicitHeight)}`);
                if (depth < 6) walk(c, depth + 1);
            }
        }
        walk(bar, 0);
        return { name, horiz, size: `${bar.width}x${bar.height}`, issues: issues.slice(0, 12), count: issues.length };
    }
    Timer {
        interval: 700; running: true; repeat: true
        onTriggered: {
            if (shell.bar) {
                const c = shell.cases[shell.step - 1];
                shell.results.push(shell.check(c[0], c[1]));
                shell.bar.destroy(); shell.bar = null;
            }
            if (shell.step >= shell.cases.length) {
                console.log("BARCHECK " + JSON.stringify(shell.results));
                Qt.quit(); return;
            }
            const c = shell.cases[shell.step++];
            Settings.barStatusIcons = shell.statusIcons;
            Settings.barHorizontal = !c[1];
            Settings.barLayout = c[0];
            shell.thick = Math.round(Settings.barInnerWidth + Math.max(Tokens.padding.small, Config.border.thickness) * 2);
            const comp = ({ full: fullC, minimal: minimalC, taskbar: taskbarC, capsule: capsuleC, dock: dockC })[c[0]];
            shell.bar = comp.createObject(host, shell.stripSize(c[0], !c[1]));
            flip.restart();
        }
    }
    function stripSize(style, horiz) {
        if (style !== "minimal" && style !== "taskbar")
            return {};
        return horiz ? { width: 1920, height: shell.thick } : { width: shell.thick, height: 1080 };
    }
    Timer {
        id: flip
        interval: 250
        onTriggered: {
            const c = shell.cases[shell.step - 1];
            Settings.barHorizontal = c[1];
            const size = shell.stripSize(c[0], c[1]);
            for (const k in size)
                shell.bar[k] = size[k];
        }
    }
}
"""

CASES = [(s, h) for s in ("minimal", "taskbar", "capsule", "dock") for h in (True, False)]


@pytest.fixture(scope="module")
def results(tmp_path_factory):
    if shutil.which("qs") is None:
        pytest.skip("Quickshell unavailable")
    out = run_probe(tmp_path_factory.mktemp("barfit"), PROBE, marker="BARCHECK", prefix="_barfit_")
    return {(r["name"], r["horiz"]): r for r in out}


@pytest.mark.parametrize("style,horizontal", CASES)
def test_bar_style_fits_its_strip(results, style, horizontal):
    r = results[(style, horizontal)]
    assert r["count"] == 0, r
