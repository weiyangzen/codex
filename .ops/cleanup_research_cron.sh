#!/usr/bin/env bash
set -euo pipefail

if ! command -v rg >/dev/null 2>&1; then
  rg() {
    grep -E "$@"
  }
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$REPO_ROOT/.cron"
STATE_FILE="$LOG_DIR/research_cleanup.state"
LOG_FILE="$LOG_DIR/research_cleanup.log"
CRON_LOCK_FILE="/tmp/research_cleanup.crontab.lock"

mkdir -p "$LOG_DIR"

ts() { date '+%F %T %z'; }
log() { echo "[$(ts)] $*" >> "$LOG_FILE"; }
count_nonempty_lines() { awk 'NF { count++ } END { print count + 0 }'; }
should_drop_cron_line() {
  local line="$1"

  [[ "$line" == *"$REPO_ROOT/.ops/generate_daily_research_todo.sh"* ]] && return 0
  [[ "$line" == *"$REPO_ROOT/.ops/research_guard.sh"* ]] && return 0
  [[ "$line" == *"cd $REPO_ROOT && ./.ops/generate_daily_research_todo.sh"* ]] && return 0
  [[ "$line" == *"cd $REPO_ROOT && ./.ops/research_guard.sh"* ]] && return 0
  return 1
}

if [[ "${1:-}" != "--execute" ]]; then
  echo "usage: $0 --execute"
  exit 1
fi

exec 8>"$CRON_LOCK_FILE"
flock -x 8

current_cron="$(crontab -l 2>/dev/null || true)"
current_lines="$(printf '%s\n' "$current_cron" | count_nonempty_lines)"
filtered_cron="$(
  while IFS= read -r line; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    if should_drop_cron_line "$line"; then
      continue
    fi
    printf '%s\n' "$line"
  done <<< "$current_cron"
)"
filtered_lines="$(printf '%s\n' "$filtered_cron" | count_nonempty_lines)"

printf '%s\n' "$filtered_cron" | sed '/^\s*$/d' | crontab -

flock -u 8 || true
exec 8>&-

echo "done $(ts)" > "$STATE_FILE"
log "removed research cron entries for ${REPO_ROOT}; removed_lines=$(( current_lines - filtered_lines ))"
echo "cleanup complete: ${REPO_ROOT}"
