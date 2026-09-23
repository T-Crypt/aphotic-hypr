#!/usr/bin/env bash
# tests/test_backend_claims.sh
# Every local inference backend is an adapter onto one claimant. A backend
# that grows its own claim or passport code again is the duplication this
# guards against.
set -euo pipefail
fail() { echo "FAIL: $1"; exit 1; }
AI="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/Configs/quickshell/aphotic/services/ai"

grep -q '^BackendClaims 1.0 BackendClaims.qml$' "$AI/qmldir" || fail "BackendClaims is not registered"
grep -q '^LmStudioClaims 1.0 LmStudioClaims.qml$' "$AI/qmldir" || fail "LmStudioClaims is not registered"
for adapter in OllamaClaims LlamaSwapClaims LmStudioClaims; do
    grep -q '^BackendClaims {' "$AI/$adapter.qml" || fail "$adapter is not a BackendClaims adapter"
    ! grep -q 'ResourceEngine.register\|WorkloadPassports.open' "$AI/$adapter.qml" \
        || fail "$adapter registers claims or passports itself"
done
grep -q 'ResourceEngine.register' "$AI/BackendClaims.qml" || fail "BackendClaims does not register claims"
grep -q 'LocalInference.report(root.owner, root.label, models)' "$AI/BackendClaims.qml" \
    || fail "BackendClaims does not report models to LocalInference"
grep -q 'embedding: m?.embedding === true' "$AI/OllamaClaims.qml" \
    && grep -q 'state: m?.state ?? ""' "$AI/LlamaSwapClaims.qml" \
    || fail "backend model metadata is dropped"
grep -q '(system RAM)".length' "$AI/BackendClaims.qml" || fail "a RAM claim's stop would unload a model named after the claim"
grep -q 'size: Number(model.size || 0)' "$AI/BackendModels.js" \
    || fail "Ollama's model size is dropped, so RAM-resident models never claim memory"

echo "PASS: local inference backends share one claimant"
