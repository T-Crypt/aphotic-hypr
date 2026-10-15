// Send and receive rules for the SMS widget. Plain functions over plain
// values so tests/test_phone_message_policy.cjs runs them under node
// exactly as QML runs them; services/PhoneMessages.qml is the wrapper
// that owns the store and the process.

// The argv tail for one send. Order matches `kdeconnect-cli --help` on
// this machine: --send-sms <message>, --destination <number>, -d <device>.
// Blank inputs yield no argv, so the caller sends nothing instead of a
// half addressed message.
function buildSendArgs(deviceId, destination, body) {
    var d = String(deviceId || '').trim();
    var to = String(destination || '').trim();
    var text = String(body || '').trim();
    if (d.length === 0 || to.length === 0 || text.length === 0)
        return [];
    return ['--send-sms', text, '--destination', to, '-d', d];
}

function isSendable(deviceId, destination, body) {
    return buildSendArgs(deviceId, destination, body).length > 0;
}

// One incoming message into the thread store shape. The daemon receive
// path is still unobserved (no paired phone on this machine), so this
// takes a plain object and rejects anything short of a full triple. The
// timestamp stays a number, 0 when absent, and the direction is always
// "in": sends are recorded by the caller, never parsed here.
function parseIncoming(payload) {
    if (!payload || typeof payload !== 'object')
        return null;
    var d = String(payload.deviceId || '').trim();
    var from = String(payload.address || '').trim();
    var text = String(payload.body || '').trim();
    if (d.length === 0 || from.length === 0 || text.length === 0)
        return null;
    var ts = Number(payload.timestamp);
    if (isNaN(ts) || ts < 0)
        ts = 0;
    return { deviceId: d, address: from, body: text, timestamp: ts, direction: 'in' };
}
