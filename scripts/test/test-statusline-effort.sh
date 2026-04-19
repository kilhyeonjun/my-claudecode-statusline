#!/bin/bash
# Test suite for statusline-effort.sh
# Validates effort level label mapping, settings.json priority (project > user-global),
# and graceful fallback on missing jq, missing files, or unknown values.
set -u

SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/statusline-effort.sh"
TMPDIR_TEST=$(mktemp -d)
trap "rm -rf '$TMPDIR_TEST'" EXIT

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

assert_output() {
  local test_name="$1"
  local expected="$2"
  local actual="$3"

  if [ "$actual" = "$expected" ]; then
    echo "✓ $test_name"
    ((TESTS_PASSED++))
  else
    echo "✗ $test_name"
    echo "  Expected: '$expected'"
    echo "  Actual:   '$actual'"
    ((TESTS_FAILED++))
  fi
}

run_test() {
  local settings_content="$1"
  local project_settings_content="${2:-}"
  local claude_project_dir="${3:-}"

  # Create isolated HOME
  local test_home=$(mktemp -d)
  mkdir -p "$test_home/.claude"

  if [ -n "$settings_content" ]; then
    echo "$settings_content" > "$test_home/.claude/settings.json"
  fi

  local test_project=""
  if [ -n "$project_settings_content" ]; then
    test_project=$(mktemp -d)
    mkdir -p "$test_project/.claude"
    echo "$project_settings_content" > "$test_project/.claude/settings.json"
  fi

  # Run script with isolated HOME
  local output
  output=$(HOME="$test_home" CLAUDE_PROJECT_DIR="${test_project:-}" bash "$SCRIPT" </dev/null 2>/dev/null)

  # Cleanup
  rm -rf "$test_home" "$test_project"

  echo "$output"
}

# Test 1: effortLevel = "max" → "⚡ MAX"
echo "Test 1: max effort level"
OUTPUT=$(run_test '{"effortLevel": "max"}')
assert_output "effortLevel=max" "⚡ MAX" "$OUTPUT"

# Test 2: effortLevel = "xhigh" → "⚡ XHIGH"
echo "Test 2: xhigh effort level"
OUTPUT=$(run_test '{"effortLevel": "xhigh"}')
assert_output "effortLevel=xhigh" "⚡ XHIGH" "$OUTPUT"

# Test 3: effortLevel = "high" → "⬆ HIGH"
echo "Test 3: high effort level"
OUTPUT=$(run_test '{"effortLevel": "high"}')
assert_output "effortLevel=high" "⬆ HIGH" "$OUTPUT"

# Test 4: effortLevel = "medium" → "· MED"
echo "Test 4: medium effort level"
OUTPUT=$(run_test '{"effortLevel": "medium"}')
assert_output "effortLevel=medium" "· MED" "$OUTPUT"

# Test 5: effortLevel = "low" → "⬇ LOW"
echo "Test 5: low effort level"
OUTPUT=$(run_test '{"effortLevel": "low"}')
assert_output "effortLevel=low" "⬇ LOW" "$OUTPUT"

# Test 6: Missing effortLevel field → empty output (widget hidden)
echo "Test 6: missing effortLevel"
OUTPUT=$(run_test '{}')
assert_output "missing effortLevel" "" "$OUTPUT"

# Test 7: Unknown effortLevel value → "? <value>"
echo "Test 7: unknown effort level"
OUTPUT=$(run_test '{"effortLevel": "weird"}')
assert_output "unknown value" "? weird" "$OUTPUT"

# Test 8: Project override priority > user-global
echo "Test 8: project override priority"
OUTPUT=$(run_test '{"effortLevel": "low"}' '{"effortLevel": "max"}')
assert_output "project overrides user-global" "⚡ MAX" "$OUTPUT"

# Test 9: Missing settings.json at both levels → empty output
echo "Test 9: missing settings.json files"
OUTPUT=$(run_test '')
assert_output "missing all settings.json" "" "$OUTPUT"

# Test 10: Stdin is consumed (no error)
echo "Test 10: stdin consumed"
OUTPUT=$(echo "some input" | run_test '{"effortLevel": "high"}')
assert_output "stdin consumed" "⬆ HIGH" "$OUTPUT"

# Test 11: Script exits with 0
echo "Test 11: exit code 0"
run_test '{"effortLevel": "high"}' >/dev/null
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
  echo "✓ exit code 0"
  ((TESTS_PASSED++))
else
  echo "✗ exit code 0 (got $EXIT_CODE)"
  ((TESTS_FAILED++))
fi

# Summary
echo ""
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
[ $TESTS_FAILED -eq 0 ] && exit 0 || exit 1
