#!/usr/bin/env bash
set -euo pipefail

export PATH="/home/sansha/.nvm/versions/node/v24.14.0/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$(basename "$REPO")"
KIMI_BIN="${KIMI_BIN:-/home/sansha/.local/bin/kimi}"
LOG_DIR="$REPO/.cron"
LOG_FILE="$LOG_DIR/research_guard.log"
STATE_FILE="$LOG_DIR/research_guard.state"
BLOCK_FILE="$LOG_DIR/research_guard.block_count"
LOCK_FILE="/tmp/${PROJECT}_research_guard.lock"
CHECKLIST_FILE="$REPO/Docs/researches/blueprint_checklist.md"
AUTO_CLEANUP_ON_COMPLETE="${AUTO_CLEANUP_ON_COMPLETE:-0}"
KIMI_EXEC_TIMEOUT_SECONDS="${KIMI_EXEC_TIMEOUT_SECONDS:-1200}"
AUTO_PUSH_ON_CHECKPOINT="${AUTO_PUSH_ON_CHECKPOINT:-0}"
MAX_BATCH_BYTES="${MAX_BATCH_BYTES:-102400}"
TMUX_WRAP_ENABLED="${TMUX_WRAP_ENABLED:-1}"
TMUX_SESSION_NAME="${TMUX_SESSION_NAME:-$PROJECT}"
WORKER_MODE="${RESEARCH_GUARD_WORKER:-0}"
KIMI_MODEL="${KIMI_MODEL:-k2p5}"
KIMI_KEYS_FILE="$HOME/kimi_keys.txt"
KIMI_KEY_INDEX_FILE="$LOG_DIR/research_guard.kimi_key_index"

mkdir -p "$LOG_DIR" "$REPO/Docs/researches"

ts() { date '+%F %T %z'; }
log() { echo "[$(ts)] $*" >> "$LOG_FILE"; }
set_state() { printf '%s\n' "$1" > "$STATE_FILE"; }
set_block() { printf '%s\n' "$1" > "$BLOCK_FILE"; }

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

