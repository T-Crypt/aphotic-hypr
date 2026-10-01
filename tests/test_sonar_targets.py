import shutil
import pytest
from test_sonar_session import run_probe

PROBE = """import QtQuick
import Quickshell
import qs.components
import qs.services
ShellRoot {
    id: root
    property var results: ({})
    property var captured: null
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 320
        implicitHeight: 240
        Item {
            id: liveItem
            x: 30; y: 40; width: 100; height: 50
            property QtObject adapter: Loader {
                active: Settings.sonarEnabled
                sourceComponent: EchoTarget {
                    target: liveItem
                    targetId: "core:probe"
                    label: "Probe"
                }
            }
        }
    }
    Timer {
        interval: 50; running: true; repeat: true
        property int phase: 0
        onTriggered: {
            if (phase++ === 0) {
                root.results.disabledAbsent = EchoRegistry.anchors.length === 0;
                Settings.sonarEnabled = true;
            } else if (phase === 2) {
                const targets = EchoRegistry.snapshot();
                root.results.live = targets.length === 1 && targets[0].rect.width === 100;
                root.results.shortcut = targets[0]?.shortcut === "Click";
                root.results.target = targets[0];
                Sonar.targets = targets;
                root.captured = Sonar.visibleTargets;
                liveItem.opacity = 0.5;
            } else if (phase === 3) {
                root.results.opacityStable = root.captured === Sonar.visibleTargets;
                liveItem.visible = false;
            } else if (phase === 4) {
                root.results.hiddenGone = EchoRegistry.snapshot().length === 0 && !EchoRegistry.isCurrent(root.results.target);
                Settings.sonarEnabled = false;
            } else if (phase === 5) {
                root.results.detached = EchoRegistry.anchors.length === 0;
                delete root.results.target;
                console.log("SONAR_SESSION " + JSON.stringify(root.results));
                Qt.quit();
            }
        }
    }
}
"""

@pytest.mark.skipif(shutil.which("qs") is None, reason="needs Quickshell")
def test_live_adapter_is_lazy_and_revokes_hidden_targets(tmp_path):
    out = run_probe(tmp_path, PROBE)
    assert set(out) == {"disabledAbsent", "live", "shortcut", "opacityStable", "hiddenGone", "detached"}, out
    assert all(out.values()), out

GHOST_PROBE = """import QtQuick
import Quickshell
import qs.services
ShellRoot {
    id: root
    property var results: ({})
    property var ghost: null
    property bool ready: PluginRegistry.isInstalled("sample") && InstallProfile.known
    QtObject {
        id: state
        property var modelData: Quickshell.screens[0]
        property bool sonar: false
        property var surfaceStack: []
        property bool dashboard: false
        property bool settings: false
        property bool notificationCenter: false
        property bool launcher: false
        property bool workspace: false
        property string dashboardTabRequest: ""
        property string settingsCategory: ""
        onSonarChanged: Surfaces.track(state,"sonar",state.sonar)
    }
    Timer {
        interval: 80; running: true; repeat: true
        property int phase: 0
        onTriggered: {
            if (!root.ready && phase === 0) return;
            if (phase++ === 0) {
                Settings.sonarEnabled = true;
                Settings.sonarGhosts = true;
                Sonar.screenStates = [state];
                Sonar.ping(state);
            } else if (phase === 2) {
                root.results.disabledHasMetadata = PluginRegistry.discoverySurfaces.some(s => s.plugin === "sample" && s.action === "enable");
                root.results.noExecution = PluginRegistry.surfaceRegistrations.length === 0;
                root.results.aiHidden = !PluginRegistry.discoverySurfaces.some(s => s.plugin === "blocked-ai");
                root.results.malformedHidden = !PluginRegistry.discoverySurfaces.some(s => s.plugin === "malformed");
                root.ghost = Sonar.visibleTargets.find(t => t.plugin === "sample");
                root.results.hasGhost = !!root.ghost;
                SafeMode.active = true;
                root.results.safeModeRevoked = !SonarDiscovery.current(root.ghost);
                SafeMode.active = false;
                PluginRegistry._data = {installed:{},disabled:[]};
            } else if (phase === 3) {
                root.results.removalRevoked = !SonarDiscovery.current(root.ghost);
                root.results.removalClickDenied = !Sonar.activateGhost(root.ghost);
                const tab = Sonar.visibleTargets.find(t => t.id === "core:dashboard/tab-flow");
                root.results.opened = Sonar.activateGhost(tab) && !Sonar.active && state.dashboard && state.dashboardTabRequest === "flow";
                console.log("SONAR_SESSION " + JSON.stringify(root.results));
                Qt.quit();
            }
        }
    }
}
"""

