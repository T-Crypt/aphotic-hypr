#!/usr/bin/env bash
# tools/devvm/proxmox.sh
# Proxmox VE helper for a disposable dev VM, modelled on the community
# scripts Proxmox VE Helper (https://community-scripts.org,
# https://github.com/community-scripts/ProxmoxVE): the same default/
# advanced split, the same checks and cleanup, minus the app installs.
#
# It runs on the Proxmox host itself:
#
#   init        write a commented example ~/.config/aphotic/devvm.env
#   install     install Proxmox VE on this bare Debian host
#   create-vm   create the dev VM from the latest Arch opencloud image
#   reset       delete the dev VM and create it again
#   destroy     stop and delete the dev VM
#   status      VM state and address
#
# `install` and `create-vm` each take a default and an advanced form.
# With no options on a terminal, the default values are shown and a
# single confirmation is asked; with no options and no terminal, the
# defaults run unattended. Any flag switches to the advanced form, where
# each setting is a flag (values from devvm.env are used as the starting
# points, as the interactive path uses them).
#
# The VM uses the machine that runs a real Hyprland session (q35, OVMF,
# host CPU, VirtIO-GPU render node) so the desktop runs under KVM, and
# cloud-init so a user and an SSH key can be seeded without a console.

set -euo pipefail
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT

ENV_FILE="${DEVVM_ENV:-$HOME/.config/aphotic/devvm.env}"

BACKTITLE="Aphotic dev VM on Proxmox VE"
TEMP_DIR="$(mktemp -d)"
CREATED_VMID=""

# --- output --------------------------------------------------------------------

