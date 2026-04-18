#!/bin/bash
# Test for statusline-autopilot.sh
# Tests the auto-pilot indicator marker detection logic.
set -e

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/statusline-autopilot.sh"
PASS=0; FAIL=0

assert_output() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $desc"; PASS=$((PASS+1))
  else
    echo "FAIL: $desc | expected='$expected' actual='$actual'"; FAIL=$((FAIL+1))
  fi
}

# Test 1: HOME with no .claude/ → 🔒 OFF
HOME_NO_CLAUDE=$(mktemp -d)
R=$(echo '{}' | HOME="$HOME_NO_CLAUDE" bash "$SCRIPT" 2>&1) || true
assert_output "no .claude/ → OFF" "🔒 OFF" "$R"
rm -rf "$HOME_NO_CLAUDE"

# Test 2: HOME with empty .claude/ → 🔒 OFF
HOME_EMPTY=$(mktemp -d)
mkdir -p "$HOME_EMPTY/.claude"
R=$(echo '{}' | HOME="$HOME_EMPTY" bash "$SCRIPT" 2>&1) || true
assert_output "empty .claude → OFF" "🔒 OFF" "$R"
rm -rf "$HOME_EMPTY"

# Test 3: HOME with fresh marker → 🔓 ON
HOME_ON=$(mktemp -d)
mkdir -p "$HOME_ON/.claude"
touch "$HOME_ON/.claude/.auto-pilot-active-99999"
R=$(echo '{}' | HOME="$HOME_ON" bash "$SCRIPT" 2>&1) || true
assert_output "fresh marker → ON" "🔓 ON" "$R"
rm -rf "$HOME_ON"

# Test 4: stdin consumed (no SIGPIPE)
HOME_EMPTY=$(mktemp -d)
mkdir -p "$HOME_EMPTY/.claude"
OUT=$(echo 'noise' | HOME="$HOME_EMPTY" bash "$SCRIPT" 2>&1)
[ "$OUT" = "🔒 OFF" ] && echo "PASS: stdin consumed, no error" && PASS=$((PASS+1)) || (echo "FAIL: stdin consumed, expected '🔒 OFF' got '$OUT'" && FAIL=$((FAIL+1)))
rm -rf "$HOME_EMPTY"

echo ""
echo "=== Results ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
exit "$FAIL"
