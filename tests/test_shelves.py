"""Shelf state/content probes use disposable state; the PanelWindow probe needs Wayland."""
import json
import os
import shutil
import subprocess
from pathlib import Path
import pytest
from test_sonar_session import run_probe

ROOT = Path(__file__).resolve().parents[1]

def test_shelf_policy_and_shared_dock_grouping():
    subprocess.run(['node', str(ROOT/'tests/test_shelves.cjs')],check=True)

PROBE = '''import QtQuick
import Quickshell
import qs.components
import qs.services
ShellRoot {
    id: root
    property var result: ({})
    property int phase: 0
    property string output: "DP-1"
    QtObject { id: state; property var modelData: ({name:"DP-1"}); property var surfaceStack: [] }
    QtObject { id: second; property var modelData: ({name:"DP-2"}); property var surfaceStack: [] }
    Component.onCompleted: { Shelves.screenStates = [state]; Sonar.screenStates = [state]; Shelves.screens = [{name:root.output,description:"Monitor"}]; }
    Timer {
        interval: 60; repeat: true; running: true
        onTriggered: {
            if (root.phase === 0) {
                root.result.disabled = !Shelves.toggle(root.output,"left");
                root.result.invalid = !Shelves.toggle(root.output,"bad");
                Shelves.update(root.output,"left",{enabled:true,pinned:["sample"]});
                Shelves.update(root.output,"right",{enabled:true});
                Shelves.toggle(root.output,"left"); Shelves.toggle(root.output,"right");
                root.result.both = Shelves.openEdges.length === 2 && state.surfaceStack.length === 2;
                Surfaces.back(state);
                root.result.back = Shelves.isOpen(root.output,"left") && !Shelves.isOpen(root.output,"right");
                Shelves.toggle(root.output,"left");
                root.result.toggleClosed = Shelves.openEdges.length === 0;
                Shelves.toggle(root.output,"left");
                Shelves.update(root.output,"left",{enabled:false});
                root.result.disable = Shelves.openEdges.length === 0;
                Shelves.toggle(root.output,"right"); Surfaces.hold("probe");
                root.result.block = Shelves.openEdges.length === 0 && !Shelves.toggle(root.output,"right");
                Surfaces.release("probe");
                Shelves.toggle(root.output,"right"); SessionLockState.locked = true;
                root.result.lock = Shelves.openEdges.length === 0;
                SessionLockState.locked = false;
                Shelves.toggle(root.output,"right"); Surfaces.track(state,"launcher",true);
                root.result.displaced = Shelves.openEdges.length === 0;
                Surfaces.track(state,"launcher",false);
                Shelves.toggle(root.output,"right");
                Shelves.screenStates = [];
                root.result.removedState = Shelves.openEdges.length === 0;
                root.result.saved = Shelves.config(root.output).right.enabled;
                root.result.newDisabled = !Shelves.config("fresh-monitor").right.enabled;
                Shelves.screenStates = [state];
                Settings.sonarGhosts = true;
                const ghosts = SonarDiscovery.snapshot([{name:root.output,x:0,y:0,width:800,height:600}],[]);
                const g = ghosts.find(t => t.id === "core:shelf/right");
                root.result.ghost = g && g.rect.x > 600 && SonarDiscovery.activate(g,state) && Shelves.isOpen(root.output,"right");
                Shelves.screens = [{name:root.output},{name:"DP-2"}];
                Shelves.screenStates = [state,second];
                Shelves.update("DP-2","left",{enabled:true}); Shelves.toggle("DP-2","left");
                Shelves.close(root.output);
                root.result.outputIsolation = Shelves.isOpen("DP-2","left") && state.surfaceStack.length === 0 && second.surfaceStack.length === 1;
                Shelves.screens = [{name:root.output}];
                root.result.outputRemoval = !Shelves.isOpen("DP-2","left") && Shelves.config("DP-2").left.enabled;
                root.phase++;
            } else {
                root.result.clean = Shelves.openEdges.length === 0 && state.surfaceStack.length === 0 && Object.keys(Surfaces.declared).length === 0;
                console.log("SONAR_SESSION " + JSON.stringify(root.result)); Qt.quit();
            }
        }
    }
}'''

@pytest.mark.skipif(shutil.which('qs') is None,reason='needs Quickshell')
def test_shelf_lifecycle_and_per_output_identity(tmp_path):
    out=run_probe(tmp_path,PROBE)
    assert len(out) == 16 and all(v is True for v in out.values()),out

