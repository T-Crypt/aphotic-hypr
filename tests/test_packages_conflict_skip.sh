#!/usr/bin/env bash
# tests/test_packages_conflict_skip.sh
#
# A profile package that conflicts with something already installed is
# skipped with a warning. pacman --noconfirm answers no to "remove the
# installed one?", so the old behaviour aborted the whole run on, for
# example, pipewire-pulse over an existing pulseaudio.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

WORKDIR=$(mktemp -d)
trap '/bin/rm -rf "$WORKDIR"' EXIT

CNT="[NOTE]"; COK="[OK]"; CER="[ERROR]"; CWR="[WARNING]"
DRY_RUN=0
INSTLOG="$WORKDIR/install.log"
: > "$INSTLOG"

FAKE_BIN="$WORKDIR/bin"
/bin/mkdir -p "$FAKE_BIN"
echo "old-server" > "$WORKDIR/installed"

/bin/cat > "$FAKE_BIN/pacman" <<EOF
#!/usr/bin/env bash
op="\$1"; shift
case "\$op" in
  -Qq|-T) /bin/grep -qxF "\$1" "$WORKDIR/installed" 2>/dev/null ;;
  -Si)
    case "\$1" in
      new-server) printf 'Name            : new-server\nConflicts With  : old-server>=1.0  other\n' ;;
      plain-pkg) printf 'Name            : plain-pkg\nConflicts With  : None\n' ;;
      *) exit 1 ;;
    esac
    ;;
  -S)
    for a in "\$@"; do
      [[ "\$a" == -* ]] && continue
      echo "\$a" >> "$WORKDIR/installed"
      echo "pacman installed \$a" >> "$WORKDIR/calls"
    done
    ;;
  *) exit 0 ;;
esac
EOF
/bin/chmod +x "$FAKE_BIN/pacman"
printf '#!/usr/bin/env bash\nexec "$@"\n' > "$FAKE_BIN/sudo"
/bin/chmod +x "$FAKE_BIN/sudo"
export PATH="$FAKE_BIN:$PATH"

source "$ROOT/lib/install/packages.sh"

out=$(install_software new-server required 2>&1) || fail "expected a conflicting package to be skipped, not to fail the run"
grep -q "old-server" <<< "$out" || fail "expected the warning to name the installed package"
grep -q "new-server" "$WORKDIR/calls" 2>/dev/null && fail "expected no install attempt for the conflicting package"

install_software plain-pkg required >/dev/null 2>&1 || fail "expected a package with no conflict to install"
grep -qx "pacman installed plain-pkg" "$WORKDIR/calls" || fail "expected plain-pkg to go through pacman -S"

echo "PASS: a profile package that conflicts with an installed one is skipped with a warning"
