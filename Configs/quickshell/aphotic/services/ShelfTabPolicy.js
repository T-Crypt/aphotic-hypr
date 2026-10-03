// Placement rules for shelf tabs, kept pure so the contract can be tested
// without a running shell. A tab is either a core one (media, agents, quick
// controls) or a plugin edge_tab surface, and the only thing this file
// decides is which edges a tab may appear on and which id a plugin tab is
// addressed by. Nothing here loads QML or asks the registry anything.
var VALID_EDGES = ['left', 'right'];

function isValidId(value) {
    return typeof value === 'string' && /^[A-Za-z0-9_.-]{1,64}$/.test(value);
}

// Absent means both edges, which is what a manifest written before the
// field existed gets. Present but unusable means none: a plugin that
// names edges this shell has never heard of is built against a newer
// contract, and showing its tab with the placement silently dropped is
// the outcome the field exists to prevent.
function edgesOf(entry) {
    if (!entry || typeof entry !== 'object')
        return VALID_EDGES.slice();
    var raw = entry.edges;
    if (raw === undefined || raw === null)
        return VALID_EDGES.slice();
    if (typeof raw === 'string')
        raw = raw.split(/[\s,]+/);
    if (!Array.isArray(raw))
        return [];
    var out = [];
    for (var i = 0; i < raw.length; i++) {
        if (VALID_EDGES.indexOf(raw[i]) < 0) return [];
        if (out.indexOf(raw[i]) < 0) out.push(raw[i]);
    }
    return out;
}

function allowsEdge(entry, edge) {
    return VALID_EDGES.indexOf(edge) >= 0 && edgesOf(entry).indexOf(edge) >= 0;
}

function isValidEdge(value) {
    return VALID_EDGES.indexOf(value) >= 0;
}

// A registry surface becomes an addressable tab, or nothing at all. The id
// is namespaced with the plugin name so two plugins declaring `panel` are
// two distinct tabs and neither can shadow a core one.
function pluginTab(surface) {
    if (!surface || typeof surface !== 'object')
        return null;
    if (!isValidId(surface.plugin) || !isValidId(surface.id))
        return null;
    if (typeof surface.componentUrl !== 'string' || surface.componentUrl.indexOf('file://') !== 0)
        return null;
    return {
        id: surface.plugin + ':' + surface.id,
        plugin: surface.plugin,
        label: surface.label || surface.id,
        icon: surface.icon || 'extension',
        componentUrl: surface.componentUrl,
        edges: edgesOf(surface),
        notch: surface.notch === true,
        requiresLayer: surface.requiresLayer || '',
        requiresData: surface.requiresData || ''
    };
}

function forEdge(tabs, edge) {
    if (!isValidEdge(edge))
        return [];
    var out = [];
    for (var i = 0; i < (tabs || []).length; i++)
        if (tabs[i] && allowsEdge(tabs[i], edge))
            out.push(tabs[i]);
    return out;
}

function find(tabs, id, edge) {
    if (typeof id !== 'string' || id.length === 0)
        return null;
    var on = forEdge(tabs, edge);
    for (var i = 0; i < on.length; i++)
        if (on[i].id === id)
            return on[i];
    return null;
}

// Notch placement is opt-in per plugin: a tab that does not declare it is
// not offered to the notch host at all.
function notchTabs(tabs) {
    var out = [];
    for (var i = 0; i < (tabs || []).length; i++)
        if (tabs[i] && tabs[i].notch === true)
            out.push(tabs[i]);
    return out;
}

// A stored selection only survives while its tab still resolves. The last
// entry wins, so the newest choice is the one a stale list keeps.
function selected(tabs, saved, edge) {
    var list = Array.isArray(saved) ? saved : [];
    for (var i = list.length - 1; i >= 0; i--) {
        if (find(tabs, list[i], edge) !== null)
            return list[i];
    }
    return '';
}