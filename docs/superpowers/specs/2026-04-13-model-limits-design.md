# Model Limits Display — Design Spec

**Date:** 2026-04-13 | **Status:** Approved

## Goal

Add Sonnet/Opus model-specific usage. Eliminate ccstatusline's redundant API polling.

## Architecture

```
StatusJSON (stdin) → statusline-rate.sh   5h/7d pct + reset (always fresh, no API)
                  → statusline-burn.sh   ctx/5h/7d burn      (unchanged)

~/.cache/my-claudecode-statusline/usage.json (TTL 60s)
  └─ stale → api.anthropic.com/api/oauth/usage (1 call covers all)
      └─ statusline-model.sh  Son/Opu display
```

ccstatusline API polling = 0. One endpoint, one cache.

## New Scripts

### `statusline-rate.sh`

Replaces built-in `session-usage`, `weekly-usage`, `reset-timer`, `weekly-reset-timer`.  
Input: StatusJSON stdin. Modes: `5h-pct` | `5h-reset` | `7d-pct` | `7d-reset`.  
Empty output when data absent (API-only accounts).

### `statusline-model.sh`

Input: cache (TTL 60s) → API fallback.  
Token: discovered via `security dump-keychain` (same logic as ccstatusline, not hardcoded).  
Modes: `sonnet` | `opus`. Output: `Son: 14% → 2hr 42m` or empty (auto-hidden).  
**No burn rate:** `seven_day_sonnet.resets_at` window duration is unknown — API does not
expose it. Show pct + time-to-reset only. Add burn rate if Anthropic exposes window later.

## settings.json

Remove: `session-usage`, `reset-timer`, `weekly-usage`, `weekly-reset-timer` widgets.  
Replace: custom-commands for `statusline-rate.sh` (4 widgets).  
Add after line 6: `statusline-model.sh sonnet`, `statusline-model.sh opus` (timeout 3000ms).

## install.sh

Deploy `statusline-rate.sh`, `statusline-model.sh` to `~/.claude/scripts/`.

## Result Layout

```
5h:  19%  →  2hr 42m  |  ⚠ burn
7d:  37%  →  4d 3hr   |  · burn
Son: 14%  →  2hr 42m
Opu: (hidden when null)
```

## Error Handling

All failures → empty output (silent). Cache write failure → use in-memory result.

## Testing

```bash
echo '{"rate_limits":{"five_hour":{"used_percentage":19,"resets_at":9999999999}}}' \
  | bash statusline-rate.sh 5h-pct        # → "19.0%"
echo '{}' | bash statusline-rate.sh 5h-pct  # → (empty)
bash statusline-model.sh sonnet            # → "Son: 14% → 2hr 42m" or empty
bash statusline-model.sh opus              # → empty (when null)
```
