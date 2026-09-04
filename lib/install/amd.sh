#!/usr/bin/env bash
# lib/install/amd.sh
set -euo pipefail

# Mirrors detect_nvidia in nvidia.sh, but matches on markers that only ever
# appear for a GPU: lspci prints AMD cards as "[AMD/ATI]" and the kernel
# driver line says amdgpu (or radeon on pre-GCN parts). Matching the plain
# vendor string "Advanced Micro Devices" instead would read a machine with
# an AMD CPU and an Intel or NVIDIA GPU as AMD, since that string shows up
# on host bridges and audio devices too. An APU's integrated Radeon is a
# real match and wants the same userspace stack a discrete card does.
detect_amd() {
  if lspci -k 2>/dev/null | grep -A 3 -E "(VGA|3D)" | grep -iqE '\[amd/ati\]|amdgpu|kernel driver in use: radeon'; then
    echo "true"
  else
    echo "false"
  fi
}

# AMD needs no out-of-tree kernel driver -- amdgpu is in the mainline
# kernel, which is the whole reason this has no equivalent of nvidia.sh's
# driver install, initramfs regeneration or reboot. What is missing on a
# stock install is userspace: hyprland depends on mesa (and through it
# opengl-driver), but nothing in the package list depends on a Vulkan
# driver, and RADV ships separately as vulkan-radeon. So an AMD machine
# got OpenGL and no Vulkan at all. The gaming layer masked this by
# accident -- steam depends on vulkan-radeon itself -- which is why it
# only showed up on installs without that layer.
setup_amd() {
  [[ "$DETECTED_AMD_PRESENT" == "true" ]] || return 0

  echo -e "$CNT - Installing AMD graphics userspace (Mesa + RADV Vulkan)..."
  install_software mesa optional
  install_software vulkan-radeon optional
  install_software vulkan-icd-loader optional

  # 32-bit Vulkan is only meaningful once multilib is on, which is the
  # gaming layer's own trigger -- installing it otherwise would enable a
  # repo the user did not ask for. Steam pulls lib32-vulkan-radeon on its
  # own, but only after it is installed; naming it here means a 32-bit
  # title works on first launch rather than after the next install run.
  if [[ "$(any_layer_requires_multilib "$LAYERS")" == "true" ]]; then
    echo -e "$CNT - Adding 32-bit AMD Vulkan for the gaming layer..."
    install_software lib32-mesa optional
    install_software lib32-vulkan-radeon optional
  fi
}
