#!/bin/bash
set -e
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/statusline-model.sh"
CACHE_DIR="$HOME/.cache/my-claudecode-statusline"
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

FUTURE_ISO="2099-01-01T00:00:00.000000+00:00"
mkdir -p "$CACHE_DIR"

# Test: sonnet present
cat > "$CACHE_DIR/usage.json" <<EOF
{"seven_day_sonnet":{"utilization":14,"resets_at":"$FUTURE_ISO"},"seven_day_opus":null}
EOF
touch "$CACHE_DIR/usage.json"
R=$(STATUSLINE_TEST_CACHE="$CACHE_DIR/usage.json" bash "$SCRIPT" sonnet)
assert_match "sonnet shows Son label" "^Son:" "$R"
assert_match "sonnet shows percentage" "14%" "$R"
assert_match "sonnet shows arrow" "→" "$R"

# Test: opus null → empty
R=$(STATUSLINE_TEST_CACHE="$CACHE_DIR/usage.json" bash "$SCRIPT" opus)
assert_eq "opus empty when null" "" "$R"

# Test: unknown mode → empty
R=$(STATUSLINE_TEST_CACHE="$CACHE_DIR/usage.json" bash "$SCRIPT" bogus)
assert_eq "unknown mode exits empty" "" "$R"

# Test: cache missing entirely → empty (no API call in test env)
rm -f "$CACHE_DIR/usage.json"
R=$(STATUSLINE_SKIP_FETCH=1 bash "$SCRIPT" sonnet)
assert_eq "empty when no cache and fetch skipped" "" "$R"

rm -f "$CACHE_DIR/usage.json"
[ "$FAIL" -eq 0 ] && echo "All $PASS tests passed" && exit 0
echo "$FAIL/$((PASS+FAIL)) tests FAILED" >&2 && exit 1
