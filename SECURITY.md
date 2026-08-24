# Security Policy

## Reporting a vulnerability

Please report security issues privately rather than opening a public
issue — use GitHub's
[private vulnerability reporting](https://github.com/T-Crypt/aphotic-hypr/security/advisories/new)
for this repo, or contact [@T-Crypt](https://github.com/T-Crypt) directly.

Include what you found, how to reproduce it, and its impact if you can.
This is a project maintained in spare time, not a funded security
program — there's no bounty, but real reports will get a real response
and a fix.

## Scope

Relevant to this project specifically:

- **Installer / `install.sh`, `uninstall.sh`** — runs with `sudo` for
  package installs and a handful of system-file writes (SDDM theme,
  `/usr/share/icons` for folder-color accents). Privilege-escalation bugs
  here, or anywhere `aphotic` shells out with elevated privileges, are in
  scope.
- **API keys** (`~/.config/aphotic/ai-keys.json`, `chmod 600`) — if you
  find a path where these leak (logs, world-readable temp files, process
  argv visible to other users, etc.), that's a real finding.
- **The `exploit-layer` install profile** (`docs/exploit-layer.md`) is
  intentionally offensive-security tooling (BlackArch packages, VPN
  access for HTB/THM-style work) for a user who opts into that layer.
  That's expected behavior, not a vulnerability in itself — but bugs in
  *how* it's installed or gated (e.g. it installing without being
  explicitly requested) are in scope.

## Out of scope

- Vulnerabilities in third-party packages this project installs
  (Hyprland, Quickshell, wallust, etc.) — report those upstream.
- Anything requiring physical access to an already-unlocked machine.
