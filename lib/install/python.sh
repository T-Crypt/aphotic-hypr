#!/usr/bin/env bash
# lib/install/python.sh
set -euo pipefail

resolve_python_bin() {
  if command -v python3 >/dev/null 2>&1; then
    echo "python3"
  elif command -v python >/dev/null 2>&1; then
    echo "python"
  else
    echo "Python not found; required for profile/manifest resolution." >&2
    exit 1
  fi
}
