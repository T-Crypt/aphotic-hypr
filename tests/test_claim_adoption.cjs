const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const vm = require('node:vm');

const ctx = vm.createContext({});
vm.runInContext(readFileSync(`${__dirname}/../Configs/quickshell/aphotic/services/profile/ClaimAdoption.js`, 'utf8'), ctx);
const A = ctx;

// Live double count: one llama-swap server (PID 1627064) started through a
// wrapper, so both llama-swap and llama.cpp adopted it and both registered a
// claim for its VRAM. The first owner must keep it.
let r = A.adopt({}, 1627064, 'llama-swap', 'foreground');
assert.equal(r.taken, false);
let adopted = r.adopted;
r = A.adopt(adopted, 1627064, 'llama.cpp', 'foreground');
assert.equal(r.taken, true, 'a second owner must not take a held PID');
assert.equal(r.adopted, adopted, 'a refused adoption leaves the map unchanged');

// Same owner re-adopting refreshes priority instead of being refused.
r = A.adopt(adopted, 1627064, 'llama-swap', 'background');
assert.equal(r.taken, false);
assert.equal(r.adopted['1627064'].priority, 'background');
adopted = r.adopted;

// The id a claim carries is the owner plus the PID.
assert.equal(A.claimId(1627064, 'llama-swap'), 'llama-swap-proc-1627064');
assert.equal(A.processClaimId(1627064), 'gpu-proc-1627064');

// The losing owner's id still names a managed PID, so a claim left over
// from before the fix is recognised and released instead of staying frozen
// beside the live one.
assert.equal(A.namesManagedPid(adopted, 'llama-swap-proc-1627064'), true);
assert.equal(A.namesManagedPid(adopted, 'llama.cpp-proc-1627064'), true);
assert.equal(A.namesManagedPid(adopted, 'gpu-proc-1627064'), true);
// A claim on a PID nobody adopted is not touched.
assert.equal(A.namesManagedPid(adopted, 'gpu-proc-999'), false);
assert.equal(A.namesManagedPid(adopted, 'gaming-proc-4242'), false);
assert.equal(A.namesManagedPid(adopted, 'llama-swap-proc-162706'), false);

// Releasing a PID hands back the owner whose claim id must go with it.
r = A.unadopt(adopted, 1627064);
assert.equal(r.owner, 'llama-swap');
assert.equal(A.namesManagedPid(r.adopted, 'llama-swap-proc-1627064'), false);
assert.equal(A.unadopt(r.adopted, 1627064).owner, '');

console.log('claim adoption: passed');
