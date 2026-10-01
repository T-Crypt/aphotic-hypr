"""Compositor reloads must restore runtime binds without replacing user binds."""
import json
import os
import shutil
from pathlib import Path

import pytest
from test_sonar_session import run_probe

STUB = '''#!/usr/bin/env python3
import fcntl,json,os,sys
from pathlib import Path
p=Path(os.environ['SONAR_BIND_STATE'])
with p.with_suffix('.lock').open('w') as lock:
 fcntl.flock(lock,fcntl.LOCK_EX)
 state=json.loads(p.read_text())
 args=sys.argv[1:]
 if args==['-j','binds'] or args==['binds','-j']:
  print('null' if state.get('invalid') else json.dumps(state['binds']))
 elif args==['test-clear']:
  state['binds']=[];state['events'].append('clear')
 elif args in (['test-conflict'],['test-invalid']):
  state['invalid']=args==['test-invalid']
  state['binds']=[{'key':k,'modmask':64,'mouse':False,'description':'User shortcut','dispatcher':'exec','arg':'user-command'} for k in ['grave','bracketleft','bracketright']]
  state['events'].append('conflict')
 elif args[:2]==['keyword','bindd']:
  _,key,description,dispatcher,command=[s.strip() for s in args[2].split(',',4)]
  state['binds'].append({'key':key,'modmask':64,'mouse':False,'description':description,'has_description':True,'dispatcher':dispatcher,'arg':command})
  state['events'].append('bind:'+key)
 elif args[:2]==['keyword','unbind']:
  key=args[2].split(',')[1].strip();state['binds']=[b for b in state['binds'] if b['key']!=key]
  state['events'].append('unbind:'+key)
 else:
  print('{}')
 p.write_text(json.dumps(state))
'''

PROBE = '''import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
ShellRoot {
    id: root
    property int phase: 0
    property var result: ({})
    property string operation: ""
    Component.onCompleted: {
        Sonar.enabled;
        Settings.sonarEnabled = true;
        Shelves.screens = [{name:"DP-1"}];
        Shelves.update("DP-1","left",{enabled:true});
        Shelves.update("DP-1","right",{enabled:true});
        ShelfKeybinds.leftReason;
    }
    Process {
        id: control
        onExited: {
            Hypr.configReloaded();
            Hypr.configReloaded();
        }
    }
    Timer {
        interval: 500; repeat: true; running: true
        onTriggered: {
            if (root.phase === 0) {
                root.result.initial = Sonar._applied.length > 0;
                control.command = ["hyprctl","test-clear"]; control.running = true;
            } else if (root.phase === 1) {
                root.result.restored = Sonar._checked && Sonar._applied.length > 0;
                control.command = ["hyprctl","test-conflict"]; control.running = true;
            } else {
                root.result.userWins = Sonar._conflict && Sonar._applied.length === 0
                    && ShelfKeybinds.leftReason.length > 0 && ShelfKeybinds.rightReason.length > 0;
                console.log("SONAR_SESSION " + JSON.stringify(root.result)); Qt.quit();
            }
            root.phase++;
        }
    }
}'''

@pytest.mark.skipif(shutil.which('qs') is None, reason='Quickshell unavailable')
@pytest.mark.parametrize('invalid', [False, True])
def test_reload_restores_sonar_and_shelves_without_replacing_user_shortcuts(tmp_path, invalid):
    stub = tmp_path / 'bin'
    stub.mkdir()
    (stub / 'hyprctl').write_text(STUB)
    (stub / 'hyprctl').chmod(0o755)
    state = tmp_path / 'binds.json'
    state.write_text(json.dumps({'binds': [], 'events': []}))
    probe = PROBE
    if invalid:
        probe = probe.replace('test-conflict', 'test-invalid').replace('Sonar._conflict &&', '!Sonar._checked &&')
    out = run_probe(tmp_path, probe, {
        'PATH': str(stub) + os.pathsep + os.environ['PATH'],
        'SONAR_BIND_STATE': str(state),
    })
    data = json.loads(state.read_text())
    assert out == {'initial': True, 'restored': True, 'userWins': True}, (out, data)
    events = data['events']
    restored = events[events.index('clear') + 1:events.index('conflict')]
    assert set(restored) == {'bind:grave', 'bind:bracketleft', 'bind:bracketright'}, data
    assert events[events.index('conflict') + 1:] == [], data
    assert all(b['arg'] == 'user-command' for b in data['binds']), data
