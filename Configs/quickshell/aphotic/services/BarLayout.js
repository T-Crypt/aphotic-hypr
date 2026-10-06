.pragma library
// The bar's structural layout plus the corner treatment applied on top of
// it. Plain functions so tests/test_bar_layout.cjs runs them under node.

var LAYOUTS = ["full", "capsule", "dock", "taskbar", "minimal"];
var CORNERS = ["sharp", "soft", "round"];

// The legacy full-layout skins and the corners each maps to; anything
// else returns null.
function legacyCorners(skin) {
    if (skin === "signal")
        return "sharp";
    if (skin === "square")
        return "soft";
    if (skin === "pill")
        return "round";
    return null;
}

// Maps a parsed settings.json object onto { layout, corners }. The new
// keys (barLayout/barCorners) win over the legacy barSkin/lastFullSkin
// values they replaced; anything missing or unknown falls back to the
// first-install defaults (capsule, sharp).
function migrate(data) {
    data = data || {};

    var layout;
    if (LAYOUTS.indexOf(data.barLayout) !== -1)
        layout = data.barLayout;
    else if (LAYOUTS.indexOf(data.barSkin) !== -1)
        layout = data.barSkin;
    else if (legacyCorners(data.barSkin) !== null)
        layout = "full";
    else
        layout = "capsule";

    var corners;
    if (CORNERS.indexOf(data.barCorners) !== -1)
        corners = data.barCorners;
    else {
        var skinCorners = legacyCorners(data.barSkin);
        if (skinCorners)
            corners = skinCorners;
        else if (layout === "full" && legacyCorners(data.lastFullSkin))
            corners = legacyCorners(data.lastFullSkin);
        else
            corners = "sharp";
    }

    return { layout: layout, corners: corners };
}

function cornerRadius(corners, thickness) {
    if (corners === "soft")
        return 6;
    if (corners === "round")
        return thickness / 2;
    return 0;
}

// Next layout in LAYOUTS order, wrapping; unknown input starts at the
// beginning of the list.
function next(layout) {
    var idx = LAYOUTS.indexOf(layout);
    if (idx === -1)
        return LAYOUTS[0];
    return LAYOUTS[(idx + 1) % LAYOUTS.length];
}
