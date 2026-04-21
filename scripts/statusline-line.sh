#!/bin/bash
set -e

MODE="$1"
SCRIPTS_DIR="${STATUSLINE_SCRIPTS_DIR:-$HOME/.claude/scripts}"

read_stdin() {
  cat
}

join_line() {
  local label="$1" pct="$2" reset="$3" burn="$4"
  if [ -n "$burn" ]; then
    printf '%s %s → %s | %s\n' "$label" "$pct" "$reset" "$burn"
  else
    printf '%s %s → %s\n' "$label" "$pct" "$reset"
  fi
}

case "$MODE" in
  5h)
    input=$(read_stdin)
    pct=$(printf '%s' "$input" | bash "$SCRIPTS_DIR/statusline-rate.sh" 5h-pct)
    [ -z "$pct" ] && exit 0
    reset=$(printf '%s' "$input" | bash "$SCRIPTS_DIR/statusline-rate.sh" 5h-reset)
    burn=$(printf '%s' "$input" | bash "$SCRIPTS_DIR/statusline-burn.sh" 5h)
    join_line '5h:' "$pct" "$reset" "$burn"
    ;;
  7d)
    input=$(read_stdin)
    pct=$(printf '%s' "$input" | bash "$SCRIPTS_DIR/statusline-rate.sh" 7d-pct)
    [ -z "$pct" ] && exit 0
    reset=$(printf '%s' "$input" | bash "$SCRIPTS_DIR/statusline-rate.sh" 7d-reset)
    burn=$(printf '%s' "$input" | bash "$SCRIPTS_DIR/statusline-burn.sh" 7d)
    join_line '7d:' "$pct" "$reset" "$burn"
    ;;
  sonnet)
    pct=$(bash "$SCRIPTS_DIR/statusline-model.sh" sonnet-pct)
    [ -z "$pct" ] && exit 0
    reset=$(bash "$SCRIPTS_DIR/statusline-model.sh" sonnet-reset)
    burn=$(bash "$SCRIPTS_DIR/statusline-model.sh" sonnet-burn)
    join_line 'Son:' "$pct" "$reset" "$burn"
    ;;
  opus)
    bash "$SCRIPTS_DIR/statusline-model.sh" opus-line
    ;;
  *)
    exit 0
    ;;
esac
