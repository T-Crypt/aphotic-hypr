#!/usr/bin/env bash
# noctis iso — build a live/installer image (archiso-based).
# @cmd: iso
# @cmd.desc: Build a Noctis live or installer ISO
# @cmd.group: BUILD
# @cmd.opt: build --live       | Build a bootable live ISO
# @cmd.opt: build --installer  | Build an installer ISO

NOCTIS_ISO_PROFILE_DIR="${NOCTIS_DOTS_DIR}/iso/profile"
NOCTIS_ISO_OUT_DIR="${NOCTIS_DOTS_DIR}/iso/out"

noctis_cmd_iso() {
    local sub="${1:-}"; shift || true
    case "$sub" in
        build)
            local mode="live"
            for arg in "$@"; do
                case "$arg" in
                    --live) mode="live" ;;
                    --installer) mode="installer" ;;
                esac
            done

            noctis_require mkarchiso || {
                noctis_err "mkarchiso not found — install archiso (pacman -S archiso)"
                return 1
            }
            [[ -d "$NOCTIS_ISO_PROFILE_DIR" ]] || {
                noctis_err "no archiso profile at ${NOCTIS_ISO_PROFILE_DIR}"
                noctis_log "TODO: scaffold releng-based profile here (packages.x86_64, airootfs/, profiledef.sh)"
                return 1
            }

            mkdir -p "$NOCTIS_ISO_OUT_DIR"
            noctis_log "building ${mode} ISO from ${NOCTIS_ISO_PROFILE_DIR}..."
            sudo mkarchiso -v -w /tmp/noctis-iso-work -o "$NOCTIS_ISO_OUT_DIR" "$NOCTIS_ISO_PROFILE_DIR"
            noctis_ok "ISO written to ${NOCTIS_ISO_OUT_DIR}"
            noctis_log "next: boot it in a fresh Proxmox VM before calling this a release"
            ;;
        ""|-h|--help)
            cat <<HELP
Usage: noctis iso build [--live|--installer]

  build --live        Build a bootable live ISO (default)
  build --installer   Build an installer ISO

Profile expected at: ${NOCTIS_ISO_PROFILE_DIR}
Output written to:   ${NOCTIS_ISO_OUT_DIR}
HELP
            ;;
        *)
            noctis_err "unknown iso subcommand: ${sub}"
            return 1
            ;;
    esac
}
