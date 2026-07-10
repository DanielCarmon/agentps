# procview

**See — and live-watch — every shell command your AI coding agent runs.**

Works with **Claude Code**, **Codex**, and **OpenCode**. When your agent runs a
shell command, procview tees it — automatically, no cooperation from the model —
into a per-command logfile under `~/.runlogs/`, and a terminal UI lets you browse
them, follow any one live, and watch real-time **CPU/RAM** per process.

```
 #  TMUX  SESSION   START     DUR   END       STATUS      CPU   RAM  DESC                    COMMAND
  1  work  8f3a1c2b  14:22:07  6m01s -         ● running   98%  1.8G  Train the model         python train.py --epochs 50 ↵ ...
  2  work  8f3a1c2b  14:21:55     3s 14:21:58  ✔ exit 0      -     -  Check git status        git status --short
  3  -     oc-9d2e1  14:19:30    12s 14:19:42  ✗ exit 1      -     -  Run the test suite      pytest -q ↵ ...
```

Columns: which **tmux**/**agent session** it ran in, **start / duration / end**,
**status** (running / exit code), live **CPU & RAM** (whole process subtree), the
agent's own one-line **description**, and the **command**.

## Install

**npm** (once the box has Node):
```sh
npm install -g procview
```

**git** (zero Node dependency — just bash + jq):
```sh
git clone https://github.com/DanielCarmon/procview
cd procview && make install
```

Either way this installs the `procview` CLI and wires up a capture adapter for
each agent it detects (Claude Code, Codex, OpenCode). **Start a new agent
session** afterwards — hooks load at startup. Pick specific agents with
`./install.sh --agent claude,opencode`.

Requirements: `bash` 4.2+, `jq`, `tput`; `tmux`/`less`/`vim` for the viewers.

## Usage

```sh
procview                 # interactive TUI (newest session)
procview all             # every session, every agent
procview watch           # read-only auto-refreshing dashboard
procview last            # jump straight to live-tailing the most recent command
procview list            # one-shot table, no TUI
procview clean [days]    # prune capture logs older than N days (default 7)
```

**Keys:** `↑/↓` (or `j/k`) select · `←/→` (or `h/l`) change a process's view mode
(tail-live / vim / pager) · `Enter` open · `Tab` focus the "go to #" field ·
`q`/`Esc` quit. Each process remembers the view mode you last used for it.

## Architecture

One agnostic core, a thin adapter per agent:

```
bin/procview              the viewer (agent-agnostic; just reads ~/.runlogs)
lib/capture-core.sh       shared: wraps a command as { cmd; } 2>&1 | tee <log>,
                          preserving exit code, recording cmd/desc/cwd/tmux/pid/agent
adapters/
  claude-code/hook.sh     PreToolUse hook  → core → updatedInput            (settings.json)
  codex/hook.sh           PreToolUse hook  → core → updatedInput            (hooks.json, experimental)
  opencode/…-capture.ts   tool.execute.before plugin → core                 (auto-loads)
```

Adding an agent = one adapter that hands its command to the core; the log format
and viewer are shared. Your permission model is untouched (no `permissionDecision`).
Disable capture per-session with `RUNLOG_HOOK_OFF=1`.

## Uninstall

```sh
make uninstall     # or: ./install.sh uninstall  — removes CLI, core, all adapters; keeps ~/.runlogs
```

## License

GNU General Public License v3.0 or later — see [LICENSE](LICENSE).

*Vibecoded by Daniel Carmon and Claude Opus 4.8.*
