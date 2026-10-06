#!/usr/bin/env bash
# shellcheck disable=SC1007,SC1090,SC1091,SC2030,SC2031
# tools/devvm/proxmox.sh without a hypervisor: fake `qm`, `pvesh`,
# `pvesm`, `pveversion`, `curl`, `apt-get` and `modprobe` stand in for the
# Proxmox host, so the test checks argument parsing, config loading, and
# the exact remote command sequence the script would run, in the recorded
# order. The fake qm keeps a small state file so create/destroy behave like
# the real thing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/tools/devvm/proxmox.sh"
[[ -f "$SCRIPT" ]] || fail "tools/devvm/proxmox.sh not found"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
BIN="$WORKDIR/bin"
mkdir -p "$BIN" "$WORKDIR/home"

# --- fakes -------------------------------------------------------------------

cat > "$BIN/qm" <<'EOF'
#!/usr/bin/env bash
state_file="${FAKE_QM_STATE:?missing FAKE_QM_STATE}"
log_file="${FAKE_QM_LOG:?missing FAKE_QM_LOG}"
cmd="$1"; shift
args=("$@")
printf '%s %s\n' "$cmd" "${args[*]}" >> "$log_file"
case "$cmd" in
  status)
    id="${args[0]}"
    grep -q "^$id$" "$state_file" 2>/dev/null && { echo "status: running"; exit 0; }
    echo "no matching qm" >&2
    exit 1 ;;
  create)
    echo "${args[0]}" >> "$state_file" ;;
  destroy)
    grep -v "^${args[0]}$" "$state_file" > "$state_file.tmp" 2>/dev/null || true
    mv "$state_file.tmp" "$state_file" 2>/dev/null || : > "$state_file" ;;
  disk)  # qm disk import ...
    if [[ "${args[0]}" == "import" && "${args[${#args[@]}-1]:-}" == "--help" ]]; then
      echo "usage: qm disk import"
      exit 0
    fi
    vmid="${args[1]}"; storage="${args[3]}"
    echo "successfully imported disk '${storage}:vm-${vmid}-disk-0'"
    ;;
  importdisk)
    vmid="${args[0]}"; storage="${args[2]}"
    echo "successfully imported disk '${storage}:vm-${vmid}-disk-0'"
    ;;
  stop|start|set) : ;;
esac
exit 0
EOF

cat > "$BIN/pvesh" <<'EOF'
#!/usr/bin/env bash
# pvesh get <path> [flags...]
[[ "${1:-}" == "get" ]] || exit 0
path="$2"
case "$path" in
  /cluster/nextid) echo "${FAKE_NEXTID:-9000}" ;;
  */status/current/ip) echo "${FAKE_VM_IP:-10.0.2.15}" ;;
esac
exit 0
EOF

cat > "$BIN/pvesm" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  status)
    if [[ "${2:-}" == "-content" ]]; then
      echo "Name Type Repl Status Content"
      echo "local-lvm lvm      -      active disks images"
    else
      echo "Name Type"
      echo "local-lvm lvm"
    fi ;;
  list)
    echo "Name Vmid Content"
    echo "local-lvm:vm-9000-disk-0 9000 image"
    ;;
esac
exit 0
EOF

cat > "$BIN/pveversion" <<'EOF'
#!/usr/bin/env bash
echo "pve-manager/${FAKE_PVE_VER:-9.1}-1/no-subscription, kernel 6.8.12"
EOF

cat > "$BIN/curl" <<'EOF'
#!/usr/bin/env bash
# Record every argument; image downloads yield a few bytes, directory
# listings yield file names.
for a in "$@"; do
  printf '%s\n' "$a" >> "${FAKE_CURL_LOG:-/dev/null}"
done
for a in "$@"; do
  case "$a" in
    *opencloud-qcow2-SSD.img)
      # invoked as: curl -fSL --show-error -o <file> <url>
      : > "$4" 2>/dev/null || true
      exit 0 ;;
    *releng/cloud*)
      printf '<a href="archlinux-x86_64-2026.09.30-opencloud-qcow2-SSD.img">old</a>\n'
      printf '<a href="archlinux-x86_64-2026.10.01-opencloud-qcow2-SSD.img">new</a>\n'
      exit 0 ;;
  esac
