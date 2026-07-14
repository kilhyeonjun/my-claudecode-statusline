#!/bin/bash
# Displays combined 5h + 7d rate-limit usage and burn rate from StatusJSON stdin.
#
# Usage: bash statusline-usage.sh
# Input: Claude Code StatusJSON on stdin
# Output: "5h 38% →2h ✓0.8x | 7d 7% →5d ·0.5x"  (each window optional, may be empty)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=statusline-lib.sh
source "$SCRIPT_DIR/statusline-lib.sh"

input=$(cat)

# Single jq call, all 4 fields, one per line. Newline-separated (not tab/IFS
# splitting) because bash `read` with a whitespace IFS char collapses leading
# empty fields. resets_at is cast to an int string so no downstream bash
# arithmetic sees a float.
{
  IFS= read -r FIVE_USED
  IFS= read -r FIVE_RESETS
  IFS= read -r SEVEN_USED
  IFS= read -r SEVEN_RESETS
} < <(printf '%s' "$input" | jq -r '
  (.rate_limits.five_hour.used_percentage // ""),
  (if .rate_limits.five_hour.resets_at then (.rate_limits.five_hour.resets_at | floor | tostring) else "" end),
  (.rate_limits.seven_day.used_percentage // ""),
  (if .rate_limits.seven_day.resets_at then (.rate_limits.seven_day.resets_at | floor | tostring) else "" end)
' 2>/dev/null) || true

NOW=$(date +%s)

segment() {
  local label="$1" used="$2" resets="$3" window="$4"
  [ -z "$used" ] && return
  local pct
  pct=$(awk -v u="$used" 'BEGIN { printf "%d", u + 0.5 }')
  local out="$label ${pct}%"
  if [ -n "$resets" ]; then
    local remaining=$((resets - NOW))
    if [ "$remaining" -gt 0 ]; then
      out="$out →$(fmt_dur "$remaining")"
      local elapsed=$((window - remaining))
      if [ "$elapsed" -gt 60 ]; then
        local burn
        burn=$(burn_project "$used" "$elapsed" "$window")
        [ -n "$burn" ] && out="$out $burn"
      fi
    fi
  fi
  printf '%s' "$out"
}

FIVE_SEG=$(segment "5h" "$FIVE_USED" "$FIVE_RESETS" 18000)
SEVEN_SEG=$(segment "7d" "$SEVEN_USED" "$SEVEN_RESETS" 604800)

if [ -n "$FIVE_SEG" ] && [ -n "$SEVEN_SEG" ]; then
  printf '%s | %s' "$FIVE_SEG" "$SEVEN_SEG"
elif [ -n "$FIVE_SEG" ]; then
  printf '%s' "$FIVE_SEG"
elif [ -n "$SEVEN_SEG" ]; then
  printf '%s' "$SEVEN_SEG"
fi

exit 0
