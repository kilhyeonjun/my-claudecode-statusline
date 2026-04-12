# Model Limits Display Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Sonnet/Opus model-specific usage display and eliminate ccstatusline's redundant API polling by replacing built-in usage widgets with stdin-based custom-commands.

**Architecture:** Two new bash scripts — `statusline-rate.sh` reads 5h/7d data from StatusJSON stdin (no API), `statusline-model.sh` fetches Sonnet/Opus from the usage API with a 60s cache. Four ccstatusline built-in widgets (`session-usage`, `reset-timer`, `weekly-usage`, `weekly-reset-timer`) are replaced with custom-commands, eliminating ccstatusline's independent API polling.

**Tech Stack:** bash, jq, awk, macOS Keychain (`security`), `curl`, ccstatusline v2.2.8

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `scripts/statusline-rate.sh` | 5h/7d pct + reset timer from StatusJSON stdin |
| Create | `scripts/statusline-model.sh` | Sonnet/Opus pct + reset from API cache |
| Modify | `ccstatusline/settings.json` | Replace 4 built-in widgets, add 2 model lines |
| Modify | `install.sh` | Deploy 2 new scripts to `~/.claude/scripts/` |

---

## Task 0: Feature Branch

**Files:** none

- [ ] **Create feature branch**

```bash
cd ~/kilhyeonjun-harness/projects/my-claudecode-statusline
git checkout -b feat/model-limits
```

Expected: `Switched to a new branch 'feat/model-limits'`

---

## Task 1: statusline-rate.sh (TDD)

**Files:**
- Create: `scripts/statusline-rate.sh`

Replaces `session-usage`, `reset-timer`, `weekly-usage`, `weekly-reset-timer` built-in widgets.
Reads `rate_limits.five_hour` / `rate_limits.seven_day` from StatusJSON stdin.

- [ ] **Step 1: Write the failing test**

Create `scripts/test/test-statusline-rate.sh`:

```bash
#!/bin/bash
set -e
SCRIPT="$(cd "$(dirname "$0")/.." && pwd)/statusline-rate.sh"
PASS=0; FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $desc"; PASS=$((PASS+1))
  else
    echo "FAIL: $desc | expected='$expected' actual='$actual'"; FAIL=$((FAIL+1))
  fi
}

FUTURE=9999999999  # unix ts far in future

# 5h-pct
R=$(echo '{"rate_limits":{"five_hour":{"used_percentage":19,"resets_at":'"$FUTURE"'}}}' | bash "$SCRIPT" 5h-pct)
assert_eq "5h-pct shows percentage" "19.0%" "$R"

R=$(echo '{"rate_limits":{"five_hour":{"used_percentage":5.5,"resets_at":'"$FUTURE"'}}}' | bash "$SCRIPT" 5h-pct)
assert_eq "5h-pct decimal" "5.5%" "$R"

R=$(echo '{}' | bash "$SCRIPT" 5h-pct)
assert_eq "5h-pct empty when missing" "" "$R"

# 5h-reset
NEAR=$(($(date +%s) + 600))  # 10 minutes from now
R=$(echo '{"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":'"$NEAR"'}}}' | bash "$SCRIPT" 5h-reset)
assert_eq "5h-reset shows minutes" "10m" "$R"

HOUR=$(($(date +%s) + 3660))  # ~1h1m
R=$(echo '{"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":'"$HOUR"'}}}' | bash "$SCRIPT" 5h-reset)
assert_eq "5h-reset shows hours+min" "1h1m" "$R"

R=$(echo '{}' | bash "$SCRIPT" 5h-reset)
assert_eq "5h-reset empty when missing" "" "$R"

# 7d-pct
R=$(echo '{"rate_limits":{"seven_day":{"used_percentage":37,"resets_at":'"$FUTURE"'}}}' | bash "$SCRIPT" 7d-pct)
assert_eq "7d-pct shows percentage" "37.0%" "$R"

R=$(echo '{}' | bash "$SCRIPT" 7d-pct)
assert_eq "7d-pct empty when missing" "" "$R"

# 7d-reset
DAY=$(($(date +%s) + 90000))  # ~25h
R=$(echo '{"rate_limits":{"seven_day":{"used_percentage":37,"resets_at":'"$DAY"'}}}' | bash "$SCRIPT" 7d-reset)
assert_eq "7d-reset shows days+hours" "1d1h" "$R"

[ "$FAIL" -eq 0 ] && echo "All $PASS tests passed" && exit 0
echo "$FAIL/$((PASS+FAIL)) tests FAILED" >&2 && exit 1
```

