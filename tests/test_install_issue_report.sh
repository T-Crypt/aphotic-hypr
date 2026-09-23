#!/usr/bin/env bash
# tests/test_install_issue_report.sh
# A failed install opens a pre-filled issue. #209 arrived as a bare title;
# this checks the body carries the details, redacts secrets and home paths,
# and stays short enough for a browser to open.
set -euo pipefail
fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"
cat > "$WORK/bin/lspci" <<'STUB'
#!/usr/bin/env bash
echo "01:00.0 VGA compatible controller: NVIDIA Corporation GP104 [GeForce GTX 1080] (rev a1)"
STUB
chmod +x "$WORK/bin/lspci"
export PATH="$WORK/bin:$PATH"

CNT="[NOTE]"; COK="[OK]"; CER="[ERROR]"; CWR="[WARNING]"
source "$ROOT/lib/install/ui.sh"
source "$ROOT/lib/install/packages.sh"
nvidia_driver_packages() { echo nvidia-580xx-dkms; }
ROOT_DIR="$ROOT"; PROFILE=minimal; LAYERS=dev; AUR_HELPER=yay
INSTLOG="$WORK/install.log"
decode() { python3 -c 'import sys,urllib.parse;print(urllib.parse.unquote(sys.stdin.read()))'; }

{
  echo "resolving dependencies..."
  echo "reading $HOME/.cache/yay/nvidia-open-dkms/PKGBUILD"
  echo "GITHUB_TOKEN=ghp_notreal123 api_key: sk-notreal"
  echo "error: failed to commit transaction (conflicting files)"
} > "$INSTLOG"

url="$(_issue_url_for nvidia-open-dkms)"
[[ "$url" == "$APHOTIC_ISSUES_URL/new?title=Install%20package%20failed%3A%20nvidia-open-dkms&body="* ]] \
  || fail "unexpected URL shape: ${url:0:120}"
body="$(printf '%s' "${url#*&body=}" | decode)"
for want in "Package: nvidia-open-dkms" "Profile: minimal, layers: dev" "GeForce GTX 1080" \
            "NVIDIA driver packages: nvidia-580xx-dkms" "AUR helper: yay" "failed to commit transaction" \
            "~/.cache/yay"; do
  grep -qF -- "$want" <<<"$body" || fail "body is missing: $want"
done
! grep -qF "$HOME" <<<"$body" || fail "home path was not redacted"
! grep -q 'ghp_notreal123\|sk-notreal' <<<"$body" || fail "secret was not redacted"
grep -q 'GITHUB_TOKEN=<redacted>' <<<"$body" || fail "redaction marker missing"

# A plus sign in a package name survives the round trip.
url="$(_issue_url_for 'gtk+3')"
[[ "$(printf '%s' "${url%%&body=*}" | decode)" == *"Install package failed: gtk+3" ]] || fail "plus sign lost in title"

# A huge log is trimmed from the top, keeping the newest lines and the header.
for i in $(seq 1 400); do echo "build line $i $(printf 'x%.0s' {1..250})"; done > "$INSTLOG"
echo "error: the real failure" >> "$INSTLOG"
url="$(_issue_url_for somepkg)"
(( ${#url} <= 7000 )) || fail "URL is ${#url} chars, over 7000"
body="$(printf '%s' "${url#*&body=}" | decode)"
grep -q "error: the real failure" <<<"$body" || fail "newest log line was trimmed"
grep -q "Package: somepkg" <<<"$body" || fail "header was trimmed"

echo "PASS: install failure opens a pre-filled, redacted, bounded issue"