@pytest.mark.skipif(shutil.which("qs") is None, reason="needs Quickshell")
def test_ghosts_are_metadata_only_and_recheck_eligibility(tmp_path):
    import json
    folder = tmp_path / "home/.local/state/aphotic"
    folder.mkdir(parents=True)
    surface = {"surface":"dashboard", "id":"panel", "label":"Panel", "component":"MustNotExecute.qml"}
    installed = {"sample":{"capabilities":["ui-surface"],"ui":{"surfaces":[surface]}},
                 "blocked-ai":{"capabilities":["ui-surface"],"ui":{"surfaces":[{**surface,"requires_layer":"ai"}]}},
                 "malformed":{"capabilities":{},"ui":{"surfaces":{}}}}
    (folder / "plugins.json").write_text(json.dumps({"installed":installed,"disabled":list(installed)}))
    profile = tmp_path / "home/Aphotic-Hypr"
    profile.mkdir(parents=True)
    (profile / "aphotic.toml").write_text('profile = "base"\nlayers = []\n')
    out = run_probe(tmp_path, GHOST_PROBE)
    assert set(out) == {"disabledHasMetadata","noExecution","aiHidden","malformedHidden","hasGhost","safeModeRevoked","removalRevoked","removalClickDenied","opened"}, out
    assert all(out.values()), out


ENABLE_PROBE = GHOST_PROBE[:GHOST_PROBE.index("    Timer {")] + """
    Timer {
        interval: 80; running: true; repeat: true
        property int phase: 0
        onTriggered: {
            if (!root.ready && phase === 0) return;
            if (phase++ === 0) {
                Settings.sonarEnabled = true;
                Settings.sonarGhosts = true;
                Sonar.screenStates = [state];
                Sonar.ping(state);
            } else if (phase === 2) {
                const target = Sonar.visibleTargets.find(t => t.plugin === "sample");
                root.results.routed = Sonar.activateGhost(target) && !Sonar.active;
                root.results.noOptimism = !PluginRegistry.isEnabled("sample");
            } else if (phase >= 3) {
                const finished = EXPECT_FAILURE ? Notifs.list.length > 0 : PluginRegistry.isEnabled("sample");
                if (!finished && phase < 12) return;
                root.results.completed = finished;
                root.results.registryCorrect = EXPECT_FAILURE ? !PluginRegistry.isEnabled("sample") : PluginRegistry.isEnabled("sample");
                console.log("SONAR_SESSION " + JSON.stringify(root.results));
                Qt.quit();
            }
        }
    }
}
"""