done
exit 0
EOF

cat > "$BIN/apt-get" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$BIN/modprobe" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$BIN/qm" "$BIN/pvesh" "$BIN/pvesm" "$BIN/pveversion" "$BIN/curl" "$BIN/apt-get" "$BIN/modprobe"

run_devvm() {  # run_devvm [args...] : script against the fake host
  env -i PATH="$BIN:/usr/bin:/bin" HOME="$WORKDIR/home" \
    DEVVM_ALLOW_NONROOT=1 \
    FAKE_QM_STATE="$WORKDIR/qm.state" FAKE_QM_LOG="$WORKDIR/qm.log" \
    FAKE_CURL_LOG="$WORKDIR/curl.log" \
    FAKE_NEXTID=9000 FAKE_VM_IP=10.0.2.15 \
    bash "$SCRIPT" "$@" </dev/null
}

write_env() {  # an env file that only pins the VM id and the SSH key
  mkdir -p "$WORKDIR/home/.config/aphotic" "$WORKDIR/home/.ssh"
  echo "fakekey" > "$WORKDIR/home/.ssh/id_ed25519"
  echo "fakepub" > "$WORKDIR/home/.ssh/id_ed25519.pub"
  cat > "$WORKDIR/home/.config/aphotic/devvm.env" <<EOF
DEVVM_VMID=${TEST_VMID:-9001}
DEVVM_SSH_KEY=$WORKDIR/home/.ssh/id_ed25519
EOF
}

# --- init ----------------------------------------------------------------------

out="$(run_devvm init)" || fail "init failed: $out"
env_out="$WORKDIR/home/.config/aphotic/devvm.env"
[[ -f "$env_out" ]] || fail "init wrote no file"
grep -q '^DEVVM_VMID=$' "$env_out" || fail "init sample should leave the VM ID blank"
grep -q '^DEVVM_RAM=12288$' "$env_out" || fail "init sample misses the working RAM default"
grep -q '^DEVVM_DISPLAY=virtio$' "$env_out" || fail "init sample misses the VirtIO-GPU default"
! grep -qE '^[A-Z_]+=[0-9]+\.[0-9]+\.[0-9]+\.' "$env_out" \
  || fail "init sample carries a network value"
run_devvm init >/dev/null 2>&1 && fail "second init should refuse to overwrite"

# --- dispatch ------------------------------------------------------------------

rc=0
run_devvm bogus >/dev/null 2>&1 || rc=$?
[[ $rc -eq 2 ]] || fail "unknown command should exit 2, got $rc"
rc=0
run_devvm >/dev/null 2>&1 || rc=$?
[[ $rc -eq 2 ]] || fail "no command should exit 2, got $rc"

# --- create-vm: the default path ------------------------------------------------

write_env
: > "$WORKDIR/qm.log"; : > "$WORKDIR/qm.state"; : > "$WORKDIR/curl.log"
out="$(run_devvm create-vm)" || fail "create-vm failed: $out"
grep -q 'VM ID:      9001' <<<"$out" || fail "create-vm summary misses the VM id: $out"
create_line="$(grep '^create 9001' "$WORKDIR/qm.log" | head -1)"
[[ -n "$create_line" ]] || fail "no qm create in log: $(tr '\n' ' ' <"$WORKDIR/qm.log")"
for want in '-machine q35' '-bios ovmf' '-cpu host' '-cores 6' '-memory 12288' \
  '-vga virtio' 'virtio,bridge=vmbr0' '-agent 1' '-ostype l26'; do
  grep -qF -- "$want" <<<"$create_line" || fail "create misses $want: $create_line"
