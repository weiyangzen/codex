#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKLIST_FILE="$REPO_ROOT/Docs/researches/blueprint_checklist.md"
DATE_TAG="$(date +%Y%m%d)"
TODO_FILE="$REPO_ROOT/Docs/researches/todos_${DATE_TAG}.md"

cd "$REPO_ROOT"

if [[ ! -f "$CHECKLIST_FILE" ]]; then
  bash "$REPO_ROOT/.ops/generate_research_blueprint_checklist.sh" >/dev/null
fi

pending_total="$( (rg -n '^- \[ \] \[(DIR|FILE)\] ' "$CHECKLIST_FILE" || true) | wc -l | tr -d ' ')"
done_total="$( (rg -n '^- \[[xX]\] \[(DIR|FILE)\] ' "$CHECKLIST_FILE" || true) | wc -l | tr -d ' ')"
dir_pending="$( (rg -n '^- \[ \] \[DIR\] ' "$CHECKLIST_FILE" || true) | wc -l | tr -d ' ')"
file_pending="$( (rg -n '^- \[ \] \[FILE\] ' "$CHECKLIST_FILE" || true) | wc -l | tr -d ' ')"

{
  echo "# Research TODOs ${DATE_TAG}"
  echo
  echo "Project: \`$(basename "$REPO_ROOT")\`"
  echo "Generated at: $(date '+%F %T %z')"
  echo "Source: \`Docs/researches/blueprint_checklist.md\`"
  echo
  echo "## Snapshot"
  echo "- Done: ${done_total}"
  echo "- Pending: ${pending_total}"
  echo "- Pending Dirs: ${dir_pending}"
  echo "- Pending Files: ${file_pending}"
  echo
  echo "## Pending Items"
  if [[ "$pending_total" == "0" ]]; then
    echo "- [x] No pending research items."
  else
    rg '^- \[ \] \[(DIR|FILE)\] ' "$CHECKLIST_FILE"
  fi
} > "$TODO_FILE"

echo "generated $TODO_FILE (pending=${pending_total}, dirs=${dir_pending}, files=${file_pending})"
echo "$TODO_FILE"