- [ ] **Step 2: Run test — expect FAIL**

```bash
bash scripts/test/test-statusline-rate.sh 2>&1 | head -5
```

Expected: error like `bash: .../statusline-rate.sh: No such file or directory`

- [ ] **Step 3: Implement statusline-rate.sh**

Create `scripts/statusline-rate.sh`:

```bash
#!/bin/bash
# Displays 5h/7d usage percentage or reset timer from StatusJSON stdin.
# Replaces ccstatusline built-in session-usage / reset-timer widgets.
#
# Usage: bash statusline-rate.sh {5h-pct|5h-reset|7d-pct|7d-reset}
# Input: Claude Code StatusJSON on stdin
set -e

MODE="$1"
input=$(cat)

case "$MODE" in
  5h-pct)   PCT_PATH='.rate_limits.five_hour.used_percentage' ;;
  7d-pct)   PCT_PATH='.rate_limits.seven_day.used_percentage' ;;
  5h-reset) RESET_PATH='.rate_limits.five_hour.resets_at' ;;
  7d-reset) RESET_PATH='.rate_limits.seven_day.resets_at' ;;
  *)        exit 0 ;;
esac

if [ -n "${PCT_PATH:-}" ]; then
  PCT=$(printf '%s' "$input" | jq -r "${PCT_PATH} // empty" 2>/dev/null)
  [ -z "$PCT" ] && exit 0
  printf '%.1f%%\n' "$PCT"
  exit 0
fi

# Reset timer mode
RESETS=$(printf '%s' "$input" | jq -r "${RESET_PATH} // empty" 2>/dev/null)
[ -z "$RESETS" ] && exit 0
NOW=$(date +%s)
REMAINING=$((RESETS - NOW))
[ "$REMAINING" -le 0 ] && exit 0

awk -v r="$REMAINING" 'BEGIN {
  function fmt(s,   d, h, m) {
    if (s < 3600) return sprintf("%dm", int(s/60))
    if (s < 86400) {
      h = int(s/3600); m = int((s % 3600) / 60)
      if (m == 0) return sprintf("%dh", h)
      return sprintf("%dh%dm", h, m)
    }
    d = int(s/86400); h = int((s % 86400) / 3600)
    if (h == 0) return sprintf("%dd", d)
    return sprintf("%dd%dh", d, h)
  }
  print fmt(r)
}'
```

- [ ] **Step 4: Run test — expect PASS**

```bash
bash scripts/test/test-statusline-rate.sh
```

Expected: `All 9 tests passed`

- [ ] **Step 5: Commit**

```bash
git add scripts/statusline-rate.sh scripts/test/test-statusline-rate.sh
git commit -m "feat: add statusline-rate.sh — 5h/7d pct+reset from StatusJSON stdin"
```

---

## Task 2: statusline-model.sh (TDD)

**Files:**
- Create: `scripts/statusline-model.sh`

Displays `Son: 14% → 2hr 42m` for Sonnet/Opus. Fetches from usage API with 60s cache.

- [ ] **Step 1: Write the failing test**

Create `scripts/test/test-statusline-model.sh`:

```bash
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
# Force fresh (touch to set mtime to now)
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
```

- [ ] **Step 2: Run test — expect FAIL**

```bash
bash scripts/test/test-statusline-model.sh 2>&1 | head -5
```

Expected: error like `No such file or directory`

- [ ] **Step 3: Implement statusline-model.sh**

Create `scripts/statusline-model.sh`:

