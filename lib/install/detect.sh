#!/usr/bin/env bash
# lib/install/detect.sh
set -euo pipefail

# One consolidated pass over what's already on this machine, run once at
# the very start of a real install (before any prompt) so later stages can
# skip, warn, or offer reinstall with full information instead of the
# scattered mid-run checks this replaces (the NVIDIA keep/reinstall
# question used to fire deep into the packages stage, BlackArch/AUR-helper
# detection happened lazily wherever those repos were first needed, etc).
# Populates the DETECTED_* globals below for every later stage to read.

DETECTED_VM=0
DETECTED_APHOTIC_INSTALL=0
DETECTED_APHOTIC_PROFILE=""
DETECTED_APHOTIC_LAYERS=""
DETECTED_DOTFILE_MANAGER=""
DETECTED_NVIDIA_PRESENT="false"
DETECTED_NVIDIA_DRIVER=""
DETECTED_AUR_HELPER=""
DETECTED_BLACKARCH_REPO=0
DETECTED_MULTILIB_REPO=0

# A handful of cheap, well-known markers -- not exhaustive dotfile-manager
# detection, just enough to warn a user who's already managing ~/.config
# some other way before install.sh starts copying/symlinking into it.
detect_dotfile_manager() {
  if [[ -d "$HOME/.local/share/chezmoi" ]]; then
    echo "chezmoi"
  elif [[ -f "$HOME/.stow-local-ignore" ]] || { command -v stow >/dev/null 2>&1 && [[ -d "$HOME/dotfiles" ]]; }; then
    echo "GNU Stow"
  else
    echo ""
  fi
}

detect_environment() {
  echo -e "$CNT - Checking what's already on this machine..."

  local vm_chassis
  vm_chassis=$(hostnamectl | grep Chassis || true)
  if [[ "$vm_chassis" == *"vm"* ]]; then
    DETECTED_VM=1
    echo -e "  $CWR running in a VM ($vm_chassis) -- not fully supported, there's a high chance this fails."
  fi

  if [[ -f "$APHOTIC_TOML" ]]; then
    DETECTED_APHOTIC_INSTALL=1
    DETECTED_APHOTIC_PROFILE=$("$PYTHON_BIN" -c '
import sys, tomllib
try:
    print(tomllib.load(open(sys.argv[1], "rb")).get("install", {}).get("profile", ""))
except Exception:
    print("")
' "$APHOTIC_TOML" 2>/dev/null)
    DETECTED_APHOTIC_LAYERS=$("$PYTHON_BIN" -c '
import sys, tomllib
try:
    print(",".join(tomllib.load(open(sys.argv[1], "rb")).get("install", {}).get("layers", [])))
except Exception:
    print("")
' "$APHOTIC_TOML" 2>/dev/null)
    echo -e "  $COK existing Aphotic install found (profile=${DETECTED_APHOTIC_PROFILE:-unknown}, layers=${DETECTED_APHOTIC_LAYERS:-none})"
  fi

  DETECTED_DOTFILE_MANAGER=$(detect_dotfile_manager)
  if [[ -n "$DETECTED_DOTFILE_MANAGER" ]]; then
    echo -e "  $CWR $DETECTED_DOTFILE_MANAGER detected managing your dotfiles -- install.sh copies/symlinks straight into ~/.config and may conflict with it. Back up first if you're unsure."
  fi

  # --config-only never installs packages or touches drivers/repos -- the
  # rest of this pass (NVIDIA, AUR helper, BlackArch/multilib) is
  # meaningless noise for it, same reasoning as load_saved_config() never
  # prompting in that mode.
  if [[ "$CONFIG_ONLY" == "1" ]]; then
    return 0
  fi

  if [[ "$(detect_nvidia)" == "true" ]]; then
    DETECTED_NVIDIA_PRESENT="true"
    if detect_nvidia_driver_installed; then
      DETECTED_NVIDIA_DRIVER="$(pacman -Qq 2>/dev/null | grep -E '^nvidia(-open)?(-lts|-dkms)?$' | paste -sd, -)"
      echo -e "  $COK NVIDIA GPU detected, driver already installed: $DETECTED_NVIDIA_DRIVER"
    else
      echo -e "  $CNT NVIDIA GPU detected, no driver installed yet"
    fi
  fi

  DETECTED_AUR_HELPER="$(detect_aur_helper)"
  if [[ -n "$DETECTED_AUR_HELPER" ]]; then
    echo -e "  $COK AUR helper found: $DETECTED_AUR_HELPER"
  else
    echo -e "  $CNT no AUR helper found -- yay will be built and installed"
  fi

  blackarch_repo_present && { DETECTED_BLACKARCH_REPO=1; echo -e "  $COK BlackArch repo already enabled"; }
  multilib_repo_present && { DETECTED_MULTILIB_REPO=1; echo -e "  $COK multilib repo already enabled"; }

  # The one decision asked during detection itself rather than just
  # surfaced: it doesn't depend on anything resolved later (AUR_HELPER
  # isn't needed until nvidia.sh acts on the answer), so asking it here
  # means the user sees this alongside every other "what's on this
  # machine" finding, instead of hitting it lost mid-package-install --
  # which is where line 241 of the old monolithic install.sh used to ask it.
  if [[ -n "$DETECTED_NVIDIA_DRIVER" && -z "$NVIDIA_DRIVER_ACTION" && "$DRY_RUN" != "1" ]]; then
    if [[ -t 0 ]]; then
      echo -e "$CAT - An NVIDIA driver is already installed (${DETECTED_NVIDIA_DRIVER})."
      if confirm "Uninstall it and let Aphotic install its recommended nvidia-open-dkms instead of keeping it?" n; then
        NVIDIA_DRIVER_ACTION="reinstall"
      else
        NVIDIA_DRIVER_ACTION="keep"
      fi
    else
      # No TTY and no --nvidia-driver flag -- "should not fail for users"
      # means the safe default is to never touch a driver the user
      # already has working, not to guess.
      echo -e "  $CWR non-interactive install with an existing NVIDIA driver and no --nvidia-driver flag -- defaulting to 'keep' (Aphotic will not touch it). Pass --nvidia-driver reinstall to opt into replacing it instead."
      NVIDIA_DRIVER_ACTION="keep"
    fi
  fi
}
