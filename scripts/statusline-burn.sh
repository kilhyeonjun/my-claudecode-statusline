#!/bin/bash
# Computes burn rate and ETA for the Claude Code context window.
# Called as a ccstatusline custom-command widget (sits mid-line after a
# separator, so guard paths print "·" instead of empty output).
#
# Usage:  bash statusline-burn.sh   (any legacy args are ignored)
# Input:  Claude Code StatusJSON on stdin
# Output: 🔥 full in 5m   (<10 min to 100%)
#         ⚠ full in 20m  (<30 min)
#         full in 2h     (plenty of room)
#         ·              (not enough data yet)
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=statusline-lib.sh
source "$SCRIPT_DIR/statusline-lib.sh"

input=$(cat)

PLACEHOLDER="·"

USED=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
DURATION_MS=$(printf '%s' "$input" | jq -r '.cost.total_duration_ms // empty' 2>/dev/null)

if [ -z "$USED" ] || [ -z "$DURATION_MS" ]; then
  printf '%s' "$PLACEHOLDER"
  exit 0
fi

ELAPSED=$(awk -v ms="$DURATION_MS" 'BEGIN { printf "%d", ms / 1000 }')

if [ "$ELAPSED" -le 60 ]; then
  printf '%s' "$PLACEHOLDER"
  exit 0
fi

OUT=$(awk -v used="$USED" -v elapsed="$ELAPSED" '
BEGIN {
  if (used <= 0 || elapsed <= 0) exit
  rate = used / elapsed
  if (rate <= 0) exit
  remain_pct = 100 - used
  if (remain_pct <= 0) exit
  eta = remain_pct / rate
  printf "%d\t%s", int(eta), (eta < 600 ? "urgent" : (eta < 1800 ? "warn" : "ok"))
}')

if [ -z "$OUT" ]; then
  printf '%s' "$PLACEHOLDER"
  exit 0
fi

ETA_SEC="${OUT%%$'\t'*}"
LEVEL="${OUT##*$'\t'}"
DUR=$(fmt_dur "$ETA_SEC")

case "$LEVEL" in
  urgent) printf '🔥 full in %s' "$DUR" ;;
  warn)   printf '⚠ full in %s' "$DUR" ;;
  *)      printf 'full in %s' "$DUR" ;;
esac

exit 0