```bash
#!/bin/bash
# Displays Sonnet/Opus model-specific usage from Claude usage API.
#
# Usage: bash statusline-model.sh {sonnet|opus}
# Output: "Son: 14% → 2hr 42m" or empty (auto-hidden by ccstatusline)
set -e

MODE="$1"
case "$MODE" in
  sonnet) FIELD="seven_day_sonnet"; LABEL="Son" ;;
  opus)   FIELD="seven_day_opus";   LABEL="Opu" ;;
  *)      exit 0 ;;
esac

CACHE_DIR="$HOME/.cache/my-claudecode-statusline"
# Allow test override
CACHE_FILE="${STATUSLINE_TEST_CACHE:-$CACHE_DIR/usage.json}"
CACHE_TTL=60

_get_token() {
  local acct raw secret
  raw=$(security dump-keychain 2>/dev/null) || return 1
  acct=$(printf '%s' "$raw" | awk '
    /Claude Code-credentials/ { found=1 }
    found && /"acct"/ {
      match($0, /"([^"]+)"$/, a)
      if (a[1] != "") { print a[1]; exit }
    }
  ')
  [ -z "$acct" ] && return 1
  secret=$(security find-generic-password \
    -s "Claude Code-credentials" -a "$acct" -w 2>/dev/null) || return 1
  printf '%s' "$secret" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    t = d.get('claudeAiOauth', {}).get('accessToken', '')
    if t: print(t)
except: pass
" 2>/dev/null
}

_refresh_cache() {
  [ "${STATUSLINE_SKIP_FETCH:-0}" = "1" ] && return 1
  local token
  token=$(_get_token) || return 1
  mkdir -p "$CACHE_DIR"
  curl -sf \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: oauth-2025-04-20" \
    "https://api.anthropic.com/api/oauth/usage" \
    > "${CACHE_FILE}.tmp" 2>/dev/null && mv "${CACHE_FILE}.tmp" "$CACHE_FILE" || return 1
}

# Check cache freshness
if [ -f "$CACHE_FILE" ]; then
  cache_mtime=$(date -r "$CACHE_FILE" +%s 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
  cache_age=$(( $(date +%s) - cache_mtime ))
  [ "$cache_age" -ge "$CACHE_TTL" ] && _refresh_cache 2>/dev/null || true
else
  _refresh_cache 2>/dev/null || true
fi

[ ! -f "$CACHE_FILE" ] && exit 0

# Parse field
ENTRY=$(jq -r ".${FIELD} // empty" "$CACHE_FILE" 2>/dev/null)
[ -z "$ENTRY" ] || [ "$ENTRY" = "null" ] && exit 0

PCT=$(printf '%s' "$ENTRY" | jq -r '.utilization // empty' 2>/dev/null)
[ -z "$PCT" ] && exit 0

RESETS_ISO=$(printf '%s' "$ENTRY" | jq -r '.resets_at // empty' 2>/dev/null)
[ -z "$RESETS_ISO" ] && exit 0

# Parse ISO8601 → unix ts (strip fractional + tz)
RESETS_CLEAN="${RESETS_ISO%%.*}"  # "2026-04-13T05:00:00"
RESETS_TS=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$RESETS_CLEAN" +%s 2>/dev/null \
         || TZ=UTC date -d "${RESETS_CLEAN}Z" +%s 2>/dev/null \
         || echo 0)

NOW=$(date +%s)
REMAINING=$((RESETS_TS - NOW))

awk -v pct="$PCT" -v rem="$REMAINING" -v label="$LABEL" 'BEGIN {
  function fmt(s,   d, h, m) {
    if (s <= 0) return "soon"
    if (s < 3600) return sprintf("%dm", int(s/60))
    if (s < 86400) {
      h = int(s/3600); m = int((s % 3600) / 60)
      if (m == 0) return sprintf("%dh", h)
      return sprintf("%dh%dm", h, m)
    }
    d = int(s/86400); h = int((s % 86400) / 3600)
    if (h == 0) return sprintf("%dd", d)
    return sprintf("%dd%dh", d, h)
  }
  printf "%s: %.0f%%  →  %s\n", label, pct, fmt(rem)
}'
```

- [ ] **Step 4: Run test — expect PASS**

```bash
bash scripts/test/test-statusline-model.sh
```

Expected: `All 4 tests passed`