done
grep -q 'macaddr=02:' <<<"$create_line" || fail "create sets no MAC: $create_line"
grep -q '^set 9001 -efidisk0 local-lvm:0,efitype=4m -scsi0' "$WORKDIR/qm.log" \
  || fail "no EFI/cloud-init qm set: $(tr '\n' ' ' <"$WORKDIR/qm.log")"
grep -q -- '--ipconfig0 ip=dhcp' "$WORKDIR/qm.log" \
  || fail "default addressing is not DHCP: $(tr '\n' ' ' <"$WORKDIR/qm.log")"
grep -q '^start 9001' "$WORKDIR/qm.log" || fail "default create-vm does not start the VM"
grep -qF 'archlinux-x86_64-2026.10.01-opencloud-qcow2-SSD.img' "$WORKDIR/curl.log" \
  || fail "did not download the newest cloud image: $(tr '\n' ' ' <"$WORKDIR/curl.log")"

# --- create-vm: the advanced path ------------------------------------------------

: > "$WORKDIR/qm.log"; : > "$WORKDIR/qm.state"
TEST_VMID=9005 write_env
out="$(run_devvm create-vm --ram 8192 --cores 4 --display std --ip 10.0.2.50/24 --no-start)" \
  || fail "advanced create-vm failed: $out"
create_line="$(grep '^create 9005' "$WORKDIR/qm.log" | head -1)"
grep -qF -- '-memory 8192' <<<"$create_line" || fail "advanced RAM ignored: $create_line"
grep -qF -- '-cores 4' <<<"$create_line" || fail "advanced cores ignored: $create_line"
grep -qF -- '-vga std' <<<"$create_line" || fail "advanced display ignored: $create_line"
grep -qF -- 'ip=10.0.2.50/24 gw=10.0.2.1' "$WORKDIR/qm.log" \
  || fail "static addressing lost: $(tr '\n' ' ' <"$WORKDIR/qm.log")"
! grep -q '^start 9005' "$WORKDIR/qm.log" || fail "--no-start still started the VM"

# --- guards ----------------------------------------------------------------------

TEST_VMID=9001 write_env
grep -q '^9001$' "$WORKDIR/qm.state" || echo 9001 >> "$WORKDIR/qm.state"
out="$(run_devvm create-vm 2>&1)" && fail "create over an existing VM should fail: $out"
grep -q 'already exists' <<<"$out" || fail "existing-VM guard missing: $out"

out="$(run_devvm create-vm --bogus 2>&1)" && fail "unknown flag should fail: $out"
rc=0
run_devvm create-vm --bogus >/dev/null 2>&1 || rc=$?
[[ $rc -eq 2 ]] || fail "unknown flag should exit 2, got $rc"

out="$(run_devvm create-vm --ram 2>&1)" && fail "--ram without a value should fail: $out"

# --- reset and destroy -------------------------------------------------------------

: > "$WORKDIR/qm.log"; : > "$WORKDIR/qm.state"; echo 9001 > "$WORKDIR/qm.state"
run_devvm reset || fail "reset failed"
n_destroy="$(grep -n '^destroy 9001' "$WORKDIR/qm.log" | cut -d: -f1 | head -1)"
n_create="$(grep -n '^create 9001' "$WORKDIR/qm.log" | cut -d: -f1 | head -1)"
n_start="$(grep -n '^start 9001' "$WORKDIR/qm.log" | cut -d: -f1 | head -1)"
[[ -n "$n_destroy" && -n "$n_create" && -n "$n_start" ]] \
  || fail "reset log misses a step: $(tr '\n' ' ' <"$WORKDIR/qm.log")"
(( n_destroy < n_create && n_create < n_start )) \
  || fail "reset steps out of order: $(tr '\n' ' ' <"$WORKDIR/qm.log")"

: > "$WORKDIR/qm.log"
run_devvm destroy || fail "destroy failed"
grep -q '^stop 9001' "$WORKDIR/qm.log" || fail "destroy did not stop the VM"
grep -q '^destroy 9001' "$WORKDIR/qm.log" || fail "destroy did not delete the VM"
! grep -q '^9001$' "$WORKDIR/qm.state" || fail "destroy left the VM in the state"
out="$(run_devvm destroy)"
grep -q 'nothing to do' <<<"$out" || fail "destroy of an absent VM should say so: $out"

