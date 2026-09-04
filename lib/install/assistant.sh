#!/usr/bin/env bash
set -euo pipefail

# Small, broadly-compatible default when llmfit isn't installed yet (e.g.
# the llmfit ai-layer integration hasn't landed on this branch) or hardware
# detection fails -- picked for safety on VRAM, not quality: this is what
# the Assistant runs on when a real per-machine recommendation isn't
# available, and it should never fail an install over that.
ASSISTANT_FALLBACK_MODEL="llama3.1:8b"

# ASSISTANT is "" (unset -- ask, or default no if unattended), "true", or
# "false". Set directly by --with-assistant/--no-assistant in install.sh's
# flag parser; resolved here otherwise. Requires $ISNVIDIA and $LAYERS to
# already be set by the caller.
resolve_assistant() {
  if [[ "$ISNVIDIA" != "true" ]]; then
    if [[ "$ASSISTANT" == "true" ]]; then
      echo -e "$CWR - --with-assistant needs an NVIDIA GPU; no NVIDIA GPU detected, skipping the Aphotic Assistant."
    fi
    ASSISTANT="false"
    return
  fi

  if [[ -n "$ASSISTANT" ]]; then
    if [[ "$ASSISTANT" == "true" && ",$LAYERS," != *",ai,"* ]]; then
      LAYERS="${LAYERS:+$LAYERS,}ai"
      echo -e "$CNT - Aphotic Assistant requires the 'ai' layer; adding it."
    fi
    return
  fi

  if [[ ",$LAYERS," == *",ai,"* ]]; then
    echo -e "\n$CNT - The Aphotic Assistant is a chatbot that runs entirely on this machine and can"
    echo -e "$CNT   answer questions about your desktop. It downloads a language model of a few GB."
    if confirm "Install the Aphotic Assistant?" y; then
      ASSISTANT="true"
    else
      ASSISTANT="false"
    fi
  else
    echo -e "\n$CNT - The Aphotic Assistant is a chatbot that runs entirely on this machine, but it"
    echo -e "$CNT   needs the AI extras (Ollama) you didn't select, and downloads a model of a few GB."
    if confirm "Add the AI extras and install the Assistant?" n; then
      ASSISTANT="true"
      LAYERS="${LAYERS:+$LAYERS,}ai"
    else
      ASSISTANT="false"
    fi
  fi
}

