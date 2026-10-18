// Plain helpers for EngineHttp.qml, tested under node by
// tests/test_engine_http_core.cjs.

// An OpenAI-style model list. Engines that add a status object or a
// `loaded` flag get that state; the rest are ready by being listed.
function parseModels(text) {
    var data;
    try {
        data = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (!data || !Array.isArray(data.data))
        return null;
    var models = [];
    for (var entry of data.data) {
        if (!entry || typeof entry.id !== "string" || entry.id.length === 0)
            continue;
        var status = entry.status && typeof entry.status === "object" ? String(entry.status.value || "") : String(entry.status || "");
        var state = status === "unloaded" || entry.loaded === false ? "unloaded" : (status === "loading" ? "loading" : "ready");
        models.push({ name: entry.id, state: state });
    }
    return models;
}

// `pgrep -af` output: "<pid> <cmdline>" per line.
function parseProcesses(text) {
    var out = [];
    for (var line of String(text || "").split("\n")) {
        var match = /^\s*(\d+)\s+(.*)$/.exec(line);
        if (match)
            out.push({ pid: Number(match[1]), cmdline: match[2] });
    }
    return out;
}

function portOf(cmdline, flag) {
    if (!flag)
        return 0;
    var parts = String(cmdline).split(/\s+/);
    for (var i = 0; i < parts.length; i++) {
        if (parts[i] === flag && i + 1 < parts.length)
            return Number(parts[i + 1]) || 0;
        if (parts[i].indexOf(flag + "=") === 0)
            return Number(parts[i].slice(flag.length + 1)) || 0;
    }
    return 0;
}

// The process an engine runs as: the only match, or the one serving the
// port the engine is asked on. Several matches and no port to tell them
// apart is no answer.
function pickProcess(processes, port, flag) {
    if (processes.length === 1)
        return processes[0];
    if (port > 0) {
        var onPort = processes.filter(function (p) { return portOf(p.cmdline, flag) === port; });
        if (onPort.length === 1)
            return onPort[0];
    }
    return null;
}

function joinUrl(base, path) {
    if (/^https?:\/\//.test(path))
        return path;
    return String(base).replace(/\/+$/, "") + "/" + String(path).replace(/^\/+/, "");
}

function hostPort(base) {
    var match = /:(\d+)(\/|$)/.exec(String(base).replace(/^https?:\/\//, ""));
    return match ? Number(match[1]) : 0;
}
