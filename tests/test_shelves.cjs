const fs = require('node:fs'), vm = require('node:vm'), assert = require('node:assert/strict');
const p = vm.createContext({});
const dir = __dirname + '/../Configs/quickshell/aphotic/services/';
vm.runInContext(fs.readFileSync(dir+'ShelfPolicy.js','utf8'),p);
const plain = x => JSON.parse(JSON.stringify(x));
assert.equal(p.config({},'DP-1').left.enabled,false);
assert.equal(p.config({'DP-1':{left:{enabled:true}}},'DP-2').left.enabled,false);
assert.equal(p.config({'DP-1':{left:{enabled:'yes'}}},'DP-1').left.enabled,false);
assert.deepEqual(plain(p.config({'DP-1':{left:{pinned:['ok','ok',4],tabs:['tab',null]}}},'DP-1').left.pinned),['ok']);
let cfg=p.update({},'DP-1','left',{enabled:true,pinned:['app']},'Monitor');
assert.equal(p.config(cfg,'DP-1').left.enabled,true);
assert.equal(p.config(cfg,'DP-1').description,'Monitor');
assert.equal(p.config(cfg,'DP-1').right.enabled,false);
assert.equal(p.update(cfg,'DP-1','bad',{enabled:true}),null);
assert.deepEqual(plain(p.reconcile(['DP-1/left','DP-2/right'],cfg,['DP-1'])),['DP-1/left']);
assert.equal(p.conflict([{modmask:64,key:'bracketleft',dispatcher:'exec',arg:'user'}],'left'),true);
assert.equal(p.conflict([{modmask:65,key:'bracketleft',dispatcher:'exec',arg:'user'}],'left'),false);
assert.equal(p.conflict([{modmask:64,key:'bracketright',dispatcher:'exec',arg:'qs -c aphotic ipc call shelves toggle right'}],'right'),false);
vm.runInContext(fs.readFileSync(dir+'DockItems.js','utf8'),p);
const entry={id:'app',name:'App',icon:'app'};
const windows=[{appClass:'a',output:'DP-1'},{appClass:'b',output:'DP-1'},{appClass:'c',output:'DP-2'}];
assert.deepEqual(plain(p.group(windows)).map(g=>g.appClass),['a','b','c']);
const items=p.dockItems(['app','missing'],p.group(windows),id=>id==='app'?entry:null,c=>c==='a'||c==='b'?entry:null);
assert.equal(items.length,2); assert.equal(items[0].windows.length,2); assert.equal(items[1].key,'c');
vm.runInContext(fs.readFileSync(dir+'ShelfTabPolicy.js','utf8'),p);
const core=[{id:'media',core:true},{id:'agents',core:true},{id:'quick',core:true}];
assert.deepEqual(plain(p.forEdge(core,'left')).map(t=>t.id),['media','agents','quick']);
assert.deepEqual(plain(p.forEdge(core,'bad')),[]);
// A plugin tab is addressable only on the edges its manifest declared.
const plugin=p.pluginTab({plugin:'notes',id:'panel',label:'Panel',componentUrl:'file:///p/qml/Panel.qml',edges:['right']});
assert.equal(plugin.id,'notes:panel');
assert.equal(plugin.notch,false);
assert.deepEqual(plain(p.forEdge([plugin],'left')),[]);
assert.equal(p.forEdge([plugin],'right').length,1);
assert.equal(p.find([plugin],'notes:panel','right').id,'notes:panel');
assert.equal(p.find([plugin],'panel','right'),null);
assert.equal(p.find([plugin],'notes:panel','left'),null);
// No declaration means both edges; an unusable one means none.
assert.deepEqual(plain(p.edgesOf({})),['left','right']);
assert.deepEqual(plain(p.edgesOf({edges:'right, left'})),['right','left']);
assert.deepEqual(plain(p.edgesOf({edges:['left','left']})),['left']);
assert.deepEqual(plain(p.edgesOf({edges:['sideways']})),[]);
assert.deepEqual(plain(p.edgesOf({edges:5})),[]);
// Malformed entries never become tabs.
assert.equal(p.pluginTab(null),null);
assert.equal(p.pluginTab({plugin:'notes',id:'panel',componentUrl:'http://x/Panel.qml'}),null);
assert.equal(p.pluginTab({plugin:'bad name',id:'panel',componentUrl:'file:///p/P.qml'}),null);
assert.equal(p.pluginTab({plugin:'notes',id:'../../etc/passwd',componentUrl:'file:///p/P.qml'}),null);
assert.equal(p.pluginTab({plugin:'notes',id:'panel',componentUrl:'file:///p/P.qml'}).notch,false);
assert.equal(p.pluginTab({plugin:'notes',id:'panel',componentUrl:'file:///p/P.qml',notch:true}).notch,true);
// Notch placement is opt-in per tab.
assert.deepEqual(plain(p.notchTabs([plugin])),[]);
const notched=p.pluginTab({plugin:'notes',id:'panel',componentUrl:'file:///p/P.qml',notch:true});
assert.equal(p.notchTabs([plugin,notched]).length,1);
// A stored selection survives only while its tab still resolves.
assert.equal(p.selected([plugin],['notes:panel'],'right'),'notes:panel');
assert.equal(p.selected([plugin],['notes:panel'],'left'),'');
assert.equal(p.selected([plugin],['gone'],'right'),'');
assert.equal(p.selected([plugin],[],'right'),'');
assert.equal(p.selected([plugin],'nope','right'),'');
assert.equal(p.selected(core,['media','quick'],'right'),'quick');

