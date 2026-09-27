// Groups ActivityProbe reports into what `aphotic runtime` prints and
// `aphotic perf` records. Plain functions so tests/test_activity.cjs runs
// them under node.
//
// Wakeups are *scheduled* wakeups -- 60 s over each live timer's own
// interval -- not measured ones. They say how often the shell asked to
// be woken, which is the number a regression moves.

function wakeups(interval) {
    return interval > 0 ? 60000 / interval : 0;
}

// reports: [{name, kind, active, interval}], one per live probe object.
function summarize(reports) {
    var by = {};
    var order = [];
    (reports || []).forEach(function (r) {
        if (!r || !r.name)
            return;
        var g = by[r.name];
        if (!g) {
            g = by[r.name] = {name: r.name, kind: r.kind || 'poll', instances: 0, active: 0, interval: 0, wakeupsPerMinute: 0};
            order.push(r.name);
        }
        g.instances += 1;
        if (r.active) {
            g.active += 1;
            g.wakeupsPerMinute += wakeups(r.interval);
            if (r.interval > 0 && (g.interval === 0 || r.interval < g.interval))
                g.interval = r.interval;
        } else if (g.active === 0 && r.interval > 0 && (g.interval === 0 || r.interval < g.interval)) {
            g.interval = r.interval;
        }
    });
    var probes = order.sort().map(function (n) {
        var g = by[n];
        g.wakeupsPerMinute = Math.round(g.wakeupsPerMinute * 10) / 10;
        return g;
    });
    var live = probes.filter(function (g) { return g.active > 0; });
    return {
        probes: probes,
        active: live.length,
        idle: probes.length - live.length,
        wakeupsPerMinute: Math.round(live.reduce(function (s, g) { return s + g.wakeupsPerMinute; }, 0) * 10) / 10
    };
}
