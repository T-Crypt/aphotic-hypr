// The headline session stays put while several agents work at once, and a
// repeated event from several processes of one harness counts once.
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const vm = require('node:vm');

const root = `${__dirname}/../Configs/quickshell/aphotic/services/ai`;
const core = vm.createContext({});
vm.runInContext(readFileSync(`${root}/AgentEventsCore.js`, 'utf8'), core);

const HOLD = 15000;
const s = (id, status, extra) => Object.assign({ id, status, statusSince: 0, busySince: 0, lastBusyAt: 0, updatedAt: 0 }, extra);

// Two busy sessions: the current pick holds even when the other is newer.
{
    const a = s('a', 'running', { busySince: 1000, lastBusyAt: 9000, updatedAt: 9000 });
    const b = s('b', 'running', { busySince: 5000, lastBusyAt: 9500, updatedAt: 9500 });
    assert.equal(core.pickActive([a, b], 'a', 10000, HOLD), 'a');
    assert.equal(core.pickActive([a, b], 'b', 10000, HOLD), 'b');
}

// A short idle between steps is still busy; a long one hands over.
{
    const a = s('a', 'idle', { busySince: 1000, lastBusyAt: 9000, updatedAt: 9000 });
    const b = s('b', 'running', { busySince: 5000, lastBusyAt: 9500, updatedAt: 9500 });
    assert.equal(core.pickActive([a, b], 'a', 12000, HOLD), 'a');
    assert.equal(core.pickActive([a, b], 'a', 30000, HOLD), 'b');
}

// Waiting beats busy, and a waiting pick holds among several waiting.
{
    const a = s('a', 'running', { busySince: 1000, lastBusyAt: 9000 });
    const b = s('b', 'waiting', { statusSince: 8000 });
    const c = s('c', 'waiting', { statusSince: 9000 });
    assert.equal(core.pickActive([a, b, c], 'a', 10000, HOLD), 'c');
    assert.equal(core.pickActive([a, b, c], 'b', 10000, HOLD), 'b');
}

// No current pick: the most recently started busy streak wins.
{
    const a = s('a', 'running', { busySince: 1000, lastBusyAt: 9000 });
    const b = s('b', 'running', { busySince: 5000, lastBusyAt: 6000 });
    assert.equal(core.pickActive([a, b], '', 10000, HOLD), 'b');
}

// Ended sessions never headline; all quiet keeps the current one.
{
    const a = s('a', 'ended');
    assert.equal(core.pickActive([a], 'a', 10000, HOLD), '');
    const b = s('b', 'idle', { updatedAt: 100 });
    const c = s('c', 'idle', { updatedAt: 200 });
    assert.equal(core.pickActive([b, c], 'b', 100000, HOLD), 'b');
    assert.equal(core.pickActive([b, c], '', 100000, HOLD), 'c');
}

// Repeats within the window collapse; a changed status does not.
{
    const last = {};
    const run = { sessionId: 'x', event: 'turn', status: 'running', t: 1000 };
    let r = core.isRepeat(last, run, 250);
    assert.equal(r.repeat, false);
    last.x = { key: r.key, at: r.at };
    assert.equal(core.isRepeat(last, Object.assign({}, run, { t: 1004 }), 250).repeat, true);
    assert.equal(core.isRepeat(last, Object.assign({}, run, { t: 2000 }), 250).repeat, false);
    assert.equal(core.isRepeat(last, Object.assign({}, run, { status: 'idle', t: 1005 }), 250).repeat, false);
    const usage = { sessionId: 'x', event: 'usage', inputTokens: 10, outputTokens: 5, t: 1000 };
    last.x = { key: core.isRepeat({}, usage, 250).key, at: 1000 };
    assert.equal(core.isRepeat(last, Object.assign({}, usage, { t: 1003 }), 250).repeat, true);
    assert.equal(core.isRepeat(last, Object.assign({}, usage, { outputTokens: 6, t: 1003 }), 250).repeat, false);
}

console.log('ok agent events steady');
