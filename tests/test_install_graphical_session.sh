#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
TESTHOME="$WORKDIR/home"
FAKEBIN="$WORKDIR/bin"
EVENTS="$WORKDIR/events"
DAEMON_MARK="$WORKDIR/awww-daemon.running"
mkdir -p "$TESTHOME/.local/bin" "$FAKEBIN" "$TESTHOME/Aphotic-Hypr"
: > "$EVENTS"

export HOME="$TESTHOME"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_RUNTIME_DIR="$WORKDIR/runtime"
export APHOTIC_DOTS_DIR="$ROOT"
export APHOTIC_SDDM_THEME_DIR="$WORKDIR/no-sddm"
export COPY_CONFIGS=1
export GREETD_PREVIEW=0
export PATH="$FAKEBIN:/usr/bin:/bin"
export INSTLOG="$WORKDIR/install.log"
export CNT='[NOTE]'
export CWR='[WARNING]'
export COK='[OK]'
export DETECTED_OMARCHY=0
export CONFIG_ONLY=0
export LAYERS_KNOWN=1
export GRAPHICAL=1
export APHOTIC_TOML="$TESTHOME/Aphotic-Hypr/aphotic.toml"
export PROFILE=minimal
export LAYERS=""
export THEME=beta
export ISNVIDIA=false
export AUR_HELPER=""
export ISAMD=false

cat > "$FAKEBIN/systemctl" <<'SYSTEMCTL'
#!/usr/bin/env bash
case "$*" in
  *"is-active"*"graphical-session.target"*)
    [[ "${GRAPHICAL:-0}" == "1" ]]
    ;;
  *"is-enabled"*aphotic-shell.service*)
    exit 0
    ;;
  *show*)
    echo 0
    ;;
  *restart*aphotic-shell.service*)
    echo restart >> "$INSTALL_EVENTS"
    ;;
esac
SYSTEMCTL
chmod +x "$FAKEBIN/systemctl"

cat > "$FAKEBIN/pgrep" <<'PGREP'
#!/usr/bin/env bash
if [[ "$1" == "-u" ]]; then
  [[ -f "$AWWW_DAEMON_MARK" ]]
  exit $?
fi
if [[ "$1" == "-f" ]]; then
  exit 0
fi
exit 1
PGREP
chmod +x "$FAKEBIN/pgrep"

cat > "$FAKEBIN/awww-daemon" <<'AWWW'
#!/usr/bin/env bash
echo daemon >> "$INSTALL_EVENTS"
touch "$AWWW_DAEMON_MARK"
AWWW
chmod +x "$FAKEBIN/awww-daemon"

cat > "$FAKEBIN/awww" <<'AWWW'
#!/usr/bin/env bash
case "$1" in
  query) [[ -f "$AWWW_DAEMON_MARK" ]] && echo '{}' ;;
  img)
    [[ -f "$HOME/Aphotic-Hypr/aphotic.toml" ]] || exit 42
    echo image >> "$INSTALL_EVENTS"
    ;;
  *) exit 1 ;;
esac
AWWW
chmod +x "$FAKEBIN/awww"
for executable in wallust sudo; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKEBIN/$executable"
  chmod +x "$FAKEBIN/$executable"
done
printf '#!/usr/bin/env bash\nexit 1\n' > "$FAKEBIN/sudo"

export INSTALL_EVENTS="$EVENTS"
export AWWW_DAEMON_MARK="$DAEMON_MARK"
mkdir -p "$TESTHOME/.local/state/aphotic"

source "$ROOT/lib/install/wizard.sh"
source "$ROOT/lib/install/config_deploy.sh"
print_stage() { :; }
setup_login_manager_theme() { :; }
install_vscode_extensions() { :; }
deploy_user_configs() {
  ln -sf "$ROOT/Configs/.local/bin/aphotic" "$HOME/.local/bin/aphotic"
  for theme in alpha beta; do
    mkdir -p "$XDG_CONFIG_HOME/awww/$theme"
    printf '[theme]\ndisplay_name = "%s"\n[wallpaper]\ndefault = "one.jpg"\n' "$theme" > "$XDG_CONFIG_HOME/awww/$theme/theme.toml"
    : > "$XDG_CONFIG_HOME/awww/$theme/one.jpg"
  done
}
sed -n '/^  print_stage 6 /,/^  print_stage 7 /p' "$ROOT/install.sh" > "$WORKDIR/deploy-stage.sh"
run_install_stage() {
  source "$WORKDIR/deploy-stage.sh"
}

run_install_stage

mapfile -t first_run < "$EVENTS"
[[ "${first_run[*]}" == "daemon image restart" ]] \
  || fail "expected daemon, theme initialization, and shell restart order; got: ${first_run[*]}"
[[ -f "$TESTHOME/.local/state/aphotic/theme.json" ]] \
  || fail "theme initializer did not create state"
[[ "$(jq -r .theme "$XDG_STATE_HOME/aphotic/theme.json")" == "beta" ]] \
  || fail "theme initialization did not use the saved install selection"

printf '{"theme":"gruvbox"}\n' > "$TESTHOME/.local/state/aphotic/theme.json"
: > "$EVENTS"
run_install_stage
mapfile -t second_run < "$EVENTS"
[[ "${second_run[*]}" == "restart" ]] \
  || fail "existing daemon should not be started twice; got: ${second_run[*]}"
grep -q 'gruvbox' "$TESTHOME/.local/state/aphotic/theme.json" \
  || fail "existing theme state was overwritten"

export GRAPHICAL=0
: > "$EVENTS"
run_install_stage
[[ ! -s "$EVENTS" ]] || fail "non-graphical session should not start daemon or restart shell"

echo "PASS: active-session initialization is ordered, idempotent, and gated"
