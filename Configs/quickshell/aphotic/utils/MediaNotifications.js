function trackKey(player, identity) {
    if (!player)
        return "";
    return [identity || player.identity || "", player.uniqueId || 0, player.trackTitle || "", player.trackArtist || ""].join("\0");
}

function shouldNotify(player, audible, lastKey, identity) {
    if (!player || !player.isPlaying || !audible || !player.trackTitle || !player.trackArtist)
        return false;
    return trackKey(player, identity) !== lastKey;
}

function normalise(value) {
    return String(value || "").toLowerCase().replace(/[^a-z0-9]/g, "");
}

function identityKeys(value) {
    const raw = String(value || "").toLowerCase().trim().replace(/\\/g, "/").split("/").pop().replace(/\.desktop$/, "");
    if (!raw)
        return [];
    const parts = raw.split(".");
    return unique([normalise(raw), normalise(parts[parts.length - 1])]);
}

function streamMatchesPlayer(stream, player, identity) {
    if (!stream || !player)
        return false;

    const properties = stream.properties || {};
    const playerKeys = [identity, player.identity, player.desktopEntry, player.dbusName].flatMap(identityKeys);
    const streamKeys = [
        properties["application.name"],
        properties["application.process.binary"],
        properties["application.id"],
        properties["client.name"],
        properties["node.name"]
    ].flatMap(identityKeys);

    return playerKeys.some(playerKey => streamKeys.includes(playerKey));
}

function streamIsAudible(stream, peak, threshold) {
    return !!stream && stream.ready !== false && !!stream.audio && !stream.audio.muted && stream.audio.volume > 0 && Number.isFinite(peak) && peak > threshold;
}

function isOutputStream(stream, audioOutType) {
    return !!stream && (stream.type & audioOutType) === audioOutType;
}

function hasAudibleOutput(player, monitors, threshold, identity, audioOutType) {
    return monitors.some(monitor => monitor && isOutputStream(monitor.modelData, audioOutType) && streamMatchesPlayer(monitor.modelData, player, identity) && streamIsAudible(monitor.modelData, monitor.peak, threshold));
}

function unique(values) {
    return values.filter((value, index) => value && values.indexOf(value) === index);
}

function sourceFor(player, identity) {
    const metadata = player && player.metadata ? player.metadata : {};
    const url = String(metadata["xesam:url"] || "");
    const match = url.match(/^[a-z][a-z0-9+.-]*:\/\/([^/:?#]+)/i);
    const host = match ? match[1].toLowerCase().replace(/^www\./, "") : "";
    let site = "";

    if (host === "youtu.be" || host === "youtube.com" || host.endsWith(".youtube.com"))
        site = "youtube";
    else if (host) {
        const labels = host.split(".");
        const suffix = labels.length > 1 ? labels[labels.length - 2] : "";
        const compound = labels.length > 2 && labels[labels.length - 1].length === 2 && ["ac", "co", "com", "gov", "net", "org"].includes(suffix);
        site = labels.length > 1 ? labels[labels.length - (compound ? 3 : 2)] : labels[0];
    }

    const fallbackName = identity || (player ? player.identity : "") || "Media";
    const name = site === "youtube" ? "YouTube" : site ? site.charAt(0).toUpperCase() + site.slice(1) : fallbackName;
    const candidates = unique([
        site,
        site === "youtube" ? "youtube-app" : "",
        player ? player.desktopEntry : "",
        player ? player.identity : "",
        identity
    ]);

    return {
        name: name,
        iconCandidates: candidates
    };
}

function firstAvailableIcon(candidates, exists, fallback) {
    return candidates.find(candidate => exists(candidate)) || fallback;
}
