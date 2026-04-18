#!/bin/bash
# Display auto-pilot indicator when a fresh marker file exists in the current project's .claude/.
# Marker format: .auto-pilot-active-<PID> (created by /auto-pilot slash command in kilhyeonjun-harness).
# Shows "🔓 AUTO" if any marker file < 24h old exists in $CLAUDE_PROJECT_DIR/.claude/.
# Silent if CLAUDE_PROJECT_DIR unset, marker dir missing, or all markers stale.
#
# Usage: bash statusline-autopilot.sh
# Input: Claude Code StatusJSON on stdin (ignored — env var suffices)
set -u

# Consume stdin to not leave data in the pipe buffer (even though we don't use it)
cat >/dev/null 2>&1 || true

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-}"
[ -z "$PROJECT_DIR" ] && exit 0

MARKER_DIR="$PROJECT_DIR/.claude"
[ -d "$MARKER_DIR" ] || exit 0

# Find any non-stale (< 24h) auto-pilot marker
FRESH=$(find "$MARKER_DIR" -maxdepth 1 -name ".auto-pilot-active-*" -type f -mtime -1 2>/dev/null | head -1)
[ -z "$FRESH" ] && exit 0

echo "🔓 AUTO"
exit 0