@pytest.mark.skipif(shutil.which("qs") is None, reason="needs Quickshell")
@pytest.mark.parametrize("failure", [False, True])
def test_ghost_enable_uses_existing_cli_and_reports_failure(tmp_path, failure):
    import json
    import os
    folder = tmp_path / "home/.local/state/aphotic"
    folder.mkdir(parents=True)
    entry = {"capabilities":["ui-surface"], "ui":{"surfaces":[{"surface":"dashboard","id":"panel","label":"Panel","component":"NeverLoad.qml"}]}}
    (folder / "plugins.json").write_text(json.dumps({"installed":{"sample":entry},"disabled":["sample"]}))
    profile = tmp_path / "home/Aphotic-Hypr"
    profile.mkdir(parents=True)
    (profile / "aphotic.toml").write_text('profile = "base"\nlayers = []\n')
    binary = tmp_path / "bin"
    binary.mkdir()
    executable = binary / "aphotic"
    executable.write_text("""#!/usr/bin/python3
import json, os, sys
from pathlib import Path
Path(os.environ['SONAR_TEST_LOG']).write_text(json.dumps(sys.argv[1:]))
if os.environ['SONAR_TEST_FAILURE'] == '1': sys.exit(7)
p = Path(os.environ['HOME']) / '.local/state/aphotic/plugins.json'
data = json.loads(p.read_text())
data['disabled'] = []
p.write_text(json.dumps(data))
""")
    executable.chmod(0o755)
    log = tmp_path / "command.json"
    out = run_probe(tmp_path, ENABLE_PROBE.replace("EXPECT_FAILURE", "true" if failure else "false"),
                    {"PATH":str(binary)+":"+os.environ["PATH"],"SONAR_TEST_LOG":str(log),"SONAR_TEST_FAILURE":"1" if failure else "0"})
    assert set(out) == {"routed","noOptimism","completed","registryCorrect"}, out
    assert all(out.values()), out
    assert json.loads(log.read_text()) == ["plugin","enable","sample"]

HOSTS_PROBE = """import QtQuick
import Quickshell
import qs.components
import qs.services
ShellRoot {
    id: root
    property var objects: []
    property var errors: []
    ScreenState { id: state; modelData: Quickshell.screens[0] }
    FloatingWindow { id: window; visible: true; implicitWidth: 1200; implicitHeight: 900 }
    Component.onCompleted: {
        const specs = [
            ["modules/bar/components/Clock.qml",{screenState:state}],
            ["modules/bar/components/StatusIcons.qml",{screenState:state}],
            ["modules/bar/components/OsIcon.qml",{}],
            ["modules/bar/components/SettingsButton.qml",{screenState:state}],
            ["modules/bar/capsule/CapsuleClock.qml",{screenState:state}],
            ["modules/notch/Notch.qml",{screenState:state}],
            ["modules/notch/NotchPaletteTile.qml",{screenState:state}],
            ["modules/notch/NotchProcessTile.qml",{screenState:state}],
            ["modules/dashboard/CommandCenterTabBar.qml",{currentTab:"flow",tabs:[{id:"flow",label:"Flow",icon:"hub"}]}]
        ];
        for (let i = 0; i < specs.length; i++) {
            const comp = Qt.createComponent(specs[i][0]);
            if (comp.status !== Component.Ready) { root.errors.push(comp.errorString()); continue; }
            const object = comp.createObject(window.contentItem,Object.assign({x:10,y:i*80,width:600,height:60},specs[i][1]));
            if (!object) root.errors.push(specs[i][0]+": "+comp.errorString());
            else root.objects.push(object);
            comp.destroy();
        }
        Settings.sonarEnabled = true;
    }
    Timer {
        interval: 200; running: true
        onTriggered: {
            const targets = EchoRegistry.snapshot();
            console.log("SONAR_SESSION " + JSON.stringify({constructed:root.objects.length, errors:root.errors,
                liveClock:targets.some(t => t.id === "core:bar/clock"), tab:targets.some(t => t.id === "core:dashboard/tab-flow")}));
            Qt.quit();
        }
    }
}
"""

@pytest.mark.skipif(shutil.which("qs") is None, reason="needs Quickshell")
def test_live_host_adapters_construct_without_loading_hidden_panels(tmp_path):
    out = run_probe(tmp_path, HOSTS_PROBE)
    assert out["errors"] == [], out
    assert out["constructed"] == 9, out
    assert out["liveClock"] and out["tab"], out
