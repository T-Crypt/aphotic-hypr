#!/usr/bin/env bash
# tests/test_install_wallust.sh
#
# wallust is fetched as a pinned upstream binary rather than through
# pacman, so the checksum gate is the only thing standing between a
# tampered or truncated download and /usr/local/bin. It must refuse to
# install anything that does not match, and it must never fail the run.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

WORKDIR=$(mktemp -d)
trap '/bin/rm -rf "$WORKDIR"' EXIT
PATH_BACKUP="$PATH"

CNT="[NOTE]"; COK="[OK]"; CER="[ERROR]"; CWR="[WARNING]"
INSTLOG="$WORKDIR/install.log"
: > "$INSTLOG"

FAKE_BIN="$WORKDIR/bin"
DEST="$WORKDIR/dest"
/bin/mkdir -p "$FAKE_BIN" "$DEST" "$WORKDIR/served"

# The payload a good download produces: a tarball holding one file named
# wallust, which is what the real release asset contains.
printf '#!/bin/sh\necho wallust 3.5.2\n' > "$WORKDIR/served/wallust"
/bin/chmod +x "$WORKDIR/served/wallust"
tar czf "$WORKDIR/served/good.tar.gz" -C "$WORKDIR/served" wallust
GOOD_SUM=$(sha256sum "$WORKDIR/served/good.tar.gz" | cut -d' ' -f1)
printf 'not the release asset' > "$WORKDIR/served/bad.tar.gz"

# curl stands in for the network: it copies whichever file the URL names.
/bin/cat > "$FAKE_BIN/curl" <<EOF
#!/bin/bash
out=""; url=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -o) out="\$2"; shift 2 ;;
    -*) shift ;;
    *) url="\$1"; shift ;;
  esac
done
src="$WORKDIR/served/\${url##*/}"
[[ -f "\$src" ]] || exit 22
/bin/cp "\$src" "\$out"
EOF
/bin/chmod +x "$FAKE_BIN/curl"

/bin/cat > "$FAKE_BIN/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF
/bin/chmod +x "$FAKE_BIN/sudo"

# PATH holds only the stubs plus the tools setup_wallust shells out to.
# A real wallust on this machine would otherwise satisfy the
# already-installed check and skip every case below.
for tool in mktemp rm sha256sum cut tar gzip install chmod; do
  real=$(command -v "$tool" 2>/dev/null) || continue
  /bin/ln -sf "$real" "$FAKE_BIN/$tool"
done
export PATH="$FAKE_BIN"
command -v wallust >/dev/null 2>&1 && fail "the test PATH must not contain a real wallust"

# shellcheck source=/dev/null
source "$ROOT/lib/install/wallust.sh"
set +e

WALLUST_BIN_DIR="$DEST"

# 1. A checksum mismatch must install nothing at all.
WALLUST_URL="file:///bad.tar.gz"
WALLUST_SHA256="$GOOD_SUM"
out=$(setup_wallust 2>&1)
[[ "$out" == *"failed its checksum"* ]] || fail "expected a checksum refusal, got: $out"
[[ -e "$DEST/wallust" ]] && fail "a mismatched download must never reach $DEST"

# 2. A download that fails outright is reported, not fatal.
WALLUST_URL="file:///nothing-here.tar.gz"
out=$(setup_wallust 2>&1)
[[ "$out" == *"Could not download"* ]] || fail "expected a download failure notice, got: $out"
[[ -e "$DEST/wallust" ]] && fail "a failed download must leave $DEST empty"

# 3. The matching payload installs, executable.
WALLUST_URL="file:///good.tar.gz"
out=$(setup_wallust 2>&1)
[[ -x "$DEST/wallust" ]] || fail "a verified download should have installed: $out"

# 4. An existing wallust on PATH is left alone: this must not overwrite a
#    working pacman-managed install.
/bin/cp "$WORKDIR/served/wallust" "$FAKE_BIN/wallust"
/bin/rm -f "$DEST/wallust"
out=$(setup_wallust 2>&1)
[[ "$out" == *"already installed"* ]] || fail "expected the already-installed skip, got: $out"
[[ -e "$DEST/wallust" ]] && fail "an existing wallust must not be reinstalled over"
/bin/rm -f "$FAKE_BIN/wallust"

# 5. Dry-run touches nothing and names the pinned version.
DRY_RUN=1
out=$(setup_wallust 2>&1)
[[ "$out" == *"[dry-run]"* ]] || fail "expected a dry-run plan, got: $out"
[[ -e "$DEST/wallust" ]] && fail "dry-run must not write anything"
unset DRY_RUN

# 6. The pinned constants the installer ships must be the real ones, so a
#    careless edit to the version does not leave a stale checksum behind.
unset WALLUST_URL WALLUST_SHA256 WALLUST_VERSION
# shellcheck source=/dev/null
source "$ROOT/lib/install/wallust.sh"
[[ "$WALLUST_URL" == *"/releases/download/$WALLUST_VERSION/"* ]] \
  || fail "WALLUST_URL must point at the pinned version's release asset"
[[ "$WALLUST_URL" != *"/archive/"* ]] \
  || fail "WALLUST_URL must use an uploaded release asset, not a generated archive"
[[ "$WALLUST_SHA256" =~ ^[0-9a-f]{64}$ ]] || fail "WALLUST_SHA256 is not a sha256"

export PATH="$PATH_BACKUP"
echo "PASS: wallust binary install"
