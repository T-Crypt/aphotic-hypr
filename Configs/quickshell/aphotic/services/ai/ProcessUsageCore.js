function ingest(previous, sample, now) {
    const hz = Number(sample?.clockTicks);
    const rows = Array.isArray(sample?.rows) ? sample.rows : [];
    const before = previous?.rows || {};
    const elapsed = previous ? (now - previous.at) / 1000 : 0;
    const next = {};
    let memoryMiB = 0;
    let cpuPercent = 0;
    let threads = 0;
    let cpuReady = elapsed > 0 && hz > 0;
    for (const row of rows) {
        const pid = Number(row?.pid);
        const start = Number(row?.startTicks);
        const ticks = Number(row?.cpuTicks);
        const pss = Number(row?.pssKiB);
        const count = Number(row?.threads);
        if (!Number.isInteger(pid) || pid <= 0 || !Number.isFinite(start)
                || !Number.isFinite(ticks) || !Number.isFinite(pss) || pss < 0)
            continue;
        next[pid] = { startTicks: start, cpuTicks: ticks };
        memoryMiB += pss / 1024;
        if (Number.isFinite(count) && count > 0)
            threads += count;
        const old = before[pid];
        if (!cpuReady || !old || old.startTicks !== start || ticks < old.cpuTicks) {
            cpuReady = false;
            continue;
        }
        cpuPercent += (ticks - old.cpuTicks) / hz / elapsed * 100;
    }
    return {
        previous: { at: now, rows: next },
        usage: Object.keys(next).length ? {
            memoryMiB: Math.round(memoryMiB * 10) / 10,
            cpuPercent: cpuReady ? Math.round(cpuPercent * 10) / 10 : null,
            threads: threads || null,
            processCount: Object.keys(next).length,
            source: 'procfs.pss',
            observedAt: now
        } : null
    };
}
