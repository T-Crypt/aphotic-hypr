#!/usr/bin/env bash
# lib/install/nvidia.sh
set -euo pipefail

detect_nvidia() {
  if lspci -k | grep -A 2 -E "(VGA|3D)" | grep -iq nvidia; then
    echo "true"
  else
    echo "false"
  fi
}

# Real, reported bug this guards against: a user with an already-working
# proprietary driver (nvidia/nvidia-dkms) ran install.sh and it blindly
# tried to install nvidia-open-dkms on top, with zero check for what was
# already there -- nvidia/nvidia-open (and their -dkms/-lts variants)
# provide overlapping files, so pacman/the AUR helper either refuses on
# a conflict or silently replaces a driver the user deliberately chose
# and had working. Covers every real variant: proprietary (nvidia,
# nvidia-lts, nvidia-dkms) and open (nvidia-open, nvidia-open-lts,
# nvidia-open-dkms).
detect_nvidia_driver_installed() {
  pacman -Qq 2>/dev/null | grep -qE '^nvidia(-open)?(-lts|-dkms)?$'
}

# Installs the actual Nvidia kernel driver (+ matching kernel headers) via
# DKMS. The keep-vs-reinstall decision itself is made once, up front, by
# detect.sh's detect_environment() (surfaced alongside every other
# already-on-this-machine finding rather than sprung on the user mid
# package-install) -- $NVIDIA_DRIVER_ACTION arrives here already resolved,
# this function only acts on it.
install_nvidia_driver() {
  if [[ -n "$DETECTED_NVIDIA_DRIVER" ]]; then
    if [[ "$NVIDIA_DRIVER_ACTION" == "keep" ]]; then
      echo -e "$CNT - Keeping existing NVIDIA driver (${DETECTED_NVIDIA_DRIVER}) -- skipping Aphotic's own driver install."
      # nvidia-utils (nvidia-smi) is a separate userspace package, not a
      # driver -- doesn't conflict with proprietary or open, and the
      # Dashboard's Performance tab needs it regardless of which driver
      # variant the user is keeping, so still make sure it's present.
      if ! pacman -Qq nvidia-utils &>/dev/null; then
        install_software nvidia-utils
      fi
      return 0
    fi

    echo -e "$CNT - Uninstalling existing NVIDIA driver (${DETECTED_NVIDIA_DRIVER}) before installing Aphotic's recommended nvidia-open-dkms..."
    # shellcheck disable=SC2086
    "$AUR_HELPER" -R --noconfirm $(echo "$DETECTED_NVIDIA_DRIVER" | tr ',' ' ') &>> "$INSTLOG" || {
      echo -e "$CER - Failed to remove the existing driver (${DETECTED_NVIDIA_DRIVER}) -- see ${INSTLOG}. Not proceeding with a fresh install on top of a driver that wouldn't uninstall cleanly."
      return 1
    }
  fi

  echo -e "$CNT - Installing Nvidia driver..."
  local kernel_pkgs
  kernel_pkgs=$(pacman -Qq | grep -E '^linux(-lts|-zen|-hardened)?$' || true)
  if [[ -z "$kernel_pkgs" ]]; then
    echo -e "$CWR - Could not detect a linux/linux-lts/linux-zen/linux-hardened package; installing linux-headers as a best-effort fallback."
    kernel_pkgs="linux"
  fi
  while IFS= read -r kpkg; do
    [[ -n "$kpkg" ]] && install_software "${kpkg}-headers"
  done <<< "$kernel_pkgs"
  install_software nvidia-open-dkms
  # nvidia-utils provides nvidia-smi -- without it the Dashboard's
  # Performance tab has no way to read live NVIDIA GPU usage/temp and
  # silently shows "N/A" forever, since the driver package alone doesn't
  # carry the userspace query tools.
  install_software nvidia-utils
}

# Wires the driver into the initramfs/UKI -- MODULES=() in mkinitcpio.conf
# and options nvidia-drm modeset=1 in modprobe.d, then rebuilds. Kept
# separate from install_nvidia_driver() itself: this step still applies
# even on the "keep existing driver" path (a driver that predates Aphotic
# may never have had these set), not just on a fresh install.
configure_nvidia_modules() {
  echo -e "$CNT - Configuring Nvidia modules..."
  sudo sed -i 's/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
  if ! sudo grep -qF "options nvidia-drm modeset=1" /etc/modprobe.d/nvidia.conf 2>/dev/null; then
    echo -e "options nvidia-drm modeset=1" | sudo tee -a /etc/modprobe.d/nvidia.conf &>> "$INSTLOG"
  fi
  # -P (process every preset's configured targets) instead of a
  # hand-picked /boot/initramfs-custom.img: on a UKI setup (systemd-boot
  # with default_uki=.../arch-linux.efi and no default_image, which is
  # what a stock Arch systemd-boot install gives you) a custom image path
  # is never referenced by any boot entry, so the actual bootable
  # image/UKI never picks up the Nvidia modules regardless of whether the
  # driver package installed correctly.
  echo -e "$CNT - Regenerating initramfs/UKI..."
  sudo mkinitcpio -P &>> "$INSTLOG" || echo -e "$CWR - mkinitcpio failed to rebuild the initramfs/UKI; check $INSTLOG, then run 'sudo mkinitcpio -P' manually before rebooting."
}

# Full GPU stage entry point: driver (or keep-existing) + module wiring.
# No-op if no NVIDIA GPU was detected.
setup_nvidia() {
  [[ "$DETECTED_NVIDIA_PRESENT" == "true" ]] || return 0
  install_nvidia_driver
  configure_nvidia_modules
}
