#!/bin/bash
# Test for statusline-autopilot.sh
# Tests the auto-pilot indicator marker detection logic.
#
# PID resolution strategy under test:
#   1. CLAUDE_PID_OVERRIDE env (test injection point)
#   2. Walk parents from $PPID; first ancestor whose command starts with `claude` wins
#   3. Fallback: $PPID (unmatched walk)
#
# SHELL_PID is intentionally NOT used: terminal integrations (cmux, ghostty)
# export SHELL_PID = outer-shell PID, which is *not* Claude's PID — the
# old SHELL_PID strategy silently failed in those environments.
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
R=$(echo '{}' | HOME="$HOME_NO_CLAUDE" CLAUDE_PID_OVERRIDE=99999 bash "$SCRIPT" 2>&1) || true
assert_output "no .claude/ → OFF" "🔒 OFF" "$R"
rm -rf "$HOME_NO_CLAUDE"

# Test 2: HOME with empty .claude/ → 🔒 OFF
HOME_EMPTY=$(mktemp -d)
mkdir -p "$HOME_EMPTY/.claude"
R=$(echo '{}' | HOME="$HOME_EMPTY" CLAUDE_PID_OVERRIDE=99999 bash "$SCRIPT" 2>&1) || true
assert_output "empty .claude → OFF" "🔒 OFF" "$R"
rm -rf "$HOME_EMPTY"

# Test 3: marker matches resolved Claude PID → 🔓 ON
HOME_ON=$(mktemp -d)
mkdir -p "$HOME_ON/.claude"
touch "$HOME_ON/.claude/.auto-pilot-active-99999"
R=$(echo '{}' | HOME="$HOME_ON" CLAUDE_PID_OVERRIDE=99999 bash "$SCRIPT" 2>&1) || true
assert_output "marker matches override PID → ON" "🔓 ON" "$R"
rm -rf "$HOME_ON"

# Test 4: stdin consumed (no SIGPIPE)
HOME_EMPTY=$(mktemp -d)
mkdir -p "$HOME_EMPTY/.claude"
OUT=$(echo 'noise' | HOME="$HOME_EMPTY" CLAUDE_PID_OVERRIDE=99999 bash "$SCRIPT" 2>&1)
[ "$OUT" = "🔒 OFF" ] && { echo "PASS: stdin consumed, no error"; PASS=$((PASS+1)); } || { echo "FAIL: stdin consumed, expected '🔒 OFF' got '$OUT'"; FAIL=$((FAIL+1)); }
rm -rf "$HOME_EMPTY"

# Test 5: marker exists but for a DIFFERENT PID → 🔒 OFF
# Proves the script doesn't just glob — it matches against the resolved Claude PID.
HOME_DIFF=$(mktemp -d)
mkdir -p "$HOME_DIFF/.claude"
touch "$HOME_DIFF/.claude/.auto-pilot-active-99999"
R=$(echo '{}' | HOME="$HOME_DIFF" CLAUDE_PID_OVERRIDE=88888 bash "$SCRIPT" 2>&1) || true
assert_output "marker for different PID → OFF" "🔒 OFF" "$R"
rm -rf "$HOME_DIFF"

# Test 6: walk discovers Claude PID via parent chain (PATH-injected fake `ps`)
# Build a fake ps that emits:
#   - For our temp PID: ppid = next temp PID, command = "fakecmd"
#   - For middle: ppid = claude PID, command = "another"
#   - For claude PID: ppid = 1, command = "claude --model X"
# Then run the script with PPID forced via a wrapper that exports PPID via a child bash;
# observe that the marker for the claude PID is detected.
HOME_WALK=$(mktemp -d)
mkdir -p "$HOME_WALK/.claude"
touch "$HOME_WALK/.claude/.auto-pilot-active-77777"

FAKE_BIN=$(mktemp -d)
cat > "$FAKE_BIN/ps" <<'EOF'
#!/bin/bash
# Minimal ps mock honoring `ps -o command= -p <pid>` and `ps -o ppid= -p <pid>`.
field=""; target=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) field="$2"; shift 2 ;;
    -p) target="$2"; shift 2 ;;
    *) shift ;;
  esac
done
case "$target" in
  44441) [ "$field" = "command=" ] && echo "innocent-child" || echo "44442" ;;
  44442) [ "$field" = "command=" ] && echo "middle-process" || echo "77777" ;;
  77777) [ "$field" = "command=" ] && echo "claude --model opus --foo" || echo "1" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$FAKE_BIN/ps"

# Inject fake ps via PATH; force starting PPID via CLAUDE_PID_WALK_START (test-only hook)
R=$(echo '{}' | HOME="$HOME_WALK" PATH="$FAKE_BIN:$PATH" CLAUDE_PID_WALK_START=44441 bash "$SCRIPT" 2>&1) || true
assert_output "walk finds claude ancestor → ON" "🔓 ON" "$R"
rm -rf "$HOME_WALK" "$FAKE_BIN"

echo ""
echo "=== Results ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
exit "$FAIL"
