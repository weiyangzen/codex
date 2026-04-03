#!/usr/bin/env bash
set -euo pipefail

CODEX_VENDOR_PATH="/home/sansha/.nvm/versions/node/v24.14.0/lib/node_modules/@openai/codex/node_modules/@openai/codex-linux-x64/vendor/x86_64-unknown-linux-musl/path"
export PATH="${CODEX_VENDOR_PATH}:/home/sansha/.nvm/versions/node/v24.14.0/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

if ! command -v rg >/dev/null 2>&1; then
  rg() {
    grep -E "$@"
  }
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKLIST_FILE="$REPO_ROOT/Docs/researches/blueprint_checklist.md"
DATE_TAG="$(date +%Y%m%d)"
TODO_FILE="$REPO_ROOT/Docs/researches/todos_${DATE_TAG}.md"

cd "$REPO_ROOT"

if [[ ! -f "$CHECKLIST_FILE" ]]; then
  bash "$REPO_ROOT/.ops/generate_research_blueprint_checklist.sh" >/dev/null
fi

pending_total="$( (rg -n '^- \[ \] \[(DIR|FILE)\] ' "$CHECKLIST_FILE" || true) | wc -l | tr -d ' ' )"
done_total="$( (rg -n '^- \[[xX]\] \[(DIR|FILE)\] ' "$CHECKLIST_FILE" || true) | wc -l | tr -d ' ' )"
dir_pending="$( (rg -n '^- \[ \] \[DIR\] ' "$CHECKLIST_FILE" || true) | wc -l | tr -d ' ' )"
file_pending="$( (rg -n '^- \[ \] \[FILE\] ' "$CHECKLIST_FILE" || true) | wc -l | tr -d ' ' )"

{
  echo "# Research TODOs ${DATE_TAG}"
  echo
  echo "Project: \`$(basename "$REPO_ROOT")\`"
  echo "Generated at: $(date '+%F %T %z')"
  echo "Source: \`Docs/researches/blueprint_checklist.md\` (code-only scope)"
  echo
  echo "## Snapshot"
  echo "- Done Code Items: ${done_total}"
  echo "- Pending Code Items: ${pending_total}"
  echo "- Pending Code Dirs: ${dir_pending}"
  echo "- Pending Code Files: ${file_pending}"
  echo
  echo "## Pending Items"
  if [[ "$pending_total" == "0" ]]; then
    echo "- [x] No pending code research items."
  else
    rg '^- \[ \] \[(DIR|FILE)\] ' "$CHECKLIST_FILE"
  fi
} > "$TODO_FILE"

echo "generated $TODO_FILE (pending=${pending_total}, dirs=${dir_pending}, files=${file_pending})"
echo "$TODO_FILE"
