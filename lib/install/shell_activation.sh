#!/usr/bin/env bash
# lib/install/shell_activation.sh
set -euo pipefail

# ACTIVATE_STARSHIP / ACTIVATE_ZSH are "" (nobody has decided -- ask), "1"
# or "0". The guided flow answers both in its one batched add-ons step, so
# these no longer interrupt it near the end of a run; a flag-driven
# install leaves them unset and still gets asked here, exactly as before.
activate_starship() {
  if [[ -n "${ACTIVATE_STARSHIP:-}" ]]; then
    [[ "$ACTIVATE_STARSHIP" == "1" ]] || return 0
  else
    echo -e "\n$CNT - The starship prompt shows the folder you are in, the git branch and similar in"
    echo -e "$CNT   your terminal, in place of the plain bash prompt. It adds one line to ~/.bashrc."
    confirm "Use the starship prompt?" n || return 0
  fi
  echo -e "$CNT - Setting up the starship prompt..."
  if ! grep -qF 'starship init bash' "$HOME/.bashrc" 2>/dev/null; then
    echo -e '\neval "$(starship init bash)"' >> "$HOME/.bashrc"
  fi
  cp "$ROOT_DIR/src/starship.toml" "$HOME/.config/"
}

activate_zsh() {
  if [[ -n "${ACTIVATE_ZSH:-}" ]]; then
    [[ "$ACTIVATE_ZSH" == "1" ]] || return 0
  else
    echo -e "\n$CNT - This copies Aphotic's zsh setup into your home folder and changes your login"
    echo -e "$CNT   shell from bash to zsh (with 'chsh'), which takes effect next time you log in."
    confirm "Switch your shell to zsh?" n || return 0
  fi
  echo -e "$CNT - Setting up zsh..."
  cp "$ROOT_DIR/Configs/.p10k.zsh" "$HOME"
  cp "$ROOT_DIR/Configs/.zshrc" "$HOME"
  chsh -s "$(which zsh)"
}
