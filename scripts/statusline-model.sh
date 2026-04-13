#!/bin/bash
# Displays Sonnet/Opus model-specific usage from Claude usage API.
#
# Usage: bash statusline-model.sh {sonnet-pct|sonnet-reset|opus-pct|opus-reset}
# Output: percentage "16%" or reset "4h11m", or empty (auto-hidden by ccstatusline)
set -e

MODE="$1"
case "$MODE" in
  sonnet-pct|sonnet-reset|sonnet-burn) FIELD="seven_day_sonnet" ;;
  opus-pct|opus-reset)                 FIELD="seven_day_opus" ;;
  opus-line)                           FIELD="seven_day_opus" ;;
  *)                                   exit 0 ;;
esac

CACHE_DIR="$HOME/.cache/my-claudecode-statusline"
# Allow test override
CACHE_FILE="${STATUSLINE_TEST_CACHE:-$CACHE_DIR/usage.json}"
CACHE_TTL=30

_get_token() {
  local secret
  secret=$(security find-generic-password \
    -s "Claude Code-credentials" -w 2>/dev/null) || return 1
  printf '%s' "$secret" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    t = d.get('claudeAiOauth', {}).get('accessToken', '')
    if t: print(t)
except: pass
" 2>/dev/null
}

_refresh_cache() {
  [ "${STATUSLINE_SKIP_FETCH:-0}" = "1" ] && return 1
  local token
  token=$(_get_token) || return 1
  mkdir -p "$CACHE_DIR"
  chmod 700 "$CACHE_DIR"
  curl -sf \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: oauth-2025-04-20" \
    "https://api.anthropic.com/api/oauth/usage" \
    > "${CACHE_FILE}.tmp" 2>/dev/null && \
    chmod 600 "${CACHE_FILE}.tmp" && \
    mv "${CACHE_FILE}.tmp" "$CACHE_FILE" || return 1
}

# Check cache freshness
if [ -f "$CACHE_FILE" ]; then
  cache_mtime=$(date -r "$CACHE_FILE" +%s 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
  cache_age=$(( $(date +%s) - cache_mtime ))
  [ "$cache_age" -ge "$CACHE_TTL" ] && _refresh_cache 2>/dev/null || true
else
  _refresh_cache 2>/dev/null || true
fi

[ ! -f "$CACHE_FILE" ] && exit 0

# Parse field
ENTRY=$(jq -r ".${FIELD} // empty" "$CACHE_FILE" 2>/dev/null)
[ -z "$ENTRY" ] || [ "$ENTRY" = "null" ] && exit 0

# Burn rate mode (sonnet-burn)
case "$MODE" in
  sonnet-burn)
    USED=$(printf '%s' "$ENTRY" | jq -r '.utilization // empty' 2>/dev/null)
    [ -z "$USED" ] && exit 0
    RESETS_ISO=$(printf '%s' "$ENTRY" | jq -r '.resets_at // empty' 2>/dev/null)
    [ -z "$RESETS_ISO" ] && exit 0
    RESETS_CLEAN="${RESETS_ISO%%[.+]*}"
    RESETS_TS=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$RESETS_CLEAN" +%s 2>/dev/null \
             || TZ=UTC date -d "${RESETS_CLEAN}Z" +%s 2>/dev/null || echo 0)
    NOW=$(date +%s); REMAINING=$((RESETS_TS - NOW))
    [ "$REMAINING" -le 0 ] && exit 0
    ELAPSED=$((604800 - REMAINING))
    [ "$ELAPSED" -le 60 ] && exit 0
    awk -v used="$USED" -v elapsed="$ELAPSED" 'BEGIN {
      window = 604800
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
          if (eta < 3600) fmt = sprintf("%dm", int(eta/60))
          else if (eta < 86400) {
            h = int(eta/3600); m = int((eta % 3600)/60)
            if (m == 0) fmt = sprintf("%dh", h); else fmt = sprintf("%dh%dm", h, m)
          } else {
            d = int(eta/86400); h = int((eta % 86400)/3600)
            if (h == 0) fmt = sprintf("%dd", d); else fmt = sprintf("%dd%dh", d, h)
          }
          printf "🔥 %.1fx \xe2\x86\x92 100%% in %s", burn, fmt
        }
      } else if (projected >= 90) {
        printf "\xe2\x9a\xa0 %.1fx \xe2\x86\x92 ends ~%d%%", burn, int(projected + 0.5)
      } else if (projected >= 60) {
        printf "\xe2\x9c\x93 %.1fx \xe2\x86\x92 ends ~%d%%", burn, int(projected + 0.5)
      } else {
        printf "\xc2\xb7 %.1fx \xe2\x86\x92 ends ~%d%%", burn, int(projected + 0.5)
      }
    }'
    exit 0
    ;;
