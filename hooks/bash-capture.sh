#!/usr/bin/env bash
# Part of procview <https://github.com/danielcarmon/procview>.
# Copyright (C) 2026 Daniel Carmon.  GNU GPL v3.0-or-later.
# Vibecoded by Daniel Carmon and Claude Opus 4.8.
# PreToolUse hook (matcher: Bash). Rewrites every Bash command so the harness
# tees its output — live — to a per-command logfile under $RUNLOG_DIR/<session>/.
# This makes EVERY process Claude Code runs visible in the `procview` viewer,
# without Claude having to cooperate.
#
# Fail-open: on any error we emit nothing and exit 0, so the original command
# runs unwrapped rather than being blocked. Disable entirely with RUNLOG_HOOK_OFF=1.

RUNLOG_DIR="${RUNLOG_DIR:-$HOME/.runlogs}"

input="$(cat)"

# global kill-switch (env inherited from the Claude Code process)
[ "${RUNLOG_HOOK_OFF:-0}" = "1" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)"
[ "$tool" = "Bash" ] || exit 0

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$cmd" ] || exit 0

# never double-wrap (defensive; the hook sees Claude's original each time anyway)
case "$cmd" in *"__RUNLOG_TEE__"*) exit 0 ;; esac

session="$(printf '%s' "$input" | jq -r '.session_id // "nosession"' 2>/dev/null)"
session="${session//[^A-Za-z0-9._-]/_}"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"

sdir="$RUNLOG_DIR/$session"
mkdir -p "$sdir" 2>/dev/null || exit 0

stamp="$(date +%Y%m%d_%H%M%S)"
ns="$(date +%N)"
# slug = first token that isn't a VAR=value assignment, basename'd
slug="$(printf '%s' "$cmd" | tr '\n' ' ' | awk '{for(i=1;i<=NF;i++){if($i !~ /^[A-Za-z_][A-Za-z0-9_]*=/){print $i; exit}}}')"
slug="$(basename -- "${slug:-cmd}" 2>/dev/null)"
slug="${slug//[^A-Za-z0-9._-]/_}"
slug="${slug:0:40}"
log="$sdir/${stamp}_${ns}_${slug}.log"

# logfile header (hook runs before the command executes)
cmd_hdr="${cmd//$'\n'/ ↵ }"; cmd_hdr="${cmd_hdr//$'\t'/ }"   # flatten to ONE header line
tmux_name=""                                                # record tmux session name if running under tmux
[ -n "${TMUX:-}" ] && tmux_name="$(tmux display-message -p -t "${TMUX_PANE:-}" '#S' 2>/dev/null || tmux display-message -p '#S' 2>/dev/null)"
{
  printf '### cmd : %s\n' "$cmd_hdr"
  printf '### cwd : %s\n' "$cwd"
  printf '### tmux: %s\n' "$tmux_name"
  printf '### time: %s\n' "$stamp"
} > "$log" 2>/dev/null || exit 0

# convenience symlink to the newest log across everything
ln -sf "$log" "$RUNLOG_DIR/latest.log" 2>/dev/null

qlog="$(printf '%q' "$log")"
nl=$'\n'

# Wrapped command:
#  - braces (not a subshell) so `cd` still persists per Claude Code's cwd tracking
#  - original command on its own lines (avoids trailing-comment / operator breakage)
#  - PYTHONUNBUFFERED for live Python output; 2>&1 merges stderr so nothing is lost
#  - PIPESTATUS captures the REAL exit code -> logged and re-exited (let it crash)
#  - __RUNLOG_TEE__ marker doubles as the double-wrap guard above
wrapped="export PYTHONUNBUFFERED=1${nl}"
wrapped+="printf '### pid: %s\\n' \$\$ >> ${qlog}${nl}"   # record shell pid for live RAM/CPU stats
wrapped+="{${nl}${cmd}${nl}} 2>&1 | tee -a ${qlog}  # __RUNLOG_TEE__${nl}"
wrapped+="__rc=\${PIPESTATUS[0]}${nl}"
wrapped+="printf '\\n### [exit %s] %s\\n' \"\$__rc\" \"\$(date +%H:%M:%S)\" >> ${qlog}${nl}"
wrapped+="exit \$__rc"

# emit decision (jq handles all JSON escaping). permissionDecision left UNSET here;
# see settings — we rely on the existing permission model matching the original cmd.
jq -n --arg cmd "$wrapped" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    updatedInput: { command: $cmd }
  }
}' 2>/dev/null || exit 0