CONTENT = '''import QtQuick
import Quickshell
import qs.services
import qs.modules.shelves
ShellRoot {
    id: root
    FloatingWindow { id: window; visible:true; implicitWidth:200; implicitHeight:700
        ShelfContent { id: content; anchors.fill:parent; output:Quickshell.screens[0].name; edge:"left" }
    }
    Timer { interval:150; running:true; onTriggered: {
        console.log("SONAR_SESSION " + JSON.stringify({ready:content.width > 0,empty:content.items.length === 0})); Qt.quit();
    }}
}'''

@pytest.mark.skipif(shutil.which('qs') is None,reason='needs Quickshell')
def test_shelf_content_constructs_without_scanning_processes(tmp_path):
    out=run_probe(tmp_path,CONTENT)
    assert all(out.values()),out

HOST = '''import QtQuick
import Quickshell
import qs.components
import qs.services
import qs.modules.shelves
ShellRoot {
    id: root
    property int phase:0
    property int cycles:0
    property var result:({})
    property string output: Quickshell.screens[0].name
    ScreenState { id:state; modelData:Quickshell.screens[0] }
    ShelfHost { id:host }
    function find(item,name) {
        if (item.objectName === name) return item;
        for (const c of item.children ?? []) { const found=root.find(c,name); if(found) return found; }
        return null;
    }
    Component.onCompleted: Shelves.screenStates=[state]
    Timer {
        interval:200; running:true; repeat:true
        onTriggered: {
            if (root.phase === 0) {
                root.result.disabledAbsent=host.mountedCount === 0;
                Shelves.update(root.output,"left",{enabled:true}); Shelves.update(root.output,"right",{enabled:true});
                root.phase++;
            } else if (root.phase === 1) {
                root.result.closedAbsent=host.mountedCount === 0;
                Shelves.toggle(root.output,"left"); Shelves.toggle(root.output,"right"); root.phase++;
            } else if (root.phase === 2) {
                root.result.bothMounted=host.mountedCount === 1;
                root.result.leftContent=host.instances[0].item.leftLoaded;
                root.result.rightContent=host.instances[0].item.rightLoaded;
                root.result.geometry=host.instances[0].item.width === Quickshell.screens[0].width;
                root.phase++;
            } else if (root.phase === 3) {
                root.find(host.instances[0].item.contentItem,"shelf-interior").clicked(null);
                root.result.insidePersists=Shelves.openEdges.length === 2;
                root.result.persistent=Shelves.openEdges.length === 2;
                Shelves.closeEdge(root.output,"left"); root.phase++;
            } else if (root.phase === 4) {
                if (host.instances[0].item.leftLoaded) return;
                root.result.oneMounted=host.mountedCount === 1 && !host.instances[0].item.leftLoaded && host.instances[0].item.rightLoaded;
                root.find(host.instances[0].item.contentItem,"shelf-click-away").clicked(null); root.phase++;
            } else if (root.phase === 5) {
                if (host.mountedCount !== 0) return;
                root.result.unmounted=true;
                if (++root.cycles < 5) { root.phase=1; return; }
                Shelves.toggle(root.output,"left"); Surfaces.hold("probe"); root.phase++;
            } else {
                root.result.suppressedAbsent=host.mountedCount === 0;
                Surfaces.release("probe");
                console.log("SONAR_SESSION " + JSON.stringify(root.result)); Qt.quit();
            }
        }
    }
    Timer { interval:10000; running:true; onTriggered: { console.log("SONAR_SESSION " + JSON.stringify({timeout:true})); Qt.quit(); } }
}'''

@pytest.mark.skipif(shutil.which('qs') is None or os.environ.get('SONAR_TEST_PLATFORM') != 'wayland',reason='needs explicit disposable Wayland backend')
def test_shelf_hosts_unmount_between_repeated_reveals(tmp_path):
    out=run_probe(tmp_path,HOST,{'QT_QPA_PLATFORM':'wayland'})
    assert out and 'timeout' not in out and all(out.values()),out

# A real plugin, installed into the probe's disposable HOME, so the tab
# path is exercised against a registry entry rather than a stubbed list.
PLUGIN = 'qml/EdgePanel.qml'
PLUGIN_QML = '''import QtQuick
Item {
    required property string edge
    required property string output
    required property string screen
    required property bool active
    objectName: "edge-tab-content"
    property int builds: builds.counter
    QtObject { id: builds; property int counter: 0; Component.onCompleted: counter++ }
    Rectangle { anchors.fill: parent; color: "transparent" }
}'''

