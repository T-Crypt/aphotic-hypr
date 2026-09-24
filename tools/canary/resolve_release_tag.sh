#!/usr/bin/env bash
set -euo pipefail

repo="${1:-.}"
tag="$(git -C "$repo" tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | sed -n '1p')"
run=false

if [[ -n "$tag" ]] \
  && [[ "$(git -C "$repo" rev-parse "${tag}^{commit}")" != "$(git -C "$repo" rev-parse HEAD)" ]]; then
  run=true
fi

printf 'tag=%s\nrun=%s\n' "$tag" "$run"
