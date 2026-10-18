const { readFileSync } = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');

const core = vm.createContext({});
vm.runInContext(readFileSync(`${__dirname}/../Configs/quickshell/aphotic/services/ai/ProcessUsageCore.js`, 'utf8'), core);

const first = core.ingest(null, {clockTicks:100, rows:[
    {pid:10, startTicks:100, cpuTicks:200, threads:8, pssKiB:1024},
    {pid:11, startTicks:200, cpuTicks:400, threads:4, pssKiB:2048}
]}, 1000);
assert.equal(first.usage.memoryMiB, 3);
assert.equal(first.usage.cpuPercent, null);
assert.equal(first.usage.threads, 12);
const next = core.ingest(first.previous, {clockTicks:100, rows:[
    {pid:10, startTicks:100, cpuTicks:300, threads:8, pssKiB:1536},
    {pid:11, startTicks:200, cpuTicks:450, threads:4, pssKiB:2048}
]}, 2000);
assert.equal(next.usage.memoryMiB, 3.5);
assert.equal(next.usage.cpuPercent, 150);
const replaced = core.ingest(next.previous, {clockTicks:100, rows:[
    {pid:10, startTicks:999, cpuTicks:500, threads:8, pssKiB:1024}
]}, 3000);
assert.equal(replaced.usage.cpuPercent, null);
assert.equal(core.ingest(first.previous, {clockTicks:100, rows:[]}, 2000).usage, null);

// A parent with one child: each process contributes its own memory.
const tree = core.ingest(null, {clockTicks:100, rows:[
    {pid:100, startTicks:10, cpuTicks:100, threads:6, pssKiB:102400},
    {pid:101, startTicks:12, cpuTicks:50, threads:3, pssKiB:51200}
]}, 1000);
assert.equal(tree.usage.memoryMiB, 150);
assert.equal(tree.usage.processCount, 2);
assert.equal(tree.usage.threads, 9);

// cpuPercent comes from the delta of two samples: no delta yet on the
// first sample, zero for an idle process, exact for a busy one.
const idle = core.ingest(null, {clockTicks:100, rows:[
    {pid:7, startTicks:5, cpuTicks:1000, threads:2, pssKiB:2048}
]}, 0);
assert.equal(idle.usage.cpuPercent, null);
const same = core.ingest(idle.previous, {clockTicks:100, rows:[
    {pid:7, startTicks:5, cpuTicks:1000, threads:2, pssKiB:2048}
]}, 1000);
assert.equal(same.usage.cpuPercent, 0);
const busy = core.ingest(same.previous, {clockTicks:100, rows:[
    {pid:7, startTicks:5, cpuTicks:1100, threads:2, pssKiB:2048}
]}, 2000);
assert.equal(busy.usage.cpuPercent, 100);

// A process that exits between samples drops out without an exception.
const gone = core.ingest(tree.previous, {clockTicks:100, rows:[
    {pid:100, startTicks:10, cpuTicks:100, threads:6, pssKiB:102400}
]}, 2000);
assert.equal(gone.usage.processCount, 1);
assert.equal(gone.usage.memoryMiB, 100);

console.log('Process usage aggregation passed');
