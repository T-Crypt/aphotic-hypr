#!/usr/bin/env bash
# tests/test_install_channel.sh
# `aphotic sync` ran install.sh --config-only with no channel, and
# install.sh defaulted to stable, so an edge machine was moved back to the
# newest release tag. Channel now comes from --channel, then the saved
# file, then stable, and sync passes the saved channel through.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export HOME="$T" XDG_STATE_HOME="$T/state"
saved="$XDG_STATE_HOME/aphotic/channel"

# shellcheck source=lib/install/channel.sh
source "$ROOT/lib/install/channel.sh"

resolved() {
  CHANNEL="$1"
  resolve_channel
  printf '%s' "$CHANNEL"
}

[[ "$(resolved "")" == "stable" ]] || fail "no flag and nothing saved must be stable"
mkdir -p "$(dirname "$saved")"
echo edge > "$saved"
[[ "$(resolved "")" == "edge" ]] || fail "a saved edge channel must be used when no flag is given"
[[ "$(resolved stable)" == "stable" ]] || fail "--channel stable must beat a saved edge"
echo nonsense > "$saved"
[[ "$(resolved "")" == "stable" ]] || fail "an unreadable saved channel must fall back to stable"

# A dots repo with a release tag behind the current commit. Its install.sh
# reports where it ran from, standing in for a real deploy.
REPO="$T/dots"
git init -q -b dev "$REPO"
git -C "$REPO" config user.email t@t.local
git -C "$REPO" config user.name t
cat > "$REPO/install.sh" <<'EOF'
#!/usr/bin/env bash
echo "deployed $(git -C "$(dirname "$0")" describe --tags --always) channel=$*"
EOF
chmod +x "$REPO/install.sh"
git -C "$REPO" add install.sh
git -C "$REPO" commit -q -m release
git -C "$REPO" tag v1.0.0
echo dev > "$REPO/WORK"
git -C "$REPO" add WORK
git -C "$REPO" commit -q -m "dev work"
dev_sha="$(git -C "$REPO" rev-parse HEAD)"

run_apply() {
  (
    ROOT_DIR="$1" CHANNEL="$2" DRY_RUN=0 CNT="" CWR=""
    ORIG_ARGS=(--config-only --channel "$2")
    unset APHOTIC_CHANNEL_RESOLVED
    apply_channel
    echo "stayed"
  )
}

out="$(run_apply "$REPO" edge)"
[[ "$out" == *stayed* ]] || fail "edge must deploy the current checkout, got: $out"
[[ "$(git -C "$REPO" rev-parse HEAD)" == "$dev_sha" ]] || fail "edge moved the checkout off the dev commit"
[[ "$(cat "$saved")" == "edge" ]] || fail "edge was not saved"

git -C "$REPO" worktree add -q --detach "$T/wt" "$dev_sha"
out="$(run_apply "$T/wt" stable)"
[[ "$(tail -n1 <<<"$out")" == "deployed v1.0.0 channel=--config-only --channel stable" ]] \
  || fail "stable in a worktree checkout must switch to the newest tag and re-run, got: $out"

out="$(run_apply "$REPO" stable)"
[[ "$(tail -n1 <<<"$out")" == "deployed v1.0.0 channel=--config-only --channel stable" ]] \
  || fail "stable must switch to the newest tag and re-run install.sh from it, got: $out"
git -C "$REPO" checkout -q dev

# aphotic sync with an edge channel saved: the stub install.sh shows which
# channel it was handed and the checkout stays on the dev commit.
echo edge > "$saved"
LIB_DIR="$ROOT/Configs/.local/lib/aphotic"
mkdir -p "$T/bin"
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/bin/pgrep"
chmod +x "$T/bin/pgrep"
log="$(
  export PATH="$T/bin:$PATH" APHOTIC_DOTS_DIR="$REPO"
  # shellcheck source=/dev/null
  source "$LIB_DIR/globalcontrol.sh"
  COMMANDS_DIR="$T/cmds"
  mkdir -p "$COMMANDS_DIR"
  printf 'aphotic_cmd_plugin() { :; }\n' > "$COMMANDS_DIR/cmd_plugin.sh"
  # shellcheck source=/dev/null
  source "$LIB_DIR/commands/cmd_sync.sh"
  _aphotic_sync_run "$REPO" 0 2>&1
)"
[[ "$log" == *"channel=--config-only --channel edge"* ]] || fail "sync did not pass the saved edge channel, got: $log"
[[ "$log" == *"on the edge channel"* ]] || fail "sync log does not name the channel, got: $log"
[[ "$log" == *"($(git -C "$REPO" rev-parse --short HEAD))"* ]] || fail "sync log does not name the deployed ref, got: $log"
[[ "$(git -C "$REPO" rev-parse HEAD)" == "$dev_sha" ]] || fail "sync on edge moved the checkout"

echo "PASS: install channel resolves flag > saved > stable; aphotic sync keeps an edge checkout"