esac

# Percentage mode
case "$MODE" in
  *-pct)
    PCT=$(printf '%s' "$ENTRY" | jq -r '.utilization // empty' 2>/dev/null)
    [ -z "$PCT" ] && exit 0
    printf '%.1f%%' "$PCT"
    exit 0
    ;;
esac

# Combined line mode (opus-line): "Opu: 14% → 2h" or empty
case "$MODE" in
  opus-line)
    PCT=$(printf '%s' "$ENTRY" | jq -r '.utilization // empty' 2>/dev/null)
    [ -z "$PCT" ] && exit 0
    RESETS_ISO=$(printf '%s' "$ENTRY" | jq -r '.resets_at // empty' 2>/dev/null)
    [ -z "$RESETS_ISO" ] && exit 0
    RESETS_CLEAN="${RESETS_ISO%%[.+]*}"
    RESETS_TS=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$RESETS_CLEAN" +%s 2>/dev/null \
             || TZ=UTC date -d "${RESETS_CLEAN}Z" +%s 2>/dev/null || echo 0)
    NOW=$(date +%s); REMAINING=$((RESETS_TS - NOW))
    [ "$REMAINING" -le 0 ] && printf 'Opu: %.1f%%' "$PCT" && exit 0
    awk -v pct="$PCT" -v r="$REMAINING" 'BEGIN {
      r = int(r/60 + 0.5) * 60
      if (r < 3600) fmt = sprintf("%dm", int(r/60))
      else if (r < 86400) {
        h = int(r/3600); m = int((r % 3600) / 60)
        if (m == 0) fmt = sprintf("%dh", h); else fmt = sprintf("%dh%dm", h, m)
      } else {
        d = int(r/86400); h = int((r % 86400) / 3600)
        if (h == 0) fmt = sprintf("%dd", d); else fmt = sprintf("%dd%dh", d, h)
      }
      printf "Opu: %.1f%%  \xe2\x86\x92  %s", pct, fmt
    }'
    exit 0
    ;;
esac

# Reset mode
RESETS_ISO=$(printf '%s' "$ENTRY" | jq -r '.resets_at // empty' 2>/dev/null)
[ -z "$RESETS_ISO" ] && exit 0

# Parse ISO8601 → unix ts (strip fractional seconds and/or timezone offset)
RESETS_CLEAN="${RESETS_ISO%%[.+]*}"  # "2026-04-13T05:00:00"
RESETS_TS=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$RESETS_CLEAN" +%s 2>/dev/null \
         || TZ=UTC date -d "${RESETS_CLEAN}Z" +%s 2>/dev/null \
         || echo 0)

NOW=$(date +%s)
REMAINING=$((RESETS_TS - NOW))
[ "$REMAINING" -le 0 ] && exit 0

awk -v r="$REMAINING" 'BEGIN {
  r = int(r/60 + 0.5) * 60
  if (r < 3600) fmt = sprintf("%dm", int(r/60))
  else if (r < 86400) {
    h = int(r/3600); m = int((r % 3600) / 60)
    if (m == 0) fmt = sprintf("%dh", h)
    else fmt = sprintf("%dh%dm", h, m)
  } else {
    d = int(r/86400); h = int((r % 86400) / 3600)
    if (h == 0) fmt = sprintf("%dd", d)
    else fmt = sprintf("%dd%dh", d, h)
  }
  print fmt
}'
