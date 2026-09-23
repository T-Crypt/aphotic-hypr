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

# Every installed NVIDIA kernel driver, whatever its package is called.
# Matching names missed legacy branches (nvidia-580xx-dkms), beta drivers
# and distro kernel-module packages, so the keep/replace prompt never
# showed and nvidia-open-dkms then failed on the NVIDIA-MODULE conflict.
# Every one of them provides NVIDIA-MODULE.
nvidia_driver_packages() {
  LC_ALL=C pacman -Qi 2>/dev/null | awk '/^Name/ { name = $3 } /^Provides/ && /[[:space:]]NVIDIA-MODULE([[:space:]]|$)/ { print name }'
}

detect_nvidia_driver_installed() {
  [[ -n "$(nvidia_driver_packages)" ]]
}

# The open kernel modules, the only NVIDIA driver in Arch's repos, need a
# Turing or newer GPU. lspci names the die: Kepler (GK), Maxwell (GM),
# Pascal (GP), Volta (GV) and older (GF, GT, G) parts cannot run them.
# A card lspci cannot name counts as modern.
nvidia_needs_legacy_driver() {
  lspci | grep -E "(VGA|3D)" | grep -i nvidia | grep -qE '\b(G[KMPVF]|GT|G)[0-9]{2,3}[A-Z]*\b'
}

# Installs the actual Nvidia kernel driver (+ matching kernel headers) via
# DKMS. The keep-vs-reinstall decision itself is made once, up front, by
# detect.sh's detect_environment() (surfaced alongside every other
# already-on-this-machine finding rather than sprung on the user mid
# package-install) -- $NVIDIA_DRIVER_ACTION arrives here already resolved,
# this function only acts on it.
install_nvidia_driver() {
  # Checked before the keep/replace branch: replacing a working legacy
  # driver with one this GPU cannot run would leave no driver at all.
  if nvidia_needs_legacy_driver; then
    if [[ -n "$DETECTED_NVIDIA_DRIVER" ]]; then
      echo -e "$CNT - This NVIDIA GPU predates Turing; keeping its driver (${DETECTED_NVIDIA_DRIVER})."
    else
      echo -e "$CWR - This NVIDIA GPU predates Turing, and Arch's nvidia-open-dkms cannot drive it. Aphotic will not install an NVIDIA driver."
      echo -e "$CWR   Maxwell and Pascal cards use the 580xx branch: yay -S nvidia-580xx-dkms nvidia-580xx-utils"
      echo -e "$CWR   Older cards need the 470xx or 390xx branch. Reboot after installing it."
    fi
    return 0
  fi

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
    # pacman, not "$AUR_HELPER": removal never needs an AUR helper, and an
    # empty one (failed yay bootstrap) would run as the empty command and
    # report a driver that "wouldn't uninstall cleanly" when nothing tried.
    # shellcheck disable=SC2086
    sudo pacman -R --noconfirm $(echo "$DETECTED_NVIDIA_DRIVER" | tr ',' ' ') &>> "$INSTLOG" || {
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
  # mkinitcpio fails the whole image build on a MODULES entry it cannot
  # find, so the wiring waits until a driver module is really installed.
  if ! detect_nvidia_driver_installed; then
    echo -e "$CWR - No NVIDIA driver module is installed, so the initramfs is left as it is."
    return 0
  fi
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
