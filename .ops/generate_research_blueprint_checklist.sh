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

mkdir -p "$REPO_ROOT/Docs/researches"
cd "$REPO_ROOT"

declare -A STATUS
declare -A CODE_DIRS
declare -a FILES

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

is_excluded_dir() {
  case "$1" in
    .git|.git/*|.cron|.cron/*|Docs|Docs/*|docs|docs/*|documentation|documentation/*|node_modules|node_modules/*|coverage|coverage/*|dist|dist/*|build|build/*|out|out/*|tmp|tmp/*|temp|temp/*|.cache|.cache/*|.next|.next/*|.turbo|.turbo/*|.venv|.venv/*|venv|venv/*|__pycache__|__pycache__/*)
      return 0
      ;;
  esac
  return 1
}

is_doc_like_file() {
  local path="$1"
  local base="${path##*/}"

  case "$base" in
    README|README.*|CHANGELOG|CHANGELOG.*|LICENSE|LICENSE.*|NOTICE|NOTICE.*|CONTRIBUTING|CONTRIBUTING.*|CODE_OF_CONDUCT|CODE_OF_CONDUCT.*|SECURITY|SECURITY.*|AUTHORS|AUTHORS.*)
      return 0
      ;;
  esac

  case "$path" in
    *.md|*.mdx|*.rst|*.adoc|*.txt|*.pdf|*.png|*.jpg|*.jpeg|*.gif|*.svg|*.webp|*.ico|*.bmp)
      return 0
      ;;
  esac

  return 1
}

is_code_like_file() {
  local path="$1"
  local base="${path##*/}"

  case "$base" in
    Dockerfile|Containerfile|Makefile|GNUmakefile|*.mk|package.json|package-lock.json|npm-shrinkwrap.json|pnpm-lock.yaml|yarn.lock|bun.lock|bun.lockb|tsconfig*.json|jsconfig*.json|deno.json|deno.jsonc|Cargo.toml|Cargo.lock|go.mod|go.sum|pyproject.toml|poetry.lock|Pipfile|Pipfile.lock|setup.py|setup.cfg|tox.ini|pytest.ini|ruff.toml|mypy.ini|.eslintrc|.eslintrc.*|eslint.config.*|prettier.config.*|vite.config.*|webpack.config.*|rollup.config.*|vitest.config.*|jest.config.*|babel.config.*|tailwind.config.*|postcss.config.*|turbo.json|justfile|Taskfile|Taskfile.yml|Taskfile.yaml|docker-compose.yml|docker-compose.yaml|compose.yml|compose.yaml)
      return 0
      ;;
  esac

  case "$path" in
    *.py|*.pyi|*.js|*.jsx|*.mjs|*.cjs|*.ts|*.tsx|*.mts|*.cts|*.sh|*.bash|*.zsh|*.fish|*.ps1|*.psm1|*.rb|*.go|*.rs|*.java|*.kt|*.kts|*.swift|*.c|*.cc|*.cpp|*.cxx|*.h|*.hh|*.hpp|*.m|*.mm|*.cs|*.php|*.lua|*.sql|*.proto|*.graphql|*.gql|*.toml|*.yaml|*.yml|*.json|*.jsonc|*.ini|*.cfg|*.conf|*.properties|*.gradle|*.sbt|*.clj|*.cljs|*.scala|*.dart|*.tf|*.tfvars|*.nix)
      return 0
      ;;
  esac

  return 1
}

while IFS= read -r path; do
  rel="${path#./}"
  [[ -n "$rel" ]] || continue

  if is_excluded_dir "$rel"; then
    continue
  fi
  if is_doc_like_file "$rel"; then
    continue
  fi
  if ! is_code_like_file "$rel"; then
    continue
  fi

  FILES+=("$rel")
  dir="$(dirname "$rel")"
  while true; do
    CODE_DIRS["$dir"]=1
    [[ "$dir" == "." ]] && break
    dir="$(dirname "$dir")"
  done
done < <(
  find . \
    \( -path './.git' -o -path './.git/*' -o -path './.cron' -o -path './.cron/*' -o -path './Docs' -o -path './Docs/*' -o -path './docs' -o -path './docs/*' -o -path './documentation' -o -path './documentation/*' -o -path './node_modules' -o -path './node_modules/*' -o -path './coverage' -o -path './coverage/*' -o -path './dist' -o -path './dist/*' -o -path './build' -o -path './build/*' -o -path './out' -o -path './out/*' -o -path './tmp' -o -path './tmp/*' -o -path './temp' -o -path './temp/*' -o -path './.cache' -o -path './.cache/*' -o -path './.next' -o -path './.next/*' -o -path './.turbo' -o -path './.turbo/*' -o -path './.venv' -o -path './.venv/*' -o -path './venv' -o -path './venv/*' -o -path './__pycache__' -o -path './__pycache__/*' \) -prune \
    -o -type f -print
)

mapfile -t DIRS < <(printf '%s\n' "${!CODE_DIRS[@]}" | awk 'NF' | LC_ALL=C sort -u)
mapfile -t SORTED_FILES < <(printf '%s\n' "${FILES[@]}" | awk 'NF' | LC_ALL=C sort -u)

{
  echo "# Research Blueprint Checklist"
  echo
  echo "Project: \`$(basename "$REPO_ROOT")\`"
  echo "Generated at: $(date '+%F %T %z')"
  echo
  echo "Notes: code-only scope. Includes code files plus directories that contain code. Excludes docs, research outputs, dependency caches, and generated runtime paths."
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
  for f in "${SORTED_FILES[@]}"; do
    key="FILE:${f}"
    mark="${STATUS[$key]:- }"
    echo "- [${mark}] [FILE] ${f}"
  done
} > "$CHECKLIST_FILE"

dir_total="${#DIRS[@]}"
file_total="${#SORTED_FILES[@]}"
pending_total="$( (rg -n '^- \[ \] \[(DIR|FILE)\] ' "$CHECKLIST_FILE" || true) | wc -l | tr -d ' ' )"
done_total="$( (rg -n '^- \[[xX]\] \[(DIR|FILE)\] ' "$CHECKLIST_FILE" || true) | wc -l | tr -d ' ' )"

echo "generated $CHECKLIST_FILE (dirs=${dir_total}, files=${file_total}, pending=${pending_total}, done=${done_total})"
