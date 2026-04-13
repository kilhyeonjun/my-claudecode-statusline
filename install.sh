#!/bin/bash
# my-claudecode-statusline installer
# - Installs ccstatusline globally via bun/npm (if missing)
# - Copies helper scripts into ~/.claude/scripts/
# - Writes ccstatusline config into ~/.config/ccstatusline/settings.json
# - Merges statusLine + Skill hooks into ~/.claude/settings.json (idempotent)
#
# Usage:
#   ./install.sh             # install
#   ./install.sh -n          # dry-run (show what would change, no writes)
#   ./install.sh -v          # verbose
set -euo pipefail

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'
BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'

info() { printf '%s[info]%s %s\n' "$BLUE" "$RESET" "$*"; }
ok()   { printf '%s[ ok ]%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s[warn]%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
err()  { printf '%s[ err]%s %s\n' "$RED" "$RESET" "$*" >&2; }

DRY_RUN=0
VERBOSE=0
while [ $# -gt 0 ]; do
  case "$1" in
    -n|--dry-run) DRY_RUN=1 ;;
    -v|--verbose) VERBOSE=1 ;;
    -h|--help)
      cat <<EOF
Usage: $0 [OPTIONS]

Install my-claudecode-statusline for the current user.

Options:
  -n, --dry-run    Show what would change without writing anything
  -v, --verbose    Show the full merged settings.json diff
  -h, --help       Show this help
EOF
      exit 0
      ;;
    *) err "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="$HOME/.claude"
CLAUDE_SCRIPTS="$CLAUDE_HOME/scripts"
CCSL_CONFIG_DIR="$HOME/.config/ccstatusline"
SETTINGS_JSON="$CLAUDE_HOME/settings.json"
CCSL_SETTINGS="$CCSL_CONFIG_DIR/settings.json"
TEMPLATE="$REPO_DIR/ccstatusline/settings.json"

printf '\n%s==>%s my-claudecode-statusline installer\n' "$BOLD" "$RESET"
[ "$DRY_RUN" = "1" ] && printf '%s(dry-run mode — no files will be modified)%s\n' "$DIM" "$RESET"
printf '\n'

case "$(uname -s)" in
  Darwin) ok "macOS detected" ;;
  Linux)  warn "Linux detected — statusline-subagents.sh uses a BSD/GNU date fallback but is primarily tested on macOS" ;;
  *) err "Unsupported OS: $(uname -s)"; exit 1 ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  err "jq not found. Install with: brew install jq   (or your package manager)"
  exit 1
fi
ok "jq found: $(command -v jq)"

PKG_MGR=""
if command -v bun >/dev/null 2>&1; then
  PKG_MGR="bun"
elif command -v npm >/dev/null 2>&1; then
  PKG_MGR="npm"
else
  err "bun or npm required to install ccstatusline"
  err "  install bun: curl -fsSL https://bun.sh/install | bash"
  err "  or node+npm: brew install node"
  exit 1
fi
ok "$PKG_MGR found: $(command -v "$PKG_MGR")"

CCSL_BIN=""
if command -v ccstatusline >/dev/null 2>&1; then
  CCSL_BIN="$(command -v ccstatusline)"
  ok "ccstatusline already installed at $CCSL_BIN"
else
  info "installing ccstatusline globally via $PKG_MGR"
  if [ "$DRY_RUN" = "1" ]; then
    info "[dry-run] would run: $PKG_MGR $([ "$PKG_MGR" = "bun" ] && echo "add -g" || echo "install -g") ccstatusline"
    CCSL_BIN="(pending install)"
  else
    if [ "$PKG_MGR" = "bun" ]; then
      bun add -g ccstatusline
    else
      npm install -g ccstatusline
    fi
    if ! command -v ccstatusline >/dev/null 2>&1; then
      err "ccstatusline installed but not on PATH. Check your PATH includes $PKG_MGR global bin dir."
      exit 1
    fi
    CCSL_BIN="$(command -v ccstatusline)"
    ok "ccstatusline installed at $CCSL_BIN"
  fi
fi

info "installing helper scripts to $CLAUDE_SCRIPTS"
if [ "$DRY_RUN" = "0" ]; then
  mkdir -p "$CLAUDE_SCRIPTS"
fi
for script in statusline-subagents.sh statusline-burn.sh statusline-rate.sh statusline-model.sh; do
  src="$REPO_DIR/scripts/$script"
  dst="$CLAUDE_SCRIPTS/$script"
  if [ ! -f "$src" ]; then
    err "missing source script: $src"
    exit 1
  fi
  if [ "$DRY_RUN" = "1" ]; then
    info "[dry-run] would install $dst"
  else
    cp "$src" "$dst"
    chmod +x "$dst"
    ok "installed $dst"
  fi
done

info "installing ccstatusline config to $CCSL_SETTINGS"
if [ "$DRY_RUN" = "0" ]; then
  mkdir -p "$CCSL_CONFIG_DIR"
