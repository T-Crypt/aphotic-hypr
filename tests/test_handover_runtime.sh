#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v qs >/dev/null || { echo 'SKIP: qs unavailable'; exit 0; }
PROBE=$(mktemp "$ROOT/Configs/quickshell/aphotic/_probe_handover_XXXXXX.qml")
TESTHOME=$(mktemp -d)
trap 'rm -f "$PROBE"; rm -rf "$TESTHOME"' EXIT
cat > "$PROBE" <<'QML'
import QtQuick
import Quickshell
import qs.services.profile
ShellRoot {
    property string ownerState: "already-off"
    function check(ok, message) { if (!ok) throw new Error(message); }
    Component.onCompleted: {
        ResourceEngine.declareResource("memory", {capacity: 64000, safetyMargin: 0.1});
        const a = {id: "vm-a", owner: "example", plane: "gaming", label: "A", resources: [{key: "pci:01", amount: 1, exclusive: true}]};
        const b = {id: "vm-b", owner: "example", plane: "gaming", label: "B", resources: [{key: "pci:02", amount: 1, exclusive: true}]};
        check(Handover.reserve(a).ok, "first lease");
        check(Handover.reserve(b).ok, "second lease");
        check(ResourceEngine.claimsFor("pci:01").length === 1, "claim visible");
        check(WorkloadPassports.live.length === 2, "two passports");
        check(!Handover.reserve(Object.assign({}, a, {id: "vm-c"})).ok, "exclusive conflict refused");
        check(ResourceEngine.register({id: "other", owner: "other", resource: "pci:01", amount: 1}).blocked, "registration blocked");
        check(ResourceEngine.claimsFor("pci:01").length === 1, "blocked registration not inserted");
        Handover.releaseLease({id: "vm-a"});
        check(ResourceEngine.claimsFor("pci:01").length === 0 && ResourceEngine.claimsFor("pci:02").length === 1, "independent release");
        ProfileEngine.register({id: "background", onShelter: function() {}, onUnshelter: function() {},
            handoverState: () => ownerState,
            handoverShelter: target => { ownerState = target; return true; },
            handoverRestore: target => { ownerState = target; return true; }});
        const before = Handover.shelterSnapshot({owner: "background"});
        check(before.ok && before.value === "already-off", "exact snapshot");
        const stage = {owner: "background", before: before.value, after: "sheltered"};
        check(Handover.shelterChange(stage, false).ok && ownerState === "sheltered", "shelter effect");
        check(Handover.shelterChange(stage, true).ok && ownerState === "already-off", "exact restore");
        Handover.shelterChange(stage, false);
        ownerState = "user-edit";
        check(!Handover.shelterChange(stage, true).ok && ownerState === "user-edit", "preserve intervening change");
        check(!Handover.shelterSnapshot({owner: "unsupported"}).ok, "unsupported provider refuses");
        Handover.ingest(JSON.stringify({schema: 1, leases: [Object.assign({}, a, {status: "acquiring", stages: [{id: "reserve", kind: "reserve", status: "applying"}]})]}));
        check(Handover.recovery.length === 1, "interrupted journal surfaced");
        check(ActionReceipts.all.some(r => r.kind === "handover" && r.status === "requested"), "receipt is pending not applied");
        Handover.ingest(JSON.stringify({schema: 1, leases: [], errors: [{file: "broken.json"}]}));
        check(ResourceEngine.leaseRecoveryBlocked && !Handover.preview(a).ok, "corrupt neighbor fails closed");
        console.log("PASS handover runtime");
    }
}
QML
result=0
HOME="$TESTHOME" XDG_STATE_HOME="$TESTHOME/state" XDG_RUNTIME_DIR="$TESTHOME" QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 4 qs -p "$PROBE" > "$TESTHOME/output" 2>&1 || result=$?
[[ "$result" == 0 || "$result" == 124 ]] || { cat "$TESTHOME/output"; exit 1; }
grep -q 'PASS handover runtime' "$TESTHOME/output" || { cat "$TESTHOME/output"; exit 1; }
echo 'PASS: handover QML runtime'