MSG_MAX_LENGTH=0
function msg_info() {
  local msg="${1:-}"
  MSG_MAX_LENGTH=$(( ${#msg} > MSG_MAX_LENGTH ? ${#msg} : MSG_MAX_LENGTH ))
  echo -ne "  [ .. ] $msg"
}
function msg_ok() {
  local msg="${1:-}"
  echo -e "\r\033[K  [ OK ] $msg"
}
function msg_error() {
  local msg="${1:-}"
  echo -e "\r\033[K  [FAIL] $msg" >&2
}
function msg() {
  local msg="${1:-}"
  MSG_MAX_LENGTH=$(( ${#msg} > MSG_MAX_LENGTH ? ${#msg} : MSG_MAX_LENGTH ))
  echo -e "  [INFO] $msg"
}

function error_handler() {
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  msg_error "error in line $line_number: exit code $exit_code while executing: $command"
  cleanup_vmid
  exit "$exit_code"
}

function cleanup() {
  rm -rf "$TEMP_DIR"
}
function cleanup_vmid() {
  [[ -n "$CREATED_VMID" ]] || return 0
  qm status "$CREATED_VMID" &>/dev/null || return 0
  qm stop "$CREATED_VMID" &>/dev/null || true
  qm destroy "$CREATED_VMID" &>/dev/null || true
}

# --- checks ---------------------------------------------------------------------

function check_root() {
  [[ "${DEVVM_ALLOW_NONROOT:-0}" == "1" ]] && return 0
  if [[ "$(id -u)" -ne 0 || $(ps -o comm= -p "$PPID" 2>/dev/null) == "sudo" ]]; then
    msg_error "please run this script as root"
    exit 1
  fi
}

# Supported: Proxmox VE 8.x and 9.x, as with the helper scripts this is
# modelled on.
function pve_check() {
  command -v pveversion >/dev/null 2>&1 || {
    msg_error "this host does not run Proxmox VE (pveversion not found)"
    msg_error "run: $SCRIPT_NAME install"
    exit 1
  }
  local pve_ver minor
  pve_ver="$(pveversion | awk -F'/' '{print $2}' | awk -F'-' '{print $1}')"
  if [[ "$pve_ver" =~ ^8\.([0-9]+) || "$pve_ver" =~ ^9\.([0-9]+) ]]; then
    minor="${BASH_REMATCH[1]:-0}"
    [[ "$minor" -lt 100 ]] && return 0
  fi
  msg_error "unsupported Proxmox VE version: $pve_ver (supported: 8.x and 9.x)"
  exit 1
}

function arch_check() {
  [[ "$(uname -m)" == "x86_64" ]] || {
    msg_error "this script only works on x86_64 hosts (KVM acceleration)"
    exit 1
  }
}

# --- configuration ---------------------------------------------------------------

# Settings, in the order the advanced path asks for them. Every value is
# overridable in devvm.env; blank means "use the built-in default".
: "${DEVVM_VMID:=}"
: "${DEVVM_NAME:=aphotic-devvm}"
: "${DEVVM_MACHINE:=q35}"
: "${DEVVM_CPU:=host}"
: "${DEVVM_DISPLAY:=virtio}"
: "${DEVVM_RAM:=12288}"
: "${DEVVM_CORES:=6}"
: "${DEVVM_DISK:=60G}"
: "${DEVVM_USER:=aphotic}"
: "${DEVVM_SSH_KEY:=$HOME/.ssh/id_ed25519}"
: "${DEVVM_IP_MODE:=dhcp}"
: "${DEVVM_STATIC_IP:=}"
: "${DEVVM_GATEWAY:=}"
: "${DEVVM_DNS:=}"
: "${DEVVM_MAC:=}"
: "${DEVVM_VLAN:=}"
: "${DEVVM_MTU:=}"
: "${PVE_STORAGE:=}"
: "${DEVVM_START:=yes}"
: "${PVE_BRIDGE:=vmbr0}"

load_env() {
  [[ -f "$ENV_FILE" ]] || return 0
  # shellcheck disable=SC1090
  source "$ENV_FILE"
}

function get_valid_nextid() {
  local try_id
  try_id="$(pvesh get /cluster/nextid 2>/dev/null || echo 100)"
  while true; do
    if [[ -f "/etc/pve/qemu-server/${try_id}.conf" ]]; then
      try_id=$((try_id + 1))
      continue
    fi
    break
  done
  echo "$try_id"
}

# --- install: Proxmox VE on a bare Debian host -----------------------------------

function install_summary() {
  local repo_text
  if [[ "$REPO" == "enterprise" ]]; then
    repo_text="Proxmox VE enterprise (apt credentials required)"
  else
    repo_text="Proxmox VE no-subscription (free)"
  fi
  echo "Repo:       $repo_text"
  echo "Kernel:     PVE kernel, installed and selected for next boot"
  echo "Microcode:  matched to the CPU vendor"
  [[ -n "${BRIDGE:-}" ]] && echo "Bridge:     $BRIDGE"
  [[ -n "${IP:-}" ]] && echo "Address:    ${IP}${GATEWAY:+ via ${GATEWAY}}${DNS:+, dns ${DNS}}"
  echo "Network:    left untouched when no bridge or address is set"
}

function debian_check() {
  [[ -r /etc/os-release ]] || { msg_error "no /etc/os-release; is this Debian?"; exit 1; }
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "debian" ]] || {
    msg_error "Proxmox VE is Debian-only, and this is: ${ID:-unknown}"
    exit 1
  }
  local major="${VERSION_ID%%.*}"
  [[ "$major" -ge 12 ]] || {
    msg_error "Debian $VERSION_ID is too old for current Proxmox VE (need 12 or newer)"
    exit 1
  }
}

function pve_repo_add() {
  local codename list
# shellcheck disable=SC1091
  codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
  if [[ "$REPO" == "enterprise" ]]; then
    list="deb http://download.proxmox.com/debian/pve $codename pve"
    msg "added the enterprise repo; Proxmox Enterprise credentials are"
    msg "required for apt (see the PVE docs, 'Installing with subscription')"
  else
    list="deb http://download.proxmox.com/debian/pve $codename pve-no-subscription"
  fi
  echo "$list" > /etc/apt/sources.list.d/proxmox.list
}

function microcode_install() {
  local vendor
  vendor="$(awk -F: '/vendor_id/ {print $2; exit}' /proc/cpuinfo | tr -d ' ')"
  case "$vendor" in
    AuthenticAMD) apt-get install -y amd64-microcode ;;
    GenuineIntel) apt-get install -y intel-microcode ;;
    *) msg "CPU vendor not recognised ($vendor); skipping microcode" ;;
  esac
}

function cmd_install() {
  SCRIPT_NAME="install"
  # Flags are parsed before the host checks so a typo is reported even on a
  # host the install would refuse anyway.
  local interactive=0
  [[ -t 0 ]] && interactive=1
  local advanced=0
  while (( $# )); do
    case "$1" in
      --advanced) advanced=1; shift ;;
      --enterprise) REPO="enterprise"; advanced=1; shift ;;
      --bridge) BRIDGE="${2:?--bridge needs a value}"; advanced=1; shift 2 ;;
      --ip) IP="${2:?--ip needs a value}"; advanced=1; shift 2 ;;
      --gateway) GATEWAY="${2:?--gateway needs a value}"; advanced=1; shift 2 ;;
      --dns) DNS="${2:?--dns needs a value}"; advanced=1; shift 2 ;;
      --help|-h) usage; return 0 ;;
      *) die_unknown "$1" ;;
    esac
  done
  load_env
  REPO="${REPO:-no-subscription}"
  check_root
  arch_check
  debian_check

  if (( advanced )); then
    msg "using advanced settings"
  else
    msg "using default settings"
  fi
  install_summary
  if (( interactive )); then
    read -r -p "Proceed? [y/N] " ans
    [[ "$ans" =~ ^[Yy] ]] || { msg "aborted"; exit 1; }
  fi

  msg "updating package lists"
  apt-get update
  msg "adding the $REPO repo"
  pve_repo_add
  msg "installing Proxmox VE (this takes a while)"
  apt-get install -y proxmox-ve
  microcode_install
  msg "loading the KVM module"
  modprobe kvm_intel 2>/dev/null || modprobe kvm_amd 2>/dev/null || \
    msg "KVM module not loaded yet; it comes up on the next boot"
  msg "done. Reboot to load the PVE kernel, then:"
  msg "  $SCRIPT_NAME create-vm"
}

