#!/usr/bin/env bash
#
# agentps installer.  Vibecoded by Daniel Carmon and Claude Opus 4.8.  GPL-3.0-or-later.
#
# Installs the `agentps` CLI, the shared capture core, and a capture adapter for
# each AI coding agent you use (Claude Code, Codex, OpenCode). Every agent tees
# its shell commands into ~/.runlogs so `agentps` can show them live.
#
#   ./install.sh                      install CLI + core + auto-detected agents
#   ./install.sh --agent claude,opencode   install for specific agents
#   ./install.sh --skip-cli           wire core+adapters only (used by npm postinstall)
#   ./install.sh uninstall            remove everything and deregister hooks
#
# Env: PREFIX (default ~/.local), CLAUDE_CONFIG_DIR (~/.claude),
#      CODEX_HOME (~/.codex), OPENCODE_CONFIG_DIR (~/.config/opencode).

set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PREFIX="${PREFIX:-$HOME/.local}"
BINDIR="$PREFIX/bin"
COREDIR="$HOME/.local/share/agentps"
CORE_DEST="$COREDIR/capture-core.sh"
BIN_DEST="$BINDIR/agentps"

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
OPENCODE_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"

msg(){ printf '\033[1;36m==>\033[0m %s\n' "$*"; }
sub(){ printf '    %s\n' "$*"; }
warn(){ printf '\033[1;33mNote:\033[0m %s\n' "$*"; }
err(){ printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; }

# ---- jq is REQUIRED: adapters parse the agent's hook JSON with it, and the
#      installer edits settings.json with it. Without jq, capture silently no-ops.
ensure_jq(){
    command -v jq >/dev/null 2>&1 && return 0
    warn "jq is required but missing — attempting to install it…"
    if   command -v apt-get >/dev/null 2>&1; then { sudo -n apt-get install -y jq || sudo apt-get install -y jq; } >/dev/null 2>&1
    elif command -v brew    >/dev/null 2>&1; then brew install jq >/dev/null 2>&1
    elif command -v dnf     >/dev/null 2>&1; then sudo dnf install -y jq >/dev/null 2>&1
    elif command -v yum     >/dev/null 2>&1; then sudo yum install -y jq >/dev/null 2>&1
    elif command -v pacman  >/dev/null 2>&1; then sudo pacman -S --noconfirm jq >/dev/null 2>&1
    elif command -v apk     >/dev/null 2>&1; then sudo apk add jq >/dev/null 2>&1; fi
    if command -v jq >/dev/null 2>&1; then msg "installed jq"; else
        err "jq is MISSING and could not be auto-installed — agentps capture will NOT work."
        err "Install it, then re-run this installer:  sudo apt-get install -y jq   (or brew/dnf/yum/apk)"
    fi
}

# ---- agent detection ----
detect_agents(){
    local a=()
    { [ -d "$CLAUDE_DIR" ]   || command -v claude   >/dev/null 2>&1; } && a+=(claude)
    { [ -d "$OPENCODE_DIR" ] || command -v opencode >/dev/null 2>&1; } && a+=(opencode)
    { [ -d "$CODEX_DIR" ]    || command -v codex    >/dev/null 2>&1; } && a+=(codex)
    printf '%s ' "${a[@]}"
}

# ---- idempotent Claude/Codex PreToolUse registration (jq) ----
register_json_hook(){   # $1=settings file  $2=hook command  $3="claude"|"codex"
    local file="$1" cmd="$2"
    command -v jq >/dev/null 2>&1 || { warn "jq missing; add PreToolUse hook to $file manually -> $cmd"; return 0; }
    mkdir -p "$(dirname "$file")"; [ -f "$file" ] || echo '{}' > "$file"
    local tmp; tmp="$(mktemp)"
    jq --arg cmd "$cmd" '
        .hooks //= {} | .hooks.PreToolUse //= [] |
        .hooks.PreToolUse |= map(select(([.hooks[]?.command] | index($cmd)) | not)) |
        .hooks.PreToolUse += [{matcher:"Bash", hooks:[{type:"command", command:$cmd}]}]
    ' "$file" > "$tmp" 2>/dev/null && mv "$tmp" "$file" || { rm -f "$tmp"; warn "could not edit $file"; }
}
deregister_json_hook(){ # $1=file $2=cmd
    local file="$1" cmd="$2" tmp
    command -v jq >/dev/null 2>&1 || return 0; [ -f "$file" ] || return 0
    tmp="$(mktemp)"
    jq --arg cmd "$cmd" 'if .hooks.PreToolUse then .hooks.PreToolUse |= map(select(([.hooks[]?.command] | index($cmd)) | not)) else . end' \
        "$file" > "$tmp" 2>/dev/null && mv "$tmp" "$file" || rm -f "$tmp"
}

