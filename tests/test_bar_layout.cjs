const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const vm = require('node:vm');

function load(relativePath) {
    const context = vm.createContext({});
    // The `.pragma library` line is QML-only syntax (same treatment as
    // tests/test_pkg_search_rank.py applies to PkgSearchRank.js).
    const source = readFileSync(`${__dirname}/../${relativePath}`, 'utf8')
        .replace(/^\.pragma library[^\n]*\n/, '');
    vm.runInContext(source, context);
    return context;
}

const bar = load('Configs/quickshell/aphotic/services/BarLayout.js');

// vm.runInContext results carry the sandbox's own prototypes, which
// assert's strict comparison rejects; a JSON round-trip strips them.
function plain(value) {
    return JSON.parse(JSON.stringify(value));
}

function migrated(data) {
    return plain(bar.migrate(data));
}

assert.deepEqual(plain(bar.LAYOUTS), ['full', 'capsule', 'dock', 'taskbar', 'minimal']);
assert.deepEqual(plain(bar.CORNERS), ['sharp', 'soft', 'round']);

// Every legacy barSkin value migrates onto the layout/corners it meant.
assert.deepEqual(migrated({ barSkin: 'signal' }), { layout: 'full', corners: 'sharp' });
assert.deepEqual(migrated({ barSkin: 'square' }), { layout: 'full', corners: 'soft' });
assert.deepEqual(migrated({ barSkin: 'pill' }), { layout: 'full', corners: 'round' });
assert.deepEqual(migrated({ barSkin: 'dock' }), { layout: 'dock', corners: 'sharp' });
assert.deepEqual(migrated({ barSkin: 'taskbar' }), { layout: 'taskbar', corners: 'sharp' });
assert.deepEqual(migrated({ barSkin: 'minimal' }), { layout: 'minimal', corners: 'sharp' });
assert.deepEqual(migrated({ barSkin: 'capsule' }), { layout: 'capsule', corners: 'sharp' });

// Missing or unknown state lands on the first-install defaults.
assert.deepEqual(migrated({}), { layout: 'capsule', corners: 'sharp' });
assert.deepEqual(migrated(null), { layout: 'capsule', corners: 'sharp' });
assert.deepEqual(migrated({ barSkin: 'nope' }), { layout: 'capsule', corners: 'sharp' });

// The new keys win over the legacy values they replaced.
assert.deepEqual(migrated({ barLayout: 'dock' }), { layout: 'dock', corners: 'sharp' });
assert.deepEqual(migrated({ barLayout: 'minimal', barSkin: 'pill' }), { layout: 'minimal', corners: 'round' });
assert.deepEqual(migrated({ barCorners: 'soft' }), { layout: 'capsule', corners: 'soft' });
assert.deepEqual(migrated({ barLayout: 'full', barCorners: 'round', barSkin: 'signal' }), { layout: 'full', corners: 'round' });
// Invalid new keys are rejected and the legacy values are used instead.
assert.deepEqual(migrated({ barLayout: 'bogus', barSkin: 'square' }), { layout: 'full', corners: 'soft' });
assert.deepEqual(migrated({ barCorners: 'bogus', barSkin: 'signal' }), { layout: 'full', corners: 'sharp' });

// lastFullSkin only feeds corners while the migrated layout is "full";
// a barSkin mapping beats it, and a non-skin lastFullSkin is ignored.
assert.deepEqual(migrated({ barLayout: 'full', lastFullSkin: 'square' }), { layout: 'full', corners: 'soft' });
assert.deepEqual(migrated({ barLayout: 'full', lastFullSkin: 'signal' }), { layout: 'full', corners: 'sharp' });
assert.deepEqual(migrated({ barLayout: 'full', lastFullSkin: 'dock' }), { layout: 'full', corners: 'sharp' });
assert.deepEqual(migrated({ barSkin: 'dock', lastFullSkin: 'pill' }), { layout: 'dock', corners: 'sharp' });
assert.deepEqual(migrated({ barSkin: 'signal', lastFullSkin: 'square' }), { layout: 'full', corners: 'sharp' });
assert.deepEqual(migrated({ lastFullSkin: 'pill' }), { layout: 'capsule', corners: 'sharp' });

assert.equal(bar.cornerRadius('sharp', 48), 0);
assert.equal(bar.cornerRadius('soft', 48), 6);
assert.equal(bar.cornerRadius('round', 48), 24);
assert.equal(bar.cornerRadius('bogus', 48), 0);

assert.equal(bar.next('full'), 'capsule');
assert.equal(bar.next('capsule'), 'dock');
assert.equal(bar.next('dock'), 'taskbar');
assert.equal(bar.next('taskbar'), 'minimal');
assert.equal(bar.next('minimal'), 'full');
assert.equal(bar.next('bogus'), 'full');

console.log('BarLayout migration and corner rules passed');
