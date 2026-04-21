#!/bin/bash
# my-claudecode-statusline uninstaller
# - Removes helper scripts from ~/.claude/scripts/
# - Restores ~/.claude/settings.json from the most recent timestamped backup,
#   or falls back to stripping ccstatusline entries via jq
# - Restores ~/.config/ccstatusline/settings.json from backup if present
#
# Usage:
#   ./uninstall.sh
#   ./uninstall.sh -n      # dry-run
set -euo pipefail

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; BLUE=$'\033[34m'; RESET=$'\033[0m'
info() { printf '%s[info]%s %s\n' "$BLUE" "$RESET" "$*"; }
ok()   { printf '%s[ ok ]%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s[warn]%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
err()  { printf '%s[ err]%s %s\n' "$RED" "$RESET" "$*" >&2; }

DRY_RUN=0
case "${1:-}" in
  -n|--dry-run) DRY_RUN=1 ;;
  -h|--help) echo "Usage: $0 [-n|--dry-run]"; exit 0 ;;
esac

CLAUDE_HOME="$HOME/.claude"
CLAUDE_SCRIPTS="$CLAUDE_HOME/scripts"
CCSL_CONFIG_DIR="$HOME/.config/ccstatusline"
SETTINGS_JSON="$CLAUDE_HOME/settings.json"
CCSL_SETTINGS="$CCSL_CONFIG_DIR/settings.json"

if ! command -v jq >/dev/null 2>&1; then
  err "jq required"
  exit 1
fi

for script in statusline-subagents.sh statusline-burn.sh statusline-rate.sh statusline-model.sh statusline-line.sh statusline-autopilot.sh; do
  f="$CLAUDE_SCRIPTS/$script"
  if [ -f "$f" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      info "[dry-run] would remove $f"
    else
      rm "$f"
      ok "removed $f"
    fi
  fi
done

restore_from_backup() {
  local target="$1"
  local pattern="$target.bak-*"
  # shellcheck disable=SC2012
  local latest
  latest=$(ls -t $pattern 2>/dev/null | head -1 || true)
  if [ -n "$latest" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      info "[dry-run] would restore $target from $latest"
    else
      cp "$latest" "$target"
      ok "restored $target ← $latest"
    fi
    return 0
  fi
  return 1
}

if [ -f "$SETTINGS_JSON" ]; then
  if ! restore_from_backup "$SETTINGS_JSON"; then
    warn "no backup found for $SETTINGS_JSON, stripping ccstatusline entries via jq"
    stripped=$(jq '
      del(.statusLine)
      | (.hooks // {}) as $h
      | if ($h | has("PreToolUse")) then
          .hooks.PreToolUse |= (
            map(.hooks = ((.hooks // []) | map(select(.command | test("ccstatusline.*--hook") | not))))
            | map(select((.hooks | length) > 0))
          )
          | if (.hooks.PreToolUse | length) == 0 then del(.hooks.PreToolUse) else . end
        else . end
      | if ($h | has("UserPromptSubmit")) then
          .hooks.UserPromptSubmit |= (
            map(.hooks = ((.hooks // []) | map(select(.command | test("ccstatusline.*--hook") | not))))
            | map(select((.hooks | length) > 0))
          )
          | if (.hooks.UserPromptSubmit | length) == 0 then del(.hooks.UserPromptSubmit) else . end
        else . end
    ' "$SETTINGS_JSON")
    if [ "$DRY_RUN" = "1" ]; then
      info "[dry-run] stripped settings preview:"
      printf '%s\n' "$stripped" | jq .
    else
      printf '%s\n' "$stripped" | jq . > "$SETTINGS_JSON"
      ok "stripped ccstatusline entries from $SETTINGS_JSON"
    fi
  fi
fi

if [ -f "$CCSL_SETTINGS" ]; then
  if ! restore_from_backup "$CCSL_SETTINGS"; then
    if [ "$DRY_RUN" = "1" ]; then
      info "[dry-run] would remove $CCSL_SETTINGS (no backup to restore)"
    else
      rm "$CCSL_SETTINGS"
      ok "removed $CCSL_SETTINGS (no backup to restore)"
    fi
  fi
fi

printf '\nuninstall complete. Send any message in Claude Code to see the change.\n'
printf 'Note: ccstatusline npm package is not uninstalled. Remove it manually with:\n'
printf '  bun remove -g ccstatusline     # or: npm uninstall -g ccstatusline\n'
