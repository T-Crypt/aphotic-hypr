#!/usr/bin/env bash
# lib/install/gpu_compute.sh
set -euo pipefail

# Which vendor's compute stack this machine wants. NVIDIA wins a tie
# because that is the card the discrete-GPU path already set up (an AMD
# APU alongside an NVIDIA card is the common laptop shape, and the NVIDIA
# part is the one worth feeding a model to).
gpu_vendor() {
  if [[ "${DETECTED_NVIDIA_PRESENT:-false}" == "true" ]]; then
    echo "nvidia"
  elif [[ "${DETECTED_AMD_PRESENT:-false}" == "true" ]]; then
    echo "amd"
  else
    echo ""
  fi
}

# Ollama on Arch is three packages, not one: `ollama` is the CPU-only
# base, and `ollama-cuda` / `ollama-rocm` are separate runners that depend
# on it. The ai layer named only `ollama`, so every install ran local
# models on the CPU -- including NVIDIA ones, where the Assistant would
# pull several GB of weights and then answer at CPU speed. Neither runner
# replaces the base package; both add to it.
resolve_ollama_accel_package() {
  case "$(gpu_vendor)" in
    nvidia) echo "ollama-cuda" ;;
    amd) echo "ollama-rocm" ;;
    *) echo "" ;;
  esac
}

# Installed after the main package list, because it depends on `ollama`
# already being there from the ai layer. Kept out of profiles/layers/ai.toml
# on purpose: that file is static and identical on every machine, and the
# right runner is a per-machine answer. Optional rather than required --
# ollama-rocm is roughly 3GB and ollama-cuda roughly 1GB, and a machine
# that cannot fetch either still has a working CPU Ollama rather than a
# failed install.
setup_gpu_compute() {
  [[ ",$LAYERS," == *",ai,"* ]] || return 0

  local pkg
  pkg="$(resolve_ollama_accel_package)"
  if [[ -z "$pkg" ]]; then
    echo -e "$CNT - No NVIDIA or AMD GPU detected; Ollama will run models on the CPU."
    return 0
  fi

  echo -e "$CNT - Installing $pkg so Ollama runs models on the GPU rather than the CPU..."
  install_software "$pkg" optional
}
