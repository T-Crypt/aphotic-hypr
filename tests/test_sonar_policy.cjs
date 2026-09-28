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
