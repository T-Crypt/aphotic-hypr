import { spawn } from "node:child_process";
import os from "node:os";
import path from "node:path";

const HOOK_PATH = path.join(os.homedir(), "Aphotic-Hypr", "Configs", ".local", "lib", "aphotic", "agent_hook.py");

const TOOL_NAMES = {
  bash: "Bash",
  read: "Read",
  write: "Write",
  edit: "Edit",
  grep: "Grep",
  glob: "Glob",
  webfetch: "WebFetch",
  websearch: "WebSearch",
  task: "Task",
  todowrite: "TodoWrite",
  todoread: "TodoRead",
  patch: "Edit",
};

function normalizeTool(name) {
  if (!name)
    return name;
  const lower = name.toLowerCase();
  if (TOOL_NAMES[lower])
    return TOOL_NAMES[lower];
  return name.charAt(0).toUpperCase() + name.slice(1);
}

function send(payload) {
  const child = spawn("python3", [HOOK_PATH], { stdio: ["pipe", "ignore", "ignore"] });
  child.on("error", () => {});
  child.stdin.on("error", () => {});
  child.stdin.write(JSON.stringify({ harness: "opencode", ...payload }));
  child.stdin.end();
}

export const AphoticAgentTracking = async ({ directory }) => {
  const models = new Map();
  const toolStarts = new Map();
  const known = new Set();

  return {
    event: async ({ event }) => {
      switch (event.type) {
        case "session.created": {
          const info = event.properties.info;
          known.add(info.id);
          send({
            session_id: info.id,
            hook_event_name: "SessionStart",
            cwd: info.directory || directory,
            model: models.get(info.id) || "",
          });
          break;
        }
        case "session.idle": {
          const id = event.properties.sessionID;
          if (!known.has(id))
            break;
          send({ session_id: id, hook_event_name: "Stop" });
          break;
        }
        case "session.deleted": {
          const id = event.properties.info.id;
          if (!known.has(id))
            break;
          send({ session_id: id, hook_event_name: "SessionEnd" });
          known.delete(id);
          models.delete(id);
          break;
        }
      }
    },
    "chat.params": async input => {
      if (!input.sessionID || !input.model)
        return;
      const resolved = `${input.model.providerID}/${input.model.id}`;
      const isNew = models.get(input.sessionID) !== resolved;
      models.set(input.sessionID, resolved);
      // session.created fires before the first chat.params call, so the
      // model is always unknown at that point -- send a follow-up
      // SessionStart-shaped update the first time it resolves (or changes
      // mid-session) so the graph label picks it up instead of staying on
      // the session id fallback.
      if (isNew && known.has(input.sessionID))
        send({ session_id: input.sessionID, hook_event_name: "SessionStart", model: resolved });
    },
    "tool.execute.before": async input => {
      toolStarts.set(input.callID, Date.now());
      send({
        session_id: input.sessionID,
        hook_event_name: "PreToolUse",
        tool_name: normalizeTool(input.tool),
        tool_use_id: input.callID,
      });
    },
    "tool.execute.after": async input => {
      const startedAt = toolStarts.get(input.callID);
      toolStarts.delete(input.callID);
      send({
        session_id: input.sessionID,
        hook_event_name: "PostToolUse",
        tool_name: normalizeTool(input.tool),
        tool_use_id: input.callID,
        duration_ms: startedAt ? Date.now() - startedAt : undefined,
      });
    },
    dispose: async () => {
      for (const id of known)
        send({ session_id: id, hook_event_name: "SessionEnd" });
      known.clear();
      models.clear();
      toolStarts.clear();
    },
  };
};
