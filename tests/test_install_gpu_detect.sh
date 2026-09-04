#!/usr/bin/env bash
# tests/test_install_gpu_detect.sh
# GPU vendor detection and the compute-runner choice that hangs off it.
# The interesting case is not "does an AMD card match" -- it is that an
# AMD *CPU* must not, since "Advanced Micro Devices" appears in lspci for
# host bridges, audio and USB controllers on every Ryzen board. A dev
# machine with an Intel or NVIDIA GPU cannot exercise that at all, so the
# lspci output is supplied as fixtures rather than read from the host.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TESTHOME=$(mktemp -d)
trap 'rm -rf "$TESTHOME"' EXIT
mkdir -p "$TESTHOME/bin"
export PATH="$TESTHOME/bin:$PATH"

# Stub lspci; each case writes the fixture it wants into this file.
cat > "$TESTHOME/bin/lspci" <<'STUB'
#!/usr/bin/env bash
cat "$LSPCI_FIXTURE"
STUB
chmod +x "$TESTHOME/bin/lspci"

CNT="[NOTE]"; COK="[OK]"; CER="[ERROR]"; CWR="[WARNING]"

source "$ROOT/lib/install/nvidia.sh"
source "$ROOT/lib/install/amd.sh"
source "$ROOT/lib/install/gpu_compute.sh"

fixture() { LSPCI_FIXTURE="$TESTHOME/fixture"; export LSPCI_FIXTURE; cat > "$LSPCI_FIXTURE"; }

check() {
    local name="$1" want_nv="$2" want_amd="$3" got_nv got_amd
    got_nv="$(detect_nvidia)"
    got_amd="$(detect_amd)"
    [[ "$got_nv" == "$want_nv" ]] || fail "$name: nvidia expected $want_nv, got $got_nv"
    [[ "$got_amd" == "$want_amd" ]] || fail "$name: amd expected $want_amd, got $got_amd"
}

# --- a real AMD card --------------------------------------------------

fixture <<'EOF'
00:00.0 Host bridge: Advanced Micro Devices, Inc. [AMD] Device 14d8
03:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Navi 31 [Radeon RX 7900 XTX] (rev cc)
	Subsystem: Sapphire Technology Limited Navi 31
	Kernel driver in use: amdgpu
	Kernel modules: amdgpu
EOF
check "discrete AMD" false true

# --- an APU's integrated Radeon is a real GPU and wants the same stack --

fixture <<'EOF'
00:00.0 Host bridge: Advanced Micro Devices, Inc. [AMD] Device 14d8
07:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Raphael (rev c1)
	Subsystem: ASUSTeK Computer Inc. Raphael
	Kernel driver in use: amdgpu
EOF
check "AMD APU" false true

# --- the regression this regex exists for -----------------------------
# Ryzen board, NVIDIA card. "Advanced Micro Devices" is all over lspci and
# the GPU is not AMD; matching the bare vendor string would call this AMD
# and install Mesa/RADV on a machine that has no AMD graphics at all.

fixture <<'EOF'
00:00.0 Host bridge: Advanced Micro Devices, Inc. [AMD] Device 14d8
00:01.0 Host bridge: Advanced Micro Devices, Inc. [AMD] Device 14da
00:08.1 PCI bridge: Advanced Micro Devices, Inc. [AMD] Device 14dd
01:00.0 VGA compatible controller: NVIDIA Corporation AD102 [GeForce RTX 4090] (rev a1)
	Subsystem: NVIDIA Corporation Device 167c
	Kernel driver in use: nvidia
	Kernel modules: nvidia
01:00.1 Audio device: NVIDIA Corporation Device 22ba
	Kernel driver in use: snd_hda_intel
0d:00.0 Non-Essential Instrumentation: Advanced Micro Devices, Inc. [AMD] Device 14de
EOF
check "AMD CPU + NVIDIA GPU" true false

# Same trap with an Intel GPU, where an AMD device follows within grep's
# context window.
fixture <<'EOF'
00:02.0 VGA compatible controller: Intel Corporation Raptor Lake-S GT1 (rev 04)
	Subsystem: ASUSTeK Computer Inc. Device 8694
	Kernel driver in use: i915
00:03.0 PCI bridge: Advanced Micro Devices, Inc. [AMD] Device 14dd
EOF
check "Intel GPU, AMD device in context" false false

# --- both cards present: each vendor gets its own userspace -----------

fixture <<'EOF'
01:00.0 VGA compatible controller: NVIDIA Corporation AD107M [GeForce RTX 4060 Max-Q] (rev a1)
	Kernel driver in use: nvidia
06:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Phoenix1 (rev c3)
	Kernel driver in use: amdgpu
EOF
check "hybrid AMD + NVIDIA laptop" true true

# --- pre-GCN cards run the `radeon` driver, not amdgpu ----------------

fixture <<'EOF'
01:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Cape Verde XT [Radeon HD 7770] (rev 01)
	Kernel driver in use: radeon
EOF
check "legacy radeon driver" false true

# --- no GPU line at all (a VM with virtio, say) -----------------------

