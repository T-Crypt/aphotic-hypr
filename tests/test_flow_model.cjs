const {readFileSync} = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ctx = vm.createContext({});
vm.runInContext(readFileSync(__dirname + '/../Configs/quickshell/aphotic/modules/flow/FlowModel.js', 'utf8'), ctx);
const claim = (id, owner, amount, priority='background') => ({id, owner, resource:'gpu-vram', amount, priority, origin:'dynamic', label:id});
const spec = {'gpu-vram': {label:'VRAM', capacity:100, safetyMargin:0.1, unit:'MiB'}};
let m = ctx.build([claim('a','ai',70),claim('b','gaming',30,'foreground')], spec, {}, {});
assert.equal(m.resources.find(r=>r.key==='gpu-vram').contended, true);
assert.equal(m.workloads[0].key, 'gaming');
assert.equal(m.edges.length, 2);
m = ctx.build([claim('a','ai',200)], {}, {}, {});
assert.equal(m.resources.find(r=>r.key==='gpu-vram').budget, null);
assert.equal(m.resources.find(r=>r.key==='gpu-vram').contended, false);
m = ctx.build([claim('a','ai',90)], spec, {}, {});
assert.equal(m.resources.find(r=>r.key==='gpu-vram').contended, false);
m = ctx.build([claim('a','ai',0),claim('b','gaming',0)], {'gpu-vram':{exclusive:true}}, {}, {});
assert.equal(m.resources.find(r=>r.key==='gpu-vram').contended, true);
m = ctx.build([], {}, {dev:{phase:'monitor',trigger:'project-open'}}, {dev:{label:'Dev'}});
assert.equal(m.workloads[0].claims.length, 0);
assert.match(m.workloads[0].detail, /project-open/);
assert.equal(m.planes.length,4);
assert.equal(m.planes.map(p=>p.key).join(','),'ai,gaming,security,dev');
m = ctx.build(Array.from({length:30},(_,i)=>claim('c'+i,'p'+i,i)), spec, {}, {});
assert.equal(m.workloads.length,8);
assert.equal(m.hiddenWorkloads,22);
assert.ok(m.edges.length<=24);
assert.equal(m.resources.find(r=>r.key==='gpu-vram').total,435);
console.log('Flow model: 15 assertions passed');
m = ctx.build([claim('model','ollama',20)], spec, {ollama:{phase:'idle'}}, {ollama:{label:'Ollama'}});
assert.equal(m.planes[0].phase,'claims active');
assert.equal(m.workloads[0].claims[0].unit,'MiB');
console.log('Ollama AI plane and claim units: passed');

// Per-plane tie-ins, install gates, summary path and redraw signature.
const layers = {ai:true, gaming:true, security:true, dev:true};
m = ctx.build([claim('llama3','ollama',40)], spec, {}, {}, layers);
let ai = m.planes.find(p => p.key === 'ai');
assert.equal(ai.phase, 'claims active');
assert.match(ai.detail, /1 claim held · 40 MiB resident/);
assert.equal(ai.active, true);
assert.equal(m.workloads[0].plane, 'ai');

m = ctx.build([], spec, {}, {}, {ai:true, gaming:false, security:true, dev:true});
assert.equal(m.planes.find(p => p.key === 'gaming').phase, 'not installed');
assert.equal(m.planes.find(p => p.key === 'gaming').installed, false);
assert.equal(m.planes.find(p => p.key === 'gaming').active, false);
assert.match(m.planes.find(p => p.key === 'gaming').detail, /layer not installed/);

m = ctx.build([], spec, {}, {}, layers);
assert.equal(m.planes.find(p => p.key === 'gaming').phase, 'unregistered');
assert.match(m.planes.find(p => p.key === 'gaming').detail, /plugin not installed/);
assert.match(m.planes.find(p => p.key === 'security').detail, /not registered/);

m = ctx.build([], spec, {}, {dev:{label:'Dev'}, security:{label:'Security'}}, layers);
assert.equal(m.planes.find(p => p.key === 'dev').phase, 'idle');
assert.match(m.planes.find(p => p.key === 'dev').detail, /No project session open/);
assert.match(m.planes.find(p => p.key === 'security').detail, /No engagement in progress/);

m = ctx.build([], spec, {dev:{phase:'monitor', trigger:'project-open'}}, {dev:{label:'Dev'}}, layers);
assert.match(m.planes.find(p => p.key === 'dev').detail, /Project: project-open/);
m = ctx.build([], spec, {security:{phase:'apply', trigger:'vpn-connect'}}, {security:{label:'Security'}}, layers);
assert.match(m.planes.find(p => p.key === 'security').detail, /Engagement: vpn-connect/);
m = ctx.build([], spec, {gaming:{phase:'monitor', trigger:'gamemode'}}, {gaming:{label:'Gaming'}}, layers);
assert.match(m.planes.find(p => p.key === 'gaming').detail, /Session: gamemode/);

