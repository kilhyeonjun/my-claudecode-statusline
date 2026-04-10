#!/bin/bash
# Computes burn rate and ETA for Claude Code rate limits and context window.
# Called as a ccstatusline custom-command widget.
#
# Usage:  bash statusline-burn.sh {5h|7d|ctx}
# Input:  Claude Code StatusJSON on stdin
# Output: one of:
#           🔥 4.0x → 100% in 15m   (urgent: over pace, hits limit)
#           ⚠ 1.1x → ends ~94%      (slightly over, tight finish)
#           ✓ 0.8x → ends ~65%      (on track, comfortable)
#           · 0.2x → ends ~25%      (under-using, plenty of headroom)
#         or empty when there is not enough data yet.
#
# For ctx mode (context window has no time-based reset):
#           🔥 full in 5m           (<10 min to 100%)
#           ⚠ full in 20m           (<30 min)
#           full in 2h              (plenty of room)
set -e

MODE="$1"
input=$(cat)

case "$MODE" in
  5h)
    WINDOW_SEC=18000
    USED=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty' 2>/dev/null)
    RESETS=$(printf '%s' "$input" | jq -r '.rate_limits.five_hour.resets_at // empty' 2>/dev/null)
    ;;
  7d)
    WINDOW_SEC=604800
    USED=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty' 2>/dev/null)
    RESETS=$(printf '%s' "$input" | jq -r '.rate_limits.seven_day.resets_at // empty' 2>/dev/null)
    ;;
  ctx)
    USED=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
    DURATION_MS=$(printf '%s' "$input" | jq -r '.cost.total_duration_ms // empty' 2>/dev/null)
    ;;
  *)
    exit 0
    ;;
esac

[ -z "$USED" ] && exit 0

if [ "$MODE" = "ctx" ]; then
  [ -z "$DURATION_MS" ] && exit 0
  ELAPSED=$((DURATION_MS / 1000))
else
  [ -z "$RESETS" ] && exit 0
  NOW=$(date +%s)
  REMAINING=$((RESETS - NOW))
  [ "$REMAINING" -le 0 ] && exit 0
  ELAPSED=$((WINDOW_SEC - REMAINING))
fi

[ "$ELAPSED" -le 60 ] && exit 0

if [ "$MODE" = "ctx" ]; then
  awk -v used="$USED" -v elapsed="$ELAPSED" '
  function fmt(s,   h, m) {
    if (s < 60) return sprintf("%ds", s)
    if (s < 3600) return sprintf("%dm", int(s/60))
    h = int(s/3600); m = int((s - h*3600)/60)
    if (m == 0) return sprintf("%dh", h)
    return sprintf("%dh%dm", h, m)
  }
  BEGIN {
    if (used <= 0 || elapsed <= 0) exit
    rate = used / elapsed
    if (rate <= 0) exit
    remain_pct = 100 - used
    if (remain_pct <= 0) exit
    eta = remain_pct / rate
    if (eta < 600) {
      printf "🔥 full in %s", fmt(eta)
    } else if (eta < 1800) {
      printf "⚠ full in %s", fmt(eta)
    } else {
      printf "full in %s", fmt(eta)
    }
  }
  '
else
  awk -v used="$USED" -v elapsed="$ELAPSED" -v window="$WINDOW_SEC" '
  function fmt(s,   h, m, d) {
    if (s < 60) return sprintf("%ds", s)
    if (s < 3600) return sprintf("%dm", int(s/60))
    if (s < 86400) {
      h = int(s/3600); m = int((s - h*3600)/60)
      if (m == 0) return sprintf("%dh", h)
      return sprintf("%dh%dm", h, m)
    }
    d = int(s/86400); h = int((s - d*86400)/3600)
    if (h == 0) return sprintf("%dd", d)
    return sprintf("%dd%dh", d, h)
  }
  BEGIN {
    if (used <= 0 || elapsed <= 0) exit
    rate = used / elapsed
    if (rate <= 0) exit
    projected = rate * window
    burn = projected / 100
    if (projected >= 100) {
      remain_pct = 100 - used
      if (remain_pct <= 0) {
        printf "🔥 LIMIT HIT"
      } else {
        eta = remain_pct / rate
        printf "🔥 %.1fx → 100%% in %s", burn, fmt(eta)
      }
    } else if (projected >= 90) {
      printf "⚠ %.1fx → ends ~%d%%", burn, int(projected + 0.5)
    } else if (projected >= 60) {
      printf "✓ %.1fx → ends ~%d%%", burn, int(projected + 0.5)
    } else {
      printf "· %.1fx → ends ~%d%%", burn, int(projected + 0.5)
    }
  }
  '
fi