# --- status ------------------------------------------------------------------------

echo 9001 > "$WORKDIR/qm.state"
out="$(run_devvm status)" || fail "status failed: $out"
grep -q '^VM 9001: status: running$' <<<"$out" || fail "status misses the VM state: $out"
grep -q '^address: 10.0.2.15$' <<<"$out" || fail "status misses the address: $out"
: > "$WORKDIR/qm.state"
out="$(run_devvm status)"
grep -q '^VM 9001: absent$' <<<"$out" || fail "status of an absent VM wrong: $out"

# --- the env file wins over built-in defaults ---------------------------------------

mkdir -p "$WORKDIR/home/.config/aphotic"
cat > "$WORKDIR/home/.config/aphotic/devvm.env" <<EOF
DEVVM_VMID=9100
PVE_BRIDGE=vmbr7
DEVVM_SSH_KEY=$WORKDIR/home/.ssh/id_ed25519
EOF
: > "$WORKDIR/qm.log"; : > "$WORKDIR/qm.state"
out="$(run_devvm create-vm)" || fail "env-driven create-vm failed: $out"
grep -q 'VM ID:      9100' <<<"$out" || fail "env VM ID ignored: $out"
grep -q 'virtio,bridge=vmbr7' "$WORKDIR/qm.log" \
  || fail "env bridge ignored: $(tr '\n' ' ' <"$WORKDIR/qm.log")"

# --- install: host bootstrap ---------------------------------------------------------

out="$(run_devvm install --bogus 2>&1)" && fail "install with an unknown flag should fail: $out"
rc=0
run_devvm install --bogus >/dev/null 2>&1 || rc=$?
[[ $rc -eq 2 ]] || fail "install unknown flag should exit 2, got $rc"

HOST_ID="$(. /etc/os-release && echo "${ID:-}")"
if [[ "$HOST_ID" != "debian" ]]; then
  # The test host is not Debian: the script must refuse before touching apt.
  out="$(run_devvm install 2>&1)" && fail "install on non-Debian should fail: $out"
  grep -q 'Debian-only' <<<"$out" || fail "non-Debian guard message missing: $out"
else
  : > "$WORKDIR/qm.log"
  out="$(run_devvm install)" || fail "install on Debian failed: $out"
  grep -q 'no-subscription' <<<"$out" || fail "default install does not name the repo: $out"
fi
out="$(run_devvm install --enterprise 2>&1)" || true
if [[ "$HOST_ID" == "debian" ]]; then
  grep -q 'enterprise' <<<"$out" || fail "advanced install does not name the enterprise repo: $out"
fi

# --- static addressing spec ------------------------------------------------------------

spec_out="$(
  export PVE_USER='' PVE_HOST=''
  source "$SCRIPT"
  DEVVM_IP_MODE=static DEVVM_STATIC_IP=10.0.2.15/24 ipconfig_spec
)"
[[ "$spec_out" == "ip=10.0.2.15/24 gw=10.0.2.1" ]] \
  || fail "static /24 spec wrong: $spec_out"

spec_out="$(
  export PVE_USER='' PVE_HOST=''
  source "$SCRIPT"
  DEVVM_IP_MODE=static DEVVM_STATIC_IP=10.0.2.15 DEVVM_GATEWAY=10.0.2.1 DEVVM_DNS=1.1.1.1 ipconfig_spec
)"
[[ "$spec_out" == "ip=10.0.2.15 gw=10.0.2.1 dns=1.1.1.1" ]] \
  || fail "static explicit spec wrong: $spec_out"

spec_out="$(
  export PVE_USER='' PVE_HOST=''
  source "$SCRIPT"
  DEVVM_IP_MODE=dhcp ipconfig_spec
)"
[[ "$spec_out" == "ip=dhcp" ]] || fail "dhcp spec wrong: $spec_out"

echo "PASS: devvm"
