#!/bin/bash
set -e
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/statusline-burn.sh"
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

# Urgent: <10 min to full
R=$(printf '%s' '{"context_window":{"used_percentage":90},"cost":{"total_duration_ms":300000}}' | bash "$SCRIPT")
assert_match "urgent: fire emoji, full in Xm" '^🔥 full in ' "$R"

# Warning: 10-30 min to full (used=20%, elapsed=300s -> rate=0.0667%/s,
# remain=80% -> eta=1200s=20m)
R=$(printf '%s' '{"context_window":{"used_percentage":20},"cost":{"total_duration_ms":300000}}' | bash "$SCRIPT")
assert_match "warning: warn emoji, full in Xm" '^⚠ full in ' "$R"

# Plenty of room
R=$(printf '%s' '{"context_window":{"used_percentage":5},"cost":{"total_duration_ms":300000}}' | bash "$SCRIPT")
assert_match "plenty: full in Xh, no emoji prefix" '^full in ' "$R"

# Guard: missing context_window.used_percentage -> "·" not empty
R=$(printf '%s' '{"cost":{"total_duration_ms":300000}}' | bash "$SCRIPT")
assert_eq "guard: missing used_percentage -> placeholder" "·" "$R"

# Guard: missing cost.total_duration_ms -> "·"
R=$(printf '%s' '{"context_window":{"used_percentage":50}}' | bash "$SCRIPT")
assert_eq "guard: missing duration -> placeholder" "·" "$R"

# Guard: elapsed <= 60s -> "·"
R=$(printf '%s' '{"context_window":{"used_percentage":50},"cost":{"total_duration_ms":30000}}' | bash "$SCRIPT")
assert_eq "guard: elapsed<=60s -> placeholder" "·" "$R"

# Guard: used <= 0 -> "·"
R=$(printf '%s' '{"context_window":{"used_percentage":0},"cost":{"total_duration_ms":300000}}' | bash "$SCRIPT")
assert_eq "guard: used<=0 -> placeholder" "·" "$R"

# Guard: totally empty input -> "·"
R=$(printf '%s' '{}' | bash "$SCRIPT")
assert_eq "guard: empty input -> placeholder" "·" "$R"

# Always exits 0
printf '%s' '{}' | bash "$SCRIPT" >/dev/null
CODE=$?
assert_eq "always exits 0" "0" "$CODE"

# Malformed stdin must never crash the widget (idiom rule 5: exit 0 always)
printf '' | bash "$SCRIPT" >/dev/null; CODE=$?
assert_eq "empty stdin -> exit 0" "0" "$CODE"

printf 'not json' | bash "$SCRIPT" >/dev/null; CODE=$?
assert_eq "non-JSON stdin -> exit 0" "0" "$CODE"

printf '{"context_window":' | bash "$SCRIPT" >/dev/null; CODE=$?
assert_eq "truncated JSON stdin -> exit 0" "0" "$CODE"

# Ignores legacy args (backward-compat with settings.json 'statusline-burn.sh ctx')
R=$(printf '%s' '{"context_window":{"used_percentage":5},"cost":{"total_duration_ms":300000}}' | bash "$SCRIPT" ctx)
assert_match "ignores legacy 'ctx' arg, still works" '^full in ' "$R"

# stdin consumed exactly once, single line output
R=$(printf '%s' '{"context_window":{"used_percentage":5},"cost":{"total_duration_ms":300000}}' | bash "$SCRIPT" 2>&1)
LINES=$(printf '%s' "$R" | wc -l | tr -d ' ')
assert_eq "single-line output" "0" "$LINES"

[ "$FAIL" -eq 0 ] && echo "All $PASS tests passed" && exit 0
echo "$FAIL/$((PASS+FAIL)) tests FAILED" >&2 && exit 1
