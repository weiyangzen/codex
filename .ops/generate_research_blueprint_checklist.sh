#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKLIST_FILE="$REPO_ROOT/Docs/researches/blueprint_checklist.md"

mkdir -p "$REPO_ROOT/Docs/researches"
cd "$REPO_ROOT"

declare -A STATUS
if [[ -f "$CHECKLIST_FILE" ]]; then
  while IFS= read -r line; do
    if [[ "$line" =~ ^-\ \[([xX\ ])\]\ \[(DIR|FILE)\]\ (.+)$ ]]; then
      mark="${BASH_REMATCH[1]}"
      kind="${BASH_REMATCH[2]}"
      path="${BASH_REMATCH[3]}"
      key="${kind}:${path}"
      if [[ "$mark" =~ [xX] ]]; then
        STATUS["$key"]="x"
      else
        STATUS["$key"]=" "
      fi
    fi
  done < "$CHECKLIST_FILE"
fi

mapfile -t DIRS < <(
  find . \
    \( -path './.git' -o -path './.git/*' -o -path './Docs/researches' -o -path './Docs/researches/*' -o -path './.cron' -o -path './.cron/*' \) -prune \
    -o -type d -print \
  | sed 's|^\./||' \
  | awk 'NF==0{print "."; next} {print}' \
  | LC_ALL=C sort -u
)

mapfile -t FILES < <(
  find . \
    \( -path './.git' -o -path './.git/*' -o -path './Docs/researches' -o -path './Docs/researches/*' -o -path './.cron' -o -path './.cron/*' \) -prune \
    -o -type f -print \
  | sed 's|^\./||' \
  | LC_ALL=C sort -u
)

{
  echo "# Research Blueprint Checklist"
  echo
  echo "Project: \`$(basename "$REPO_ROOT")\`"
  echo "Generated at: $(date '+%F %T %z')"
  echo
  echo "Notes: excludes generated runtime paths \`.git/\`, \`.cron/\`, and \`Docs/researches/\`."
  echo "Legend: \`[ ]\` pending, \`[x]\` researched."
  echo
  echo "## Directories"
  for d in "${DIRS[@]}"; do
    key="DIR:${d}"
    mark="${STATUS[$key]:- }"
    echo "- [${mark}] [DIR] ${d}"
  done
  echo
  echo "## Files"
  for f in "${FILES[@]}"; do
    key="FILE:${f}"
    mark="${STATUS[$key]:- }"
    echo "- [${mark}] [FILE] ${f}"
  done
} > "$CHECKLIST_FILE"

dir_total="${#DIRS[@]}"
file_total="${#FILES[@]}"
pending_total="$( (rg -n '^- \[ \] \[(DIR|FILE)\] ' "$CHECKLIST_FILE" || true) | wc -l | tr -d ' ')"
done_total="$( (rg -n '^- \[[xX]\] \[(DIR|FILE)\] ' "$CHECKLIST_FILE" || true) | wc -l | tr -d ' ')"

echo "generated $CHECKLIST_FILE (dirs=${dir_total}, files=${file_total}, pending=${pending_total}, done=${done_total})"
