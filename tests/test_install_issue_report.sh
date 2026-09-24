#!/usr/bin/env bash
# tests/test_install_issue_report.sh
set -euo pipefail
fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"

cat > "$WORK/bin/lspci" <<'STUB'
#!/usr/bin/env bash
echo '0000:01:00.0 "VGA compatible controller [0300]" "NVIDIA Corporation [10de]" "Device [2684]"'
STUB
cat > "$WORK/bin/pacman" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == "-Q" && "$2" == "sample" ]] && echo "sample 1.2.3-1"
STUB
chmod +x "$WORK/bin/lspci" "$WORK/bin/pacman"
export PATH="$WORK/bin:$PATH"

CNT="[NOTE]"; CWR="[WARNING]"; CER="[ERROR]"
ROOT_DIR="$ROOT"
PYTHON_BIN=python3
APHOTIC_ISSUES_URL="https://github.com/T-Crypt/Aphotic-Hypr/issues"
source "$ROOT/lib/install/report.sh"

INSTLOG="$WORK/install.log"
BUNDLE="$WORK/report.txt"
{
  echo "reading /home/alice/.cache/yay/sample/PKGBUILD on aphotic-test"
  echo "user alice at 192.168.1.5 aa:bb:cc:dd:ee:ff bob@example.com"
  echo "error: failed to commit transaction (conflicting files)"
} > "$INSTLOG"

HOME=/home/alice USER=alice HOSTNAME=aphotic-test \
  _install_report_write_bundle sample "$INSTLOG" "$BUNDLE"

redacted_home="~""/.cache/yay"
for want in "Failed package: sample" "GPU vendor: NVIDIA Corporation" \
            "Installed package: sample 1.2.3-1" "failed to commit transaction" \
            "$redacted_home" "<user>" "<host>" "<ip>" "<mac>" "<email>"; do
  grep -qF -- "$want" "$BUNDLE" || fail "bundle is missing: $want"
done
for private in "/home/alice" "alice" "aphotic-test" "192.168.1.5" \
               "aa:bb:cc:dd:ee:ff" "bob@example.com"; do
  ! grep -qF -- "$private" "$BUNDLE" || fail "bundle leaked: $private"
done

title="install: sample failed (2026-09-23)"
url="$(_install_report_issue_url "$title" "$BUNDLE")"
(( ${#url} <= 6000 )) || fail "URL is ${#url} chars, over 6000"
decoded=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read()))' <<< "$url")
grep -qF "$title" <<< "$decoded" || fail "URL title is missing"
grep -qF "Failed package: sample" <<< "$decoded" || fail "URL body is missing"

echo "PASS: install failure report is redacted and bounded"
