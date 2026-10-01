var LIMIT = 64;

function normalize(plugin, local, value) {
    if (!/^[a-z][a-z0-9-]*$/.test(plugin || '') || !/^[a-z][a-z0-9-]*$/.test(local || '') || !value)
        return null;
    var r = value.rect;
    if (!r || ![r.x, r.y, r.width, r.height].every(function (n) { return typeof n === 'number' && isFinite(n) && Math.abs(n) <= 100000; }) || r.width <= 0 || r.height <= 0)
        return null;
    if (typeof value.label !== 'string' || !value.label.trim() || value.label.length > 80 || typeof value.output !== 'string' || !value.output || value.output.length > 128)
        return null;
    var action = value.action || '';
    if (typeof action !== 'string' || action.length > 160)
        return null;
    // An action names one of the plugin's own declared surfaces, so it
    // must be exactly the surface-name grammar, not just the prefix.
    if (action && !(new RegExp('^plugin:' + plugin + '/[a-z][a-z0-9-]*$')).test(action))
        return null;
    return {id: 'plugin:' + plugin + '/' + local, plugin: plugin, local: local, label: value.label.trim(), output: value.output,
        rect: {x:r.x, y:r.y, width:r.width, height:r.height}, action:action, shortcut:typeof value.shortcut === 'string' ? value.shortcut.slice(0, 60) : ''};
}

function distance(point, rect) {
    var dx = Math.max(rect.x - point.x, 0, point.x - rect.x - rect.width);
    var dy = Math.max(rect.y - point.y, 0, point.y - rect.y - rect.height);
    return Math.sqrt(dx * dx + dy * dy);
}

function radius(point, outputs) {
    var result = 1;
    outputs.forEach(function (o) {
        [o.x, o.x + o.width].forEach(function (x) {
            [o.y, o.y + o.height].forEach(function (y) {
                result = Math.max(result, Math.hypot(x - point.x, y - point.y));
            });
        });
    });
    return result;
}

function put(records, value) {
    if (!value)
        return null;
    var owned = Object.keys(records).filter(function (id) { return records[id].plugin === value.plugin; });
    if (!records[value.id] && (owned.length >= LIMIT || Object.keys(records).length >= 1024))
        return null;
    var next = Object.assign({}, records);
    next[value.id] = value;
    return next;
}

function removePlugin(records, plugin) {
    var next = {};
    Object.keys(records).forEach(function (id) {
        if (records[id].plugin !== plugin)
            next[id] = records[id];
    });
    return next;
}
