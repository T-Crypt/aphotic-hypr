// Which PID holds VRAM, and under which owner. GpuVramSource keeps the
// adoption map; these are the rules it applies so the decisions are
// testable outside QML.
//
// A PID holds its memory once, so adoption is first-owner-wins: a second
// adapter that spots the same process (llama-swap's server started through
// a wrapper looks like a standalone llama.cpp server) must not take it, or
// both register a claim for one process.

function claimId(pid, owner) {
    return owner + "-proc-" + pid;
}

function processClaimId(pid) {
    return "gpu-proc-" + pid;
}

// Returns the next map and whether another owner already holds the PID.
function adopt(adopted, pid, owner, priority) {
    const key = String(pid);
    const existing = (adopted || {})[key];
    if (existing && existing.owner !== owner)
        return {adopted: adopted || {}, taken: true};
    const next = Object.assign({}, adopted || {});
    next[key] = {owner: owner, priority: priority === "foreground" ? "foreground" : "background"};
    return {adopted: next, taken: false};
}

function unadopt(adopted, pid) {
    const key = String(pid);
    if (!adopted || !Object.prototype.hasOwnProperty.call(adopted, key))
        return {adopted: adopted || {}, owner: ""};
    const next = Object.assign({}, adopted);
    const owner = adopted[key].owner;
    delete next[key];
    return {adopted: next, owner: owner};
}

// A claim id that names a managed PID, the generic gpu-proc-<pid> or any
// <owner>-proc-<pid>. The previous owner's id matches too, which is how a
// claim orphaned by an owner change is recognised and released instead of
// staying frozen beside the live one.
function namesManagedPid(adopted, id) {
    for (const pid of Object.keys(adopted || {})) {
        if (id === processClaimId(pid) || id.endsWith("-proc-" + pid))
            return true;
    }
    return false;
}
