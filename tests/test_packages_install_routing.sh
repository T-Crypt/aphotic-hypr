#!/usr/bin/env bash
# tests/test_packages_install_routing.sh
#
# install_software must not need an AUR helper for a package a repo already
# carries. Before this, every package went through "$AUR_HELPER", so a
# failed yay bootstrap left it empty and the first base prep package
# (qt5-wayland, a plain repo package) died with "command not found".
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

FAKE_BIN="$WORKDIR/bin"
/bin/mkdir -p "$FAKE_BIN"

# pacman stub: repo-pkg is in the repos, aur-pkg is not, and nothing is
# installed until -S lands it (recorded in $WORKDIR/installed).
/bin/cat > "$FAKE_BIN/pacman" <<EOF
#!/usr/bin/env bash
op="\$1"; shift
case "\$op" in
  -Qq) /bin/grep -qxF "\$1" "$WORKDIR/installed" 2>/dev/null ;;
  -Si) [[ "\$1" == "repo-pkg" ]] ;;
  -S)
    for a in "\$@"; do
      [[ "\$a" == -* ]] && continue
      if [[ "\$a" != "repo-pkg" ]]; then
        echo "error: target not found: \$a"
        exit 1
      fi
      echo "\$a" >> "$WORKDIR/installed"
      echo "pacman installed \$a" >> "$WORKDIR/calls"
    done
    ;;
  *) exit 0 ;;
esac
EOF
/bin/chmod +x "$FAKE_BIN/pacman"

/bin/cat > "$FAKE_BIN/sudo" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF
/bin/chmod +x "$FAKE_BIN/sudo"

/bin/cat > "$FAKE_BIN/yay" <<EOF
#!/usr/bin/env bash
op="\$1"; shift
if [[ "\$op" == "-S" ]]; then
  for a in "\$@"; do
    [[ "\$a" == -* ]] && continue
    echo "\$a" >> "$WORKDIR/installed"
    echo "yay installed \$a" >> "$WORKDIR/calls"
  done
fi
EOF
/bin/chmod +x "$FAKE_BIN/yay"

export PATH="$FAKE_BIN:$PATH_BACKUP"
: > "$WORKDIR/installed"
: > "$WORKDIR/calls"

# shellcheck source=/dev/null
source "$ROOT/lib/install/packages.sh"
set +e

# 1. Repo package with no AUR helper at all: must install via pacman.
AUR_HELPER=""
out=$(install_software repo-pkg 2>&1) || fail "repo-pkg failed with no AUR helper: $out"
/bin/grep -qxF "pacman installed repo-pkg" "$WORKDIR/calls" \
  || fail "repo-pkg was not routed to pacman (calls: $(/bin/cat "$WORKDIR/calls"))"

# 2. Already-installed check must not shell out to the empty helper either.
out=$(install_software repo-pkg 2>&1) || fail "second repo-pkg call failed: $out"
[[ "$out" == *"already installed"* ]] || fail "expected already-installed short-circuit, got: $out"

# 3. An AUR-only package with no helper fails with the real reason, not a
#    bare "check the log".
: > "$WORKDIR/calls"
out=$(install_software aur-pkg optional 2>&1) || fail "optional aur-pkg should not abort the run"
[[ "$out" == *"no AUR helper"* ]] || fail "expected the missing-helper reason, got: $out"
[[ "$out" == *"Skipped, the install continues"* ]] || fail "an optional failure must say the install carries on, got: $out"

# 4. With a helper present, an AUR-only package goes to the helper and a
#    repo package still goes to pacman.
: > "$WORKDIR/calls"
AUR_HELPER="yay"
out=$(install_software aur-pkg 2>&1) || fail "aur-pkg failed with a helper present: $out"
/bin/grep -qxF "yay installed aur-pkg" "$WORKDIR/calls" || fail "aur-pkg was not routed to the AUR helper"

: > "$WORKDIR/calls"
: > "$WORKDIR/installed"
out=$(install_software repo-pkg 2>&1) || fail "repo-pkg failed with a helper present: $out"
/bin/grep -qxF "pacman installed repo-pkg" "$WORKDIR/calls" \
  || fail "repo-pkg should prefer pacman even when an AUR helper exists"

export PATH="$PATH_BACKUP"
echo "PASS: package install routing"