# --- create-vm -------------------------------------------------------------------

function create_default_settings() {
  [[ -z "$DEVVM_VMID" ]] && DEVVM_VMID="$(get_valid_nextid)"
  VM_NAME="$DEVVM_NAME"
  MAC="$DEVVM_MAC"
  if [[ -z "$MAC" ]] && command -v openssl >/dev/null 2>&1; then
    MAC="02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')"
  fi
  [[ -z "$MAC" ]] && MAC="02:00:00:00:00:00"
  START_VM="${START_VM_OVERRIDE:-$DEVVM_START}"
  echo "VM ID:      $DEVVM_VMID"
  echo "Name:       $VM_NAME"
  echo "Machine:    $DEVVM_MACHINE (OVMF)"
  echo "CPU:        $DEVVM_CPU, $DEVVM_CORES cores"
  echo "Display:    $DEVVM_DISPLAY (VirtIO-GPU gives the guest a render node)"
  echo "RAM:        $DEVVM_RAM MiB"
  echo "Disk:       $DEVVM_DISK on storage '${PVE_STORAGE:-auto-detected}'"
  echo "Bridge:     $PVE_BRIDGE"
  echo "Address:    $(ip_mode_text)"
  echo "Cloud-init: user '$DEVVM_USER', key $DEVVM_SSH_KEY"
  echo "Start:      $START_VM"
}

function ip_mode_text() {
  if [[ "$DEVVM_IP_MODE" == "dhcp" ]]; then
    echo "DHCP"
  else
    echo "static: $DEVVM_STATIC_IP${DEVVM_GATEWAY:+ via $DEVVM_GATEWAY}"
  fi
}

