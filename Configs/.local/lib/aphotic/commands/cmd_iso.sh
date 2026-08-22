#!/usr/bin/env bash
# aphotic iso — build a live/installer image (archiso-based).
# @cmd: iso
# @cmd.desc: Build a Aphotic live or installer ISO
# @cmd.group: BUILD
# @cmd.opt: build --live       | Build a bootable live ISO
# @cmd.opt: build --installer  | Build an installer ISO

APHOTIC_ISO_PROFILE_DIR="${APHOTIC_DOTS_DIR}/iso/profile"
APHOTIC_ISO_OUT_DIR="${APHOTIC_DOTS_DIR}/iso/out"

aphotic_cmd_iso() {
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

            aphotic_require mkarchiso || {
                aphotic_err "mkarchiso not found — install archiso (pacman -S archiso)"
                return 1
            }
            [[ -d "$APHOTIC_ISO_PROFILE_DIR" ]] || {
                aphotic_err "no archiso profile at ${APHOTIC_ISO_PROFILE_DIR}"
                aphotic_log "TODO: scaffold releng-based profile here (packages.x86_64, airootfs/, profiledef.sh)"
                return 1
            }

            mkdir -p "$APHOTIC_ISO_OUT_DIR"
            aphotic_log "building ${mode} ISO from ${APHOTIC_ISO_PROFILE_DIR}..."
            sudo mkarchiso -v -w /tmp/aphotic-iso-work -o "$APHOTIC_ISO_OUT_DIR" "$APHOTIC_ISO_PROFILE_DIR"
            aphotic_ok "ISO written to ${APHOTIC_ISO_OUT_DIR}"
            aphotic_log "next: boot it in a fresh Proxmox VM before calling this a release"
            ;;
        ""|-h|--help)
            cat <<HELP
Usage: aphotic iso build [--live|--installer]

  build --live        Build a bootable live ISO (default)
  build --installer   Build an installer ISO

Profile expected at: ${APHOTIC_ISO_PROFILE_DIR}
Output written to:   ${APHOTIC_ISO_OUT_DIR}
HELP
            ;;
        *)
            aphotic_err "unknown iso subcommand: ${sub}"
            return 1
            ;;
    esac
}