def _registry(tmp_path, edges=("left", "right"), notch=False, enabled=True):
    """Write a plugins.json with one edge_tab plugin and return its dir."""
    home=tmp_path/'home'
    plug=home/'.local/share/aphotic/plugins/edge-demo/qml'
    plug.mkdir(parents=True,exist_ok=True)
    (plug/'EdgePanel.qml').write_text(PLUGIN_QML)
    state=home/'.local/state/aphotic'
    state.mkdir(parents=True,exist_ok=True)
    surface={"surface":"edge_tab","id":"panel","label":"Panel","icon":"dock_to_left",
        "component":"qml/EdgePanel.qml","edges":list(edges),"notch":notch}
    registry={"installed":{"edge-demo":{
        "name":"edge-demo","display_name":"Edge Demo","version":"1.0.0","capabilities":["ui-surface"],
        "ui":{"surfaces":[surface]},
        "disabled":[] if enabled else ["edge-demo"]}}}
    (state/'plugins.json').write_text(json.dumps(registry))
    return home

TABS='''import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services
import qs.modules.shelves
ShellRoot {
    id: root
    property int phase:0
    property var result:({})
    property string output: "DP-1"
    property var screens: [{name:root.output,description:"Probe"}]
    QtObject { id:state; property var modelData: ({name:"DP-1"}); property var surfaceStack: [] }

    function find(item,name) {
        if (item === null || item === undefined) return null;
        if (item.objectName === name) return item;
        for (const c of item.children ?? []) { const found=root.find(c,name); if(found) return found; }
        return null;
    }
    function countBuilds(item) {
        if (item === null || item === undefined) return 0;
        let total = item.objectName === "edge-tab-content" && item.builds > 0 ? 1 : 0;
        for (const c of item.children ?? []) total += root.countBuilds(c);
        return total;
    }
    Component.onCompleted: {
        Shelves.screenStates=[state];
        Shelves.screens=root.screens;
        Shelves.update(root.output,"left",{enabled:true});
    }
    FloatingWindow { visible:true; implicitWidth:240; implicitHeight:640
        ShelfContent { id: content; anchors.fill:parent; output:root.output; edge:"left"; screen:root.output }
    }
    Timer {
        interval:150; running:true; repeat:true
        onTriggered: {
            if (root.phase === 0) {
                // Core tabs resolve for either edge; a plugin tab resolves
                // only where its manifest allowed it.
                root.result.core=ShelfTabs.find("media","left") !== null && ShelfTabs.find("media","right") !== null;
                root.result.pluginLeft=ShelfTabs.find("edge-demo:panel","left") !== null;
                root.result.pluginRight=ShelfTabs.find("edge-demo:panel","right") !== null;
                root.result.bogus=ShelfTabs.find("nope","left") === null;
                root.result.namespaced=ShelfTabs.find("panel","left") === null;
                root.phase++;
            } else if (root.phase === 1) {
                // Opening through IPC refuses what the registry cannot
                // resolve, and an unknown id leaves the shelf as it was.
                root.result.unknownRefused=!Shelves.openTab(root.output,"left","nope");
                root.result.badEdgeRefused=!Shelves.openTab(root.output,"middle","media");
                root.result.emptyRefused=!Shelves.openTab(root.output,"left","");
                root.result.stillClosed=Shelves.openEdges.length === 0 && content.tabOpen === false;
                root.phase++;
            } else if (root.phase === 2) {
                root.result.opened=Shelves.openTab(root.output,"left","edge-demo:panel");
                root.phase++;
            } else if (root.phase === 3) {
                root.result.panelOpen=content.tabOpen && root.find(content,"edge-tab-content") !== null;
                root.result.saved=Shelves.config(root.output).left.tabs.length === 1;
                // Core content mounts too, in the same budget.
                Shelves.openTab(root.output,"left","media");
                root.phase++;
            } else if (root.phase === 4) {
                root.result.mediaOpen=Shelves.tabFor(root.output,"left")?.id === "media";
                root.result.onePanel=root.countBuilds(content) === 0;
                Shelves.closeTab(root.output,"left");
                root.phase++;
            } else if (root.phase === 5) {
                // Closing a tab leaves the shelf on its dock and unmounts
                // the plugin content with it.
                root.result.tabClosed=!content.tabOpen && root.countBuilds(content) === 0;
                root.result.dockBack=Shelves.isOpen(root.output,"left");
                root.phase++;
            } else if (root.phase === 6) {
                // Disabling the plugin revokes its registration: the tab
                // stops existing and the stored selection stops resolving.
                Shelves.openTab(root.output,"left","edge-demo:panel");
                SafeMode.active=true;
                root.phase++;
            } else if (root.phase === 7) {
                root.result.revoked=ShelfTabs.find("edge-demo:panel","left") === null;
                root.result.revokedRefused=!Shelves.openTab(root.output,"left","edge-demo:panel");
                root.result.panelGone=root.countBuilds(content) === 0;
                SafeMode.active=false;
                root.phase++;
            } else if (root.phase === 8) {
                // Notch exposure is opt-in and declaration-gated.
                root.result.notchOff=ShelfTabs.notchTabs.length === 0;
                Settings.shelfNotchTabs=true;
                root.phase++;
            } else if (root.phase === 9) {
                root.result.notchOn=ShelfTabs.notchTabs.length === 1;
                Settings.shelfNotchTabs=false;
                // Acknowledgement is off by default and never loops.
                ShelfTabs.notchTabs.length;
                Shelves.acknowledge(root.output,"left");
                root.result.ackOff=Shelves.ackCount(root.output,"left") === 0;
                Settings.shelfTabAcknowledge=true;
                Shelves.openTab(root.output,"left","quick");
                root.phase++;
            } else {
                root.result.ackOn=Shelves.ackCount(root.output,"left") === 1;
                const chip=root.find(content,"shelf-tab-quick");
                root.result.ackVisual=chip !== null && root.find(chip,"shelf-tab-trace").opacity > 0;
                console.log("SONAR_SESSION " + JSON.stringify(root.result)); Qt.quit();
            }
        }
    }
    Timer { interval:15000; running:true; onTriggered: { console.log("SONAR_SESSION " + JSON.stringify({timeout:true})); Qt.quit(); } }
}'''

