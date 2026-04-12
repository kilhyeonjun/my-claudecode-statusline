#!/bin/bash
# Displays Sonnet/Opus model-specific usage from Claude usage API.
#
# Usage: bash statusline-model.sh {sonnet|opus}
# Output: "Son: 14% → 2h42m" or empty (auto-hidden by ccstatusline)
set -e

MODE="$1"
case "$MODE" in
  sonnet) FIELD="seven_day_sonnet"; LABEL="Son" ;;
  opus)   FIELD="seven_day_opus";   LABEL="Opu" ;;
  *)      exit 0 ;;
esac

CACHE_DIR="$HOME/.cache/my-claudecode-statusline"
# Allow test override
CACHE_FILE="${STATUSLINE_TEST_CACHE:-$CACHE_DIR/usage.json}"
CACHE_TTL=60

_get_token() {
  local acct raw secret
  raw=$(security dump-keychain 2>/dev/null) || return 1
  acct=$(printf '%s' "$raw" | grep -A 3 '"svce".*Claude Code-credentials"' | \
    grep '"acct"' | sed 's/.*"acct"<blob>="\([^"]*\)".*/\1/' | head -1)
  [ -z "$acct" ] && return 1
  secret=$(security find-generic-password \
    -s "Claude Code-credentials" -a "$acct" -w 2>/dev/null) || return 1
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

PCT=$(printf '%s' "$ENTRY" | jq -r '.utilization // empty' 2>/dev/null)
[ -z "$PCT" ] && exit 0

RESETS_ISO=$(printf '%s' "$ENTRY" | jq -r '.resets_at // empty' 2>/dev/null)
[ -z "$RESETS_ISO" ] && exit 0

# Parse ISO8601 → unix ts (strip fractional seconds and/or timezone offset)
RESETS_CLEAN="${RESETS_ISO%%[.+]*}"  # "2026-04-13T05:00:00"
RESETS_TS=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$RESETS_CLEAN" +%s 2>/dev/null \
         || TZ=UTC date -d "${RESETS_CLEAN}Z" +%s 2>/dev/null \
         || echo 0)

NOW=$(date +%s)
REMAINING=$((RESETS_TS - NOW))

awk -v pct="$PCT" -v rem="$REMAINING" -v label="$LABEL" 'BEGIN {
  if (rem <= 0) fmt_str = "soon"
  else if (rem < 3600) fmt_str = sprintf("%dm", int(rem/60))
  else if (rem < 86400) {
    h = int(rem/3600); m = int((rem % 3600) / 60)
    if (m == 0) fmt_str = sprintf("%dh", h)
    else fmt_str = sprintf("%dh%dm", h, m)
  } else {
    d = int(rem/86400); h = int((rem % 86400) / 3600)
    if (h == 0) fmt_str = sprintf("%dd", d)
    else fmt_str = sprintf("%dd%dh", d, h)
  }
  printf "%s: %.0f%%  →  %s", label, pct, fmt_str
}'
