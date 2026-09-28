#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
FAKEBIN="$WORKDIR/bin"
LOG="$WORKDIR/calls"
mkdir -p "$FAKEBIN" "$WORKDIR/etc"
: > "$LOG"

# Only the stubs and the few real tools the functions use, so the host's
# own greetd or start-hyprland cannot leak in.
for b in bash cat cp dirname mkdir grep rm touch chmod; do ln -s "$(command -v "$b")" "$FAKEBIN/$b"; done
export PATH="$FAKEBIN"
export INSTLOG="$WORKDIR/install.log" CNT='[NOTE]' CWR='[WARNING]' COK='[OK]'
export ROOT_DIR="$ROOT"
export APHOTIC_GREETD_CONFIG="$WORKDIR/etc/config.toml"
export APHOTIC_GREETD_BACKUP="$WORKDIR/etc/config.toml.aphotic-backup"
export APHOTIC_GREETER_QML="$WORKDIR/etc/shell.qml"
export APHOTIC_GREETER_HYPR_CONF="$WORKDIR/etc/hyprland-greeter.lua"
export APHOTIC_DM_CHOICE_FILE="$WORKDIR/state/displaymanager"

for bin in greetd start-hyprland qs; do printf '#!/bin/sh\n' > "$FAKEBIN/$bin"; done
cat > "$FAKEBIN/sudo" <<'EOF'
#!/usr/bin/env bash
"$@"
EOF
cat > "$FAKEBIN/systemctl" <<EOF
#!/usr/bin/env bash
echo "systemctl \$*" >> "$LOG"
[[ "\$1" == "is-enabled" ]] && [[ -f "$WORKDIR/greetd-enabled" ]] && exit 0
[[ "\$1" == "is-enabled" ]] && exit 1
exit 0
EOF
chmod +x "$FAKEBIN"/{greetd,start-hyprland,qs,sudo,systemctl}
touch "$APHOTIC_GREETER_QML" "$APHOTIC_GREETER_HYPR_CONF"

# shellcheck source=/dev/null
source "$ROOT/lib/install/display_manager.sh"

# shellcheck disable=SC2034
reset_env() { KEEP_SDDM=0 DETECTED_OMARCHY=0 APHOTIC_CONTAINER=0 DRY_RUN=0; rm -f "$APHOTIC_DM_CHOICE_FILE"; : > "$LOG"; }

reset_env
greetd_switch_blocker >/dev/null && fail "a ready machine must not be blocked"

reset_env; DETECTED_OMARCHY=1
[[ "$(greetd_switch_blocker)" == *Omarchy* ]] || fail "Omarchy must keep its login"

reset_env; KEEP_SDDM=1
greetd_switch_blocker >/dev/null || fail "--keep-sddm must block"

reset_env; mkdir -p "$(dirname "$APHOTIC_DM_CHOICE_FILE")"; echo sddm > "$APHOTIC_DM_CHOICE_FILE"
[[ "$(greetd_switch_blocker)" == *"chose sddm"* ]] || fail "a user who switched back to sddm must stay there"

reset_env; rm "$FAKEBIN/start-hyprland"
greetd_switch_blocker >/dev/null || fail "a missing start-hyprland must block"
printf '#!/bin/sh\n' > "$FAKEBIN/start-hyprland"; chmod +x "$FAKEBIN/start-hyprland"

reset_env; rm "$APHOTIC_GREETER_HYPR_CONF"
greetd_switch_blocker >/dev/null || fail "missing greeter files must block"
touch "$APHOTIC_GREETER_HYPR_CONF"

# Blocked: nothing touches systemd or /etc.
reset_env; DETECTED_OMARCHY=1
activate_greetd >/dev/null
[[ -s "$LOG" ]] && fail "a blocked switch must not call systemctl, got: $(cat "$LOG")"
[[ -f "$APHOTIC_GREETD_CONFIG" ]] && fail "a blocked switch must not write config.toml"

# An older greetd config gets backed up once, then replaced.
reset_env
echo 'command = "Hyprland --config /etc/greetd/aphotic/hyprland-greeter.conf"' > "$APHOTIC_GREETD_CONFIG"
activate_greetd >/dev/null
grep -q 'hyprland-greeter.conf' "$APHOTIC_GREETD_BACKUP" || fail "the previous config.toml must be backed up"
grep -q 'start-hyprland' "$APHOTIC_GREETD_CONFIG" || fail "config.toml must use the current greeter command"
grep -q 'disable sddm.service' "$LOG" || fail "sddm must be disabled"
grep -q 'enable greetd.service' "$LOG" || fail "greetd must be enabled"

# Already on greetd: refresh the config, leave services alone.
reset_env; touch "$WORKDIR/greetd-enabled"
activate_greetd >/dev/null
grep -q 'disable sddm' "$LOG" && fail "an existing greetd setup must not touch sddm"
rm "$WORKDIR/greetd-enabled"

reset_env; DRY_RUN=1; rm -f "$APHOTIC_GREETD_CONFIG"
activate_greetd >/dev/null
[[ -f "$APHOTIC_GREETD_CONFIG" ]] && fail "dry-run must not write config.toml"

echo "PASS: display manager switch"
