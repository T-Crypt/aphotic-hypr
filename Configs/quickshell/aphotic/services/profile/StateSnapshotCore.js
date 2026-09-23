function parseRender(text) {
    const rows = String(text || "").split("\n").filter(line => line.trim().length > 0);
    if (rows.length < 3)
        return null;
    try {
        const value = row => typeof row.int === "number" ? row.int : (row.bool ? 1 : 0);
        return {
            blur: value(JSON.parse(rows[0])),
            shadow: value(JSON.parse(rows[1])),
            animations: value(JSON.parse(rows[2])),
        };
    } catch (error) {
        return null;
    }
}

function renderBatch(snapshot, current) {
    if (!snapshot)
        return "";
    if (current
            && snapshot.blur === current.blur
            && snapshot.shadow === current.shadow
            && snapshot.animations === current.animations)
        return "";
    return `keyword decoration:blur:enabled ${snapshot.blur} ; keyword decoration:shadow:enabled ${snapshot.shadow} ; keyword animations:enabled ${snapshot.animations}`;
}

// The Lua config parser refuses `hyprctl keyword`; it takes hl.config()
// through `hyprctl eval`. Hyprland.usingLua reads false until Quickshell's
// IPC settles, so unless it is known true, try eval and fall back.
function renderCommand(target, current, usingLua) {
    const batch = renderBatch(target, current);
    if (!batch)
        return null;
    const on = v => (v ? "true" : "false");
    const lua = `hl.config({ decoration = { blur = { enabled = ${on(target.blur)} }, shadow = { enabled = ${on(target.shadow)} } }, animations = { enabled = ${on(target.animations)} } })`;
    if (usingLua === true)
        return ["hyprctl", "eval", lua];
    return ["sh", "-c", `hyprctl eval '${lua}' | grep -qx ok || hyprctl --batch '${batch}'`];
}
