# my-claudecode-statusline

Personal [Claude Code](https://claude.com/claude-code) status line on top of
[ccstatusline](https://github.com/sirmalloc/ccstatusline), with burn-rate analysis,
subagent tracking, and skills usage.

An 8-line status bar designed for readability and pacing awareness — so you can
slow down before hitting a 5-hour limit instead of after.

## What it shows

```
 Model: Opus 4.6  |  cwd: /path/to/project
 ⎇ main  |  +5 ~3
 Context: [██████████░░░░░░] 650k/1000k (65%)  |  🔥 full in 8m
 Cost: $3.45  |  Session: 15m
 5h:  80.0%  →  3hr 59m  |  🔥 4.0x → 100% in 15m
 7d:  60.0%  →  3d 23hr 59m  |  🔥 1.4x → 100% in 2d
 Skills: brainstorming, commit, debug
 🤖 ▶ Explore 2m · ▶ Plan 30s · ✓ code-reviewer 2m
```

Empty lines (skills, subagents) are auto-hidden, so an idle session collapses to
six lines.

## Features

- **Burn rate** for 5h / 7d rate limits and the context window: projected
  end-of-window usage, ETA to 100%, and a pace multiplier so you know whether
  you're running hot (`🔥 2.0x`), on pace (`⚠ 1.0x`), or underusing (`· 0.3x`).
- **Context ETA**: "full in 8m" tells you when to run `/compact`, before
  context fills up mid-thought.
- **Subagent monitor**: lists currently running `Task` / `Agent` subagents with
  elapsed time, plus recently completed ones (5-minute fade) marked with
  `✓` or `✗`.
- **Skills list**: shows which Claude Code skills have fired this session
  (via `PreToolUse` + `UserPromptSubmit` hooks registered by the installer).
- **Rate limits with ETA**: 5h and 7d usage percentages alongside
  "time until reset".

## Requirements

- **macOS** (primary target). Linux is best-effort — the subagent script has a
  GNU `date` fallback but has not been extensively tested there.
- [`jq`](https://jqlang.github.io/jq/)
- [`bun`](https://bun.sh) or [`node` + `npm`](https://nodejs.org) (for the
  `ccstatusline` npm package)
- [Claude Code](https://claude.com/claude-code) itself

## Install

```bash
git clone https://github.com/kilhyeonjun/my-claudecode-statusline.git
cd my-claudecode-statusline
./install.sh
```

Preview what will change first:

```bash
./install.sh --dry-run
```

See the full merged settings:

```bash
./install.sh --verbose
```

The installer:

1. Installs `ccstatusline` globally via `bun` (or `npm` as fallback) if missing.
2. Copies the helper scripts into `~/.claude/scripts/`.
3. Writes `~/.config/ccstatusline/settings.json` (with absolute paths
   substituted for your user).
4. Merges `statusLine` and `Skill` hooks into `~/.claude/settings.json`,
   preserving all your existing hooks and plugin config.

Running the installer again is safe — it removes stale `ccstatusline` hook
entries before re-adding fresh ones, so it acts as an upgrade step.

Timestamped backups are stored next to the originals:

```
~/.claude/settings.json.bak-20260410-140000
~/.config/ccstatusline/settings.json.bak-20260410-140000
```

## Uninstall

```bash
./uninstall.sh
```

Restores both settings files from the most recent timestamped backups. If no
backup exists, it uses `jq` to strip the `ccstatusline` entries it added and
leaves everything else untouched. The `ccstatusline` npm package is not
removed — do that manually with `bun remove -g ccstatusline` or
`npm uninstall -g ccstatusline`.

## Layout

The ccstatusline config lives at `ccstatusline/settings.json` as a template
with a single placeholder (`__CLAUDE_SCRIPTS__`) that the installer replaces
with the real path.

| Line | Widgets                                                              |
| ---- | -------------------------------------------------------------------- |
| 1    | `model` · `current-working-dir`                                      |
| 2    | `git-branch` · `git-changes`                                         |
| 3    | `context-bar` · custom-command (`statusline-burn.sh ctx`)            |
| 4    | `session-cost` · `session-clock`                                     |
| 5    | `5h:` · `session-usage` → `reset-timer` · custom-command (`5h`)      |
| 6    | `7d:` · `weekly-usage` → `weekly-reset-timer` · custom-command (`7d`)|
| 7    | `skills` (list mode, `hideWhenEmpty`)                                |
| 8    | custom-command (`statusline-subagents.sh`)                           |

`flexMode` is set to `"full"` — the status line uses the full terminal width
instead of the default `full-minus-40`, which avoids truncating long paths.

## Customization

Edit `~/.config/ccstatusline/settings.json` directly (it is regular JSON, and
a TUI is available via `ccstatusline`), or run `ccstatusline` without stdin
to get an interactive widget editor from the upstream project.

To tweak the subagent display thresholds, edit
`~/.claude/scripts/statusline-subagents.sh`:

- `MAX_AGE_SEC=300` — how many seconds a completed subagent stays visible
- `MAX_SHOW=6` — maximum number of subagents to list

To tweak burn-rate thresholds, edit `~/.claude/scripts/statusline-burn.sh`:
the `awk` block near the bottom decides when to show 🔥 vs ⚠ vs ✓ vs ·.

## How burn rate is calculated

For a window with a known reset time:

```
elapsed        = window_seconds - (reset_at - now)
rate_per_sec   = current_used_percentage / elapsed
projected_pct  = rate_per_sec * window_seconds
burn           = projected_pct / 100
eta_to_100_sec = (100 - current_used_percentage) / rate_per_sec
```

For the context window (no time-based reset), only `eta_to_100_sec` is shown
since the notion of "projected end of window" does not apply.

The first minute of any window is ignored — the sample is too small to produce
a meaningful rate, so 5h/7d/ctx burn stays blank until a real rate can be
estimated.

## Notes

- **Rate limit widgets (5h, 7d) require a Claude.ai Pro/Max subscription.**
  API-only accounts will see `ctx` burn but blank 5h/7d lines. The burn script
  exits silently when `rate_limits` is absent, so no "no data" noise.
- **Tested against ccstatusline v2.2.8** as of 2026-04. If widget type names
  change upstream, the template may need updates.
- The Skills widget shows nothing until a skill is actually invoked, because
  it reads from a hook-populated state file. This is expected behavior.

## License

MIT — see [LICENSE](LICENSE).