# ipconfig_spec: the cloud-init line for the first NIC.
function ipconfig_spec() {
  if [[ "$DEVVM_IP_MODE" == "dhcp" ]]; then
    printf 'ip=dhcp'
  elif [[ "$DEVVM_IP_MODE" == "static" ]]; then
    [[ -n "$DEVVM_STATIC_IP" ]] || { msg_error "DEVVM_IP_MODE is static but no static IP is set"; exit 1; }
    local spec="ip=$DEVVM_STATIC_IP"
    # A /24 suffix means the gateway is the .1 of that subnet.
    if [[ "$DEVVM_STATIC_IP" == */24 && -z "$DEVVM_GATEWAY" ]]; then
      local base="${DEVVM_STATIC_IP%%/24}"
      spec+=" gw=${base%.*}.1"
    fi
    [[ -n "$DEVVM_GATEWAY" && "$DEVVM_STATIC_IP" != */* ]] && spec+=" gw=$DEVVM_GATEWAY"
    [[ -n "$DEVVM_DNS" ]] && spec+=" dns=$DEVVM_DNS"
    printf '%s' "$spec"
  else
    msg_error "DEVVM_IP_MODE must be dhcp or static, got: $DEVVM_IP_MODE"
    exit 1
  fi
}

function storage_pick() {
  local line
  mapfile -t STORAGES < <(pvesm status -content images 2>/dev/null | awk 'NR>1 {print $1}')
  ((${#STORAGES[@]})) || { msg_error "no storage pool can hold images (pvesm status -content images)"; exit 1; }
  if [[ -n "$PVE_STORAGE" ]]; then
    for line in "${STORAGES[@]}"; do
      [[ "$line" == "$PVE_STORAGE" ]] && return 0
    done
    msg_error "storage '$PVE_STORAGE' not found; available: ${STORAGES[*]}"
    exit 1
  fi
  if ((${#STORAGES[@]} == 1)); then
    PVE_STORAGE="${STORAGES[0]}"
    msg_ok "using storage $PVE_STORAGE"
    return 0
  fi
  local menu=() s
  for s in "${STORAGES[@]}"; do menu+=("$s" " $s" OFF); done
  msg "multiple image storages: ${STORAGES[*]}"
  if command -v whiptail >/dev/null 2>&1; then
    PVE_STORAGE="$(whiptail --backtitle "$BACKTITLE" --title "Storage" --radiolist \
      "Which storage pool for the disk?" 12 58 3 "${menu[@]}" 3>&1 1>&2 2>&3)" \
      || { msg_error "no storage chosen"; exit 1; }
  else
    read -r -p "Storage [${STORAGES[0]}]: " PVE_STORAGE
    [[ -n "$PVE_STORAGE" ]] || PVE_STORAGE="${STORAGES[0]}"
  fi
}

function arch_image() {
  # Latest Arch opencloud image, by the date in its file name. Progress
  # goes to stderr: the caller captures stdout and treats it as the path.
  local fname url
  msg_info "finding the latest Arch opencloud image" >&2
  fname="$(curl -fsSL https://archlinux.org/releng/cloud/ \
    | grep -o 'archlinux-x86_64-[0-9][0-9.]*-opencloud-qcow2-SSD\.img' | sort -V | tail -n1)"
  msg_ok >&2
  [[ -n "$fname" ]] || { msg_error "could not find an image at https://archlinux.org/releng/cloud/"; exit 1; }
  url="https://archlinux.org/releng/cloud/$fname"
  msg_info "downloading $fname" >&2
  curl -fSL --show-error -o "$TEMP_DIR/$fname" "$url"
  msg_ok >&2
  echo "$TEMP_DIR/$fname"
}

function create_vm() {
  # The machine that runs Hyprland under KVM: q35 + OVMF + host CPU +
  # VirtIO-GPU (a render node), the guest agent, cloud-init.
  local machine_args=() cpu_args=() net_args="virtio,bridge=$PVE_BRIDGE"
  [[ "$DEVVM_MACHINE" == "q35" ]] && machine_args+=(-machine q35)
  [[ "$DEVVM_CPU" == "host" ]] && cpu_args+=(-cpu host)
  [[ -n "$MAC" ]] && net_args+=",macaddr=$MAC"
  [[ -n "$DEVVM_VLAN" ]] && net_args+=",tag=$DEVVM_VLAN"
  [[ -n "$DEVVM_MTU" ]] && net_args+=",mtu=$DEVVM_MTU"

  local image disk_ref
  image="$(arch_image)"

  storage_pick
  local storage_type disk_ext="" disk_ref_prefix=""
  local -a import_fmt=()
  storage_type="$(pvesm status -storage "$PVE_STORAGE" | awk 'NR>1 {print $2}')"
  case "$storage_type" in
    nfs|dir|cifs) disk_ext=".qcow2"; disk_ref_prefix="$DEVVM_VMID/"; import_fmt=(--format qcow2) ;;
    btrfs) disk_ext=".raw"; disk_ref_prefix="$DEVVM_VMID/"; import_fmt=(--format raw) ;;
    *) import_fmt=(--format raw) ;;
  esac

  msg_info "creating VM $DEVVM_VMID"
  qm create "$DEVVM_VMID" -agent 1 "${machine_args[@]}" -tablet 0 -localtime 1 \
    -bios ovmf "${cpu_args[@]}" -cores "$DEVVM_CORES" -memory "$DEVVM_RAM" \
    -name "$VM_NAME" -net0 "$net_args" -onboot 1 -ostype l26 \
    -scsihw virtio-scsi-pci -vga "$DEVVM_DISPLAY"
  CREATED_VMID="$DEVVM_VMID"
  msg_ok

  local -a import_cmd=(qm disk import)
  qm disk import --help >/dev/null 2>&1 || import_cmd=(qm importdisk)
  local import_out disk_ref_imported
  import_out="$("${import_cmd[@]}" "$DEVVM_VMID" "$image" "$PVE_STORAGE" "${import_fmt[@]}" 2>&1 || true)"
  disk_ref_imported="$(printf '%s\n' "$import_out" | sed -n "s/.*successfully imported disk '\([^']\+\)'.*/\1/p" | tr -d "$(printf '\r"\047')")"
  [[ -z "$disk_ref_imported" ]] && \
    disk_ref_imported="$(pvesm list "$PVE_STORAGE" | awk -v id="$DEVVM_VMID" '$5 ~ ("vm-"id"-disk-") {print $1":"$5}' | sort | tail -n1)"
  [[ -n "$disk_ref_imported" ]] || {
    msg_error "could not determine the imported disk reference"
    echo "$import_out"
    exit 1
  }
  disk_ref="${disk_ref_prefix}${disk_ref_imported}${disk_ext:+,}$disk_ext"
  msg_ok "imported disk ($disk_ref)"

  qm set "$DEVVM_VMID" \
    -efidisk0 "$PVE_STORAGE:0,efitype=4m" \
    -scsi0 "$disk_ref" \
    -ide2 "$PVE_STORAGE:cloudinit" \
    -boot order=scsi0 \
    -serial0 socket >/dev/null
  if [[ "$DEVVM_IP_MODE" == "static" ]]; then
    qm set "$DEVVM_VMID" --ciuser "$DEVVM_USER" --sshkeys "$DEVVM_SSH_KEY.pub" \
      --ipconfig0 "$(ipconfig_spec)"
  else
    qm set "$DEVVM_VMID" --ciuser "$DEVVM_USER" --sshkeys "$DEVVM_SSH_KEY.pub" \
      --ipconfig0 ip=dhcp
  fi

  msg_ok "created VM $DEVVM_VMID ($VM_NAME)"
  if [[ "$START_VM" == "yes" ]]; then
    msg_info "starting VM $DEVVM_VMID"
    qm start "$DEVVM_VMID"
    msg_ok
  fi
  msg "address appears in: $SCRIPT_NAME status"
}

function cmd_create_vm() {
  SCRIPT_NAME="create-vm"
  check_root
  arch_check
  pve_check
  load_env

  local interactive=0
  [[ -t 0 ]] && interactive=1
  local advanced=0
  while (( $# )); do
    case "$1" in
      --advanced) advanced=1; shift ;;
      --vmid) DEVVM_VMID="${2:?--vmid needs a value}"; advanced=1; shift 2 ;;
      --name) DEVVM_NAME="${2:?--name needs a value}"; advanced=1; shift 2 ;;
      --machine) DEVVM_MACHINE="${2:?--machine needs a value}"; advanced=1; shift 2 ;;
      --cpu) DEVVM_CPU="${2:?--cpu needs a value}"; advanced=1; shift 2 ;;
      --cores) DEVVM_CORES="${2:?--cores needs a value}"; advanced=1; shift 2 ;;
      --ram) DEVVM_RAM="${2:?--ram needs a value}"; advanced=1; shift 2 ;;
      --disk) DEVVM_DISK="${2:?--disk needs a value}"; advanced=1; shift 2 ;;
      --display) DEVVM_DISPLAY="${2:?--display needs a value}"; advanced=1; shift 2 ;;
      --bridge) PVE_BRIDGE="${2:?--bridge needs a value}"; advanced=1; shift 2 ;;
      --storage) PVE_STORAGE="${2:?--storage needs a value}"; advanced=1; shift 2 ;;
      --mac) DEVVM_MAC="${2:?--mac needs a value}"; advanced=1; shift 2 ;;
      --vlan) DEVVM_VLAN="${2:?--vlan needs a value}"; advanced=1; shift 2 ;;
      --mtu) DEVVM_MTU="${2:?--mtu needs a value}"; advanced=1; shift 2 ;;
      --user) DEVVM_USER="${2:?--user needs a value}"; advanced=1; shift 2 ;;
      --ssh-key) DEVVM_SSH_KEY="${2:?--ssh-key needs a value}"; advanced=1; shift 2 ;;
      --ip) DEVVM_IP_MODE="static"; DEVVM_STATIC_IP="${2:?--ip needs a value}"; advanced=1; shift 2 ;;
      --gateway) DEVVM_GATEWAY="${2:?--gateway needs a value}"; advanced=1; shift 2 ;;
      --dns) DEVVM_DNS="${2:?--dns needs a value}"; advanced=1; shift 2 ;;
      --no-start) START_VM_OVERRIDE="no"; advanced=1; shift ;;
      --help|-h) usage; return 0 ;;
      *) die_unknown "$1" ;;
    esac
  done
  if (( advanced )); then
    msg "using advanced settings"
  fi
  create_default_settings
  if (( interactive )); then
    read -r -p "Proceed? [y/N] " ans
    [[ "$ans" =~ ^[Yy] ]] || { msg "aborted"; exit 1; }
  fi

  [[ -n "$DEVVM_VMID" ]] || { msg_error "no VM ID (set DEVVM_VMID in $ENV_FILE or pass --vmid)"; exit 1; }
  qm status "$DEVVM_VMID" &>/dev/null && {
    msg_error "VM $DEVVM_VMID already exists; use: $SCRIPT_NAME reset --vmid $DEVVM_VMID"
    exit 1
  }
  [[ -f "$DEVVM_SSH_KEY.pub" ]] || { msg_error "public key not found: $DEVVM_SSH_KEY.pub"; exit 1; }

  create_vm
}

