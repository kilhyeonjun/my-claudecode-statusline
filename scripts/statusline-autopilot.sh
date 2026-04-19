#!/bin/bash
# Display auto-pilot status for THIS session only (per-PPID).
# Reads marker from ~/.claude/.auto-pilot-active-$PPID (Claude Code process).
# Shows 🔓 ON only when current session's marker exists. Otherwise 🔒 OFF.
#
# Why per-PPID: a shared "ANY marker fresh" scan causes sessions that never
# activated auto-pilot to visually show ON when a sibling session activated it.
# See .claude/rules/state-placement.md (PID scoping pattern).
#
# Usage: bash statusline-autopilot.sh
# Input: Claude Code StatusJSON on stdin (ignored — status comes from filesystem)
set -u

# Consume stdin to avoid SIGPIPE from upstream
cat >/dev/null 2>&1 || true

MARKER_DIR="$HOME/.claude"
STATUS="🔒 OFF"

if [ -f "$MARKER_DIR/.auto-pilot-active-$PPID" ]; then
  STATUS="🔓 ON"
fi

echo "$STATUS"
exit 0