@pytest.mark.skipif(shutil.which('qs') is None,reason='needs Quickshell')
def test_shelf_tabs_resolve_through_the_registry_and_mount_while_shown(tmp_path):
    home=_registry(tmp_path,notch=True)
    out=run_probe(tmp_path,TABS,{'HOME':str(home)})
    assert out and 'timeout' not in out and all(out.values()),out

RIGHT_ONLY='''import QtQuick
import Quickshell
import qs.config
import qs.components
import qs.services
import qs.modules.shelves
ShellRoot {
    id: root
    property string output: Quickshell.screens[0].name
    property var result:({})
    FloatingWindow { visible:true; implicitWidth:240; implicitHeight:640
        ShelfContent { anchors.fill:parent; output:root.output; edge:"right"; screen:root.output }
    }
    Timer { interval:200; running:true; onTriggered: {
        root.result.absentLeft=ShelfTabs.find("edge-demo:panel","left") === null;
        root.result.presentRight=ShelfTabs.find("edge-demo:panel","right") !== null;
        root.result.stripHiddenLeft=ShelfTabs.forEdge("left").every(t => t.core);
        console.log("SONAR_SESSION " + JSON.stringify(root.result)); Qt.quit();
    }}
    Timer { interval:10000; running:true; onTriggered: { console.log("SONAR_SESSION " + JSON.stringify({timeout:true})); Qt.quit(); } }
}'''

@pytest.mark.skipif(shutil.which('qs') is None,reason='needs Quickshell')
def test_shelf_tab_placement_limits_which_edges_offer_it(tmp_path):
    home=_registry(tmp_path,edges=("right",),notch=True)
    out=run_probe(tmp_path,RIGHT_ONLY,{'HOME':str(home)})
    assert out and 'timeout' not in out and all(out.values()),out

SHORTCUT = '''import QtQuick
import Quickshell
import qs.services
ShellRoot {
    id: root
    property int phase:0
    property var result:({})
    Component.onCompleted: {
        Shelves.screens=[{name:"DP-1"}];
        Shelves.update("DP-1","left",{enabled:true});
        Shelves.update("DP-1","right",{enabled:true});
    }
    Timer {
        interval:150; repeat:true; running:true
        onTriggered: {
            if (ShelfKeybinds.running) return;
            if (root.phase === 0) {
                root.result.leftBlocked=ShelfKeybinds.leftReason.length > 0;
                root.result.rightFree=ShelfKeybinds.rightReason.length === 0;
                Shelves.update("DP-1","right",{enabled:false}); root.phase++;
            } else {
                root.result.settled=!ShelfKeybinds.running;
                console.log("SONAR_SESSION " + JSON.stringify(root.result)); Qt.quit();
            }
        }
    }
}'''

