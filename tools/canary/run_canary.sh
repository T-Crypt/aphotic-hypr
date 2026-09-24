#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="$ROOT_DIR/canary-out"
CANARY_DATE="$(date -u +%F)"
BUILD_USER="${CANARY_BUILD_USER:-}"
TEMP_DIR="$(mktemp -d)"
chmod 755 "$TEMP_DIR"

BROKEN_PACKAGES=()
BROKEN_SOURCES=()
BROKEN_ERRORS=()
PACMAN=(pacman)
AS_BUILD_USER=()

cleanup() {
  rm -rf -- "$TEMP_DIR"
}
trap cleanup EXIT

mkdir -p "$OUT_DIR"
rm -f -- "$OUT_DIR/known-good.lock" "$OUT_DIR/status.json"

if [[ $EUID -eq 0 ]]; then
  if [[ -z "$BUILD_USER" || "$BUILD_USER" == "root" ]] || ! id "$BUILD_USER" &>/dev/null; then
    echo "Set CANARY_BUILD_USER to an existing non-root user." >&2
    exit 2
  fi
  AS_BUILD_USER=(sudo -H -u "$BUILD_USER" --)
else
  BUILD_USER="$(id -un)"
  PACMAN=(sudo pacman)
fi

profile_packages() {
  awk '
    /^\[packages\][[:space:]]*$/ { in_packages = 1; next }
    in_packages && /^\[/ { in_packages = 0 }
    in_packages && /^[[:space:]]*(prep|main)[[:space:]]*=/ {
      line = $0
      while (line !~ /\]/ && (getline next_line) > 0) {
        line = line " " next_line
      }
      while (match(line, /"[^"]+"/)) {
        print substr(line, RSTART + 1, RLENGTH - 2)
        line = substr(line, RSTART + RLENGTH)
      }
    }
  ' "$@"
}

error_tail() {
  local log_file="$1"
  tail -n 20 "$log_file" \
    | sed $'s/\033\\[[0-9;?]*[[:alpha:]]//g' \
    | LC_ALL=C tr -d '\000-\010\013\014\016-\037\177'
}

record_failure() {
  local package="$1" source="$2" log_file="$3" tail_text
  tail_text="$(error_tail "$log_file")"
  [[ -n "$tail_text" ]] || tail_text="command failed without output"
  BROKEN_PACKAGES+=("$package")
  BROKEN_SOURCES+=("$source")
  BROKEN_ERRORS+=("$tail_text")
  printf 'FAILED %s (%s)\n' "$package" "$source" >&2
}

json_string() {
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '"%s"' "$value"
}

write_status() {
  local green="$1" index
  {
    printf '{\n  "date": '
    json_string "$CANARY_DATE"
    printf ',\n  "green": %s,\n  "broken": [' "$green"
    if ((${#BROKEN_PACKAGES[@]})); then
      printf '\n'
      for index in "${!BROKEN_PACKAGES[@]}"; do
        printf '    {"package": '
        json_string "${BROKEN_PACKAGES[$index]}"
        printf ', "source": '
        json_string "${BROKEN_SOURCES[$index]}"
        printf ', "error_tail": '
        json_string "${BROKEN_ERRORS[$index]}"
        if ((index + 1 < ${#BROKEN_PACKAGES[@]})); then
          printf '},\n'
        else
          printf '}\n'
        fi
      done
      printf '  ]\n}\n'
    else
      printf ']\n}\n'
    fi
  } > "$OUT_DIR/status.json"
}

# The installer also installs Hyprland and the GPU stacks by name outside
# the profiles; read those from its own install_software calls.
installer_packages() {
  grep -rhoE 'install_software [a-z0-9][a-z0-9._+-]*' \
    "$ROOT_DIR/install.sh" "$ROOT_DIR"/lib/install/*.sh \
    | awk '{print $2}'
}

mapfile -t packages < <(
  {
    profile_packages \
      "$ROOT_DIR/profiles/base/full.toml" \
      "$ROOT_DIR/profiles/base/minimal.toml"
    installer_packages
  } | LC_ALL=C sort -u
)

repo_packages=()
aur_packages=()
for package in "${packages[@]}"; do
  if pacman -Si "$package" &>/dev/null; then
    repo_packages+=("$package")
  else
    aur_packages+=("$package")
  fi
done

printf 'Resolved %d repo packages and %d AUR packages.\n' \
  "${#repo_packages[@]}" "${#aur_packages[@]}"

if ((${#repo_packages[@]})); then
  repo_log="$TEMP_DIR/repo-transaction.log"
  if ! "${PACMAN[@]}" -S --needed --noconfirm "${repo_packages[@]}" &> "$repo_log"; then
    echo "Repository transaction failed; retrying packages one at a time." >&2
    for package in "${repo_packages[@]}"; do
      package_log="$TEMP_DIR/repo-$package.log"
      if ! "${PACMAN[@]}" -S --needed --noconfirm "$package" &> "$package_log"; then
        record_failure "$package" repo "$package_log"
      fi
    done
  fi
fi

aur_root="$TEMP_DIR/aur"
mkdir -p "$aur_root"
if [[ $EUID -eq 0 ]]; then
  chown "$BUILD_USER:$(id -gn "$BUILD_USER")" "$aur_root"
fi

for package in "${aur_packages[@]}"; do
  package_dir="$aur_root/$package"
  package_log="$TEMP_DIR/aur-$package.log"
  printf 'Building AUR package %s\n' "$package"
  if ! "${AS_BUILD_USER[@]}" git clone \
    "https://aur.archlinux.org/$package.git" "$package_dir" &> "$package_log"; then
    record_failure "$package" aur "$package_log"
    continue
  fi
  if ! (
    cd "$package_dir"
    "${AS_BUILD_USER[@]}" makepkg -si --noconfirm
  ) >> "$package_log" 2>&1; then
    record_failure "$package" aur "$package_log"
  fi
done

if ((${#BROKEN_PACKAGES[@]})); then
  write_status false
  printf 'Canary found %d broken package(s).\n' "${#BROKEN_PACKAGES[@]}" >&2
  exit 1
fi

{
  printf '# canary %s\n' "$CANARY_DATE"
  pacman -Q | LC_ALL=C sort
} > "$OUT_DIR/known-good.lock"

write_status true
echo "Canary completed without package failures."
