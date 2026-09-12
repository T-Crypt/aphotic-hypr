#!/usr/bin/env bash
# tests/test_packages_aur_cache_recovery.sh
#
# A failed AUR build leaves a half-written source tarball in the helper's
# build dir. makepkg validates that file on the next run instead of fetching
# it again, so every later install fails with "did not pass the validity
# check" on a package that is fine. install_software clears the derived
# files and retries once, and leaves a user-edited PKGBUILD alone.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

WORKDIR=$(mktemp -d)
trap '/bin/rm -rf "$WORKDIR"' EXIT
PATH_BACKUP="$PATH"

CNT="[NOTE]"; COK="[OK]"; CER="[ERROR]"; CWR="[WARNING]"
APHOTIC_ISSUES_URL="https://example.invalid/issues"
DRY_RUN=0
INSTLOG="$WORKDIR/install.log"
: > "$INSTLOG"
: > "$WORKDIR/installed"

export XDG_CACHE_HOME="$WORKDIR/cache"
FAKE_BIN="$WORKDIR/bin"
/bin/mkdir -p "$FAKE_BIN" "$XDG_CACHE_HOME"

# Nothing is in a repo, so every package here routes to the AUR helper.
/bin/cat > "$FAKE_BIN/pacman" <<EOF
#!/usr/bin/env bash
op="\$1"; shift
case "\$op" in
  -Qq) /bin/grep -qxF "\$1" "$WORKDIR/installed" 2>/dev/null ;;
  -Si) exit 1 ;;
  *) exit 0 ;;
esac
EOF
/bin/chmod +x "$FAKE_BIN/pacman"

# Stands in for makepkg's source validation: the build succeeds only once
# the stale tarball is gone from the build dir.
/bin/cat > "$FAKE_BIN/yay" <<EOF
#!/usr/bin/env bash
op="\$1"; shift
pkg=""
for a in "\$@"; do [[ "\$a" == -* ]] || pkg="\$a"; done
[[ "\$op" == "-S" ]] || exit 0
echo "attempt \$pkg" >> "$WORKDIR/attempts"
if [[ -e "$XDG_CACHE_HOME/yay/\$pkg/\$pkg-1.0.tar.gz" ]]; then
  echo "==> ERROR: One or more files did not pass the validity check!"
  exit 1
fi
echo "\$pkg" >> "$WORKDIR/installed"
EOF
/bin/chmod +x "$FAKE_BIN/yay"

# A build dir in the state a killed build leaves behind: a clean checkout
# with a partial download sitting next to it.
seed_build_dir() {
  local pkg="$1"
  local dir="$XDG_CACHE_HOME/yay/$pkg"
  /bin/rm -rf "$dir"
  /bin/mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.invalid
  git -C "$dir" config user.name test
  echo "pkgname=$pkg" > "$dir/PKGBUILD"
  git -C "$dir" add PKGBUILD
  git -C "$dir" commit -qm initial
  printf 'truncated' > "$dir/$pkg-1.0.tar.gz"
}

export PATH="$FAKE_BIN:$PATH_BACKUP"
# shellcheck source=/dev/null
source "$ROOT/lib/install/packages.sh"
set +e
AUR_HELPER="yay"

# 1. Stale tarball: the first build fails its checksum, the cache is cleared
#    and the second build succeeds.
: > "$WORKDIR/attempts"
seed_build_dir stale-pkg
out=$(install_software stale-pkg 2>&1) || fail "stale-pkg should recover after the cache is cleared: $out"
[[ $(/bin/grep -c . "$WORKDIR/attempts") == "2" ]] \
  || fail "expected exactly two build attempts, got $(/bin/cat "$WORKDIR/attempts")"
[[ "$out" == *"Cleared stale downloads"* ]] || fail "expected the cache-clear notice, got: $out"
[[ "$out" == *"was installed"* ]] || fail "expected success after the retry, got: $out"
[[ -e "$XDG_CACHE_HOME/yay/stale-pkg/stale-pkg-1.0.tar.gz" ]] \
  && fail "the stale tarball should have been removed"
[[ -f "$XDG_CACHE_HOME/yay/stale-pkg/PKGBUILD" ]] \
  || fail "the tracked PKGBUILD must survive the clean"

# 2. A PKGBUILD the user edited is theirs. No clean, no retry, and the
#    message names the directory.
: > "$WORKDIR/attempts"
: > "$WORKDIR/installed"
seed_build_dir edited-pkg
echo "# a deliberate local change" >> "$XDG_CACHE_HOME/yay/edited-pkg/PKGBUILD"
out=$(install_software edited-pkg optional 2>&1)
[[ $(/bin/grep -c . "$WORKDIR/attempts") == "1" ]] \
  || fail "a user-edited PKGBUILD must not trigger a retry, got $(/bin/cat "$WORKDIR/attempts")"
[[ "$out" == *"local edits to tracked files"* ]] || fail "expected the local-edit warning, got: $out"
[[ "$out" == *"Left alone"* ]] || fail "expected the leave-it-alone notice, got: $out"
/bin/grep -qF "a deliberate local change" "$XDG_CACHE_HOME/yay/edited-pkg/PKGBUILD" \
  || fail "the user's PKGBUILD edit was discarded"

# 3. No build dir at all (a repo package, or a first-ever build): one
#    attempt, no retry, nothing invented.
: > "$WORKDIR/attempts"
out=$(install_software never-built optional 2>&1)
[[ $(/bin/grep -c . "$WORKDIR/attempts") == "1" ]] \
  || fail "expected a single attempt with no build dir, got $(/bin/cat "$WORKDIR/attempts")"

export PATH="$PATH_BACKUP"
echo "PASS: AUR build cache recovery"
