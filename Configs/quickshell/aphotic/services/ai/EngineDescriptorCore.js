// Engine descriptors: one record from three sources (a repo or drop-in
// TOML file, and a plugin manifest copied into plugins.json), parsed and
// validated in one place. Plain functions so
// tests/test_engine_descriptor_core.cjs runs them under node, the way
// PluginKeybindCore.js and PluginRegistryCore.js are tested. Nothing here
// reads Qt or a file: the caller hands in text and gets a descriptor back.

var PROTOCOLS = ["ollama", "llama-swap", "lmstudio", "openai-models", "engine-report"];
var CAPABILITY_TOKENS = ["models", "claims", "stats", "progress", "chat", "start", "stop", "load", "unload", "switch"];
var CONTROL_VERBS = ["start", "stop", "load", "unload", "switch"];
var ID_PATTERN = /^[a-z][a-z0-9-]*$/;
var KEY_PATTERN = /^[A-Za-z][A-Za-z0-9_]*$/;
// The characters a command line needs a shell to interpret. `{` and `}`
// are left out on purpose: `{model}` is a verb placeholder, not syntax.
var SHELL_SYNTAX = /[\n;&|$`<>()]/;

function _trim(value) {
    return String(value == null ? "" : value).trim();
}

function _scalar(value) {
    if (value.length >= 2 && value.charAt(0) === "[" && value.charAt(value.length - 1) === "]") {
        var list = [];
        for (var part of value.slice(1, -1).split(",")) {
            var item = part.trim();
            if (item.length >= 2 && item.charAt(0) === '"' && item.charAt(item.length - 1) === '"')
                item = item.slice(1, -1);
            if (item.length > 0)
                list.push(item);
        }
        return list;
    }
    if (value.length >= 2 && value.charAt(0) === '"' && value.charAt(value.length - 1) === '"')
        return value.slice(1, -1);
    var number = Number(value);
    if (value.length > 0 && !isNaN(number))
        return number;
    return value;
}

// The flat TOML shape the shared reader speaks: `[engine]`, `[engine.control]`,
// `[engine.stats]`, `[engine.progress]`, single-line `key = "value"` and
// one-line quoted arrays. Returns the `[engine]` table with the three nested
// tables under `control`/`stats`/`progress`, or null when the text has no
// `[engine]` section at all (an empty file, or a plugin that declares none).
function parse(text) {
    if (typeof text !== "string" || text.length === 0)
        return null;
    var out = null;
    var current = null;
    for (var raw of text.split("\n")) {
        var line = raw.trim();
        if (line.length === 0 || line.charAt(0) === "#")
            continue;
        if (line.charAt(0) === "[") {
            var close = line.indexOf("]");
            var section = close < 0 ? "" : line.slice(1, close).trim();
            current = null;
            if (out === null) {
                if (section === "engine") {
                    out = {};
                    current = out;
                }
                continue;
            }
            if (section === "engine") {
                current = out;
            } else if (section === "engine.control") {
                out.control = {};
                current = out.control;
            } else if (section === "engine.stats") {
                out.stats = {};
                current = out.stats;
            } else if (section === "engine.progress") {
                out.progress = {};
                current = out.progress;
            }
            continue;
        }
        if (current === null)
            continue;
        var eq = line.indexOf("=");
        if (eq < 0)
            continue;
        var key = line.slice(0, eq).trim();
        if (key.length === 0)
            continue;
        current[key] = _scalar(line.slice(eq + 1).trim());
    }
    return out;
}

// "http POST /path" or "run /usr/bin/thing arg" -> a parsed form, else null.
function verb(value) {
    var text = _trim(value);
    var parts = text.length > 0 ? text.split(/\s+/) : [];
    if (parts.length === 3 && parts[0] === "http" && /^[A-Z]+$/.test(parts[1]))
        return { kind: "http", method: parts[1], path: parts[2] };
    if (parts.length >= 2 && parts[0] === "run")
        return { kind: "run", command: parts.slice(1).join(" ") };
    return null;
}

function hasShellSyntax(value) {
    return SHELL_SYNTAX.test(_trim(value));
}

function _backed(control, stats, progress, token) {
    if (token === "chat" || token === "models" || token === "claims")
        return true;
    if (token === "stats")
        return stats.endpoint.length > 0;
    if (token === "progress")
        return progress.protocol.length > 0 && progress.file.length > 0;
    if (CONTROL_VERBS.indexOf(token) >= 0)
        return control[token].length > 0;
    return false;
}

// Turn one source record into the in-memory descriptor. Returns
// {descriptor, warnings}. A rejected descriptor is null; the warnings carry
// the reason. Accepted-with-drops keep the descriptor and name the dropped
// part, so one bad token does not lose a working engine.
function normalize(raw, source, sourceName) {
    var warnings = [];
    var label = sourceName || source || "";
    if (raw == null || typeof raw !== "object")
        return { descriptor: null, warnings: warnings };

    var id = _trim(raw.id);
    if (id.length === 0) {
        warnings.push("aphotic engine: " + label + " skipped, it has no id");
        return { descriptor: null, warnings: warnings };
    }
    if (!ID_PATTERN.test(id)) {
        warnings.push("aphotic engine: '" + id + "' skipped, an engine id must be lowercase, start with a letter, and use only [a-z0-9-]");
        return { descriptor: null, warnings: warnings };
    }
    var protocol = _trim(raw.protocol);
    if (protocol.length === 0) {
        warnings.push("aphotic engine: '" + id + "' skipped, no protocol");
        return { descriptor: null, warnings: warnings };
    }
    if (PROTOCOLS.indexOf(protocol) < 0) {
        warnings.push("aphotic engine: '" + id + "' skipped, protocol '" + protocol + "' is not one this shell speaks");
        return { descriptor: null, warnings: warnings };
    }

    var hostKey = _trim(raw.host_key);
    if (hostKey.length > 0 && !KEY_PATTERN.test(hostKey)) {
        warnings.push("aphotic engine: '" + id + "' ignored host key '" + hostKey + "', it is not a settings key name");
        hostKey = "";
    }
    var key = _trim(raw.key);
    if (key.length > 0 && !KEY_PATTERN.test(key)) {
        warnings.push("aphotic engine: '" + id + "' ignored host key '" + key + "', it is not a settings key name");
        key = "";
    }
    var endpoint = _trim(raw.endpoint);
    if (endpoint.length === 0) {
        warnings.push("aphotic engine: '" + id + "' skipped, no endpoint");
        return { descriptor: null, warnings: warnings };
    }
    var defaultHost = _trim(raw.default_host);
    if (!/^https?:\/\//.test(endpoint) && hostKey.length === 0 && defaultHost.length === 0) {
        warnings.push("aphotic engine: '" + id + "' skipped, it has no host to ask");
        return { descriptor: null, warnings: warnings };
    }

    var rawControl = raw.control && typeof raw.control === "object" ? raw.control : {};
    var control = { start: "", stop: "", load: "", unload: "", switch: "" };
    var declaredControl = false;
    for (var name of CONTROL_VERBS) {
        var value = _trim(rawControl[name]);
        if (value.length === 0)
            continue;
        declaredControl = true;
        if (verb(value) === null) {
            warnings.push("aphotic engine: '" + id + "' ignored control verb '" + name + "', it is neither 'http <METHOD> <path>' nor 'run <command>'");
            continue;
        }
        if (hasShellSyntax(value)) {
            warnings.push("aphotic engine: '" + id + "' ignored control verb '" + name + "', it carries shell syntax");
            continue;
        }
        if ((name === "start" || name === "stop") && value.indexOf("{model}") >= 0) {
            warnings.push("aphotic engine: '" + id + "' ignored control verb '" + name + "', no model is in scope");
            continue;
        }
        control[name] = value;
    }

    var gateway = _trim(raw.gateway);
    var gatewayEntry = _trim(raw.gateway_entry);
    if (gateway.length > 0 && declaredControl) {
        warnings.push("aphotic engine: '" + id + "' skipped, it declares control verbs and a gateway, and the gateway owns its lifecycle");
        return { descriptor: null, warnings: warnings };
    }
    if (gatewayEntry.length > 0 && gateway.length === 0) {
        warnings.push("aphotic engine: '" + id + "' ignored its gateway '" + gateway + "', no such engine");
        gatewayEntry = "";
    }

    var rawProgress = raw.progress && typeof raw.progress === "object" ? raw.progress : null;
    var progress = { protocol: "", file: "", staleAfter: 0, rateUnit: "" };
    if (rawProgress) {
        var progressProtocol = _trim(rawProgress.protocol);
        var progressFile = _trim(rawProgress.file);
        if (progressFile.length === 0) {
            warnings.push("aphotic engine: '" + id + "' ignored its progress source, it names no file");
        } else if (progressProtocol !== "engine-progress-report") {
            warnings.push("aphotic engine: '" + id + "' ignored its progress source, protocol '" + progressProtocol + "' is not one this shell speaks");
        } else {
            progress = { protocol: progressProtocol, file: progressFile,
                staleAfter: Number(rawProgress.stale_after || 0) || 0,
                rateUnit: _trim(rawProgress.rate_unit) };
        }
    }

    var rawStats = raw.stats && typeof raw.stats === "object" ? raw.stats : null;
    var stats = { endpoint: "", interval: 0 };
    if (rawStats)
        stats = { endpoint: _trim(rawStats.endpoint), interval: Number(rawStats.interval || 0) || 0 };

    var manages = Array.isArray(raw.manages) ? raw.manages.map(String) : [];
    if (manages.length === 0)
        manages = [id];

    var process = _trim(raw.process);
    var portFlag = _trim(raw.port_flag);
    if (process.length > 0 && portFlag.length === 0)
        portFlag = "--port";

    var capabilities = [];
    var declared = Array.isArray(raw.capabilities) ? raw.capabilities.map(String) : [];
    for (var token of declared) {
        if (CAPABILITY_TOKENS.indexOf(token) < 0) {
            warnings.push("aphotic engine: '" + id + "' ignored capability '" + token + "', which isn't one this shell speaks");
            continue;
        }
        if (!_backed(control, stats, progress, token)) {
            warnings.push("aphotic engine: '" + id + "' ignored capability '" + token + "', nothing in the descriptor provides it");
            continue;
        }
        capabilities.push(token);
    }

    return { descriptor: {
        id: id,
        label: _trim(raw.label).length > 0 ? _trim(raw.label) : id,
        protocol: protocol,
        endpoint: endpoint,
        hostKey: hostKey,
        defaultHost: defaultHost,
        key: key,
        process: process,
        portFlag: portFlag,
        manages: manages,
        gateway: gateway,
        gatewayEntry: gatewayEntry,
        capabilities: capabilities,
        control: control,
        stats: stats,
        progress: progress,
        source: source || "",
        sourceName: sourceName || "",
        requiresLayer: _trim(raw.requires_layer),
        requiresData: _trim(raw.requires_data),
        overriddenBy: "",
        warnings: []
    }, warnings: warnings };
}

var RANK = { "drop-in": 0, "plugin": 1, "core": 2 };

function _sourceLabel(source, sourceName) {
    if (source === "drop-in")
        return "a drop-in";
    if (source === "plugin")
        return "plugin '" + sourceName + "'";
    return "core";
}

// Precedence is drop-in over plugin over core, and a tie inside one tier
// core, and a tie inside one tier keeps the first in registry order. Feed
// the list highest-tier first. Every entry stays in `descriptors`, winner
// before the entry it shadows; a shadowed entry carries an
// `overriddenBy` note so a Settings row can say it lost and to what,
// rather than the loser vanishing. `shadowed` also lists the losers, so a
// caller that only wants the conflicts can read that.
function resolve(list) {
    var warnings = [];
    var winners = {};
    var descriptors = [];
    var shadowed = [];
    for (var descriptor of (list || [])) {
        var rank = RANK[descriptor.source] == null ? 3 : RANK[descriptor.source];
        descriptor.overriddenBy = "";
        if (!(descriptor.id in winners)) {
            winners[descriptor.id] = { descriptor: descriptor, rank: rank };
            descriptors.push(descriptor);
            continue;
        }
        var held = winners[descriptor.id];
        var winner, loser;
        if (rank < held.rank) {
            winner = descriptor;
            loser = held.descriptor;
            winners[descriptor.id] = { descriptor: descriptor, rank: rank };
        } else {
            winner = held.descriptor;
            loser = descriptor;
        }
        loser.overriddenBy = _overriddenBy(winner);
        warnings.push("aphotic engine: '" + descriptor.id + "' from " + _sourceLabel(winner.source, winner.sourceName)
            + " shadows " + _sourceLabel(loser.source, loser.sourceName));
        shadowed.push({ id: loser.id, source: loser.source, sourceName: loser.sourceName });
        descriptors.push(descriptor);
    }

    var known = {};
    for (var winner of descriptors)
        known[winner.id] = true;
    for (var engine of descriptors) {
        if (engine.gateway.length > 0 && !known[engine.gateway]) {
            warnings.push("aphotic engine: '" + engine.id + "' ignored its gateway '" + engine.gateway + "', no such engine");
            engine.gateway = "";
            engine.gatewayEntry = "";
        }
    }

    return { descriptors: descriptors, shadowed: shadowed, warnings: warnings };
}

function _overriddenBy(winner) {
    if (winner.source === "drop-in")
        return "~/.config/aphotic/engines/" + winner.sourceName;
    if (winner.source === "plugin")
        return "plugin '" + winner.sourceName + "'";
    return "core";
}
