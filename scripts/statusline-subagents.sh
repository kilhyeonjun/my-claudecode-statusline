#!/bin/bash
# Reports currently running and recently completed Task/Agent subagents
# by parsing the Claude Code session transcript (.jsonl) from stdin.
#
# Input:  Claude Code StatusJSON on stdin (must contain transcript_path)
# Output: a single line like:
#           🤖 ▶ Explore 2m · ▶ Plan 30s · ✓ code-reviewer 1m
#         or empty if no running / recently-completed subagents.
#
# Completed subagents are shown for MAX_AGE_SEC seconds after finishing,
# then hidden. Failed ones are marked with ✗.
set -e

input=$(cat)
TRANSCRIPT=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)

[ -z "$TRANSCRIPT" ] && exit 0
[ ! -f "$TRANSCRIPT" ] && exit 0

MAX_AGE_SEC=300
MAX_SHOW=6
NOW=$(date +%s)

TASK_LIST=$(jq -r '
  select(.type=="assistant")
  | .timestamp as $ts
  | .message.content[]?
  | select(.type=="tool_use" and (.name=="Agent" or .name=="Task"))
  | "\(.id)\t\(.input.subagent_type // "agent")\t\($ts)"
' "$TRANSCRIPT" 2>/dev/null)

[ -z "$TASK_LIST" ] && exit 0

RESULT_LIST=$(jq -r '
  select(.type=="user")
  | .timestamp as $ts
  | .message.content[]?
  | select(.type=="tool_result")
  | "\(.tool_use_id)\t\($ts)\t\(.is_error // false)"
' "$TRANSCRIPT" 2>/dev/null)

declare -A result_ts
declare -A result_err

if [ -n "$RESULT_LIST" ]; then
  while IFS=$'\t' read -r rid rts rerr; do
    [ -z "$rid" ] && continue
    result_ts[$rid]="$rts"
    result_err[$rid]="$rerr"
  done <<< "$RESULT_LIST"
fi

parse_utc() {
  local ts="${1%.*}"
  TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$ts" +%s 2>/dev/null \
    || TZ=UTC date -d "${ts}Z" +%s 2>/dev/null \
    || echo 0
}

format_dur() {
  local s=$1
  local m h r
  if [ "$s" -lt 60 ]; then
    printf '%ds' "$s"
  elif [ "$s" -lt 3600 ]; then
    m=$((s / 60))
    r=$((s % 60))
    if [ "$r" -eq 0 ]; then
      printf '%dm' "$m"
    else
      printf '%dm%ds' "$m" "$r"
    fi
  else
    h=$((s / 3600))
    m=$(((s % 3600) / 60))
    if [ "$m" -eq 0 ]; then
      printf '%dh' "$h"
    else
      printf '%dh%dm' "$h" "$m"
    fi
  fi
}

RUNNING=""
RECENT_DONE=""
TOTAL_SHOWN=0

while IFS=$'\t' read -r id name start_ts; do
  [ -z "$id" ] && continue
  [ "$TOTAL_SHOWN" -ge "$MAX_SHOW" ] && break

  start_epoch=$(parse_utc "$start_ts")
  [ "$start_epoch" = "0" ] && continue

  end_ts="${result_ts[$id]:-}"
  err="${result_err[$id]:-false}"

  if [ -n "$end_ts" ]; then
    end_epoch=$(parse_utc "$end_ts")
    [ "$end_epoch" = "0" ] && continue

    age=$((NOW - end_epoch))
    [ "$age" -gt "$MAX_AGE_SEC" ] && continue

    duration=$((end_epoch - start_epoch))
    [ "$duration" -lt 0 ] && duration=0

    DUR=$(format_dur "$duration")
    if [ "$err" = "true" ]; then
      ICON="✗"
    else
      ICON="✓"
    fi
    ITEM="$ICON $name $DUR"
    if [ -z "$RECENT_DONE" ]; then
      RECENT_DONE="$ITEM"
    else
      RECENT_DONE="$RECENT_DONE · $ITEM"
    fi
    TOTAL_SHOWN=$((TOTAL_SHOWN + 1))
  else
    duration=$((NOW - start_epoch))
    [ "$duration" -lt 0 ] && duration=0
    DUR=$(format_dur "$duration")
    ITEM="▶ $name $DUR"
    if [ -z "$RUNNING" ]; then
      RUNNING="$ITEM"
    else
      RUNNING="$RUNNING · $ITEM"
    fi
    TOTAL_SHOWN=$((TOTAL_SHOWN + 1))
  fi
done <<< "$TASK_LIST"

OUTPUT=""
if [ -n "$RUNNING" ]; then
  OUTPUT="🤖 $RUNNING"
fi
if [ -n "$RECENT_DONE" ]; then
  if [ -n "$OUTPUT" ]; then
    OUTPUT="$OUTPUT · $RECENT_DONE"
  else
    OUTPUT="$RECENT_DONE"
  fi
fi

[ -z "$OUTPUT" ] && exit 0
printf '%s' "$OUTPUT"
