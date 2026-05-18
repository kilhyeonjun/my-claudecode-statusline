#!/bin/bash
# Display auto-pilot status for THIS session only.
#
# Resolves the *Claude Code* PID by walking the process tree upward from
# $PPID (the ccstatusline orchestrator) until a process whose program name
# is `claude` is found. That PID is then used to look up the marker
# `~/.claude/.auto-pilot-active-<claude-pid>` written by
# core/bin/auto-pilot.sh (`AUTO_PILOT_PID="$PPID"` forward from the slash
# command captures the same PID).
#
# Why not $SHELL_PID: terminal integrations (cmux, ghostty shell-integration)
# export SHELL_PID = the *outer shell* PID into the environment before
# launching Claude. Claude inherits that env var, so $SHELL_PID inside
# subprocesses is NOT Claude's PID — the marker lookup silently fails.
#
# Why not $PPID: this script is invoked by ccstatusline (a Node process),
# so $PPID == ccstatusline's PID, not Claude's.
#
# Test hooks (env vars; production never sets these):
#   CLAUDE_PID_OVERRIDE     — short-circuit resolution, return this PID
#   CLAUDE_PID_WALK_START   — start walk from this PID instead of $PPID
#
# See domains/knowledge/tools/claude-code/session-pid-identification.md
# and .claude/rules/cascading-updates.md (auto-pilot marker row).
#
# Usage: bash statusline-autopilot.sh
# Input: Claude Code StatusJSON on stdin (consumed, ignored)
set -u

cat >/dev/null 2>&1 || true

MARKER_DIR="$HOME/.claude"

resolve_claude_pid() {
  if [ -n "${CLAUDE_PID_OVERRIDE:-}" ]; then
    printf '%s' "$CLAUDE_PID_OVERRIDE"
    return 0
  fi
  local pid="${CLAUDE_PID_WALK_START:-$PPID}"
  local hops=0
  while [ -n "$pid" ] && [ "$pid" != "1" ] && [ "$hops" -lt 16 ]; do
    local cmd first base
    cmd=$(ps -o command= -p "$pid" 2>/dev/null | head -c 200)
    first=$(printf '%s' "$cmd" | awk '{print $1}')
    base="${first##*/}"
    if [ "$base" = "claude" ]; then
      printf '%s' "$pid"
      return 0
    fi
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' \t\n')
    hops=$((hops + 1))
  done
  printf '%s' "${CLAUDE_PID_WALK_START:-$PPID}"
  return 1
}

CLAUDE_PID=$(resolve_claude_pid)
STATUS="🔒 OFF"

if [ -f "$MARKER_DIR/.auto-pilot-active-$CLAUDE_PID" ]; then
  STATUS="🔓 ON"
fi

echo "$STATUS"
exit 0
