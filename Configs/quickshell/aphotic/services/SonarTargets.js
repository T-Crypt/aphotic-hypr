function overlaps(a, b, gap) {
    return a.x < b.x + b.width + gap && a.x + a.width + gap > b.x
        && a.y < b.y + b.height + gap && a.y + a.height + gap > b.y;
}

function clipRect(a, b) {
    var x = Math.max(a.x, b.x), y = Math.max(a.y, b.y);
    var w = Math.min(a.x + a.width, b.x + b.width) - x;
    var h = Math.min(a.y + a.height, b.y + b.height) - y;
    return w > 0 && h > 0 ? {x:x, y:y, width:w, height:h} : null;
}

function placeLabels(targets, width, height, gap) {
    var labels = [], grouped = [];
    (targets || []).slice().sort(function(a,b) { return a.id < b.id ? -1 : a.id > b.id ? 1 : 0; }).forEach(function(t) {
        var w = Math.min(t.labelWidth, width - gap * 2), h = t.labelHeight;
        if (w <= 0 || h > height - gap * 2) { grouped.push(t.id); return; }
        var rect = t.rect;
        var candidates = [{x:rect.x, y:rect.y + rect.height + gap}, {x:rect.x, y:rect.y - h - gap}];
        for (var y = gap * 2 + 28; y + h <= height - gap; y += h + gap)
            for (var x = gap; x + w <= width - gap; x += w + gap)
                candidates.push({x:x,y:y});
        var found = null;
        for (var i = 0; i < candidates.length; i++) {
            var r = {id:t.id, x:Math.max(gap, Math.min(candidates[i].x, width - w - gap)),
                y:Math.max(gap * 2 + 28, Math.min(candidates[i].y, height - h - gap)), width:w, height:h};
            if (r.y + h <= height - gap && !labels.some(function(o) {return overlaps(r,o,gap);})) {found=r;break;}
        }
        if (found) labels.push(found); else grouped.push(t.id);
    });
    return {labels:labels, grouped:grouped};
}

function shortcut(entries, description) {
    var entry = (entries || []).find(function(e) {return e.description === description;});
    return entry ? entry.combo : 'Click';
}

function discoveryDecision(entry, surface, context) {
    if (!entry || !surface || typeof surface.id !== 'string' || !/^[a-z][a-z0-9-]*$/.test(surface.id)
        || typeof surface.label !== 'string' || !surface.label.trim() || surface.label.length > 80
        || ![entry.capabilities ?? [],entry.requires_binaries ?? [],entry.api?.uses ?? [],entry.owns?.config_keys ?? [],entry.owns?.external_config ?? []]
            .every(function(a) { return Array.isArray(a) && a.every(function(v) {return typeof v === 'string';}); })
        || !context.gate || context.safe || context.sheltered
        || !['dashboard','notch','bar','settings','workspace','overlay','fullscreen-overlay','background'].includes(surface.surface)
        || (entry.api && ![1,2].includes(entry.api.version))) return null;
    if (!context.disabled) return {action:'open',reason:''};
    var needsReview = (entry.requires_binaries || []).length > 0 || (entry.api?.uses || []).length > 0
        || (entry.owns?.config_keys || []).length > 0 || (entry.owns?.external_config || []).length > 0
        || !(entry.capabilities || []).every(function(c) {return c === 'ui-surface';});
    return needsReview ? {action:'settings',reason:'Review dependencies, grants and configuration in Settings'} : {action:'enable',reason:''};
}