@pytest.mark.skipif(shutil.which('qs') is None,reason='needs Quickshell')
def test_shelf_shortcuts_preserve_conflicts_and_remove_owned_binds(tmp_path):
    import json
    mock=tmp_path/'bin'
    mock.mkdir()
    state=tmp_path/'binds.json'
    user={'modmask':64,'key':'bracketleft','dispatcher':'exec','arg':'user-command'}
    state.write_text(json.dumps([user]))
    log=tmp_path/'calls.jsonl'
    script=mock/'hyprctl'
    script.write_text('''#!/usr/bin/python3
import os,json,sys,re
from pathlib import Path
state=Path(os.environ['SHELF_BINDS']); log=Path(os.environ['SHELF_CALLS'])
args=sys.argv[1:]
with log.open('a') as f: f.write(json.dumps(args)+'\\n')
binds=json.loads(state.read_text())
if args == ['-j','binds']: print(json.dumps(binds))
elif args[:2] == ['keyword','bindd']:
    parts=[s.strip() for s in args[2].split(',')]
    binds=[b for b in binds if b['key'] != parts[1]]
    binds.append({'modmask':64,'key':parts[1],'dispatcher':'exec','arg':parts[4]})
    state.write_text(json.dumps(binds)); print('ok')
elif args[:2] == ['keyword','unbind']:
    key=args[2].split(',')[1].strip()
    state.write_text(json.dumps([b for b in binds if b['key'] != key])); print('ok')
else: print('ok')
''')
    script.chmod(0o755)
    out=run_probe(tmp_path,SHORTCUT,{'PATH':str(mock)+':'+os.environ['PATH'],'SHELF_BINDS':str(state),'SHELF_CALLS':str(log)})
    assert all(out.values()),out
    assert json.loads(state.read_text()) == [user]
    calls=[json.loads(l) for l in log.read_text().splitlines()]
    assert any(c[:2] == ['keyword','bindd'] and 'bracketright' in c[2] for c in calls),calls
    assert any(c[:2] == ['keyword','unbind'] and 'bracketright' in c[2] for c in calls),calls
    assert not any(c[0] != '-j' and 'bracketleft' in ' '.join(c) for c in calls),calls

CONTENT_GATES = '''import QtQuick
import Quickshell
import qs.components
import qs.services
import qs.services.ai
import qs.modules.shelves
ShellRoot {
    id: root
    property int phase:0
    property var result:({})
    property var notchObject:null
    property var first:null
    property var second:null
    QtObject { id:state; property var modelData:({name:"DP-1"}) }
    FloatingWindow { id:window; visible:true; implicitWidth:700; implicitHeight:700 }
    Component { id:agents; ShelfAgentsTab {} }
    function find(item,name) {
        if (!item) return null;
        if(item.objectName === name) return item;
        for(const c of item.children ?? []) { const got=root.find(c,name); if(got) return got; }
        return null;
    }
    Component.onCompleted: Settings.shelfNotchTabs=true
    Timer {
        interval:150; repeat:true; running:true
        onTriggered: {
            if(root.phase === 0) {
                if(ShelfTabs.notchTabs.length === 0) return;
                const tab=ShelfTabs.notchTabs[0], tile={id:"shelf:"+tab.id,label:tab.label,icon:tab.icon,tab:tab};
                const c=Qt.createComponent("modules/notch/NotchBody.qml");
                root.notchObject=c.createObject(window.contentItem,{width:360,tiles:[tile],pluginTiles:[],shelfTiles:Qt.binding(() => ShelfTabs.notchTabs.map(t => ({id:"shelf:"+t.id,label:t.label,icon:t.icon,tab:t}))),
                    screenState:state,switchable:true,expanded:true,shownTileId:tile.id,activeTile:tile});
                root.result.notchConstructed=root.notchObject !== null;
                c.destroy();
                root.first=agents.createObject(window.contentItem,{owner:"shelf-agents:DP-1:left"});
                root.second=agents.createObject(window.contentItem,{owner:"shelf-agents:DP-2:right"});
                root.result.twoHolds=Object.keys(AgentEvents._holders).filter(k => k.startsWith("shelf-agents:")).length === 2;
                root.first.destroy(); root.phase++;
            } else if(root.phase === 1) {
                root.result.remainingHold=AgentEvents._holders["shelf-agents:DP-2:right"] !== undefined && AgentEvents._holders["shelf-agents:DP-1:left"] === undefined;
                const plugin=root.find(root.notchObject,"edge-tab-content");
                root.result.notchPlugin=plugin !== null && plugin.edge === "notch" && plugin.screen === "DP-1" && plugin.active;
                SafeMode.active=true; root.second.destroy(); root.phase++;
            } else {
                root.result.revoked=root.find(root.notchObject,"edge-tab-content") === null;
                root.result.released=Object.keys(AgentEvents._holders).filter(k => k.startsWith("shelf-agents:")).length === 0;
                console.log("SONAR_SESSION " + JSON.stringify(root.result)); Qt.quit();
            }
        }
    }
    Timer { interval:6000; running:true; onTriggered: { console.log("SONAR_SESSION " + JSON.stringify({timeout:true})); Qt.quit(); } }
}'''