vm.runInContext(fs.readFileSync(dir+'ShelfEchoPolicy.js','utf8'),p);
assert.equal(p.answerable({app:1000},'app',1500,6000),true);
assert.equal(p.answerable({app:1000},'app',7000,6000),false);
assert.equal(p.answerable({app:1000},'app',500,6000),false,'a clock that moved back is not answerable');
assert.equal(p.answerable({app:1000},'other',1500,6000),false);
assert.equal(p.answerable({app:1000},'app',1500,0),false);
assert.equal(p.answerable(null,'app',1500,6000),false);
assert.equal(p.answerable({app:'soon'},'app',1500,6000),false);
assert.deepEqual(Object.keys(p.consume({app:1,other:2},'app')),['other']);
// One launch request earns at most one echo, and stale ones drop on write.
let req=p.record({},'app',1000,6000);
assert.deepEqual(Object.keys(req),['app']);
req=p.record(req,'app',1200,6000);
assert.equal(req.app,1200,'a second launch restarts the window');
assert.deepEqual(Object.keys(p.record(req,'old',9000,6000)),['old'],'a write prunes what expired');
assert.deepEqual(plain(p.record({app:1},'',2000,6000)),{app:1});
assert.deepEqual(plain(p.record({},'x',2000,0)),{x:2000});

vm.runInContext(fs.readFileSync(dir+'SurfacePolicy.js','utf8'),p);
const extra={'shelf:DP-1:left':{role:'shelf'},'shelf:DP-1:right':{role:'shelf'}};
assert.deepEqual(plain(p.transition(['shelf:DP-1:left'],'shelf:DP-1:right',true,extra).close),[]);
assert.deepEqual(plain(p.transition(['shelf:DP-1:left'],'launcher',true,extra).close),['shelf:DP-1:left']);
console.log('Shelves policy and dock parity: passed');

assert.deepEqual(plain(p.newWindows(['old'],[{address:'old'},{address:'new'}])),[{address:'new'}]);
assert.equal(p.answerable({'DP-1:left/app':1000},'DP-2:left/app',1200,6000),false);

vm.runInContext(fs.readFileSync(dir+'PluginPaths.js','utf8'),p);
for(const bad of ['../other/Q.qml','/tmp/Q.qml','qml/%2e%2e/Q.qml','qml/%252e%252e/Q.qml','qml/Q.qml?x','qml/Q.qml#x','file:Q.qml']) assert.equal(p.safeComponent('sample',bad),false,bad);
assert.equal(p.safeComponent('sample','qml/Panel.qml'),true);

assert.deepEqual(plain(p.edgesOf({edges:['left',17]})),[]);
assert.deepEqual(plain(p.edgesOf({edges:['right','sideways']})),[]);
