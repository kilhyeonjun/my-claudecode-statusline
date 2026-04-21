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

# Test: sonnet-pct
cat > "$CACHE_DIR/usage.json" <<EOF
{"seven_day_sonnet":{"utilization":14,"resets_at":"$FUTURE_ISO"},"seven_day_opus":null}
EOF
touch "$CACHE_DIR/usage.json"
R=$(ANTHROPIC_BASE_URL="" STATUSLINE_TEST_CACHE="$CACHE_DIR/usage.json" bash "$SCRIPT" sonnet-pct)
assert_match "sonnet-pct shows percentage" "14" "$R"
assert_match "sonnet-pct has % sign" "%" "$R"

# Test: sonnet-reset
R=$(ANTHROPIC_BASE_URL="" STATUSLINE_TEST_CACHE="$CACHE_DIR/usage.json" bash "$SCRIPT" sonnet-reset)
assert_match "sonnet-reset shows time" "[0-9]+(d|h|m)" "$R"

# Test: opus-pct null → empty
R=$(ANTHROPIC_BASE_URL="" STATUSLINE_TEST_CACHE="$CACHE_DIR/usage.json" bash "$SCRIPT" opus-pct)
assert_eq "opus-pct empty when null" "" "$R"

# Test: opus-reset null → empty
R=$(ANTHROPIC_BASE_URL="" STATUSLINE_TEST_CACHE="$CACHE_DIR/usage.json" bash "$SCRIPT" opus-reset)
assert_eq "opus-reset empty when null" "" "$R"

# Test: unknown mode → empty
R=$(ANTHROPIC_BASE_URL="" STATUSLINE_TEST_CACHE="$CACHE_DIR/usage.json" bash "$SCRIPT" bogus)
assert_eq "unknown mode exits empty" "" "$R"

# Test: sonnet-burn — normal case (resets ~3 days out, half used)
HALF_RESET=$(date -u -v+3d "+%Y-%m-%dT%H:%M:%S.000000+00:00" 2>/dev/null \
  || date -u -d "3 days" "+%Y-%m-%dT%H:%M:%S.000000+00:00" 2>/dev/null)
cat > "$CACHE_DIR/usage.json" <<EOF
{"seven_day_sonnet":{"utilization":50,"resets_at":"$HALF_RESET"},"seven_day_opus":null}
EOF
touch "$CACHE_DIR/usage.json"
R=$(ANTHROPIC_BASE_URL="" STATUSLINE_TEST_CACHE="$CACHE_DIR/usage.json" bash "$SCRIPT" sonnet-burn)
assert_match "sonnet-burn shows rate" "[0-9]\.[0-9]x" "$R"
assert_match "sonnet-burn shows projected" "ends ~[0-9]+" "$R"

# Test: sonnet-burn — past reset → empty
PAST_ISO="2020-01-01T00:00:00.000000+00:00"
cat > "$CACHE_DIR/usage.json" <<EOF
{"seven_day_sonnet":{"utilization":50,"resets_at":"$PAST_ISO"},"seven_day_opus":null}
EOF
touch "$CACHE_DIR/usage.json"
R=$(ANTHROPIC_BASE_URL="" STATUSLINE_TEST_CACHE="$CACHE_DIR/usage.json" bash "$SCRIPT" sonnet-burn)
assert_eq "sonnet-burn empty when reset passed" "" "$R"

# Test: sonnet-burn — far future reset (elapsed ≤ 60) → empty
cat > "$CACHE_DIR/usage.json" <<EOF
{"seven_day_sonnet":{"utilization":14,"resets_at":"$FUTURE_ISO"},"seven_day_opus":null}
EOF
touch "$CACHE_DIR/usage.json"
R=$(ANTHROPIC_BASE_URL="" STATUSLINE_TEST_CACHE="$CACHE_DIR/usage.json" bash "$SCRIPT" sonnet-burn)
assert_eq "sonnet-burn empty when elapsed too short" "" "$R"

# Test: gateway-backed provider should hide OAuth-only widgets
cat > "$CACHE_DIR/usage.json" <<EOF
{"seven_day_sonnet":{"utilization":14,"resets_at":"$FUTURE_ISO"},"seven_day_opus":{"utilization":22,"resets_at":"$HALF_RESET"}}
EOF
touch "$CACHE_DIR/usage.json"
R=$(ANTHROPIC_BASE_URL="http://127.0.0.1:8317" STATUSLINE_TEST_CACHE="$CACHE_DIR/usage.json" bash "$SCRIPT" sonnet-pct)
assert_eq "sonnet-pct empty for codex gateway provider" "" "$R"
R=$(ANTHROPIC_BASE_URL="http://127.0.0.1:8317" STATUSLINE_TEST_CACHE="$CACHE_DIR/usage.json" bash "$SCRIPT" opus-line)
assert_eq "opus-line empty for codex gateway provider" "" "$R"
R=$(ANTHROPIC_BASE_URL="http://localhost:8000" STATUSLINE_TEST_CACHE="$CACHE_DIR/usage.json" bash "$SCRIPT" sonnet-pct)
assert_eq "sonnet-pct empty for kiro gateway provider" "" "$R"
R=$(ANTHROPIC_BASE_URL="https://proxy.example.com" STATUSLINE_TEST_CACHE="$CACHE_DIR/usage.json" bash "$SCRIPT" sonnet-pct)
assert_match "sonnet-pct still shows for non-gateway proxy" "14" "$R"

# Test: cache missing entirely → empty (no API call in test env)
rm -f "$CACHE_DIR/usage.json"
R=$(ANTHROPIC_BASE_URL="" STATUSLINE_SKIP_FETCH=1 bash "$SCRIPT" sonnet-pct)
assert_eq "empty when no cache and fetch skipped" "" "$R"

rm -f "$CACHE_DIR/usage.json"
[ "$FAIL" -eq 0 ] && echo "All $PASS tests passed" && exit 0
echo "$FAIL/$((PASS+FAIL)) tests FAILED" >&2 && exit 1