# ---- per-agent wiring ----
wire_claude(){
    local dest="$CLAUDE_DIR/hooks/agentps-capture.sh"
    mkdir -p "$CLAUDE_DIR/hooks"; install -m 0755 "$here/adapters/claude-code/hook.sh" "$dest"
    register_json_hook "$CLAUDE_DIR/settings.json" "$dest" claude
    sub "Claude Code   -> $dest  (registered in settings.json)"
}
unwire_claude(){
    local dest="$CLAUDE_DIR/hooks/agentps-capture.sh"
    deregister_json_hook "$CLAUDE_DIR/settings.json" "$dest"; rm -f "$dest"
    sub "Claude Code   removed"
}
wire_codex(){
    local dest="$CODEX_DIR/hooks/agentps-capture.sh"
    mkdir -p "$CODEX_DIR/hooks"; install -m 0755 "$here/adapters/codex/hook.sh" "$dest"
    register_json_hook "$CODEX_DIR/hooks.json" "$dest" codex
    sub "Codex (exp.)  -> $dest  (registered in hooks.json)"
}
unwire_codex(){
    local dest="$CODEX_DIR/hooks/agentps-capture.sh"
    deregister_json_hook "$CODEX_DIR/hooks.json" "$dest"; rm -f "$dest"
    sub "Codex         removed"
}
wire_opencode(){
    mkdir -p "$OPENCODE_DIR/plugin"
    install -m 0644 "$here/adapters/opencode/agentps-capture.ts" "$OPENCODE_DIR/plugin/agentps-capture.ts"
    sub "OpenCode      -> $OPENCODE_DIR/plugin/agentps-capture.ts  (auto-loads)"
}
unwire_opencode(){
    rm -f "$OPENCODE_DIR/plugin/agentps-capture.ts"
    sub "OpenCode      removed"
}

# ---- args ----
ACTION=install; AGENTS=""; SKIP_CLI=0
for arg in "$@"; do
    case "$arg" in
        uninstall) ACTION=uninstall ;;
        --skip-cli) SKIP_CLI=1 ;;
        --agent=*|--agents=*) AGENTS="${arg#*=}" ;;
        --agent|--agents) shift; AGENTS="${1:-}" ;;   # tolerate space form under set -u
        -h|--help) echo "usage: ./install.sh [uninstall] [--agent a,b] [--skip-cli]"; exit 0 ;;
    esac
done
AGENTS="${AGENTS//,/ }"
[ -n "$AGENTS" ] || AGENTS="$(detect_agents)"

if [ "$ACTION" = install ]; then
    ensure_jq
    if [ "$SKIP_CLI" = 0 ]; then
        msg "CLI      -> $BIN_DEST"
        mkdir -p "$BINDIR"; install -m 0755 "$here/bin/agentps" "$BIN_DEST"
    fi
    msg "Core     -> $CORE_DEST"
    mkdir -p "$COREDIR"; install -m 0755 "$here/lib/capture-core.sh" "$CORE_DEST"
    msg "Agents   ($(echo $AGENTS))"
    [ -n "$AGENTS" ] || warn "no agents detected — pass --agent claude,opencode,codex"
    for ag in $AGENTS; do
        case "$ag" in
            claude)   wire_claude ;;
            codex)    wire_codex ;;
            opencode) wire_opencode ;;
            *) warn "unknown agent: $ag" ;;
        esac
    done
    if [ "$SKIP_CLI" = 0 ]; then
        case ":$PATH:" in *":$BINDIR:"*) : ;; *) warn "$BINDIR not on PATH — add: export PATH=\"$BINDIR:\$PATH\"" ;; esac
    fi
    msg "Done. Start a NEW agent session (hooks load at startup), then run:  agentps"
else
    msg "Uninstalling agentps"
    for ag in claude codex opencode; do
        case "$ag" in claude) unwire_claude ;; codex) unwire_codex ;; opencode) unwire_opencode ;; esac
    done
    rm -f "$BIN_DEST" "$CORE_DEST"; rmdir "$COREDIR" 2>/dev/null || true
    msg "Removed CLI, core, and all adapters. Capture logs under ~/.runlogs were left intact."
fi