read_kimi_keys() {
  KIMI_KEYS=()
  if [[ ! -f "$KIMI_KEYS_FILE" ]]; then
    return 1
  fi

  local line key
  while IFS= read -r line || [[ -n "$line" ]]; do
    key="$(trim "${line%%#*}")"
    [[ -n "$key" ]] || continue
    KIMI_KEYS+=("$key")
  done < "$KIMI_KEYS_FILE"

  (( ${#KIMI_KEYS[@]} > 0 ))
}

read_kimi_key_index() {
  local idx
  idx=0
  if [[ -f "$KIMI_KEY_INDEX_FILE" ]]; then
    idx="$(tr -cd '0-9' < "$KIMI_KEY_INDEX_FILE" | head -c 32)"
    [[ -n "$idx" ]] || idx=0
  fi
  printf '%s' "$idx"
}

write_kimi_key_index() {
  local idx="$1"
  printf '%s\n' "$idx" > "$KIMI_KEY_INDEX_FILE"
}

run_research_with_kimi() {
  local task="$1"
  local rc idx key_count attempt slot key

  if ! read_kimi_keys; then
    log "error: kimi key file missing/empty: $KIMI_KEYS_FILE"
    return 86
  fi

  key_count="${#KIMI_KEYS[@]}"
  idx="$(read_kimi_key_index)"
  if ! [[ "$idx" =~ ^[0-9]+$ ]]; then
    idx=0
  fi
  idx=$(( idx % key_count ))

  rc=1
  for ((attempt=1; attempt<=key_count; attempt++)); do
    slot=$(( (idx + attempt - 1) % key_count ))
    key="${KIMI_KEYS[$slot]}"
    log "info: kimi exec attempt=${attempt}/${key_count} key_index=${slot} model=${KIMI_MODEL}"

    rc=0
    if [[ "$KIMI_EXEC_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] && (( KIMI_EXEC_TIMEOUT_SECONDS > 0 )); then
      timeout "$KIMI_EXEC_TIMEOUT_SECONDS" env \
        KIMI_API_KEY="$key" \
        MOONSHOT_API_KEY="$key" \
        OPENAI_API_KEY="$key" \
        "$KIMI_BIN" \
        --print \
        --yolo \
        --model "$KIMI_MODEL" \
        --work-dir "$REPO" \
        --prompt "$task" >> "$LOG_FILE" 2>&1 || rc=$?
    else
      env \
        KIMI_API_KEY="$key" \
        MOONSHOT_API_KEY="$key" \
        OPENAI_API_KEY="$key" \
        "$KIMI_BIN" \
        --print \
        --yolo \
        --model "$KIMI_MODEL" \
        --work-dir "$REPO" \
        --prompt "$task" >> "$LOG_FILE" 2>&1 || rc=$?
    fi

    if [[ "$rc" -eq 0 ]]; then
      write_kimi_key_index "$slot"
      return 0
    fi

    log "warn: kimi exec failed rc=${rc} key_index=${slot}; rotating key"
  done

  write_kimi_key_index $(( (idx + 1) % key_count ))
  return "$rc"
}

if [[ "$TMUX_WRAP_ENABLED" == "1" && "$WORKER_MODE" != "1" ]]; then
  if command -v tmux >/dev/null 2>&1; then
    exec 8>"$LOCK_FILE"
    if ! flock -n 8; then
      log "skip: research worker lock is busy"
      exec 8>&-
      exit 0
    fi
    flock -u 8 || true
    exec 8>&-

    tmux_cmd="cd \"$REPO\" && RESEARCH_GUARD_WORKER=1 bash .ops/research_guard.sh"
    if tmux has-session -t "$TMUX_SESSION_NAME" 2>/dev/null; then
      win_name="research-guard-$(date +%H%M%S)"
      if tmux new-window -d -t "$TMUX_SESSION_NAME" -n "$win_name" "$tmux_cmd" >/dev/null 2>&1; then
        log "delegated to existing tmux session=${TMUX_SESSION_NAME} window=${win_name}"
        exit 0
      fi
      log "warn: tmux new-window failed for session=${TMUX_SESSION_NAME}; fallback local run"
    else
      if tmux new-session -d -s "$TMUX_SESSION_NAME" "$tmux_cmd" >/dev/null 2>&1; then
        log "delegated to new tmux session=${TMUX_SESSION_NAME}"
        exit 0
      fi
      log "warn: tmux new-session failed for session=${TMUX_SESSION_NAME}; fallback local run"
    fi
  else
    log "warn: tmux not found; fallback local run"
  fi
fi

auto_push_with_conflict_resolution() {
  local branch upstream_ref remote_ref max_attempts attempt conflict_files path
  max_attempts=3

  if git push >/dev/null 2>&1; then
    return 0
  fi

  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [[ -z "$branch" || "$branch" == "HEAD" ]]; then
    log "warn: auto-resolve push aborted (detached HEAD)"
    return 1
  fi

  upstream_ref="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
  if [[ -z "$upstream_ref" ]]; then
    if git push --set-upstream origin "$branch" >/dev/null 2>&1; then
      log "push succeeded with upstream setup: origin/$branch"
      return 0
    fi
    upstream_ref="origin/$branch"
  fi

  for ((attempt=1; attempt<=max_attempts; attempt++)); do
    log "warn: git push failed; auto-resolve attempt=${attempt} using ${upstream_ref}"
    if ! git fetch --prune origin "$branch" >/dev/null 2>&1; then
      log "warn: auto-resolve fetch failed (attempt=${attempt})"
      return 1
    fi

    remote_ref="$upstream_ref"
    if ! git show-ref --verify --quiet "refs/remotes/${remote_ref}"; then
      remote_ref="origin/$branch"
    fi

    if ! git rebase "$remote_ref" >/dev/null 2>&1; then
      conflict_files="$(git diff --name-only --diff-filter=U || true)"
      if [[ -z "$conflict_files" ]]; then
        git rebase --abort >/dev/null 2>&1 || true
        log "warn: rebase failed without conflict files (attempt=${attempt})"
        return 1
      fi

      while [[ -n "$conflict_files" ]]; do
        while IFS= read -r path; do
          [[ -n "$path" ]] || continue
          git checkout --ours -- "$path" >/dev/null 2>&1 || true
          git add -- "$path" >/dev/null 2>&1 || true
        done <<< "$conflict_files"

        if ! GIT_EDITOR=true git rebase --continue >/dev/null 2>&1; then
          conflict_files="$(git diff --name-only --diff-filter=U || true)"
          if [[ -z "$conflict_files" ]]; then
            if ! GIT_EDITOR=true git rebase --continue >/dev/null 2>&1; then
              git rebase --abort >/dev/null 2>&1 || true
              log "warn: rebase continue failed after auto-resolve (attempt=${attempt})"
              return 1
            fi
          fi
        fi

        if [[ -d .git/rebase-merge || -d .git/rebase-apply ]]; then
          conflict_files="$(git diff --name-only --diff-filter=U || true)"
        else
          conflict_files=""
        fi
      done

      if [[ -d .git/rebase-merge || -d .git/rebase-apply ]]; then
        git rebase --abort >/dev/null 2>&1 || true
        log "warn: rebase still active after auto-resolve (attempt=${attempt})"
        return 1
      fi

      log "auto-resolved rebase conflicts by preferring local changes"
    fi

    if git push >/dev/null 2>&1; then
      log "push succeeded after auto-resolve attempt=${attempt}"
      return 0
    fi
  done

  log "warn: auto-resolve exhausted retries for git push"
  return 1
}

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "skip: previous research guard run still active"
  exit 0
fi

cd "$REPO"

if [[ ! -x "$KIMI_BIN" ]]; then
  if command -v kimi >/dev/null 2>&1; then
    KIMI_BIN="$(command -v kimi)"
  else
    set_state "failed_no_kimi"
    log "error: kimi binary not found"
    exit 0
  fi
fi

if ! bash .ops/generate_research_blueprint_checklist.sh >> "$LOG_FILE" 2>&1; then
  set_state "failed_blueprint"
  log "error: failed to generate research blueprint checklist"
  exit 0
fi

TODO_OUT="$(bash .ops/generate_daily_research_todo.sh 2>>"$LOG_FILE" | tail -n 1 || true)"
log "today_todo=${TODO_OUT}"

PENDING_LINE="$(rg -n '^- \[ \] \[(DIR|FILE)\] ' "$CHECKLIST_FILE" | head -n 1 || true)"
if [[ -z "$PENDING_LINE" ]]; then
  set_state "completed"
  set_block 0
  log "all research checklist items completed"
  if [[ "$AUTO_CLEANUP_ON_COMPLETE" == "1" && -x .ops/cleanup_research_cron.sh ]]; then
    .ops/cleanup_research_cron.sh --execute >> "$LOG_FILE" 2>&1 || true
  fi
  exit 0
fi

LINE_NO="${PENDING_LINE%%:*}"
ITEM_TEXT="${PENDING_LINE#*:}"
TARGET_TYPE="$(echo "$ITEM_TEXT" | sed -E 's/^- \[ \] \[([A-Z]+)\] .+$/\1/')"
TARGET_PATH="$(echo "$ITEM_TEXT" | sed -E 's/^- \[ \] \[[A-Z]+\] //')"

TARGET_DESC="${TARGET_TYPE} ${TARGET_PATH}"
COMMIT_TITLE="${TARGET_TYPE} ${TARGET_PATH}"
TASK=""

if [[ "$TARGET_TYPE" == "DIR" ]]; then
  if [[ "$TARGET_PATH" == "." ]]; then
    REPORT_DIR="$REPO/Docs/researches"
  else
    REPORT_DIR="$REPO/Docs/researches/$TARGET_PATH"
  fi
  REPORT_PATH="$REPORT_DIR/current_folder_research.md"
  mkdir -p "$REPORT_DIR"

  read -r -d '' TASK <<PROMPT || true
请研究${TARGET_TYPE} ${TARGET_PATH}。

你在项目仓库根目录工作。请完成以下任务并直接修改文件：
1) 深入阅读目标对象与其上下文依赖（调用方、被调用方、配置、测试、脚本、文档）。
2) 产出详尽研究文档到：${REPORT_PATH}
   - 必须包含章节：
     - 场景与职责
     - 功能点目的
     - 具体技术实现（关键流程/数据结构/协议/命令）
     - 关键代码路径与文件引用
     - 依赖与外部交互
     - 风险、边界与改进建议
3) 若目标是 FILE：文档文件名必须是“原文件名_research.md”。
4) 若目标是 DIR：文档文件名必须是“current_folder_research.md”。
5) 文档写完后，把 checklist 第 ${LINE_NO} 行对应项从 [ ] 改为 [x]。
6) 运行：bash .ops/generate_daily_research_todo.sh 更新当天 todo。
7) 若有变更，执行一次提交（不 push）：
   git add Docs/researches .ops || true
   git add -A
   git commit -m "docs(research): ${COMMIT_TITLE}" || true

