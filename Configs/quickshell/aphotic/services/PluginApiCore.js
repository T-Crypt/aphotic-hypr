// The shell runtime API plugins may call (manifest v3.9's [api]). Plain
// functions so tests/test_plugin_api.cjs runs them under node; the ids
// must match APHOTIC_PLUGIN_API_USES in cmd_plugin.sh, and
// tests/test_plugin_api.sh holds the two equal.

var VERSION = 2;

var USES = ['context.observe', 'context.request', 'resource.observe', 'surface.declare', 'notifications.publish', 'sonar.register'];

// Minimum time between one plugin's context suggestions. A suggestion is
// a notification the user has to look at; a plugin re-suggesting on
// every state change would be noise wearing the user's authority.
var REQUEST_INTERVAL_MS = 60000;

// What a registry entry's `api` block grants: the declared `uses` this
// build knows, and nothing when the plugin declared no [api], asked for
// a newer version, or is not enabled. Install refuses a newer version;
// this is the same answer for a registry written by a newer CLI.
function grants(api, enabled) {
    if (!enabled || !api || typeof api.version !== 'number' || api.version % 1 !== 0 || api.version < 1 || api.version > VERSION)
        return [];
    var uses = Array.isArray(api.uses) ? api.uses : [];
    return USES.filter(function (u) { return uses.indexOf(u) >= 0 && (u !== 'sonar.register' || api.version >= 2); });
}

// Plugin surfaces live in one namespace with core surface names, so a
// plugin's local name is prefixed with its own: it can never shadow or
// close `launcher`, or another plugin's surface.
var PREFIX = 'plugin:';

function surfaceName(plugin, local) {
    if (!plugin || !local || !/^[a-z][a-z0-9-]*$/.test(local))
        return '';
    return PREFIX + plugin + '/' + local;
}

// The owning plugin and local name of a namespaced surface, or null.
function parseSurface(name) {
    var m = /^plugin:([a-z][a-z0-9-]*)\/([a-z][a-z0-9-]*)$/.exec(name || '');
    return m ? {plugin: m[1], local: m[2]} : null;
}

// Whether a context suggestion may go out now.
function mayRequest(last, now) {
    return !(last > 0) || now - last >= REQUEST_INTERVAL_MS;
}
