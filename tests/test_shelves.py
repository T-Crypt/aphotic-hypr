"""Shelf state/content probes use disposable state; the PanelWindow probe needs Wayland."""
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