要求：
- 必须是实质研究，不要空文档或模板占位。
- 使用 kimi cli 非 REPL（print）模式执行本任务，模型使用 ${KIMI_MODEL}。
PROMPT
else
  TARGET_DIR="$(dirname "$TARGET_PATH")"
  BATCH_COUNT=0
  BATCH_TOTAL_BYTES=0
  BATCH_ITEMS=""
  OVERSIZE_SINGLE_ALLOWED=0

  while IFS= read -r CAND_LINE; do
    CAND_LINE_NO="${CAND_LINE%%:*}"
    CAND_TEXT="${CAND_LINE#*:}"
    CAND_PATH="$(echo "$CAND_TEXT" | sed -E 's/^- \[ \] \[FILE\] //')"
    CAND_DIR="$(dirname "$CAND_PATH")"
    [[ "$CAND_DIR" == "$TARGET_DIR" ]] || continue

    CAND_ABS="$REPO/$CAND_PATH"
    [[ -f "$CAND_ABS" ]] || continue
    CAND_SIZE="$(wc -c < "$CAND_ABS" | tr -d ' ')"
    if (( BATCH_COUNT == 0 )) && (( CAND_SIZE > MAX_BATCH_BYTES )); then
      OVERSIZE_SINGLE_ALLOWED=1
      log "info: single file exceeds batch limit but allowed: path=${CAND_PATH} size=${CAND_SIZE} limit=${MAX_BATCH_BYTES}"
    else
      OVERSIZE_SINGLE_ALLOWED=0
    fi
    if (( BATCH_COUNT > 0 )) && (( BATCH_TOTAL_BYTES + CAND_SIZE > MAX_BATCH_BYTES )); then
      break
    fi

    if [[ "$CAND_DIR" == "." ]]; then
      CAND_REPORT_DIR="$REPO/Docs/researches"
    else
      CAND_REPORT_DIR="$REPO/Docs/researches/$CAND_DIR"
    fi
    CAND_BASE="$(basename "$CAND_PATH")"
    CAND_REPORT_PATH="$CAND_REPORT_DIR/${CAND_BASE}_research.md"
    mkdir -p "$CAND_REPORT_DIR"

    BATCH_COUNT=$((BATCH_COUNT + 1))
    BATCH_TOTAL_BYTES=$((BATCH_TOTAL_BYTES + CAND_SIZE))
    BATCH_ITEMS+="- 行${CAND_LINE_NO} | ${CAND_PATH} | ${CAND_REPORT_PATH} | ${CAND_SIZE} bytes"$'\n'
    if (( OVERSIZE_SINGLE_ALLOWED == 1 )); then
      break
    fi
  done < <(rg -n '^- \[ \] \[FILE\] ' "$CHECKLIST_FILE")

  if (( BATCH_COUNT <= 1 )); then
    FILE_DIR="$TARGET_DIR"
    FILE_BASE="$(basename "$TARGET_PATH")"
    if [[ "$FILE_DIR" == "." ]]; then
      REPORT_DIR="$REPO/Docs/researches"
    else
      REPORT_DIR="$REPO/Docs/researches/$FILE_DIR"
    fi
    REPORT_PATH="$REPORT_DIR/${FILE_BASE}_research.md"
    mkdir -p "$REPORT_DIR"
    COMMIT_TITLE="FILE ${TARGET_PATH}"

    read -r -d '' TASK <<PROMPT || true
