#!/usr/bin/env bash
# tests/test_doctor_version_drift.sh
# `aphotic doctor`'s version section reports whether the dots checkout is
# behind origin/main -- the trap noted in this repo's session docs: local
# main can sit behind origin/main with nothing surfacing it. Exercises
# _aphotic_doctor_version_drift directly against fabricated git state
# rather than the real checkout, so the test doesn't depend on this
# machine's actual fetch history.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/Configs/.local/lib/aphotic/commands/cmd_doctor.sh"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

mkrepo() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q -b main
    git -C "$dir" config user.email test@test.local
    git -C "$dir" config user.name test
    echo "9.9.9" > "$dir/VERSION"
    git -C "$dir" add VERSION
    git -C "$dir" commit -q -m init
}

# --- not a git checkout at all ---
NOTGIT="$WORKDIR/notgit"
mkdir -p "$NOTGIT"
out="$(APHOTIC_DOTS_DIR="$NOTGIT" APHOTIC_VERSION="9.9.9" _aphotic_doctor_version_drift)"
[[ "$out" == *"is not a git checkout"* ]] || fail "expected a non-git dots dir to be reported, got: $out"

# --- on main, no origin/main ref cached ---
NOFETCH="$WORKDIR/nofetch"
mkrepo "$NOFETCH"
out="$(APHOTIC_DOTS_DIR="$NOFETCH" APHOTIC_VERSION="9.9.9" _aphotic_doctor_version_drift)"
[[ "$out" == *"no origin/main ref cached"* ]] || fail "expected a missing origin/main ref to be reported, got: $out"

# --- on main, up to date with origin/main ---
UPTODATE="$WORKDIR/uptodate"
mkrepo "$UPTODATE"
head="$(git -C "$UPTODATE" rev-parse HEAD)"
git -C "$UPTODATE" update-ref refs/remotes/origin/main "$head"
out="$(APHOTIC_DOTS_DIR="$UPTODATE" APHOTIC_VERSION="9.9.9" _aphotic_doctor_version_drift)"
[[ "$out" == *"[ok]   up to date with origin/main"* ]] || fail "expected up-to-date main to report ok, got: $out"

# --- on main, behind origin/main ---
BEHIND="$WORKDIR/behind"
mkrepo "$BEHIND"
c1="$(git -C "$BEHIND" rev-parse HEAD)"
echo "9.9.9-next" > "$BEHIND/VERSION"
git -C "$BEHIND" commit -q -am next
c2="$(git -C "$BEHIND" rev-parse HEAD)"
git -C "$BEHIND" reset -q --hard "$c1"
git -C "$BEHIND" update-ref refs/remotes/origin/main "$c2"
out="$(APHOTIC_DOTS_DIR="$BEHIND" APHOTIC_VERSION="9.9.9" _aphotic_doctor_version_drift)"
[[ "$out" == *"[warn] 1 commit(s) behind origin/main"* ]] || fail "expected 1 commit behind to be reported, got: $out"

# --- not on main ---
OTHERBRANCH="$WORKDIR/otherbranch"
mkrepo "$OTHERBRANCH"
git -C "$OTHERBRANCH" checkout -q -b feature/whatever
out="$(APHOTIC_DOTS_DIR="$OTHERBRANCH" APHOTIC_VERSION="9.9.9" _aphotic_doctor_version_drift)"
[[ "$out" == *"not on main"* ]] || fail "expected a non-main branch to be reported, got: $out"

echo "ok: test_doctor_version_drift"