fi
if [ -f "$CCSL_SETTINGS" ] && [ "$DRY_RUN" = "0" ]; then
  backup="$CCSL_SETTINGS.bak-$(date +%Y%m%d-%H%M%S)"
  cp "$CCSL_SETTINGS" "$backup"
  ok "backed up existing config → $backup"
fi

if [ "$DRY_RUN" = "1" ]; then
  info "[dry-run] would substitute __CLAUDE_SCRIPTS__ → $CLAUDE_SCRIPTS and write $CCSL_SETTINGS"
else
  sed "s|__CLAUDE_SCRIPTS__|$CLAUDE_SCRIPTS|g" "$TEMPLATE" > "$CCSL_SETTINGS"
  if ! jq . "$CCSL_SETTINGS" >/dev/null 2>&1; then
    err "generated ccstatusline config is invalid JSON: $CCSL_SETTINGS"
    exit 1
  fi
  ok "installed $CCSL_SETTINGS"
fi

info "merging $SETTINGS_JSON (statusLine + Skill hooks)"
if [ ! -f "$SETTINGS_JSON" ]; then
  if [ "$DRY_RUN" = "1" ]; then
    info "[dry-run] would create empty $SETTINGS_JSON"
  else
    mkdir -p "$CLAUDE_HOME"
    echo '{}' > "$SETTINGS_JSON"
    ok "created empty $SETTINGS_JSON"
  fi
fi

if [ -f "$SETTINGS_JSON" ] && [ "$DRY_RUN" = "0" ]; then
  backup="$SETTINGS_JSON.bak-$(date +%Y%m%d-%H%M%S)"
  cp "$SETTINGS_JSON" "$backup"
  ok "backed up existing settings → $backup"
fi

STATUS_CMD="$CCSL_BIN"
HOOK_CMD="$CCSL_BIN --hook"

if [ -f "$SETTINGS_JSON" ]; then
  input_src="$SETTINGS_JSON"
else
  input_src=/dev/null
fi

merged=$(jq --arg cmd "$STATUS_CMD" --arg hookcmd "$HOOK_CMD" '
  . as $root
  | (if ($root | type) == "object" then $root else {} end)
  | .statusLine = { type: "command", command: $cmd, padding: 0 }
  | .hooks //= {}
  | .hooks.PreToolUse //= []
  | .hooks.PreToolUse |= map(
      .hooks = ((.hooks // []) | map(select(.command | test("ccstatusline.*--hook") | not)))
    )
  | .hooks.PreToolUse |= map(select((.hooks | length) > 0))
  | .hooks.PreToolUse += [{
      matcher: "Skill",
      hooks: [{ type: "command", command: $hookcmd, timeout: 3 }]
    }]
  | .hooks.UserPromptSubmit //= []
  | .hooks.UserPromptSubmit |= map(
      .hooks = ((.hooks // []) | map(select(.command | test("ccstatusline.*--hook") | not)))
    )
  | .hooks.UserPromptSubmit |= map(select((.hooks | length) > 0))
  | .hooks.UserPromptSubmit += [{
      matcher: "",
      hooks: [{ type: "command", command: $hookcmd, timeout: 3 }]
    }]
' "$input_src")

if [ -z "$merged" ]; then
  err "jq merge produced empty output"
  exit 1
fi

if [ "$DRY_RUN" = "1" ]; then
  info "[dry-run] diff of settings.json changes:"
  if [ -f "$SETTINGS_JSON" ]; then
    diff -u <(jq . "$SETTINGS_JSON") <(printf '%s' "$merged" | jq .) || true
  else
    printf '%s' "$merged" | jq .
  fi
else
  printf '%s\n' "$merged" | jq . > "$SETTINGS_JSON"
  ok "merged $SETTINGS_JSON"
  if [ "$VERBOSE" = "1" ]; then
    info "resulting statusLine + hooks section:"
    jq '{statusLine, "hooks.PreToolUse": .hooks.PreToolUse, "hooks.UserPromptSubmit": .hooks.UserPromptSubmit}' "$SETTINGS_JSON"
  fi
fi

printf '\n%sinstallation complete%s\n\n' "$BOLD$GREEN" "$RESET"
cat <<EOF
What's installed:
  • ccstatusline:         $CCSL_BIN
  • helper scripts:       $CLAUDE_SCRIPTS/statusline-{subagents,burn,rate,model}.sh
  • ccstatusline config:  $CCSL_SETTINGS
  • Claude Code settings: statusLine + Skill hooks merged into $SETTINGS_JSON

Next steps:
  1. Send any message in Claude Code to trigger a status line update
  2. To revert:  ./uninstall.sh
  3. Timestamped backups live alongside the originals

Notes:
  • Running this script again is safe (idempotent) — it will remove stale
    ccstatusline hook entries before re-adding fresh ones.
  • Rate-limit widgets (5h, 7d) only show data for Claude.ai Pro/Max accounts.
    API-only accounts will see context burn but blank 5h/7d lines.
EOF
