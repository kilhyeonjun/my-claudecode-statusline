#!/bin/bash
# Display auto-pilot status (always visible).
# Reads marker from ~/.claude/.auto-pilot-active-*. If ANY fresh (< 24h) marker exists in the
# current user's $HOME/.claude/, show 🔓 ON. Otherwise 🔒 OFF.
#
# Marker path: $HOME/.claude/.auto-pilot-active-<PID> (user-global; see state-placement.md)
# PID scoping for strict isolation is at the hook layer — statusline is a visual cue.
#
# Usage: bash statusline-autopilot.sh
# Input: Claude Code StatusJSON on stdin (ignored — status comes from filesystem)
set -u

# Consume stdin to avoid SIGPIPE from upstream
cat >/dev/null 2>&1 || true

MARKER_DIR="$HOME/.claude"
STATUS="🔒 OFF"

if [ -d "$MARKER_DIR" ]; then
  FRESH=$(find "$MARKER_DIR" -maxdepth 1 -name ".auto-pilot-active-*" -type f -mtime -1 2>/dev/null | head -1)
  if [ -n "$FRESH" ]; then
    STATUS="🔓 ON"
  fi
fi

echo "$STATUS"
exit 0
