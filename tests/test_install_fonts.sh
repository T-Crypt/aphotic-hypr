#!/usr/bin/env bash
# tests/test_install_fonts.sh
#
# A fresh install could finish with Material Symbols installed but missing
# from the font cache, and the shell drew every icon as its name.
# refresh_font_cache must force a rebuild of both caches and say whether the
# icon font resolves; aphotic doctor must report the same thing.
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

WORKDIR=$(mktemp -d)
trap '/bin/rm -rf "$WORKDIR"' EXIT

CNT="[NOTE]"; COK="[OK]"; CWR="[WARNING]"
INSTLOG="$WORKDIR/install.log"
: > "$INSTLOG"

FAKE_BIN="$WORKDIR/bin"
/bin/mkdir -p "$FAKE_BIN"

/bin/cat > "$FAKE_BIN/sudo" <<EOF
#!/usr/bin/env bash
echo "sudo \$*" >> "$WORKDIR/calls"
exec "\$@"
EOF
/bin/cat > "$FAKE_BIN/fc-cache" <<EOF
#!/usr/bin/env bash
echo "fc-cache \$*" >> "$WORKDIR/calls"
EOF
# fc-list prints whatever families the test put in $WORKDIR/families.
/bin/cat > "$FAKE_BIN/fc-list" <<EOF
#!/usr/bin/env bash
/bin/cat "$WORKDIR/families" 2>/dev/null
EOF
/bin/cat > "$FAKE_BIN/pacman" <<EOF
#!/usr/bin/env bash
[[ -f "$WORKDIR/pkg_installed" ]]
EOF
/bin/chmod +x "$FAKE_BIN"/*
PATH="$FAKE_BIN:/usr/bin:/bin"

# shellcheck source=/dev/null
source "$ROOT/lib/install/fonts.sh"
set +e

# Font present: both caches rebuilt with -f, system one through sudo.
printf 'Inter\nMaterial Symbols Rounded\n' > "$WORKDIR/families"
: > "$WORKDIR/calls"
out=$(DRY_RUN=0 refresh_font_cache)
grep -qxF "sudo fc-cache -f -s" "$WORKDIR/calls" || fail "system cache must be force-rebuilt through sudo, calls: $(cat "$WORKDIR/calls")"
grep -qxF "fc-cache -f" "$WORKDIR/calls" || fail "user cache must be force-rebuilt, calls: $(cat "$WORKDIR/calls")"
[[ "$out" == *"[OK]"*"Material Symbols Rounded"* ]] || fail "a resolved font must report OK, got: $out"

# Font still missing after the rebuild: warn and name the fix.
printf 'Inter\n' > "$WORKDIR/families"
out=$(DRY_RUN=0 refresh_font_cache)
[[ "$out" == *"[WARNING]"*"still missing"* ]] || fail "a missing font must warn, got: $out"
[[ "$out" == *"fc-cache -f"*"restart aphotic-shell.service"* ]] || fail "the warning must name the fix, got: $out"

# Dry run touches nothing.
: > "$WORKDIR/calls"
out=$(DRY_RUN=1 refresh_font_cache)
[[ ! -s "$WORKDIR/calls" ]] || fail "dry run must not run fc-cache, calls: $(cat "$WORKDIR/calls")"
[[ "$out" == *"[dry-run]"* ]] || fail "dry run must say what it would do, got: $out"

# shellcheck source=/dev/null
source "$ROOT/Configs/.local/lib/aphotic/commands/cmd_doctor.sh"

printf 'Material Symbols Rounded\n' > "$WORKDIR/families"
out=$(_aphotic_doctor_icon_font)
[[ "$out" == *"[ok]"* ]] || fail "doctor must pass a resolved font, got: $out"

printf 'Inter\n' > "$WORKDIR/families"
touch "$WORKDIR/pkg_installed"
out=$(_aphotic_doctor_icon_font)
[[ "$out" == *"[warn]"*"font cache"* && "$out" == *"fc-cache -f"* ]] || fail "doctor must flag an installed but uncached font, got: $out"

/bin/rm -f "$WORKDIR/pkg_installed"
out=$(_aphotic_doctor_icon_font)
[[ "$out" == *"[MISS]"* && "$out" == *"pacman -S --needed ttf-material-symbols-variable"* ]] || fail "doctor must flag a missing package, got: $out"

echo "PASS: install fonts"
