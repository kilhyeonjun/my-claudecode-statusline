#!/bin/bash
# Display auto-pilot status for THIS session only.
# Uses $SHELL_PID (Claude Code process PID; env-propagated through nested
# processes). Falls back to $PPID if SHELL_PID unset.
#
# Why not $PPID: this script is invoked by ccstatusline as a widget, so
# $PPID is ccstatusline's PID, not Claude's. SHELL_PID is env-inherited
# from Claude Code and reliable across invocation depth.
#
# See .claude/rules/state-placement.md (PID scoping pattern).
#
# Usage: bash statusline-autopilot.sh
# Input: Claude Code StatusJSON on stdin (ignored)
set -u

cat >/dev/null 2>&1 || true

MARKER_DIR="$HOME/.claude"
CLAUDE_PID="${SHELL_PID:-$PPID}"
STATUS="🔒 OFF"

if [ -f "$MARKER_DIR/.auto-pilot-active-$CLAUDE_PID" ]; then
  STATUS="🔓 ON"
fi

echo "$STATUS"
exit 0
