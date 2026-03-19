#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="$REPO_ROOT/.cron"
STATE_FILE="$LOG_DIR/research_cleanup.state"
LOG_FILE="$LOG_DIR/research_cleanup.log"

mkdir -p "$LOG_DIR"

ts() { date '+%F %T %z'; }
log() { echo "[$(ts)] $*" >> "$LOG_FILE"; }

if [[ "${1:-}" != "--execute" ]]; then
  echo "usage: $0 --execute"
  exit 1
fi

current_cron="$(crontab -l 2>/dev/null || true)"
filtered_cron="$(printf '%s\n' "$current_cron" | rg -v "${REPO_ROOT}/\\.ops/(generate_daily_research_todo\\.sh|research_guard\\.sh)" || true)"

printf '%s\n' "$filtered_cron" | sed '/^\s*$/d' | crontab -

echo "done $(ts)" > "$STATE_FILE"
log "removed research cron entries for ${REPO_ROOT}"
echo "cleanup complete: ${REPO_ROOT}"