@pytest.mark.skipif(shutil.which('qs') is None,reason='needs Quickshell')
def test_notch_tab_revocation_and_independent_agent_feed_holds(tmp_path):
    home=_registry(tmp_path,notch=True)
    out=run_probe(tmp_path,CONTENT_GATES,{'HOME':str(home)})
    assert len(out) == 6 and all(v is True for v in out.values()),out

API_BOUNDARIES = '''import QtQuick
import Quickshell
import qs.services
ShellRoot {
    id: root
    property int phase:0
    property var result:({})
    property var held:null
    property int callbacks:0
    QtObject { id:state; property var surfaceStack:[] }
    Timer {
        interval:100; repeat:true; running:true
        onTriggered: {
            if(root.phase === 0) {
                if(!PluginRegistry.isInstalled("edge-demo")) return;
                EchoRegistry.screens=[{name:"DP-1"}];
                const h=PluginApi.handle("edge-demo");
                root.result.declared=h.surfaces.declare("panel","primary");
                h.surfaces.onCloseRequested(() => root.callbacks++);
                h.surfaces.track(state,"panel",true);
                const descriptor={label:"Panel",output:"DP-1",rect:{x:1,y:1,width:20,height:20}};
                root.result.unknownRejected=!h.sonar.register("unknown",Object.assign({},descriptor,{output:"DP-999"}));
                root.result.knownAccepted=h.sonar.register("known",descriptor);
                root.held=EchoRegistry.snapshot().find(t => t.id === "plugin:edge-demo/known");
                EchoRegistry.screens=[];
                root.result.removedOutput=!EchoRegistry.isCurrent(root.held) && !EchoRegistry.snapshot().some(t => t.plugin === "edge-demo");
                const data=JSON.parse(JSON.stringify(PluginRegistry._data));
                data.installed["edge-demo"].api.uses=["sonar.register"];
                PluginRegistry._data=data;
                root.phase++;
            } else {
                root.result.undeclared=Surfaces.declared["plugin:edge-demo/panel"] === undefined && state.surfaceStack.length === 0;
                Surfaces.closeRequested(state,"plugin:edge-demo/panel");
                root.result.handlerRevoked=root.callbacks === 0;
                root.result.handleRevoked=!PluginApi.handle("edge-demo").has("surface.declare");
                const data=JSON.parse(JSON.stringify(PluginRegistry._data));
                data.installed["edge-demo"].ui.surfaces[0].component="qml/%2e%2e/Outside.qml";
                PluginRegistry._data=data;
                root.result.pathRejected=ShelfTabs.find("edge-demo:panel","left") === null;
                console.log("SONAR_SESSION " + JSON.stringify(root.result)); Qt.quit();
            }
        }
    }
    Timer { interval:5000; running:true; onTriggered: { console.log("SONAR_SESSION " + JSON.stringify({timeout:true})); Qt.quit(); } }
}'''

@pytest.mark.skipif(shutil.which('qs') is None,reason='needs Quickshell')
def test_runtime_grant_output_and_component_boundaries(tmp_path):
    home=_registry(tmp_path)
    file=home/'.local/state/aphotic/plugins.json'
    data=json.loads(file.read_text())
    data['installed']['edge-demo']['api']={'version':2,'uses':['surface.declare','sonar.register']}
    file.write_text(json.dumps(data))
    out=run_probe(tmp_path,API_BOUNDARIES,{'HOME':str(home)})
    assert len(out) == 8 and all(v is True for v in out.values()),out
