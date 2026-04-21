#!/bin/bash
set -e
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/statusline-line.sh"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CACHE_DIR="$HOME/.cache/my-claudecode-statusline"
TMP_HOME="$(mktemp -d)"
PASS=0; FAIL=0
cleanup() {
  rm -rf "$TMP_HOME"
}
trap cleanup EXIT

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

mkdir -p "$CACHE_DIR"
NOW=$(date +%s)
FIVE_RESET=$((NOW + 14400))
SEVEN_RESET=$((NOW + 432000))
MODEL_RESET=$(date -u -v+3d "+%Y-%m-%dT%H:%M:%S.000000+00:00" 2>/dev/null || date -u -d "3 days" "+%Y-%m-%dT%H:%M:%S.000000+00:00" 2>/dev/null)

R=$(printf '%s' '{"rate_limits":{"five_hour":{"used_percentage":19,"resets_at":'"$FIVE_RESET"'}}}' | HOME="$TMP_HOME" STATUSLINE_SCRIPTS_DIR="$SCRIPT_DIR" ANTHROPIC_BASE_URL="" bash "$SCRIPT" 5h)
assert_match "5h line shows full combined output" '^5h: 19\.0% .*ends ~95%$' "$R"

R=$(printf '%s' '{}' | ANTHROPIC_BASE_URL="" bash "$SCRIPT" 5h)
assert_eq "5h line empty when rate limits missing" "" "$R"

R=$(printf '%s' '{"rate_limits":{"seven_day":{"used_percentage":30,"resets_at":'"$SEVEN_RESET"'}}}' | ANTHROPIC_BASE_URL="" bash "$SCRIPT" 7d)
assert_match "7d line shows full combined output" '^7d: 30\.0% .*' "$R"

cat > "$CACHE_DIR/usage.json" <<EOF
{"seven_day_sonnet":{"utilization":50,"resets_at":"$MODEL_RESET"},"seven_day_opus":{"utilization":22,"resets_at":"$MODEL_RESET"}}
EOF
R=$(ANTHROPIC_BASE_URL="" STATUSLINE_TEST_CACHE="$CACHE_DIR/usage.json" bash "$SCRIPT" sonnet)
assert_match "sonnet line shows combined output" '^Son: 50\.0% .*' "$R"

R=$(ANTHROPIC_BASE_URL="http://127.0.0.1:8317" STATUSLINE_TEST_CACHE="$CACHE_DIR/usage.json" bash "$SCRIPT" sonnet)
assert_eq "sonnet line empty for gateway provider" "" "$R"

R=$(ANTHROPIC_BASE_URL="" STATUSLINE_TEST_CACHE="$CACHE_DIR/usage.json" bash "$SCRIPT" opus)
assert_match "opus line delegates to combined output" '^Opu: 22\.0% .*' "$R"

rm -f "$CACHE_DIR/usage.json"
[ "$FAIL" -eq 0 ] && echo "All $PASS tests passed" && exit 0
echo "$FAIL/$((PASS+FAIL)) tests FAILED" >&2 && exit 1
