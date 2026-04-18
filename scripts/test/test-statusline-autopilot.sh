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

# Test 1: No CLAUDE_PROJECT_DIR set — silent
R=$(CLAUDE_PROJECT_DIR="" bash "$SCRIPT" </dev/null 2>&1) || true
assert_output "no CLAUDE_PROJECT_DIR — silent" "" "$R"

# Test 2: Marker dir doesn't exist — silent
TESTDIR=$(mktemp -d)
R=$(CLAUDE_PROJECT_DIR="$TESTDIR" bash "$SCRIPT" </dev/null 2>&1) || true
assert_output "marker dir missing — silent" "" "$R"
rmdir "$TESTDIR"

# Test 3: Marker dir exists, but no markers — silent
TESTDIR=$(mktemp -d)
mkdir -p "$TESTDIR/.claude"
R=$(CLAUDE_PROJECT_DIR="$TESTDIR" bash "$SCRIPT" </dev/null 2>&1) || true
assert_output "marker dir empty — silent" "" "$R"
rm -rf "$TESTDIR"

# Test 4: Fresh marker exists — output 🔓 AUTO with trailing separator
TESTDIR=$(mktemp -d)
mkdir -p "$TESTDIR/.claude"
touch "$TESTDIR/.claude/.auto-pilot-active-99999"
R=$(CLAUDE_PROJECT_DIR="$TESTDIR" bash "$SCRIPT" </dev/null 2>&1) || true
assert_output "fresh marker present — shows 🔓 AUTO |" "🔓 AUTO |" "$R"
rm -rf "$TESTDIR"

# Test 5: Stdin consumed (no SIGPIPE)
R=$(printf '{"test":"json"}' | CLAUDE_PROJECT_DIR="" bash "$SCRIPT" 2>&1) || true
assert_output "stdin consumed (no SIGPIPE)" "" "$R"

echo ""
echo "=== Results ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
exit "$FAIL"
