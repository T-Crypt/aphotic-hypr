// Semantic status colours from a wallpaper-derived seed. ANSI slots carry
// no guaranteed hue, so each status keeps the seed's hue only inside its
// own band, gets a saturation floor, and has its lightness moved until it
// reads against every surface it sits on.

const SPECS = {
    error: { center: 0, spread: 14, minSat: 0.55, fallback: "#d9534f" },
    warning: { center: 42, spread: 12, minSat: 0.6, fallback: "#e0a030" },
    success: { center: 130, spread: 30, minSat: 0.4, fallback: "#4caf6a" }
};

const MIN_CONTRAST = 4.5;
// Past these a colour reads as black or white and its hue is gone.
const MIN_LIGHTNESS = 0.18;
const MAX_LIGHTNESS = 0.88;

function parseHex(value) {
    const m = /^#?(?:[0-9a-f]{2})?([0-9a-f]{6})$/i.exec(String(value || "").trim());
    if (!m)
        return null;
    const n = parseInt(m[1], 16);
    return [((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255];
}

function toHex(rgb) {
    return "#" + rgb.map(v => Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, "0")).join("");
}

function rgbToHsl(rgb) {
    const [r, g, b] = rgb;
    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    const l = (max + min) / 2;
    if (max === min)
        return [0, 0, l];
    const d = max - min;
    const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    let h;
    if (max === r)
        h = (g - b) / d + (g < b ? 6 : 0);
    else if (max === g)
        h = (b - r) / d + 2;
    else
        h = (r - g) / d + 4;
    return [h * 60, s, l];
}

function hslToRgb(hsl) {
    const [h, s, l] = hsl;
    const c = (1 - Math.abs(2 * l - 1)) * s;
    const hp = (((h % 360) + 360) % 360) / 60;
    const x = c * (1 - Math.abs((hp % 2) - 1));
    const m = l - c / 2;
    const table = [[c, x, 0], [x, c, 0], [0, c, x], [0, x, c], [x, 0, c], [c, 0, x]];
    const [r, g, b] = table[Math.min(5, Math.floor(hp))];
    return [r + m, g + m, b + m];
}

function luminance(rgb) {
    const chan = v => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    return 0.2126 * chan(rgb[0]) + 0.7152 * chan(rgb[1]) + 0.0722 * chan(rgb[2]);
}

function contrast(a, b) {
    const la = luminance(a);
    const lb = luminance(b);
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

function hueDelta(h, center) {
    return ((h - center + 540) % 360) - 180;
}

function clampHue(h, center, spread) {
    const d = hueDelta(h, center);
    if (Math.abs(d) <= spread)
        return ((h % 360) + 360) % 360;
    return (((center + (d > 0 ? spread : -spread)) % 360) + 360) % 360;
}

function worstContrast(rgb, surfaces) {
    return surfaces.reduce((worst, s) => Math.min(worst, contrast(rgb, s)), Infinity);
}

// Nearest lightness, either way from the seed's own, that clears the floor
// against every surface; the most readable one if none does.
function readableLightness(h, s, l, surfaces, floor) {
    let best = l;
    let bestRatio = -1;
    for (let step = 0; step <= 200; step++) {
        const delta = step * 0.005;
        for (const candidate of [l + delta, l - delta]) {
            if (candidate < MIN_LIGHTNESS || candidate > MAX_LIGHTNESS)
                continue;
            const ratio = worstContrast(hslToRgb([h, s, candidate]), surfaces);
            if (ratio >= floor)
                return candidate;
            if (ratio > bestRatio) {
                bestRatio = ratio;
                best = candidate;
            }
        }
    }
    return best;
}

function derive(kind, seed, surfaces) {
    const spec = SPECS[kind];
    if (!spec)
        return String(seed);
    const rgb = parseHex(seed) || parseHex(spec.fallback);
    const backs = (surfaces || []).map(parseHex).filter(v => v);
    let [h, s, l] = rgbToHsl(rgb);
    h = s < 0.08 ? spec.center : clampHue(h, spec.center, spec.spread);
    s = Math.max(s, spec.minSat);
    l = Math.max(MIN_LIGHTNESS, Math.min(MAX_LIGHTNESS, l));
    if (backs.length > 0)
        l = readableLightness(h, s, l, backs, MIN_CONTRAST);
    return toHex(hslToRgb([h, s, l]));
}
