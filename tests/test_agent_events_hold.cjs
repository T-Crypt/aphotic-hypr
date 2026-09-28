// Every AgentEvents holder gets the backlog, not only the one whose hold
// started the tail. Drives AgentEventsCore.js the way AgentEvents.qml does.
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const vm = require('node:vm');

const root = `${__dirname}/../Configs/quickshell/aphotic/services/ai`;
const core = vm.createContext({});
vm.runInContext(readFileSync(`${root}/AgentEventsCore.js`, 'utf8'), core);
const plain = v => JSON.parse(JSON.stringify(v));

function feed(cap) {
    const f = { holders: {}, backlog: [], tailing: false, seen: {} };
    const deliver = (owner, event) => (f.seen[owner] = f.seen[owner] || []).push(event);
    f.hold = (owner, want) => {
        const change = core.hold(f.holders, owner, want, f.tailing);
        if (!change)
            return;
        f.holders = change.holders;
        if (!want)
            delete f.seen[owner];
        if (change.replay)
            f.backlog.forEach(e => deliver(owner, e));
        const wanted = Object.keys(f.holders).length > 0;
        if (wanted && !f.tailing)
            f.tailing = true;
        if (!wanted && f.tailing) {
            f.tailing = false;
            f.backlog = [];
        }
    };
    f.ingest = event => {
        f.backlog = core.appendBacklog(f.backlog, event, cap);
        Object.keys(f.holders).forEach(o => deliver(o, event));
    };
    return f;
}

const ev = n => ({ sessionId: 's1', event: 'pre_tool_use', n });
const ns = list => (list || []).map(e => e.n);

// The first holder starts the tail and receives the backlog as it streams.
let f = feed(400);
f.hold('bar-agents', true);
assert.equal(f.tailing, true);
[1, 2, 3].forEach(n => f.ingest(ev(n)));
assert.deepEqual(ns(f.seen['bar-agents']), [1, 2, 3]);

// A second and third holder joining the running tail get the same backlog.
f.hold('agent-graph', true);
f.hold('notch-tile', true);
assert.deepEqual(ns(f.seen['agent-graph']), [1, 2, 3]);
assert.deepEqual(ns(f.seen['notch-tile']), [1, 2, 3]);

// Live events after the replay reach everyone once, with no duplicates.
f.ingest(ev(4));
for (const owner of ['bar-agents', 'agent-graph', 'notch-tile'])
    assert.deepEqual(ns(f.seen[owner]), [1, 2, 3, 4], owner);

// Re-asserting a held hold is a no-op, so nothing replays twice.
f.hold('agent-graph', true);
assert.deepEqual(ns(f.seen['agent-graph']), [1, 2, 3, 4]);

// Releasing and re-holding while the tail runs replays the current backlog.
f.hold('agent-graph', false);
f.ingest(ev(5));
f.hold('agent-graph', true);
assert.deepEqual(ns(f.seen['agent-graph']), [1, 2, 3, 4, 5]);

// The last release drops the backlog; the next first holder starts clean.
['bar-agents', 'agent-graph', 'notch-tile'].forEach(o => f.hold(o, false));
assert.equal(f.tailing, false);
assert.deepEqual(plain(f.backlog), []);

// The backlog is bounded to the tail's history length.
f = feed(3);
f.hold('a', true);
[1, 2, 3, 4, 5].forEach(n => f.ingest(ev(n)));
f.hold('b', true);
assert.deepEqual(ns(f.seen.b), [3, 4, 5]);

// Core.hold edge cases.
assert.equal(core.hold({}, '', true, false), null);
assert.equal(core.hold({}, 'x', false, true), null);
assert.deepEqual(plain(core.hold({}, 'x', true, false)), { holders: { x: true }, replay: false });
assert.deepEqual(plain(core.hold({ y: true }, 'x', true, true)), { holders: { y: true, x: true }, replay: true });
assert.deepEqual(plain(core.hold({ x: true }, 'x', false, true)), { holders: {}, replay: false });

// AgentEvents.qml routes hold() and ingest through the core and emits the replay.
const qml = readFileSync(`${root}/AgentEvents.qml`, 'utf8');
assert.match(qml, /import "AgentEventsCore\.js" as Core/);
assert.match(qml, /signal backlog\(string owner, var events\)/);
assert.match(qml, /Core\.hold\(root\._holders, owner, want, root\.tailing\)/);
assert.match(qml, /root\.backlog\(owner, root\._backlog\.slice\(\)\)/);
assert.match(qml, /Core\.appendBacklog\(root\._backlog, event, root\.historyLines\)/);
assert.match(qml, /root\._backlog = \[\];/);

console.log('PASS: AgentEvents hold replays the backlog to every holder');