function cmd_reset() {
  SCRIPT_NAME="reset"
  check_root
  arch_check
  pve_check
  load_env
  # reset is create-vm with the existing VM deleted first; the create path
  # re-parses the same flags, so they pass straight through.
  local vmid="$DEVVM_VMID"
  local -a passthrough=()
  while (( $# )); do
    case "$1" in
      --vmid) vmid="${2:?--vmid needs a value}"; passthrough+=("$1" "$2"); shift 2 ;;
      *) passthrough+=("$1"); shift ;;
    esac
  done
  if [[ -z "$vmid" ]]; then
    msg_error "no VM ID to reset (set DEVVM_VMID in $ENV_FILE or pass --vmid)"
    exit 1
  fi
  if qm status "$vmid" &>/dev/null; then
    msg_info "deleting VM $vmid"
    qm status "$vmid" | grep -q 'status: running' && qm stop "$vmid" || true
    qm destroy "$vmid"
    msg_ok
  fi
  cmd_create_vm --vmid "$vmid" "${passthrough[@]}"
}

function cmd_destroy() {
  SCRIPT_NAME="destroy"
  check_root
  pve_check
  load_env
  local vmid="$DEVVM_VMID"
  while (( $# )); do
    case "$1" in
      --vmid) vmid="${2:?--vmid needs a value}"; shift 2 ;;
      --help|-h) usage; return 0 ;;
      *) die_unknown "$1" ;;
    esac
  done
  [[ -n "$vmid" ]] || { msg_error "no VM ID (set DEVVM_VMID in $ENV_FILE or pass --vmid)"; exit 1; }
  if ! qm status "$vmid" &>/dev/null; then
    msg "VM $vmid does not exist; nothing to do"
    return 0
  fi
  qm status "$vmid" | grep -q 'status: running' && qm stop "$vmid" || true
  qm destroy "$vmid"
  msg_ok "deleted VM $vmid"
}

