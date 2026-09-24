#!/usr/bin/env bash
# lib/install/report.sh
set -euo pipefail

_install_report_root() {
  if [[ -n "${ROOT_DIR:-}" && -r "${ROOT_DIR}/VERSION" ]]; then
    printf '%s\n' "$ROOT_DIR"
    return 0
  fi
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

_install_report_log_tail() {
  local log_file="$1"
  [[ -r "$log_file" ]] || return 0
  tail -n 200 "$log_file" 2>/dev/null | tr '\r' '\n'
}

install_failure_explain() {
  local package="$1" log_file="$2" output="" sentence conflict_line=""
  local first_package="" second_package="" conflict_package=""
  # Only error lines: pacman prints "checking keys in keyring" and makepkg
  # "verifying signatures" on every successful run too.
  output=$(_install_report_log_tail "$log_file" \
    | sed $'s/\033\\[[0-9;?]*[a-zA-Z]//g' \
    | grep -iE 'error|fail|conflict|not found|could not|invalid|corrupt|unknown public key|missing' || true)

  if grep -qiE 'signature.*(unknown trust|invalid|marginal trust|corrupt)|required key missing|key could not be looked up|invalid or corrupted package|unknown public key' <<< "$output"; then
    sentence="Your package keyring is out of date; run 'sudo pacman -Sy archlinux-keyring' and try again."
  elif grep -qiE 'could not resolve host|failed retrieving file' <<< "$output"; then
    sentence="A mirror or network connection failed while downloading the package; check your connection, refresh your mirrors, and try again."
  elif grep -qiE 'conflicting files|are in conflict|conflicts with' <<< "$output"; then
    conflict_line=$(grep -iE 'are in conflict|conflicts with' <<< "$output" | tail -n 1 || true)
    if [[ "$conflict_line" =~ ([[:alnum:]@._+:-]+)[[:space:]]+and[[:space:]]+([[:alnum:]@._+:-]+)[[:space:]]+are[[:space:]]+in[[:space:]]+conflict ]]; then
      first_package="${BASH_REMATCH[1]}"
      second_package="${BASH_REMATCH[2]}"
      [[ "$first_package" == "$package" ]] && conflict_package="$second_package" || conflict_package="$first_package"
    elif [[ "$conflict_line" =~ ([[:alnum:]@._+:-]+)[[:space:]]+conflicts[[:space:]]+with[[:space:]]+([[:alnum:]@._+:-]+) ]]; then
      first_package="${BASH_REMATCH[1]}"
      second_package="${BASH_REMATCH[2]}"
      [[ "$first_package" == "$package" ]] && conflict_package="$second_package" || conflict_package="$first_package"
    fi
    conflict_package="${conflict_package%.}"
    if [[ -n "$conflict_package" ]]; then
      sentence="This package conflicts with the installed package $conflict_package; resolve the conflict and try again."
    else
      sentence="This package conflicts with an installed package; resolve the conflict and try again."
    fi
  elif grep -qi 'target not found' <<< "$output"; then
    sentence="This package is not in the repositories right now because an upstream package changed."
  elif grep -qiE 'makepkg|==>[[:space:]]+ERROR' <<< "$output"; then
    sentence="The AUR build for this package broke upstream; try again later or check the AUR package page."
  else
    sentence="The installer could not determine the cause from the package output; review the log and try again."
  fi

  printf '%b\n' "${CER:-[ERROR]} - $package failed. $sentence"
  if [[ -n "$output" ]]; then
    printf '%b\n' "${CER:-[ERROR]}   Last error lines from the log:"
    tail -n 5 <<< "$output" | sed 's/^/      /'
  fi
}

_install_report_gpu_vendors() {
  command -v lspci >/dev/null 2>&1 || { printf '%s\n' "unknown"; return 0; }
  local vendors
  vendors=$(lspci -Dmm -nn 2>/dev/null | awk -F '"' '
    $2 ~ /\[(0300|0302)\]$/ {
      vendor = $4
      sub(/ \[[[:xdigit:]]{4}\]$/, "", vendor)
      if (!seen[vendor]++) {
        if (count++) printf ", "
        printf "%s", vendor
      }
    }
    END { if (!count) printf "unknown"; printf "\n" }
  ')
  printf '%s\n' "${vendors:-unknown}"
}

_install_report_packages() {
  local package="$1" failed_package package_state
  local -a failed_packages=()
  if [[ "$package" == "optional" ]] && declare -p FAILED_OPTIONAL_PACKAGES >/dev/null 2>&1; then
    failed_packages=("${FAILED_OPTIONAL_PACKAGES[@]}")
  else
    failed_packages=("$package")
  fi

  for failed_package in "${failed_packages[@]}"; do
    package_state=""
    if command -v pacman >/dev/null 2>&1; then
      package_state=$(pacman -Q "$failed_package" 2>/dev/null || true)
    fi
    [[ -n "$package_state" ]] && printf '%s\n' "$package_state"
  done
  return 0
}

_install_report_write_bundle() {
  local package="$1" log_file="$2" bundle="$3"
  local root version commit hostname_value gpu_vendors package_state python_bin
  root=$(_install_report_root)
  version=$(cat "$root/VERSION" 2>/dev/null || printf '%s' "unknown")
  commit=$(git -C "$root" rev-parse HEAD 2>/dev/null || printf '%s' "unknown")
  hostname_value="${HOSTNAME:-}"
  [[ -n "$hostname_value" ]] || hostname_value=$(hostname 2>/dev/null || true)
  gpu_vendors=$(_install_report_gpu_vendors)
  package_state=$(_install_report_packages "$package")
  python_bin="${PYTHON_BIN:-python3}"

  {
    printf 'Aphotic install failure report\n'
    printf 'Failed package: %s\n' "$package"
    if [[ "$package" == "optional" ]] && declare -p FAILED_OPTIONAL_PACKAGES >/dev/null 2>&1; then
      printf 'Failed optional packages: %s\n' "${FAILED_OPTIONAL_PACKAGES[*]}"
    fi
    printf 'Aphotic version: %s\n' "$version"
    printf 'Git commit: %s\n' "$commit"
    printf 'Kernel: %s\n' "$(uname -r 2>/dev/null || printf '%s' "unknown")"
    printf 'GPU vendor: %s\n' "$gpu_vendors"
    printf 'Profile: %s, layers: %s\n' "${PROFILE:-unknown}" "${LAYERS:-none}"
    printf 'AUR helper: %s\n' "${AUR_HELPER:-none}"
    if declare -F nvidia_driver_packages >/dev/null; then
      printf 'NVIDIA driver packages: %s\n' "$(nvidia_driver_packages 2>/dev/null | paste -sd, -)"
    fi
    [[ -n "$package_state" ]] && printf 'Installed package: %s\n' "$package_state"
    printf '\nLast 60 lines of the install log:\n'
    if [[ -r "$log_file" ]]; then
      tail -n 60 "$log_file" 2>/dev/null
    else
      printf 'The install log was not readable.\n'
    fi
  } | "$python_bin" -c '
import ipaddress
import re
import sys

home, user, hostname = sys.argv[1:4]
text = sys.stdin.read()
text = re.sub(
    r"(?i)\b((?:token|key|password|passwd|secret)[A-Za-z0-9_]*)\s*([=:])\s*\S+",
    r"\1\2<redacted>",
    text,
)
text = re.sub(r"[A-Za-z0-9.!#$%&\x27*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?", "<email>", text)
text = re.sub(r"(?i)(?<![0-9a-f])(?:[0-9a-f]{2}:){5}[0-9a-f]{2}(?![0-9a-f])", "<mac>", text)
text = re.sub(r"(?<![0-9])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![0-9])", "<ip>", text)

ipv6 = re.compile(r"(?<![0-9A-Za-z:])(?:[0-9A-Fa-f]*:){2,}[0-9A-Fa-f]*(?![0-9A-Za-z:])")
def redact_ipv6(match):
    try:
        ipaddress.ip_address(match.group(0))
    except ValueError:
        return match.group(0)
    return "<ip>"

text = ipv6.sub(redact_ipv6, text)
if home:
    text = text.replace(home, "~")
if user:
    text = re.sub(r"(?<![A-Za-z0-9_.-])" + re.escape(user) + r"(?![A-Za-z0-9_.-])", "<user>", text)
if hostname:
    text = text.replace(hostname, "<host>")
sys.stdout.write(text)
' "${HOME:-}" "${USER:-}" "$hostname_value" > "$bundle"
}

_install_report_issue_url() {
  local title="$1" bundle="$2" python_bin
  python_bin="${PYTHON_BIN:-python3}"
  "$python_bin" -c '
import sys
import urllib.parse

base, title, bundle = sys.argv[1:4]
with open(bundle, encoding="utf-8", errors="replace") as handle:
    body = handle.read()
marker = "\n\n[Report shortened to fit this URL.]"

def make_url(value):
    query = urllib.parse.urlencode({"title": title, "body": value}, quote_via=urllib.parse.quote)
    return base.rstrip("/") + "/new?" + query

if len(make_url(body)) > 6000:
    low, high = 0, len(body)
    while low < high:
        middle = (low + high + 1) // 2
        if len(make_url(body[:middle] + marker)) <= 6000:
            low = middle
        else:
            high = middle - 1
    body = body[:low] + marker
print(make_url(body))
' "${APHOTIC_ISSUES_URL:-https://github.com/T-Crypt/Aphotic-Hypr/issues}" "$title" "$bundle"
}

install_offer_report() {
  local package="$1" log_file="$2" bundle answer title issue_url
  [[ "${APHOTIC_NO_REPORT:-0}" != "1" ]] || return 0
  [[ "${DRY_RUN:-0}" != "1" ]] || return 0
  if [[ ! -t 0 ]]; then
    printf '%b\n' "${CWR:-[WARNING]} - Report this at ${APHOTIC_ISSUES_URL:-https://github.com/T-Crypt/Aphotic-Hypr/issues} with the end of $log_file."
    return 0
  fi

  bundle=$(mktemp "${TMPDIR:-/tmp}/aphotic-install-report.XXXXXX") || {
    printf '%b\n' "${CWR:-[WARNING]} - Could not create the install report bundle."
    return 0
  }
  if ! _install_report_write_bundle "$package" "$log_file" "$bundle"; then
    printf '%b\n' "${CWR:-[WARNING]} - Could not build the install report bundle."
    rm -f "$bundle"
    return 0
  fi

  printf '%b\n' "${CNT:-[NOTE]} - Review the redacted report before sending it:"
  printf '%s\n' "----------------------------------------"
  cat "$bundle"
  printf '%s\n' "----------------------------------------"
  printf 'Send this as a GitHub issue? [y/N] '
  IFS= read -r answer || answer=""
  [[ "$answer" =~ ^[Yy]$ ]] || { rm -f "$bundle"; return 0; }

  title="install: $package failed ($(date +%F))"
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    # No --label: only maintainers can set labels, so it would fail for users.
    if gh issue create --repo T-Crypt/Aphotic-Hypr --title "$title" --body-file "$bundle"; then
      rm -f "$bundle"
      return 0
    fi
    printf '%b\n' "${CWR:-[WARNING]} - GitHub did not accept the report; use the link below instead."
  fi
  issue_url=$(_install_report_issue_url "$title" "$bundle")
  printf 'Open this prefilled issue and review it before submitting:\n%s\n' "$issue_url"
  if [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] && command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$issue_url" >/dev/null 2>&1 || true
  fi
  rm -f "$bundle"
}
