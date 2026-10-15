// Pure device-list rules for the phone bridge. Plain functions over plain
// text so tests/test_phone_policy.cjs runs them under node exactly as QML
// runs them; services/Phone.qml is the reactive wrapper.

// One device per line of `kdeconnect-cli --list-available --id-name-only`:
// the id, whitespace, then the device's name. Everything else in the
// stream is not a device -- the "N devices found" summary line included --
// so a changed command or a changed KDE Connect version yields no devices
// rather than something that looks like one.
var ID = /^[0-9a-f_]{8,}$/i;

function parseDevices(text) {
    var out = [];
    var lines = String(text || '').split('\n');
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (line.length === 0)
            continue;
        var split = line.search(/\s/);
        var id = split < 0 ? line : line.slice(0, split);
        if (!ID.test(id))
            continue;
        // A device the daemon never named is still a device; its own id is
        // the only label there is.
        var label = split < 0 ? '' : line.slice(split).trim();
        out.push({ id: id, label: label.length > 0 ? label : id });
    }
    return out;
}