- [ ] **Step 5: Commit**

```bash
git add scripts/statusline-model.sh scripts/test/test-statusline-model.sh
git commit -m "feat: add statusline-model.sh — Sonnet/Opus usage from API cache"
```

---

## Task 3: Update ccstatusline/settings.json

**Files:**
- Modify: `ccstatusline/settings.json`

Replace 4 built-in widgets on lines 5 & 6 with custom-commands. Add 2 model lines.

- [ ] **Step 1: Update settings.json**

Replace the full `lines` array in `ccstatusline/settings.json`.
Lines 1–4 and 7–8 are unchanged. Lines 5–6 replace built-in widgets. Lines 7–8 are new model lines. Old lines 7–8 become 9–10.

Replace the `"lines"` array with:

```json
"lines": [
  [
    { "id": "l1-model",   "type": "model",              "color": "cyan" },
    { "id": "l1-sep1",    "type": "separator" },
    { "id": "l1-cwd",     "type": "current-working-dir","color": "blue" }
  ],
  [
    { "id": "l2-branch",  "type": "git-branch",  "color": "magenta" },
    { "id": "l2-sep1",    "type": "separator" },
    { "id": "l2-changes", "type": "git-changes", "color": "yellow" }
  ],
  [
    { "id": "l3-ctxbar",  "type": "context-bar",    "color": "green" },
    { "id": "l3-sep1",    "type": "separator" },
    { "id": "l3-ctxburn", "type": "custom-command",
      "commandPath": "bash __CLAUDE_SCRIPTS__/statusline-burn.sh ctx",
      "timeout": 2000, "color": "brightBlack", "preserveColors": false }
  ],
  [
    { "id": "l4-cost",  "type": "session-cost",  "color": "brightYellow" },
    { "id": "l4-sep1",  "type": "separator" },
    { "id": "l4-clock", "type": "session-clock", "color": "brightBlack" }
  ],
  [
    { "id": "l5-label5h", "type": "custom-text", "customText": "5h:", "color": "brightBlack" },
    { "id": "l5-pct",     "type": "custom-command",
      "commandPath": "bash __CLAUDE_SCRIPTS__/statusline-rate.sh 5h-pct",
      "timeout": 2000, "color": "brightCyan", "preserveColors": false },
    { "id": "l5-eta",     "type": "custom-text", "customText": "→", "color": "brightBlack" },
    { "id": "l5-reset",   "type": "custom-command",
      "commandPath": "bash __CLAUDE_SCRIPTS__/statusline-rate.sh 5h-reset",
      "timeout": 2000, "color": "brightBlack", "preserveColors": false },
    { "id": "l5-sep2",    "type": "separator" },
    { "id": "l5-burn",    "type": "custom-command",
      "commandPath": "bash __CLAUDE_SCRIPTS__/statusline-burn.sh 5h",
      "timeout": 2000, "color": "brightCyan", "preserveColors": false }
  ],
  [
    { "id": "l6-label7d", "type": "custom-text", "customText": "7d:", "color": "brightBlack" },
    { "id": "l6-pct",     "type": "custom-command",
      "commandPath": "bash __CLAUDE_SCRIPTS__/statusline-rate.sh 7d-pct",
      "timeout": 2000, "color": "brightMagenta", "preserveColors": false },
    { "id": "l6-eta",     "type": "custom-text", "customText": "→", "color": "brightBlack" },
    { "id": "l6-reset",   "type": "custom-command",
      "commandPath": "bash __CLAUDE_SCRIPTS__/statusline-rate.sh 7d-reset",
      "timeout": 2000, "color": "brightBlack", "preserveColors": false },
    { "id": "l6-sep2",    "type": "separator" },
    { "id": "l6-burn",    "type": "custom-command",
      "commandPath": "bash __CLAUDE_SCRIPTS__/statusline-burn.sh 7d",
      "timeout": 2000, "color": "brightMagenta", "preserveColors": false }
  ],
  [
    { "id": "l7-sonnet",  "type": "custom-command",
      "commandPath": "bash __CLAUDE_SCRIPTS__/statusline-model.sh sonnet",
      "timeout": 3000, "color": "brightCyan", "preserveColors": false }
  ],
  [
    { "id": "l8-opus",    "type": "custom-command",
      "commandPath": "bash __CLAUDE_SCRIPTS__/statusline-model.sh opus",
      "timeout": 3000, "color": "brightMagenta", "preserveColors": false }
  ],
  [
    { "id": "l9-skills",  "type": "skills", "color": "brightMagenta",
      "metadata": { "mode": "list", "hideWhenEmpty": "true", "listLimit": "6" } }
  ],
  [
    { "id": "l10-agents", "type": "custom-command",
      "commandPath": "bash __CLAUDE_SCRIPTS__/statusline-subagents.sh",
      "timeout": 2500, "color": "brightGreen", "preserveColors": false }
  ]
]
```

