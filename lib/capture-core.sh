#!/usr/bin/env bash
#
# agentps capture core — agent-agnostic.  Vibecoded by Daniel Carmon and Claude Opus 4.8.  GPL-3.0-or-later.
#
# One source of truth for wrapping a shell command so its live output is tee'd to
# a per-command logfile that `agentps` can display. Every agent adapter (Claude
# Code hook, Codex hook, OpenCode plugin) funnels through this.
#
# Inputs (via environment):
#   PV_CMD      required — the original shell command to run
#   PV_DESC     the agent's one-line command description (optional)
#   PV_AGENT    agent name for the log (claude|codex|opencode|...); default "unknown"
#   PV_SESSION  session id (becomes the ~/.local/share/agentps/runlogs/<session>/ dir); default "nosession"
#   PV_CWD      working directory to record; default $PWD
#   PV_TMUX     tmux session name to record (optional)
#   RUNLOG_DIR  base dir; default ~/.local/share/agentps/runlogs
#
# Output: prints the WRAPPED command on stdout (caller substitutes it for PV_CMD).
# Side effect: writes the log header for this command. Fail-open: on any error it
# prints PV_CMD unchanged so execution is never blocked.

set -u
cmd="${PV_CMD:-}"
[ -z "$cmd" ] && exit 0
# never double-wrap
case "$cmd" in *"__RUNLOG_TEE__"*) printf '%s' "$cmd"; exit 0 ;; esac

RUNLOG_DIR="${RUNLOG_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/agentps/runlogs}"
agent="${PV_AGENT:-unknown}"
session="${PV_SESSION:-nosession}"; session="${session//[^A-Za-z0-9._-]/_}"
cwd="${PV_CWD:-$PWD}"

sdir="$RUNLOG_DIR/$session"
mkdir -p "$sdir" 2>/dev/null || { printf '%s' "$cmd"; exit 0; }

stamp="$(date +%Y%m%d_%H%M%S)"; ns="$(date +%N)"
slug="$(printf '%s' "$cmd" | tr '\n' ' ' | awk '{for(i=1;i<=NF;i++){if($i !~ /^[A-Za-z_][A-Za-z0-9_]*=/){print $i; exit}}}')"
slug="$(basename -- "${slug:-cmd}" 2>/dev/null)"; slug="${slug//[^A-Za-z0-9._-]/_}"; slug="${slug:0:40}"
log="$sdir/${stamp}_${ns}_${slug}.log"

cmd_hdr="${cmd//$'\n'/ ↵ }"; cmd_hdr="${cmd_hdr//$'\t'/ }"   # flatten to ONE header line
{
  printf '### cmd : %s\n'  "$cmd_hdr"
  printf '### desc: %s\n'  "${PV_DESC:-}"
  printf '### cwd : %s\n'  "$cwd"
  printf '### tmux: %s\n'  "${PV_TMUX:-}"
  printf '### agent: %s\n' "$agent"
  printf '### time: %s\n'  "$stamp"
} > "$log" 2>/dev/null || { printf '%s' "$cmd"; exit 0; }
ln -sf "$log" "$RUNLOG_DIR/latest.log" 2>/dev/null

qlog="$(printf '%q' "$log")"; nl=$'\n'
# braces (not subshell) preserve cwd; PIPESTATUS preserves the real exit code;
# pid line enables live RAM/CPU; __RUNLOG_TEE__ is the double-wrap guard.
# After the command, record any background jobs it left (jobs -p) as ### bgpid:
# lines — so detached long jobs (setsid/nohup/&) stay visible as "running".
wrapped="export PYTHONUNBUFFERED=1${nl}"
wrapped+="export AGENTPS_JOB=${qlog}${nl}"   # inherited by every descendant -> agentps finds live jobs via /proc even after detach
wrapped+="printf '### pid: %s\\n' \$\$ >> ${qlog}${nl}"
wrapped+="{${nl}${cmd}${nl}"
wrapped+="__aps_rc=\$?; jobs -p 2>/dev/null | sed 's/^/### bgpid: /' >> ${qlog}; (exit \$__aps_rc)${nl}"
wrapped+="} 2>&1 | tee -a ${qlog}  # __RUNLOG_TEE__${nl}"
wrapped+="__rc=\${PIPESTATUS[0]}${nl}"
wrapped+="printf '\\n### [exit %s] %s\\n' \"\$__rc\" \"\$(date +%H:%M:%S)\" >> ${qlog}${nl}"
wrapped+="exit \$__rc"
printf '%s' "$wrapped"
