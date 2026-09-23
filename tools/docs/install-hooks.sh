#!/usr/bin/env bash
set -euo pipefail

root=$(git rev-parse --show-toplevel)
git -C "$root" config core.hooksPath .githooks
printf 'Git hooks now run from .githooks.\n'