- [ ] **Step 2: Validate JSON**

```bash
jq . ccstatusline/settings.json > /dev/null && echo "valid JSON"
```

Expected: `valid JSON`

- [ ] **Step 3: Commit**

```bash
git add ccstatusline/settings.json
git commit -m "feat: replace built-in usage widgets with custom-commands, add Sonnet/Opus lines"
```

---

## Task 4: Update install.sh

**Files:**
- Modify: `install.sh`

Deploy `statusline-rate.sh` and `statusline-model.sh` to `~/.claude/scripts/`.

- [ ] **Step 1: Find the existing script deployment block**

```bash
grep -n "statusline-burn\|statusline-subagents\|SCRIPTS_DIR\|claude/scripts" install.sh | head -20
```

Note the line numbers of the copy/chmod block for `statusline-burn.sh`.

- [ ] **Step 2: Add new scripts to the deployment loop**

`install.sh:111` has a `for script in` loop. Change that line to:

```bash
for script in statusline-subagents.sh statusline-burn.sh statusline-rate.sh statusline-model.sh; do
```

- [ ] **Step 3: Verify install.sh is valid**

```bash
bash -n install.sh && echo "syntax OK"
```

Expected: `syntax OK`

- [ ] **Step 4: Run dry-run install**

```bash
bash install.sh --dry-run 2>&1 | grep -E "rate|model|would"
```

Expected: lines mentioning `statusline-rate.sh` and `statusline-model.sh`

- [ ] **Step 5: Commit**

```bash
git add install.sh
git commit -m "feat: deploy statusline-rate.sh and statusline-model.sh in install.sh"
```

---

## Task 5: Integration Verification

- [ ] **Step 1: Run all tests**

```bash
bash scripts/test/test-statusline-rate.sh && bash scripts/test/test-statusline-model.sh
```

Expected: both exit 0 with `All N tests passed`

- [ ] **Step 2: Install and verify live**

```bash
bash install.sh
```

Expected: no errors, mentions deploying `statusline-rate.sh` and `statusline-model.sh`

- [ ] **Step 3: Verify Son line appears**

Open a new Claude Code session. Check the status bar shows `Son: XX% → Xhr Ym`.

- [ ] **Step 4: Create PR**

```bash
git log --oneline main..HEAD
gh pr create \
  --title "feat: model-specific limits display + eliminate ccstatusline API polling" \
  --body "$(cat <<'EOF'
## Summary

- Add `statusline-rate.sh` — replaces ccstatusline built-in usage widgets using StatusJSON stdin (no API)
- Add `statusline-model.sh` — displays Sonnet/Opus model limit from usage API with 60s cache
- Remove `session-usage`, `reset-timer`, `weekly-usage`, `weekly-reset-timer` ccstatusline widgets
- ccstatusline makes 0 usage API calls; one cache covers all model data

## Test plan
- [ ] `bash scripts/test/test-statusline-rate.sh` passes
- [ ] `bash scripts/test/test-statusline-model.sh` passes
- [ ] Status bar shows `Son: XX% → Xhr Ym` line
- [ ] Opus line hidden when null
- [ ] `bash install.sh --dry-run` mentions both new scripts

🤖 Assisted by [kilhyeonjun-harness](https://github.com/kilhyeonjun/kilhyeonjun-harness)
EOF
)"
```
