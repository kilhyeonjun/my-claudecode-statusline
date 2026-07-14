#!/bin/bash
set -e
LIB="$(cd "$(dirname "$0")/.." && pwd)/statusline-lib.sh"
PASS=0; FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $desc"; PASS=$((PASS+1))
  else
    echo "FAIL: $desc | expected='$expected' actual='$actual'"; FAIL=$((FAIL+1))
  fi
}

source "$LIB"

# fmt_dur: seconds-only
R=$(fmt_dur 45)
assert_eq "fmt_dur seconds" "45s" "$R"

# fmt_dur: minutes
R=$(fmt_dur 600)
assert_eq "fmt_dur minutes" "10m" "$R"

# fmt_dur: hours+minutes
R=$(fmt_dur 12000)  # 3h20m
assert_eq "fmt_dur hours+minutes" "3h20m" "$R"

# fmt_dur: exact hours (no dangling 0m)
R=$(fmt_dur 3600)
assert_eq "fmt_dur exact hour" "1h" "$R"

# fmt_dur: days+hours
R=$(fmt_dur 183600)  # 2d3h
assert_eq "fmt_dur days+hours" "2d3h" "$R"

# fmt_dur: exact days (no dangling 0h)
R=$(fmt_dur 172800)
assert_eq "fmt_dur exact day" "2d" "$R"

# fmt_dur: round-to-minute avoids "Xh60m" overflow
R=$(fmt_dur 3599.6)
assert_eq "fmt_dur rounds to minute boundary" "1h" "$R"

# burn_project: urgent (hits 100%)
R=$(burn_project 80 3000 18000)  # rate=80/3000=0.0267/s -> projected=480 -> way over
assert_match_regex() {
  local desc="$1" pattern="$2" actual="$3"
  if [[ "$actual" =~ $pattern ]]; then
    echo "PASS: $desc"; PASS=$((PASS+1))
  else
    echo "FAIL: $desc | pattern='$pattern' actual='$actual'"; FAIL=$((FAIL+1))
  fi
}
assert_match_regex "burn_project urgent format" '^🔥 [0-9]+\.[0-9]x → 100% in ' "$R"

# burn_project: warning (projected 90-99%)
R=$(burn_project 30 3000 18000)  # rate=0.01/s -> projected=180... need 90-99 band, tune below
# Solve for projected in [90,100): used=U, elapsed=E, window=W=18000
# rate=U/E, projected=rate*W
# Pick U=25, E=15000 -> rate=0.001667 -> projected=30 (too low); recompute directly with awk-verified values instead
R=$(burn_project 18.9 18000 18000)  # elapsed==window, rate=18.9/18000, projected=18.9 (under)
# Use explicit precomputed cases instead of guessing:
R=$(burn_project 47 10000 18000)  # rate=0.0047, projected=84.6 -> ✓ band actually (60-90)
assert_match_regex "burn_project on-track format (✓)" '^✓ [0-9]+\.[0-9]x → ends ~[0-9]+%$' "$R"

R=$(burn_project 50 10000 18000)  # rate=0.005, projected=90 -> ⚠ band (>=90)
assert_match_regex "burn_project warning format (⚠)" '^⚠ [0-9]+\.[0-9]x → ends ~[0-9]+%$' "$R"

R=$(burn_project 5 10000 18000)  # rate=0.0005, projected=9 -> under-using (· band)
assert_match_regex "burn_project under-using format (·)" '^· [0-9]+\.[0-9]x → ends ~[0-9]+%$' "$R"

R=$(burn_project 100 5000 18000)  # already >=100 used, remain<=0
assert_eq "burn_project empty when already at/over limit with no remain" "" "$R"

R=$(burn_project 0 5000 18000)
assert_eq "burn_project empty when used<=0" "" "$R"

R=$(burn_project 10 0 18000)
assert_eq "burn_project empty when elapsed<=0" "" "$R"

[ "$FAIL" -eq 0 ] && echo "All $PASS tests passed" && exit 0
echo "$FAIL/$((PASS+FAIL)) tests FAILED" >&2 && exit 1
