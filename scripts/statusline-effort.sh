#!/bin/bash
# Display Claude Code effort level from settings.json.
# Reads effortLevel from settings.json with priority: project > user-global.
# Maps effort level to emoji + label according to user-defined scheme.
#
# Why settings.json, not env: settings.json can change mid-session via UI,
# whereas env is a snapshot at session start.
#
# Usage: bash statusline-effort.sh
# Input: Claude Code StatusJSON on stdin (ignored)
# Output: Label mapping (e.g. "⚡ MAX", "· MED", or empty if unset)
set -u

cat >/dev/null 2>&1 || true

# Priority: project override > user-global
EFFORT_LEVEL=""

# Check project-level settings.json first
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/.claude/settings.json" ]; then
  if command -v jq >/dev/null 2>&1; then
    EFFORT_LEVEL=$(jq -r '.effortLevel // empty' "$CLAUDE_PROJECT_DIR/.claude/settings.json" 2>/dev/null) || true
  else
    # Fallback: grep + sed when jq unavailable
    EFFORT_LEVEL=$(grep -o '"effortLevel"\s*:\s*"[^"]*"' "$CLAUDE_PROJECT_DIR/.claude/settings.json" 2>/dev/null | sed 's/.*"\([^"]*\)"/\1/') || true
  fi
fi

# Fall back to user-global settings.json if not found in project
if [ -z "$EFFORT_LEVEL" ] && [ -f "$HOME/.claude/settings.json" ]; then
  if command -v jq >/dev/null 2>&1; then
    EFFORT_LEVEL=$(jq -r '.effortLevel // empty' "$HOME/.claude/settings.json" 2>/dev/null) || true
  else
    # Fallback: grep + sed when jq unavailable
    EFFORT_LEVEL=$(grep -o '"effortLevel"\s*:\s*"[^"]*"' "$HOME/.claude/settings.json" 2>/dev/null | sed 's/.*"\([^"]*\)"/\1/') || true
  fi
fi

# If no effort level found, output nothing (widget hidden by ccstatusline)
[ -z "$EFFORT_LEVEL" ] && exit 0

# Map effort level to display label
case "$EFFORT_LEVEL" in
  max)    echo "⚡ MAX" ;;
  xhigh)  echo "⚡ XHIGH" ;;
  high)   echo "⬆ HIGH" ;;
  medium) echo "· MED" ;;
  low)    echo "⬇ LOW" ;;
  *)      echo "? $EFFORT_LEVEL" ;;
esac

exit 0
