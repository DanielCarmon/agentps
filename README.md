# procview

**See — and live-watch — every process Claude Code runs.**

By default, when Claude Code runs a shell command you don't see much: output is
collapsed, long jobs just hang with no live feedback, and once a command scrolls
away it's gone. `procview` fixes that. A `PreToolUse` hook tees **every** Bash
command Claude Code runs — automatically, no cooperation from the model — into a
per-command logfile under `~/.runlogs/`, and a terminal UI lets you browse them,
follow any one live, and watch real-time **CPU/RAM** per process.

```
 #  TMUX  SESSION   START     DUR   END       STATUS       CPU   RAM  COMMAND
  1  work  8f3a1c2b  14:22:07  6m01s -         ● running    98%  1.8G  python train.py --epochs 50 ↵ ...
  2  work  8f3a1c2b  14:21:55     3s 14:21:58  ✔ exit 0       -     -  git status --short
  3  -     8f3a1c2b  14:19:30    12s 14:19:42  ✗ exit 1       -     -  pytest -q ↵ ...
```

## Why

- **Live output**, even for long jobs — follow any process with a real-time tail.
- **Nothing gets lost** — every command is on disk (a "black box"), full output
  preserved even when Claude's own view is truncated.
- **Resource visibility** — live CPU% and RAM (RSS, whole subtree) per running
  process. Handy for spotting the job that's about to OOM your box.
- **Zero cooperation required** — it's a harness hook, so it captures *everything*,
  not only what the model remembers to log.

## Install

```sh
git clone https://github.com/danielcarmon/procview
cd procview
make install        # installs to ~/.local/bin; override with PREFIX=/usr/local
```

This installs the `procview` CLI and registers the capture hook in
`~/.claude/settings.json` (needs `jq`). **Start a new Claude Code session**
afterwards — hooks load at startup.

Requirements: `bash` 4.2+, `jq`, `tmux`/`less`/`vim` for the viewers, `tput`.

## Usage

```sh
procview                 # interactive TUI (newest Claude session)
procview all             # every session
procview watch           # read-only auto-refreshing dashboard
procview last            # jump straight to live-tailing the most recent process
procview list            # one-shot table, no TUI
procview clean [days]    # prune capture logs older than N days (default 7)
```

**Keys:** `↑/↓` (or `j/k`) select · `←/→` (or `h/l`) change a process's view mode
(tail-live / vim / pager) · `Enter` open it · `Tab` focus the "go to #" field ·
`q`/`Esc` quit. Each process remembers the view mode you last used for it.

## How it works

- **Capture** — `hooks/bash-capture.sh` is a `PreToolUse` hook matched to the
  `Bash` tool. It rewrites each command to `{ cmd; } 2>&1 | tee -a <log>`,
  preserving the real exit code, forcing unbuffered output, and recording the
  command, cwd, tmux session, and pid header. Your permission model is untouched
  (it does not set `permissionDecision`). Disable per-session with
  `RUNLOG_HOOK_OFF=1`.
- **View** — `bin/procview` reads `~/.runlogs/<session>/*.log`, caches per-file
  metadata, and pulls live CPU/RAM from a single `ps` snapshot per refresh. The
  TUI is flicker-free (alternate screen + in-place redraw) and fork-free on
  keypress, so navigation stays instant.

## Uninstall

```sh
make uninstall     # removes the CLI + hook and deregisters it; keeps ~/.runlogs
```

## License

GNU General Public License v3.0 or later — see [LICENSE](LICENSE).

*Vibecoded by Daniel Carmon and Claude Opus 4.8.*