请研究FILE ${TARGET_PATH}。

你在项目仓库根目录工作。请完成以下任务并直接修改文件：
1) 深入阅读目标对象与其上下文依赖（调用方、被调用方、配置、测试、脚本、文档）。
2) 产出详尽研究文档到：${REPORT_PATH}
   - 必须包含章节：
     - 场景与职责
     - 功能点目的
     - 具体技术实现（关键流程/数据结构/协议/命令）
     - 关键代码路径与文件引用
     - 依赖与外部交互
     - 风险、边界与改进建议
3) 文档文件名必须是“原文件名_research.md”。
4) 文档写完后，把 checklist 第 ${LINE_NO} 行对应项从 [ ] 改为 [x]。
5) 运行：bash .ops/generate_daily_research_todo.sh 更新当天 todo。
6) 若有变更，执行一次提交（不 push）：
   git add Docs/researches .ops || true
   git add -A
   git commit -m "docs(research): ${COMMIT_TITLE}" || true

要求：
- 必须是实质研究，不要空文档或模板占位。
- 使用 kimi cli 非 REPL（print）模式执行本任务，模型使用 ${KIMI_MODEL}。
PROMPT
  else
    BATCH_LABEL="$TARGET_DIR"
    if [[ "$BATCH_LABEL" == "." ]]; then
      BATCH_LABEL="root"
    fi
    TARGET_DESC="FILE_BATCH ${BATCH_LABEL} (${BATCH_COUNT} files, ${BATCH_TOTAL_BYTES} bytes)"
    COMMIT_TITLE="FILE_BATCH ${BATCH_LABEL} (${BATCH_COUNT} files)"

    read -r -d '' TASK <<PROMPT || true
