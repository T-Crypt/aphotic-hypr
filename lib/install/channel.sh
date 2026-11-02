#!/usr/bin/env bash
# lib/install/channel.sh
set -euo pipefail

aphotic_channel_file() {
  printf '%s/aphotic/channel' "${XDG_STATE_HOME:-$HOME/.local/state}"
}

# --channel wins, then the channel saved by the last install, then stable.
# Without the saved file an edge machine updating through `aphotic sync`
# was moved back to the newest release tag.
resolve_channel() {
  [[ -n "$CHANNEL" ]] && return 0
  local saved=""
  [[ -r "$(aphotic_channel_file)" ]] && saved="$(head -n1 "$(aphotic_channel_file)" 2>/dev/null || true)"
  case "$saved" in
    stable|edge) CHANNEL="$saved" ;;
    *) CHANNEL="stable" ;;
  esac
}

# Saves the channel and, on stable, checks out the newest release tag and
# re-runs install.sh from it. The re-run is marked through the environment
# rather than a flag, because an older install.sh at the tag would reject
# an unknown flag and any flag skips the guided first-run path.
apply_channel() {
  [[ "${APHOTIC_CHANNEL_RESOLVED:-0}" == "1" || "$DRY_RUN" == "1" ]] && return 0

  mkdir -p "$(dirname "$(aphotic_channel_file)")"
  echo "$CHANNEL" > "$(aphotic_channel_file)"

  [[ -e "$ROOT_DIR/.git" ]] || return 0

  if [[ "$CHANNEL" == "edge" ]]; then
    echo -e "$CNT - Installing the development branch (current checkout, channel edge)."
    return 0
  fi

  git -C "$ROOT_DIR" fetch --tags --quiet || { echo -e "$CWR - Could not fetch tags; installing the current tree."; }
  local tag
  tag="$(git -C "$ROOT_DIR" tag -l 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -n1)"
  if [[ -z "$tag" ]]; then
    echo -e "$CWR - No release tags found; installing the current tree."
  elif [[ "$(git -C "$ROOT_DIR" rev-parse HEAD)" == "$(git -C "$ROOT_DIR" rev-parse "$tag" 2>/dev/null || true)" ]]; then
    echo -e "$CNT - Installing ${tag} (up to date)."
  elif ! git -C "$ROOT_DIR" diff --quiet || ! git -C "$ROOT_DIR" diff --cached --quiet; then
    echo -e "$CWR - Local changes in the checkout; not switching to ${tag}. Installing the current tree."
  else
    echo -e "$CNT - Installing ${tag}."
    git -C "$ROOT_DIR" checkout --quiet "$tag"
    APHOTIC_CHANNEL_RESOLVED=1 exec "$ROOT_DIR/install.sh" "${ORIG_ARGS[@]}"
  fi
}
