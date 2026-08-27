#!/usr/bin/env bash
set -euo pipefail

prompt_profile() {
  local answer
  read -rp "Profile? [minimal/full] (full): " answer
  answer="${answer:-full}"
  if [[ "$answer" != "minimal" && "$answer" != "full" ]]; then
    echo "full"
  else
    echo "$answer"
  fi
}

prompt_layers() {
  local layers=()
  local answer

  read -rp "Enable gaming layer? [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]] && layers+=("gaming")

  read -rp "Enable dev layer? [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]] && layers+=("dev")

  read -rp "Enable ai layer? [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]] && layers+=("ai")

  read -rp "Enable exploit/offensive-security tooling? Adds the BlackArch repo for most sublayers -- less stable than Arch's official repos, see docs/exploit-layer.md [y/N]: " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    read -rp "  Use the default bundle (recon + web + network)? [Y/n]: " answer
    if [[ ! "$answer" =~ ^[Nn]$ ]]; then
      layers+=("exploit")
    else
      read -rp "  Enable exploit-recon (nmap, amass, subfinder, theHarvester, recon-ng)? [y/N]: " answer
      [[ "$answer" =~ ^[Yy]$ ]] && layers+=("exploit-recon")

      read -rp "  Enable exploit-web (Burp Suite CE, sqlmap, ffuf, gobuster, nikto, ZAP)? [y/N]: " answer
      [[ "$answer" =~ ^[Yy]$ ]] && layers+=("exploit-web")

      read -rp "  Enable exploit-network (Wireshark, aircrack-ng, bettercap, tcpdump)? [y/N]: " answer
      [[ "$answer" =~ ^[Yy]$ ]] && layers+=("exploit-network")
    fi

    read -rp "  Enable exploit-passwords (John the Ripper, hashcat, Hydra)? [y/N]: " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      layers+=("exploit-passwords")
      read -rp "    Also fetch the rockyou wordlist? ~130MB decompressed, from the OWASP SecLists project -- always separate, never bundled automatically [y/N]: " answer
      [[ "$answer" =~ ^[Yy]$ ]] && layers+=("exploit-wordlists")
    fi

    read -rp "  Enable exploit-reversing (Ghidra, radare2, Cutter, gdb+pwndbg, binwalk)? [y/N]: " answer
    [[ "$answer" =~ ^[Yy]$ ]] && layers+=("exploit-reversing")

    read -rp "  Enable exploit-forensics (Autopsy, Sleuth Kit, Volatility 3)? [y/N]: " answer
    [[ "$answer" =~ ^[Yy]$ ]] && layers+=("exploit-forensics")

    read -rp "  Enable exploit-reporting (engagement report scaffolding, aphotic report CLI)? [y/N]: " answer
    [[ "$answer" =~ ^[Yy]$ ]] && layers+=("exploit-reporting")
  fi

  local IFS=","
  echo "${layers[*]}"
}

prompt_theme() {
  local answer
  read -rp "Theme? (default): " answer
  echo "${answer:-default}"
}

write_aphotic_toml() {
  local path="$1" profile="$2" layers="$3" theme="$4" nvidia="$5" aur_helper="$6" installed_at="$7"

  local layers_toml="[]"
  if [[ -n "$layers" ]]; then
    layers_toml="[$(echo "$layers" | sed -E 's/([^,]+)/"\1"/g; s/,/, /g')]"
  fi

  cat > "$path" <<EOF
[install]
profile = "$profile"
layers = $layers_toml
installed_at = "$installed_at"

[theme]
name = "$theme"

[system]
nvidia = $nvidia
aur_helper = "$aur_helper"
EOF
}