// Signature is stable across rebuilds of identical state and moves when a
// claim, a plane phase or contention does.
const a = ctx.build([claim('a','ai',70), claim('b','gaming',30,'foreground')], spec, {}, {}, layers);
const b = ctx.build([claim('b','gaming',30,'foreground'), claim('a','ai',70)], spec, {}, {}, layers);
assert.equal(a.signature, b.signature);
assert.notEqual(a.signature, ctx.build([claim('a','ai',71), claim('b','gaming',30,'foreground')], spec, {}, {}, layers).signature);
assert.notEqual(a.signature, ctx.build([claim('a','ai',70), claim('b','gaming',30,'foreground')], spec, {gaming:{phase:'monitor'}}, {}, layers).signature);

const s = ctx.summarize([claim('a','ai',70), claim('b','gaming',30,'foreground')], spec, {}, {}, layers);
assert.equal(s.claimCount, 2);
assert.equal(s.contentionCount, 1);
assert.equal(s.activePlanes, 2);
assert.equal(s.planes.length, 4);
assert.equal(s.resources, undefined);
assert.equal(ctx.summarize([], {}, {}, {}, {}).planes.every(p => p.installed), true);
console.log('Flow planes, install gates, signature and summary: 26 assertions passed');

// --- passports, receipts and the contention projection -----------------
const pass = (over={}) => Object.assign({token:'w1', plane:'dev', owner:'dev', label:'build',
    trigger:'build-start', status:'live', claims:[]}, over);

// Work an owner reported shows up even with no claim behind it, and is
// never counted as capacity.
let w = ctx.build([], spec, {}, {}, {}, [pass()]);
assert.equal(w.workloads.length, 1);
assert.equal(w.workloads[0].key, 'dev');
assert.equal(w.workloads[0].claims.length, 0);
assert.equal(w.workloads[0].phase, 'reported');
assert.equal(w.resources.find(r => r.key === 'gpu-vram').total, 0);
assert.match(w.workloads[0].detail, /1 workload/);
assert.equal(w.planes.find(p => p.key === 'dev').active, true);

// A stale source is labelled stale, not finished.
let st = ctx.build([], spec, {}, {}, {}, [pass({status:'stale'})]);
assert.equal(st.workloads[0].stale, true);
assert.equal(st.staleCount, 1);
assert.match(st.workloads[0].work[0].detail, /source went quiet/);

// Receipts ride with their owner and pending never reads as applied.
let rc = ctx.build([], spec, {}, {}, {}, [pass()],
    [{id:'r1', profileId:'dev', kind:'shelter', status:'requested'},
     {id:'r2', profileId:'dev', kind:'dnd', status:'failed'}]);
assert.equal(rc.pendingActions, 1);
assert.equal(rc.workloads[0].receipts[0].statusLabel, 'Requested');
assert.equal(ctx.receiptLabel({status:'applied', completedAt:1757000000000}).slice(0,7), 'Applied');
assert.match(rc.workloads[0].detail, /1 pending · 1 failed/);

// The signature moves when a passport or receipt changes, so the map
// repaints on those and still ignores a metric tick.
const base = ctx.build([], spec, {}, {}, {}, [pass()], []).signature;
assert.notEqual(ctx.build([], spec, {}, {}, {}, [pass({status:'stale'})], []).signature, base);
assert.notEqual(ctx.build([], spec, {}, {}, {}, [pass()], [{id:'r1', profileId:'dev', status:'requested'}]).signature, base);
assert.equal(ctx.build([], spec, {}, {}, {}, [pass()], []).signature, base);

// Contention preview: declared arithmetic only, and an unsupported owner
// says so instead of offering an action.
const neg = {resource:'gpu-vram', unit:'MiB', total:120, budget:90,
    claimant:{owner:'ai', amount:70}, requestor:{owner:'gaming', amount:50},
    claimantSuspendable:true};
const proj = ctx.projection(neg, [{owner:'ai', resource:'gpu-vram', amount:70},
    {owner:'gaming', resource:'gpu-vram', amount:50}]);
assert.equal(proj.reclaimable, '70 MiB');
assert.equal(proj.after, '50 MiB');
assert.equal(proj.fits, true);
assert.match(proj.note, /Nothing changes until you choose/);
const unsupported = ctx.projection(Object.assign({}, neg, {claimantSuspendable:false}), []);
assert.equal(unsupported.supported, false);
assert.equal(unsupported.reclaimable, '0 MiB');
assert.match(unsupported.note, /no graceful stop/);
assert.equal(ctx.projection(null, []), null);

const sp = ctx.summarize([], spec, {}, {}, {}, [pass(), pass({token:'w2', status:'stale'})],
    [{id:'r1', profileId:'dev', status:'requested'}]);
assert.equal(sp.workloadCount, 2);
assert.equal(sp.staleCount, 1);
assert.equal(sp.pendingActions, 1);

console.log('Flow passports, receipts and projection: 22 assertions passed');
