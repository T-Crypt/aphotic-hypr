#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $1"; exit 1; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
TESTHOME="$WORKDIR/home"
mkdir -p "$TESTHOME/.local/bin"
LOG="$WORKDIR/aphotic.log"

cat > "$TESTHOME/.local/bin/aphotic" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "$LOG"
EOF
chmod +x "$TESTHOME/.local/bin/aphotic"

cat > "$WORKDIR/harness.lua" <<'EOF'
local home = os.getenv("TEST_HOME")
local log = os.getenv("APHOTIC_TEST_LOG")

local function shell_quote(value)
    return "'" .. value:gsub("'", "'\\\\''") .. "'"
end

hl = {}
function hl.on(name, callback)
    assert(name == "hyprland.start")
    callback()
end

function hl.exec_cmd(command)
    if command:match("^aphotic ") or command:match("^~/.local/bin/aphotic ") then
        local wrapped = "env -i HOME=" .. shell_quote(home) ..
            " PATH='/usr/bin:/bin' sh -c " .. shell_quote(command .. " >> " .. shell_quote(log))
        local ok, _, status = os.execute(wrapped)
        assert(ok == true and status == 0, "startup command failed: " .. command)
    end
end

dofile(os.getenv("APHOTIC_STARTUP"))
EOF

TEST_HOME="$TESTHOME" APHOTIC_TEST_LOG="$LOG" APHOTIC_STARTUP="$ROOT/Configs/hypr/startup.lua" \
  lua "$WORKDIR/harness.lua" \
  || fail "startup could not resolve Aphotic CLI without ~/.local/bin on PATH"

grep -qx 'theme ensure-default' "$LOG" \
  || fail "startup did not execute theme ensure-default through the user-local CLI"
grep -qx 'vpn autostart' "$LOG" \
  || fail "startup did not execute vpn autostart through the user-local CLI"
grep -qx 'whatsnew' "$LOG" \
  || fail "startup did not execute whatsnew through the user-local CLI"

echo "PASS: startup resolves Aphotic CLI without login PATH"
