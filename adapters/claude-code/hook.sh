#!/usr/bin/env bash
#
# Claude Code PreToolUse adapter for procview.  GPL-3.0-or-later.
# Vibecoded by Daniel Carmon and Claude Opus 4.8.
#
# Parses Claude Code's PreToolUse JSON (stdin), asks the shared capture core to
# wrap the command, and returns it via updatedInput. Fail-open; disable with
# RUNLOG_HOOK_OFF=1. The permission model is untouched (no permissionDecision).

CORE="${PROCVIEW_CORE:-$HOME/.local/share/procview/capture-core.sh}"

input="$(cat)"
[ "${RUNLOG_HOOK_OFF:-0}" = "1" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
[ "$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)" = "Bash" ] || exit 0

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$cmd" ] || exit 0
case "$cmd" in *"__RUNLOG_TEE__"*) exit 0 ;; esac

session="$(printf '%s' "$input" | jq -r '.session_id // "nosession"' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
desc="$(printf '%s' "$input" | jq -r '.tool_input.description // empty' 2>/dev/null | tr '\n\t' '  ')"
tmux_name=""
[ -n "${TMUX:-}" ] && tmux_name="$(tmux display-message -p -t "${TMUX_PANE:-}" '#S' 2>/dev/null || tmux display-message -p '#S' 2>/dev/null)"

wrapped="$(PV_CMD="$cmd" PV_DESC="$desc" PV_AGENT=claude PV_SESSION="$session" PV_CWD="$cwd" PV_TMUX="$tmux_name" bash "$CORE" 2>/dev/null)"
[ -n "$wrapped" ] || exit 0

jq -n --arg cmd "$wrapped" '{hookSpecificOutput:{hookEventName:"PreToolUse", updatedInput:{command:$cmd}}}' 2>/dev/null || exit 0
