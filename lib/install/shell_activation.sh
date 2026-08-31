#!/usr/bin/env bash
# lib/install/shell_activation.sh
set -euo pipefail

activate_starship() {
  confirm "Would you like to activate the starship shell?" n || return 0
  echo -e "$CNT - Activating starship..."
  if ! grep -qF 'starship init bash' "$HOME/.bashrc" 2>/dev/null; then
    echo -e '\neval "$(starship init bash)"' >> "$HOME/.bashrc"
  fi
  cp "$ROOT_DIR/src/starship.toml" "$HOME/.config/"
}

activate_zsh() {
  confirm "Would you like to activate zsh shell?" n || return 0
  echo -e "$CNT - Activating zsh..."
  cp "$ROOT_DIR/Configs/.p10k.zsh" "$HOME"
  cp "$ROOT_DIR/Configs/.zshrc" "$HOME"
  chsh -s "$(which zsh)"
}
