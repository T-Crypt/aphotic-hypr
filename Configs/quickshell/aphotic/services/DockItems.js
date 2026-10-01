function group(windows) {
    var order = [], groups = Object.create(null);
    for (var w of windows) {
        if (!groups[w.appClass]) { groups[w.appClass] = []; order.push(w.appClass); }
        groups[w.appClass].push(w);
    }
    return order.map(function(appClass) { return {appClass:appClass,windows:groups[appClass]}; });
}
function dockItems(pinnedIds, grouped, lookupId, lookupClass) {
    const items = [];
    const seenClasses = new Set();

    for (const id of pinnedIds) {
        const entry = lookupId(id);
        if (!entry)
            continue;
        // One pinned app can resolve from several window classes.
        const matches = grouped.filter(g => (lookupClass(g.appClass)?.id ?? "") === id);
        items.push({
            key: id,
            name: entry.name,
            iconName: entry.icon,
            iconKeys: [id, entry.name],
            running: matches.length > 0,
            windows: matches.flatMap(g => g.windows),
            entry
        });
        for (const m of matches)
            seenClasses.add(m.appClass);
    }

    for (const g of grouped) {
        if (seenClasses.has(g.appClass))
            continue;
        const entry = lookupClass(g.appClass);
        items.push({
            key: g.appClass,
            name: entry?.name ?? g.appClass,
            iconName: entry?.icon ?? "",
            iconKeys: g.appClass,
            running: true,
            windows: g.windows,
            entry: entry ?? null
        });
    }

    return items;
}
