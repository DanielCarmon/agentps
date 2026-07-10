// procview capture plugin for OpenCode.
// Vibecoded by Daniel Carmon and Claude Opus 4.8.  GPL-3.0-or-later.
//
// Tees every bash command OpenCode runs into ~/.runlogs so `procview` can show
// it live. Delegates the actual wrapping to the shared, agent-agnostic core at
// ~/.local/share/procview/capture-core.sh, so Claude Code / Codex / OpenCode all
// produce identical logs.
//
// Auto-loaded by OpenCode from ~/.config/opencode/plugin/ (no registration needed).

import { execFileSync } from "node:child_process"
import { homedir } from "node:os"
import { join } from "node:path"

const CORE = process.env.PROCVIEW_CORE || join(homedir(), ".local", "share", "procview", "capture-core.sh")

export const ProcviewCapture = async ({ directory }) => {
  return {
    "tool.execute.before": async (input, output) => {
      if (input.tool !== "bash") return
      try {
        const cmd = String((output.args && output.args.command) || "")
        if (!cmd) return
        const wrapped = execFileSync("bash", [CORE], {
          env: {
            ...process.env,
            PV_CMD: cmd,
            PV_DESC: String((output.args && output.args.description) || ""),
            PV_AGENT: "opencode",
            PV_SESSION: input.sessionID || "opencode",
            PV_CWD: directory || process.cwd(),
          },
          encoding: "utf8",
          maxBuffer: 64 * 1024 * 1024,
        })
        if (wrapped) output.args.command = wrapped
      } catch (e) {
        // fail-open: never block a command because capture failed
      }
    },
  }
}
