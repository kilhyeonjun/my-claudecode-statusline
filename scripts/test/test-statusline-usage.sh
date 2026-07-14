#!/bin/bash
set -e
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/statusline-usage.sh"
PASS=0; FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $desc"; PASS=$((PASS+1))
  else
    echo "FAIL: $desc | expected='$expected' actual='$actual'"; FAIL=$((FAIL+1))
  fi
}

assert_match() {
  local desc="$1" pattern="$2" actual="$3"
  if echo "$actual" | grep -qE "$pattern"; then
    echo "PASS: $desc"; PASS=$((PASS+1))
  else
    echo "FAIL: $desc | pattern='$pattern' actual='$actual'"; FAIL=$((FAIL+1))
  fi
}

NOW=$(date +%s)

# Both windows present, burn computable for both
FIVE_RESET=$((NOW + 7200))    # 2h from now -> elapsed = 18000-7200=10800
SEVEN_RESET=$((NOW + 432000)) # 5d from now -> elapsed = 604800-432000=172800
R=$(printf '%s' '{"rate_limits":{"five_hour":{"used_percentage":38,"resets_at":'"$FIVE_RESET"'},"seven_day":{"used_percentage":7,"resets_at":'"$SEVEN_RESET"'}}}' | bash "$SCRIPT")
assert_match "both windows: 5h segment present" '^5h 38% →2h ' "$R"
assert_match "both windows: 7d segment present" ' \| 7d 7% →5d ' "$R"
assert_match "both windows: percentages are integers (no decimal)" '5h 38% ' "$R"

# One window absent (7d missing) -> only 5h segment
R=$(printf '%s' '{"rate_limits":{"five_hour":{"used_percentage":38,"resets_at":'"$FIVE_RESET"'}}}' | bash "$SCRIPT")
assert_match "5h only when 7d absent" '^5h 38% →2h' "$R"
if echo "$R" | grep -q '7d'; then
  echo "FAIL: 5h only should not contain 7d segment | actual='$R'"; FAIL=$((FAIL+1))
else
  echo "PASS: 5h only should not contain 7d segment"; PASS=$((PASS+1))
fi

# One window absent (5h missing) -> only 7d segment
R=$(printf '%s' '{"rate_limits":{"seven_day":{"used_percentage":7,"resets_at":'"$SEVEN_RESET"'}}}' | bash "$SCRIPT")
assert_match "7d only when 5h absent" '^7d 7% →5d' "$R"

# Both windows absent -> empty output, exit 0
OUT=$(printf '%s' '{}' | bash "$SCRIPT"; echo "EXIT:$?")
R="${OUT%EXIT:*}"
CODE="${OUT##*EXIT:}"
assert_eq "both absent -> empty output" "" "$R"
assert_eq "both absent -> exit 0" "0" "$CODE"

# Float resets_at (no bash arithmetic error)
FLOAT_RESET="${NOW}.123456"
FLOAT_TARGET=$((NOW + 7200))
FLOAT_RESET="${FLOAT_TARGET}.5"
R=$(printf '%s' '{"rate_limits":{"five_hour":{"used_percentage":38,"resets_at":'"$FLOAT_RESET"'}}}' | bash "$SCRIPT" 2>&1)
assert_match "float resets_at handled without arithmetic error" '^5h 38% →2h' "$R"

# Expired resets_at -> no dangling "→ " (omit reset segment but keep pct)
PAST=$((NOW - 60))
R=$(printf '%s' '{"rate_limits":{"five_hour":{"used_percentage":38,"resets_at":'"$PAST"'}}}' | bash "$SCRIPT")
if echo "$R" | grep -qE '→\s*($| )'; then
  echo "FAIL: expired reset should not leave dangling arrow | actual='$R'"; FAIL=$((FAIL+1))
else
  echo "PASS: expired reset has no dangling arrow"; PASS=$((PASS+1))
fi

# Burn omitted when elapsed < 60s in window (reset almost exactly at window length away)
NEAR_FULL_WINDOW=$((NOW + 17945))  # elapsed = 18000-17945=55s < 60
R=$(printf '%s' '{"rate_limits":{"five_hour":{"used_percentage":1,"resets_at":'"$NEAR_FULL_WINDOW"'}}}' | bash "$SCRIPT")
assert_match "burn omitted when elapsed<60s in window" '^5h 1% →' "$R"
if echo "$R" | grep -qE '[✓⚠🔥·][0-9]'; then
  echo "FAIL: burn indicator should be omitted | actual='$R'"; FAIL=$((FAIL+1))
else
  echo "PASS: burn indicator omitted for short elapsed"; PASS=$((PASS+1))
fi

# stdin consumed exactly once (no leftover causing SIGPIPE-ish issues)
R=$(printf '%s' '{"rate_limits":{"five_hour":{"used_percentage":38,"resets_at":'"$FIVE_RESET"'}}}' | bash "$SCRIPT" 2>&1)
assert_match "stdin consumed, single clean output line" '^5h 38%' "$R"
LINES=$(printf '%s' "$R" | wc -l | tr -d ' ')
assert_eq "single-line output" "0" "$LINES"

# Malformed stdin must never crash the widget (idiom rule 5: exit 0 always)
OUT=$(printf '' | bash "$SCRIPT"; echo "EXIT:$?")
CODE="${OUT##*EXIT:}"
assert_eq "empty stdin -> exit 0" "0" "$CODE"

OUT=$(printf 'not json' | bash "$SCRIPT"; echo "EXIT:$?")
CODE="${OUT##*EXIT:}"
assert_eq "non-JSON stdin -> exit 0" "0" "$CODE"

OUT=$(printf '{"rate_limits":' | bash "$SCRIPT"; echo "EXIT:$?")
CODE="${OUT##*EXIT:}"
assert_eq "truncated JSON stdin -> exit 0" "0" "$CODE"

[ "$FAIL" -eq 0 ] && echo "All $PASS tests passed" && exit 0
echo "$FAIL/$((PASS+FAIL)) tests FAILED" >&2 && exit 1