fixture <<'EOF'
00:00.0 Host bridge: Intel Corporation 440FX (rev 02)
00:02.0 Unclassified device: Red Hat, Inc. Virtio GPU
EOF
check "no VGA/3D device" false false

# --- the runner choice that hangs off the vendor ----------------------

DETECTED_NVIDIA_PRESENT="true" DETECTED_AMD_PRESENT="false"
[[ "$(gpu_vendor)" == "nvidia" ]] || fail "expected nvidia vendor"
[[ "$(resolve_ollama_accel_package)" == "ollama-cuda" ]] || fail "NVIDIA should get ollama-cuda"

DETECTED_NVIDIA_PRESENT="false" DETECTED_AMD_PRESENT="true"
[[ "$(gpu_vendor)" == "amd" ]] || fail "expected amd vendor"
[[ "$(resolve_ollama_accel_package)" == "ollama-rocm" ]] || fail "AMD should get ollama-rocm"

# A hybrid machine feeds the discrete NVIDIA card, which is the one the
# driver path already set up.
DETECTED_NVIDIA_PRESENT="true" DETECTED_AMD_PRESENT="true"
[[ "$(resolve_ollama_accel_package)" == "ollama-cuda" ]] || fail "hybrid should prefer ollama-cuda"

# No GPU means no runner, not a guess -- plain `ollama` still works on CPU.
DETECTED_NVIDIA_PRESENT="false" DETECTED_AMD_PRESENT="false"
[[ -z "$(resolve_ollama_accel_package)" ]] || fail "no GPU should resolve to no accel package"

# --- setup_gpu_compute only fires for the ai layer --------------------

installed=""
install_software() { installed="$installed $1"; }
DETECTED_NVIDIA_PRESENT="true" DETECTED_AMD_PRESENT="false"

LAYERS="gaming,dev" setup_gpu_compute >/dev/null
[[ -z "$installed" ]] || fail "setup_gpu_compute installed '$installed' without the ai layer"

LAYERS="dev,ai" setup_gpu_compute >/dev/null
[[ "$installed" == " ollama-cuda" ]] || fail "expected ollama-cuda with the ai layer, got '$installed'"

# No GPU: the ai layer is on, but there is nothing to accelerate with.
installed=""
DETECTED_NVIDIA_PRESENT="false" DETECTED_AMD_PRESENT="false"
LAYERS="ai" setup_gpu_compute >/dev/null
[[ -z "$installed" ]] || fail "expected no accel package with no GPU, got '$installed'"

# --- end to end through install.sh --dry-run --------------------------
# Proves the wiring, not just the functions: that detect.sh sets the flag,
# the plan reports it, and the ai layer's runner choice reaches the output.

cd "$ROOT"
plan_with() {
    local fixture="$1"; shift
    mkdir -p "$TESTHOME/dryrun"
    cat > "$TESTHOME/dryrun/lspci" <<STUB
#!/usr/bin/env bash
cat <<'PCI'
$fixture
PCI
STUB
    chmod +x "$TESTHOME/dryrun/lspci"
    PATH="$TESTHOME/dryrun:$PATH" bash install.sh --dry-run "$@" </dev/null 2>&1
}

out="$(plan_with '03:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Navi 31 [Radeon RX 7900 XTX] (rev cc)
	Kernel driver in use: amdgpu' --profile minimal --with ai --theme default --no-assistant)"
grep -q "amd: true" <<<"$out" || fail "dry-run plan did not report the AMD GPU: $out"
grep -q "nvidia: false" <<<"$out" || fail "dry-run plan should not report NVIDIA on an AMD box: $out"
grep -q "ollama acceleration: ollama-rocm" <<<"$out" || fail "AMD + ai layer should plan ollama-rocm: $out"
grep -q "would install AMD graphics userspace" <<<"$out" || fail "dry-run should plan the Mesa/RADV install: $out"

out="$(plan_with '01:00.0 VGA compatible controller: NVIDIA Corporation AD102 [GeForce RTX 4090] (rev a1)
	Kernel driver in use: nvidia' --profile minimal --with ai --theme default --no-assistant)"
grep -q "ollama acceleration: ollama-cuda" <<<"$out" || fail "NVIDIA + ai layer should plan ollama-cuda: $out"
grep -q "would install AMD graphics userspace" <<<"$out" && fail "should not plan AMD userspace on an NVIDIA-only box: $out"

# No ai layer: no runner line at all, and the AMD userspace still installs
# because that is a graphics concern, not an AI one.
out="$(plan_with '03:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Navi 31 (rev cc)
	Kernel driver in use: amdgpu' --profile minimal --with dev --theme default --no-assistant)"
grep -q "ollama acceleration" <<<"$out" && fail "no ai layer should mean no runner line: $out"
grep -q "would install AMD graphics userspace" <<<"$out" || fail "AMD userspace should install regardless of the ai layer: $out"

rm -f "$ROOT/aphotic.toml"

echo "PASS: GPU vendor detection (AMD CPU is not an AMD GPU, hybrid, legacy radeon) and the Ollama runner choice"