function cmd_status() {
  SCRIPT_NAME="status"
  check_root
  pve_check
  load_env
  local vmid="${DEVVM_VMID:-$(get_valid_nextid)}"
  local state
  state="$(qm status "$vmid" 2>/dev/null || true)"
  echo "VM $vmid: ${state:-absent}"
  if [[ "$state" == *"running"* ]]; then
    local ip
    ip="$(pvesh get "/nodes/$(hostname -s)/qemu/$vmid/status/current/ip" -getvalue 0 2>/dev/null || true)"
    echo "address: ${ip:-pending (guest agent not up yet)}"
  fi
}

function cmd_init() {
  if [[ -e "$ENV_FILE" ]]; then
    msg_error "$ENV_FILE already exists; edit it, or remove it to re-init"
    exit 1
  fi
  mkdir -p "$(dirname "$ENV_FILE")"
  cat > "$ENV_FILE" <<EOF
# aphotic dev VM on Proxmox VE -- fill in, then:
#   tools/devvm/proxmox.sh create-vm     (or: reset)
# Every value may stay blank; the built-in defaults then apply.

# --- the VM --------------------------------------------------------------------
# Blank VM ID: the next free ID on the host is used (pvesh /cluster/nextid).
DEVVM_VMID=
DEVVM_NAME=aphotic-devvm
# Machine type: q35 (runs Hyprland under KVM) or i440fx.
DEVVM_MACHINE=q35
# CPU: host (passthrough, fastest) or kvm64.
DEVVM_CPU=host
# Display: virtio (VirtIO-GPU, the guest gets a render node Hyprland draws
# through) or std (software fallback only).
DEVVM_DISPLAY=virtio
# RAM in MiB and cores -- the values the working Hyprland guest uses.
DEVVM_RAM=12288
DEVVM_CORES=6
# Disk in GiB or with a G suffix.
DEVVM_DISK=60G
# Storage pool for the disk; blank = the first pool that holds images.
PVE_STORAGE=
# Bridge the VM's VirtIO NIC attaches to (vmbr0 on a stock install).
PVE_BRIDGE=vmbr0

# --- the guest ---------------------------------------------------------------
# cloud-init user the desktop session runs as; a member of wheel, so the
# in-guest work can use passwordless sudo.
DEVVM_USER=aphotic
# Private key whose public half is seeded into the guest.
DEVVM_SSH_KEY=$HOME/.ssh/id_ed25519
# Addressing: dhcp, or static with DEVVM_STATIC_IP (a /24 suffix implies
# the .1 gateway; otherwise set DEVVM_GATEWAY).
DEVVM_IP_MODE=dhcp
DEVVM_STATIC_IP=
DEVVM_GATEWAY=
DEVVM_DNS=
# Blank MAC: a generated address is used.
DEVVM_MAC=
# VLAN tag (1-4094) and interface MTU (576-65520), both optional.
DEVVM_VLAN=
DEVVM_MTU=
# Start the VM once created: yes or no.
DEVVM_START=yes
EOF
  msg_ok "wrote $ENV_FILE; next: tools/devvm/proxmox.sh create-vm"
}

