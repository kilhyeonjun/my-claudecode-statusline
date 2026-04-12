#!/bin/bash
# Displays 5h/7d usage percentage or reset timer from StatusJSON stdin.
# Replaces ccstatusline built-in session-usage / reset-timer widgets.
#
# Usage: bash statusline-rate.sh {5h-pct|5h-reset|7d-pct|7d-reset}
# Input: Claude Code StatusJSON on stdin
set -e

MODE="$1"
input=$(cat)

case "$MODE" in
  5h-pct)   PCT_PATH='.rate_limits.five_hour.used_percentage' ;;
  7d-pct)   PCT_PATH='.rate_limits.seven_day.used_percentage' ;;
  5h-reset) RESET_PATH='.rate_limits.five_hour.resets_at' ;;
  7d-reset) RESET_PATH='.rate_limits.seven_day.resets_at' ;;
  *)        exit 0 ;;
esac

if [ -n "${PCT_PATH:-}" ]; then
  PCT=$(printf '%s' "$input" | jq -r "${PCT_PATH} // empty" 2>/dev/null)
  [ -z "$PCT" ] && exit 0
  printf '%.1f%%\n' "$PCT"
  exit 0
fi

# Reset timer mode
RESETS=$(printf '%s' "$input" | jq -r "${RESET_PATH} // empty" 2>/dev/null)
[ -z "$RESETS" ] && exit 0
NOW=$(date +%s)
REMAINING=$((RESETS - NOW))
[ "$REMAINING" -le 0 ] && exit 0

awk -v r="$REMAINING" 'BEGIN {
  if (r < 3600) {
    print sprintf("%dm", int(r/60 + 0.5))
  } else if (r < 86400) {
    h = int(r/3600); m = int((r % 3600) / 60 + 0.5)
    if (m == 0) print sprintf("%dh", h)
    else print sprintf("%dh%dm", h, m)
  } else {
    d = int(r/86400); h = int((r % 86400) / 3600 + 0.5)
    if (h == 0) print sprintf("%dd", d)
    else print sprintf("%dd%dh", d, h)
  }
}'
