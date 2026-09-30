const {readFileSync, existsSync} = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const dir = __dirname + '/../Configs/quickshell/aphotic/services/';
const p = vm.createContext({});
vm.runInContext(readFileSync(dir + 'SurfacePolicy.js', 'utf8'), p);
const plain = x => JSON.parse(JSON.stringify(x));
assert.deepEqual(plain(p.transition(['workspace', 'dashboard'], 'sonar', true)), {stack:['workspace','dashboard','sonar'],close:[]});
assert.equal(p.focusOwner(['dashboard','sonar'], ''), 'sonar');
assert.equal(p.engaged(['sonar'], ''), false);
assert.equal(p.engaged(['dashboard','sonar'], ''), true);
assert.deepEqual(plain(p.transition(['workspace','sonar'], 'launcher', true)).close, ['sonar']);
assert.equal(p.focusOwner(['sonar'], 'negotiation'), 'negotiation');
assert.equal(p.back(['sonar'], ''), 'sonar');
assert.ok(existsSync(dir + 'EchoPolicy.js'), 'echo rules must exist');
vm.runInContext(readFileSync(dir + 'EchoPolicy.js', 'utf8'), p);
const valid = {label:'Panel', output:'DP-2',rect:{x:10,y:20,width:100,height:40},action:'plugin:sample/show'};
assert.equal(p.normalize('sample','panel',valid).id, 'plugin:sample/panel');
assert.equal(p.normalize('sample','panel',{...valid,action:'plugin:other/show'}), null);
assert.equal(p.normalize('sample','panel',{...valid,action:'plugin:sample/show/extra'}), null);
assert.equal(p.normalize('sample','panel',{...valid,action:'plugin:sample/Not Ok'}), null);
assert.equal(p.normalize('sample','panel',{...valid,action:'plugin:sample/ok-name'}).action, 'plugin:sample/ok-name');
assert.equal(p.normalize('sample','panel',{...valid,rect:{x:0,y:0,width:Infinity,height:10}}), null);
assert.equal(p.normalize('sample','panel',{...valid,rect:{x:0,y:0,width:-1,height:10}}), null);
assert.equal(p.normalize('sample','../panel',valid), null);
assert.equal(p.normalize('sample','panel',{...valid,label:''}), null);
assert.equal(p.distance({x:0,y:0},{x:3,y:4,width:10,height:10}),5);
assert.equal(p.distance({x:5,y:5},{x:3,y:4,width:10,height:10}),0);
assert.equal(p.radius({x:0,y:0},[{x:-3,y:-4,width:3,height:4}]),5);
console.log('Sonar policy: passed');
let records = {};
records = p.put(records, p.normalize('sample','panel',valid));
assert.equal(Object.keys(records).length,1);
assert.equal(p.put(records, null), null);
for(let i=0;i<63;i++) records=p.put(records,p.normalize('sample','item-'+i,valid));
assert.equal(p.put(records,p.normalize('sample','overflow',valid)),null);
assert.equal(Object.keys(p.removePlugin(records,'sample')).length,0);
assert.equal(Object.keys(p.put(records,p.normalize('sample','panel',{...valid,label:'Updated'}))).length,64);

// The registry's global cap holds across plugins, not just per plugin:
// 15 plugins x 64 plus the sample 64 reach it.
for(let j=0;j<15;j++){
    const other={...valid, action:'plugin:other-'+j+'/show'};
    for(let i=0;i<64;i++) records=p.put(records,p.normalize('other-'+j,'item-'+i,other));
}
assert.equal(Object.keys(records).length,1024);
assert.equal(p.put(records,p.normalize('another','overflow',{...valid,action:'plugin:another/show'})),null);
assert.equal(Object.keys(p.removePlugin(records,'other-0')).length,960);

// Session rules (services/Sonar.qml is the reactive wrapper).
assert.ok(existsSync(dir + 'SonarPolicy.js'), 'sonar session rules must exist');
vm.runInContext(readFileSync(dir + 'SonarPolicy.js', 'utf8'), p);
assert.equal(p.canPing(true, '', false), true);
assert.equal(p.canPing(false, '', false), false);
assert.equal(p.canPing(true, 'negotiation', false), false);
assert.equal(p.canPing(true, '', true), false);
assert.deepEqual(plain(p.parseCursorPos('12, 345')), {x:12, y:345});
assert.deepEqual(plain(p.parseCursorPos('-5,0')), {x:-5, y:0});
assert.equal(p.parseCursorPos(''), null);
assert.equal(p.parseCursorPos('cursor at 12, 345'), null);
assert.deepEqual(plain(p.originFallback({x:100, y:200, width:3440, height:1440})), {x:1820, y:920});
assert.deepEqual(plain(p.originFallback(null)), {x:0, y:0});
assert.equal(p.radiusFraction(0.3, false), 0.5);
assert.equal(p.radiusFraction(0.6, false), 1);
assert.equal(p.radiusFraction(0.9, false), 1);
assert.equal(p.radiusFraction(0, true), 1);
assert.equal(p.opacityAt(0.5, false), 1);
assert.equal(p.opacityAt(0.875, false), 0.5);
assert.equal(p.opacityAt(1, false), 0);
assert.equal(p.opacityAt(0.5, true), 1);
assert.equal(p.reached({x:0, y:0}, {x:3, y:4, width:10, height:10}, 5), true);
assert.equal(p.reached({x:0, y:0}, {x:3, y:4, width:10, height:10}, 4.9), false);
assert.equal(p.reached({x:5, y:5}, {x:3, y:4, width:10, height:10}, 0), true);
assert.equal(p.superBindConflict([{key:'grave', modmask:64, description:'someone else'}]), true);
assert.equal(p.superBindConflict([{key:'grave', modmask:64, description:'Ping Sonar discovery'}]), false);
assert.equal(p.superBindConflict([{key:'grave', modmask:65, description:'someone else'}]), false);
assert.equal(p.superBindConflict([{key:'grave', modmask:64, mouse:true, description:'x'}]), false);
assert.equal(p.superBindConflict([{key:'w', modmask:64, description:'x'}]), false);
assert.equal(p.superBindConflict(null), false);

assert.equal(p.dismissKey(96, true), false);
assert.equal(p.dismissKey(96, false), true);
assert.equal(p.dismissKey(65, true), true);
assert.equal(p.dismissKey(65, false), true);