# Prints an Ollama tag on stdout and returns 0, or returns 1 with nothing
# printed (caller falls back to ASSISTANT_FALLBACK_MODEL). Mirrors the
# llm-fit plugin's qml/LlmFitService.qml guessOllamaTag() (extracted from
# the shell's own services/LlmFit.qml, PLG-02) -- keep the two in sync if
# this changes, since there's no shared implementation between bash and
# QML to point at instead. This function itself calls `llmfit` directly
# and is independent of whether that plugin is installed.
#
# Real bug found and fixed here (2026-08-29): this used to GUESS an Ollama
# tag from any recommended model's raw name/param-count via regex, with no
# check that the model was actually an Ollama-pullable one. llmfit's
# recommendation pool is dominated by community fine-tunes in vLLM/AWQ/
# GPTQ quantized formats (every field-tested candidate on a 24GB-VRAM
# RTX 4090 had `ollama_name: null`) -- the guess heuristic happily turned
# one of those into a plausible-looking tag like `louismuk/gemma:26.6b`,
# which isn't a real Ollama registry entry. `ollama pull` for that tag
# failed near-instantly (~200ms, confirmed via the ollama.service journal,
# not assumed) with no visible error surfaced to the user beyond a generic
# install warning -- `~/.config/aphotic/assistant-system-prompt.md` got
# rendered (that step doesn't depend on the pull succeeding) but
# `ai-config.json` was never written, so the Assistant silently never
# became available as a provider despite the install otherwise finishing
# and reporting done. Fixed: only trust a candidate that llmfit itself
# marks as having a real Ollama tag (`ollama_name` populated) -- use that
# tag directly, never a guess. When no candidate qualifies (the common
# case on high-VRAM hardware today, where llmfit's top picks skew toward
# non-Ollama formats), this correctly returns failure so the caller falls
# through to the known-safe, always-real ASSISTANT_FALLBACK_MODEL instead
# of a plausible-but-broken guess.
resolve_assistant_model_via_llmfit() {
  command -v llmfit >/dev/null 2>&1 || return 1

  local json
  json=$(llmfit recommend --json --limit 15 --use-case general --min-fit good 2>>"$INSTLOG") || return 1

  # A python script fed via stdin (`python3 -`) can't ALSO read its input
  # data from stdin -- the interpreter already consumes stdin as the
  # program source. Write the script to a real temp file instead and pipe
  # the JSON into that.
  local py_script
  py_script=$(mktemp)
  cat > "$py_script" <<'PYEOF'
import json, re, sys

data = json.load(sys.stdin)
candidates = [
    m for m in data.get("models", [])
    if m.get("fit_level") in ("Perfect", "Good") and m.get("ollama_name")
]
if not candidates:
    sys.exit(1)

def param_b(m):
    match = re.search(r"([\d.]+)", (m.get("parameter_count") or "").lower())
    return float(match.group(1)) if match else 0.0

candidates.sort(key=param_b)
mid = candidates[(len(candidates) - 1) // 2]
print(mid["ollama_name"])
PYEOF

  local tag rc
  tag=$(printf '%s' "$json" | "$PYTHON_BIN" "$py_script" 2>>"$INSTLOG")
  rc=$?
  rm -f "$py_script"
  [[ $rc -eq 0 && -n "$tag" ]] || return 1
  printf '%s\n' "$tag"
}

# Renders lib/ai/aphotic-assistant-prompt.md's {{PROFILE}}/{{LAYERS}}/
# {{THEME}} placeholders with this install's resolved values and writes the
# result to ~/.config/aphotic/assistant-system-prompt.md, which
# AiProviders.qml reads as plain text -- no TOML parser needed at shell
# runtime. A snapshot, not live: if layers/theme change later, this stays
# as it was at install time until install.sh runs again. Theme especially
# can drift quickly (theme switching is a everyday action, this file isn't
# regenerated when it happens) -- a known, accepted gap for this pass, not
# an oversight.
render_assistant_prompt() {
  local profile="$1" layers="$2" theme="$3" dest_dir="$HOME/.config/aphotic"
  mkdir -p "$dest_dir"
  sed -e "s/{{PROFILE}}/${profile}/g" -e "s/{{LAYERS}}/${layers:-none}/g" -e "s/{{THEME}}/${theme}/g" \
    "$ROOT_DIR/lib/ai/aphotic-assistant-prompt.md" > "$dest_dir/assistant-system-prompt.md"
}

# Merges assistant fields into ai-config.json (~/.config/aphotic/) without
# clobbering activeProvider/ollamaHost/ollamaModel, which the QML side
# writes to the same file -- read-modify-write, matching the "same file,
# not a separate untracked one" requirement.
write_assistant_config() {
  local model="$1" installed_at="$2" dest_dir="$HOME/.config/aphotic"
  mkdir -p "$dest_dir"
  "$PYTHON_BIN" - "$dest_dir/ai-config.json" "$model" "$installed_at" <<'PYEOF'
import json, sys

path, model, installed_at = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
data["assistantEnabled"] = True
data["assistantModel"] = model
data["assistantInstalledAt"] = installed_at
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PYEOF
}

# Ensures a local Ollama service is actually running (the ai layer alone
# doesn't imply this -- Settings -> AI supports pointing at a remote LAN
# host instead, so this only runs when the Assistant specifically needs a
# model pulled onto THIS machine), resolves a model (llmfit if available,
# else the fallback), pulls it, and records the result. Never exits the
# install over a pull failure -- the Assistant just stays unconfigured
# until the user runs `ollama pull <model>` themselves.
setup_assistant() {
  # The `ai` layer is a hard prerequisite, not a nicety: it is what installs
  # Ollama, and the shell now drops every locally-hosted provider (the
  # Assistant included) when the layer is off, so an Assistant installed
  # without it would pull several GB for a pill that never renders.
  # resolve_assistant already adds the layer for every path that sets
  # ASSISTANT=true, so reaching here without it means something upstream
  # changed -- refuse rather than pull the model anyway.
  if [[ ",$LAYERS," != *",ai,"* ]]; then
    echo -e "$CER - The Aphotic Assistant needs the 'ai' layer, which isn't enabled; skipping it."
    return 1
  fi

  echo -e "$CNT - Setting up the Aphotic Assistant..."
  render_assistant_prompt "$PROFILE" "$LAYERS" "$THEME"

  if [[ "$DRY_RUN" != "1" ]]; then
    sudo systemctl enable --now ollama.service &>> "$INSTLOG" || echo -e "$CWR - Could not enable ollama.service; start Ollama yourself before the Assistant can pull/use a model."
  fi

  local model="" source_label=""
  model=$(resolve_assistant_model_via_llmfit || true)
  if [[ -n "$model" ]]; then
    source_label="llmfit recommendation"
  else
    model="$ASSISTANT_FALLBACK_MODEL"
    if command -v llmfit >/dev/null 2>&1; then
      source_label="fallback (llmfit ran but returned nothing usable)"
    else
      source_label="fallback (llmfit not installed)"
    fi
  fi

  echo -e "$COK - Aphotic Assistant model: $model [$source_label]"

  if [[ "$DRY_RUN" == "1" ]]; then
    echo -e "$CNT - [dry-run] would pull $model for the Aphotic Assistant"
    return 0
  fi

  echo -e "$CNT - Pulling $model (this can take a while)..."
  if ! ollama pull "$model" &>> "$INSTLOG"; then
    echo -e "$CER - Failed to pull $model; the Aphotic Assistant is disabled until you run: ollama pull $model"
    return 1
  fi

  write_assistant_config "$model" "$(date -Iseconds)"
  echo -e "$COK - Aphotic Assistant installed with model: $model"
}
