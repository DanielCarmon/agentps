#!/usr/bin/env bash
#
# procview installer.  Vibecoded by Daniel Carmon and Claude Opus 4.8.  GNU GPL v3.0-or-later.
#
# Installs the `procview` CLI and wires up the PreToolUse capture hook so that
# EVERY Bash command Claude Code runs is tee'd to ~/.runlogs and viewable live.
#
#   ./install.sh            install (or re-install / upgrade)
#   ./install.sh uninstall  remove the CLI + hook and deregister it
#
# Honors: PREFIX (default ~/.local), CLAUDE_CONFIG_DIR (default ~/.claude).

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PREFIX="${PREFIX:-$HOME/.local}"
BINDIR="$PREFIX/bin"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
HOOKDIR="$CLAUDE_DIR/hooks"
SETTINGS="$CLAUDE_DIR/settings.json"
BIN_DEST="$BINDIR/procview"
HOOK_DEST="$HOOKDIR/procview-capture.sh"

msg(){ printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33mNote:\033[0m %s\n' "$*"; }
err(){ printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; }

register_hook(){
    if ! command -v jq >/dev/null 2>&1; then
        warn "jq not found — cannot auto-edit settings.json. Add this PreToolUse hook manually:"
        printf '  matcher "Bash"  ->  command: %s\n' "$HOOK_DEST"
        return 0
    fi
    mkdir -p "$CLAUDE_DIR"
    [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
    local tmp; tmp="$(mktemp)"
    # idempotent: drop any prior entry that references our hook, then add a clean one
    jq --arg cmd "$HOOK_DEST" '
        .hooks //= {} |
        .hooks.PreToolUse //= [] |
        .hooks.PreToolUse |= map(select(([.hooks[]?.command] | index($cmd)) | not)) |
        .hooks.PreToolUse += [{matcher:"Bash", hooks:[{type:"command", command:$cmd}]}]
    ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
}

deregister_hook(){
    command -v jq >/dev/null 2>&1 || { warn "jq not found — remove the hook from $SETTINGS by hand."; return 0; }
    [ -f "$SETTINGS" ] || return 0
    local tmp; tmp="$(mktemp)"
    jq --arg cmd "$HOOK_DEST" '
        if .hooks.PreToolUse then .hooks.PreToolUse |= map(select(([.hooks[]?.command] | index($cmd)) | not)) else . end
    ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
}

do_install(){
    msg "CLI      -> $BIN_DEST"
    mkdir -p "$BINDIR"; install -m 0755 "$here/bin/procview" "$BIN_DEST"
    msg "Hook     -> $HOOK_DEST"
    mkdir -p "$HOOKDIR"; install -m 0755 "$here/hooks/bash-capture.sh" "$HOOK_DEST"
    msg "Register -> $SETTINGS (PreToolUse / Bash)"
    register_hook
    case ":$PATH:" in
        *":$BINDIR:"*) : ;;
        *) warn "$BINDIR is not on your PATH. Add to your shell rc:"; printf '  export PATH="%s:$PATH"\n' "$BINDIR" ;;
    esac
    msg "Installed. Start a NEW Claude Code session (hooks load at startup), then run:  procview"
}

do_uninstall(){
    msg "Removing $BIN_DEST";  rm -f "$BIN_DEST"
    msg "Removing $HOOK_DEST"; rm -f "$HOOK_DEST"
    msg "Deregistering hook from $SETTINGS"; deregister_hook
    msg "Done. Your capture logs under ~/.runlogs were left intact."
}

case "${1:-install}" in
    install)   do_install ;;
    uninstall) do_uninstall ;;
    *) err "usage: $0 [install|uninstall]"; exit 2 ;;
esac
