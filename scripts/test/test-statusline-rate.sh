#!/bin/bash
set -e
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/statusline-rate.sh"
PASS=0; FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $desc"; PASS=$((PASS+1))
  else
    echo "FAIL: $desc | expected='$expected' actual='$actual'"; FAIL=$((FAIL+1))
  fi
}

FUTURE=9999999999  # unix ts far in future

# 5h-pct
R=$(echo '{"rate_limits":{"five_hour":{"used_percentage":19,"resets_at":'"$FUTURE"'}}}' | bash "$SCRIPT" 5h-pct)
assert_eq "5h-pct shows percentage" "19.0%" "$R"

R=$(echo '{"rate_limits":{"five_hour":{"used_percentage":5.5,"resets_at":'"$FUTURE"'}}}' | bash "$SCRIPT" 5h-pct)
assert_eq "5h-pct decimal" "5.5%" "$R"

R=$(echo '{}' | bash "$SCRIPT" 5h-pct)
assert_eq "5h-pct empty when missing" "" "$R"

# 5h-reset
NEAR=$(($(date +%s) + 600))  # 10 minutes from now
R=$(echo '{"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":'"$NEAR"'}}}' | bash "$SCRIPT" 5h-reset)
assert_eq "5h-reset shows minutes" "10m" "$R"

HOUR=$(($(date +%s) + 3660))  # ~1h1m
R=$(echo '{"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":'"$HOUR"'}}}' | bash "$SCRIPT" 5h-reset)
assert_eq "5h-reset shows hours+min" "1h1m" "$R"

R=$(echo '{}' | bash "$SCRIPT" 5h-reset)
assert_eq "5h-reset empty when missing" "" "$R"

# 7d-pct
R=$(echo '{"rate_limits":{"seven_day":{"used_percentage":37,"resets_at":'"$FUTURE"'}}}' | bash "$SCRIPT" 7d-pct)
assert_eq "7d-pct shows percentage" "37.0%" "$R"

R=$(echo '{}' | bash "$SCRIPT" 7d-pct)
assert_eq "7d-pct empty when missing" "" "$R"

# 7d-reset
DAY=$(($(date +%s) + 90000))  # ~25h
R=$(echo '{"rate_limits":{"seven_day":{"used_percentage":37,"resets_at":'"$DAY"'}}}' | bash "$SCRIPT" 7d-reset)
assert_eq "7d-reset shows days+hours" "1d1h" "$R"

# Boundary: 100% usage
R=$(echo '{"rate_limits":{"five_hour":{"used_percentage":100,"resets_at":'"$FUTURE"'}}}' | bash "$SCRIPT" 5h-pct)
assert_eq "5h-pct at 100%" "100.0%" "$R"

# Boundary: reset timestamp already passed → empty (no negative countdown)
PAST=$(($(date +%s) - 60))
R=$(echo '{"rate_limits":{"five_hour":{"used_percentage":50,"resets_at":'"$PAST"'}}}' | bash "$SCRIPT" 5h-reset)
assert_eq "5h-reset empty when reset already passed" "" "$R"

[ "$FAIL" -eq 0 ] && echo "All $PASS tests passed" && exit 0
echo "$FAIL/$((PASS+FAIL)) tests FAILED" >&2 && exit 1