请按同目录批次研究 FILE（总大小上限 ${MAX_BATCH_BYTES} bytes）。

本批次文件如下（相近目录合并，避免过度零碎）：
${BATCH_ITEMS}

你在项目仓库根目录工作。请完成以下任务并直接修改文件：
1) 逐个深入阅读本批次文件与其上下文依赖（调用方、被调用方、配置、测试、脚本、文档）。
2) 为每个文件分别产出详尽研究文档到其对应路径（每个文件一个 `原文件名_research.md`，路径已在上方列表给出）。
3) 每个文档必须包含章节：
   - 场景与职责
   - 功能点目的
   - 具体技术实现（关键流程/数据结构/协议/命令）
   - 关键代码路径与文件引用
   - 依赖与外部交互
   - 风险、边界与改进建议
4) 文档写完后，将上方列表中的每个 checklist 行从 [ ] 改为 [x]。
5) 运行：bash .ops/generate_daily_research_todo.sh 更新当天 todo。
6) 若有变更，执行一次提交（不 push）：
   git add Docs/researches .ops || true
   git add -A
   git commit -m "docs(research): ${COMMIT_TITLE}" || true

要求：
- 本批次必须是实质研究，不要空文档或模板占位。
- 若单文件本身超过 ${MAX_BATCH_BYTES} bytes，允许作为单文件批次继续研究，不要跳过。
- 使用 kimi cli 非 REPL（print）模式执行本任务，模型使用 ${KIMI_MODEL}。
PROMPT
  fi
fi

set_state "running_exec"
set_block 0

run_rc=0
run_research_with_kimi "$TASK" || run_rc=$?

if ! git diff --quiet || ! git diff --cached --quiet; then
  git add -A
  if ! git diff --cached --quiet; then
    msg="chore(research): checkpoint $(date '+%F %T %z')"
    if git commit -m "$msg" >/dev/null 2>&1; then
      if [[ "$AUTO_PUSH_ON_CHECKPOINT" == "1" ]]; then
        auto_push_with_conflict_resolution || true
        log "checkpoint committed and push attempted: $msg"
      else
        log "checkpoint committed locally (auto-push disabled): $msg"
      fi
    fi
  fi
fi

if [[ "$run_rc" -eq 0 ]]; then
  set_state "exec_completed"
  log "research exec finished for ${TARGET_DESC}"
elif [[ "$run_rc" -eq 124 ]]; then
  set_state "exec_timeout"
  log "warn: research exec timeout for ${TARGET_DESC}"
else
  set_state "exec_failed"
  log "warn: research exec failed rc=${run_rc} for ${TARGET_DESC}"
fi