function die_unknown() {
  msg_error "unknown option: $1"
  usage
  exit 2
}

function usage() {
  cat <<'EOF'
Usage: tools/devvm/proxmox.sh <command> [options]

Commands:
  init        Write a commented example ~/.config/aphotic/devvm.env
  install     Install Proxmox VE on this bare Debian host
  create-vm   Create the dev VM from the latest Arch opencloud image
  reset       Delete the dev VM and create it again
  destroy     Stop and delete the dev VM
  status      Show the VM state and address

install options (advanced; the default path takes no options):
  --enterprise    use the Proxmox enterprise repo (credentials required)
  --bridge NAME   define bridge NAME for the first physical NIC
  --ip A.B.C.D/LEN  static address for that bridge
  --gateway IP    gateway for --ip
  --dns IP        nameserver for --ip

create-vm / reset / destroy options (advanced):
  --vmid ID       VM ID (default: from devvm.env or the next free ID)
  --name NAME     VM name
  --machine M     q35 (default) or i440fx
  --cpu C         host (default) or kvm64
  --cores N       CPU cores
  --ram N         RAM in MiB
  --disk SIZE     disk size (e.g. 60G)
  --display D     virtio (default, VirtIO-GPU) or std
  --bridge NAME   bridge for the VM NIC
  --storage S     storage pool for the disk
  --mac MAC       fixed MAC address
  --vlan N        VLAN tag on the NIC
  --mtu N         interface MTU
  --user USER     cloud-init user
  --ssh-key PATH  private key seeded into the guest
  --ip A.B.C.D/LEN  static address (switches the NIC to static)
  --gateway IP    gateway for --ip
  --dns IP        nameserver
  --no-start      do not start the VM when created

Settings come from ~/.config/aphotic/devvm.env (DEVVM_ENV overrides the
path); `init` writes a commented example.
EOF
}

# --- dispatch --------------------------------------------------------------------

SCRIPT_NAME=""
function main() {
  local cmd="${1:-}"
  [[ -n "$cmd" ]] || { usage; exit 2; }
  shift
  case "$cmd" in
    init) cmd_init "$@" ;;
    install) cmd_install "$@" ;;
    create-vm) cmd_create_vm "$@" ;;
    reset) cmd_reset "$@" ;;
    destroy) cmd_destroy "$@" ;;
    status) cmd_status "$@" ;;
    help|--help|-h) usage ;;
    *) usage; exit 2 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
