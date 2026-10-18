// The engine-report protocol: one JSON document that says which models an
// engine holds and what they cost. A gateway that runs several engines
// lists each under `engines`; a single engine puts its `models` at the top
// level. Plain functions, tested under node by tests/test_engine_report_core.cjs.

var REPORT_VERSION = "aphotic-engine/1";
var ENGINE_ID = /^[a-z][a-z0-9-]*$/;

function _number(value) {
    var n = Number(value);
    return isFinite(n) && n > 0 ? n : 0;
}

function _model(raw) {
    if (!raw || typeof raw !== "object")
        return null;
    var name = String(raw.name == null ? "" : raw.name).trim();
    if (name.length === 0)
        return null;
    var pid = Math.floor(_number(raw.pid));
    return {
        name: name,
        state: String(raw.state == null ? "" : raw.state),
        embedding: raw.embedding === true,
        pid: pid,
        vramMiB: Math.round(_number(raw.vramMiB)),
        ramMiB: Math.round(_number(raw.ramMiB))
    };
}

function _engine(raw, fallbackId) {
    if (!raw || typeof raw !== "object")
        return null;
    var id = String(raw.id == null ? fallbackId : raw.id).trim();
    if (!ENGINE_ID.test(id))
        return null;
    var models = (Array.isArray(raw.models) ? raw.models : []).map(_model).filter(function (m) { return m !== null; });
    var cpu = Number(raw.cpuPercent);
    return {
        id: id,
        label: String(raw.label == null || raw.label === "" ? id : raw.label),
        state: String(raw.state == null ? (models.length > 0 ? "ready" : "idle") : raw.state),
        cpuPercent: isFinite(cpu) && cpu >= 0 ? Math.round(cpu * 10) / 10 : null,
        threads: Math.floor(_number(raw.threads)) || null,
        models: models
    };
}

// -> {ok, warning, engines}. A report this shell cannot read is one warning
// and no engines, never an exception.
function parse(text, descriptorId) {
    var data;
    try {
        data = JSON.parse(text);
    } catch (error) {
        return { ok: false, warning: "not JSON", engines: [] };
    }
    if (!data || typeof data !== "object")
        return { ok: false, warning: "not an object", engines: [] };
    if (data.protocol !== REPORT_VERSION)
        return { ok: false, warning: "protocol '" + data.protocol + "' is not " + REPORT_VERSION, engines: [] };
    var engines = [];
    if (Array.isArray(data.engines)) {
        for (var raw of data.engines) {
            var engine = _engine(raw, "");
            if (engine !== null)
                engines.push(engine);
        }
    } else {
        var single = _engine({
            id: descriptorId,
            label: data.engine && data.engine.label,
            state: data.engine && data.engine.state,
            cpuPercent: data.engine && data.engine.cpuPercent,
            models: data.models
        }, descriptorId);
        if (single !== null)
            engines.push(single);
    }
    var seen = {};
    engines = engines.filter(function (e) {
        if (seen[e.id])
            return false;
        seen[e.id] = true;
        return true;
    });
    return { ok: true, warning: "", engines: engines };
}

// The ids a stream may own: every id it has reported before, plus new ids
// no other adapter holds. `taken(id)` answers for the rest of the shell.
function claimable(engines, owned, taken) {
    return engines.filter(function (e) { return owned[e.id] === true || !taken(e.id); });
}
