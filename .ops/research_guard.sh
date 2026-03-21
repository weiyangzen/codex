#!/usr/bin/env bash
set -euo pipefail

CODEX_VENDOR_PATH="/home/sansha/.nvm/versions/node/v24.14.0/lib/node_modules/@openai/codex/node_modules/@openai/codex-linux-x64/vendor/x86_64-unknown-linux-musl/path"
export PATH="${CODEX_VENDOR_PATH}:/home/sansha/.nvm/versions/node/v24.14.0/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

if ! command -v rg >/dev/null 2>&1; then
  rg() {
    grep -E "$@"
  }
fi

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$(basename "$REPO")"
KIMI_BIN="${KIMI_BIN:-/home/sansha/.local/bin/kimi}"
LOG_DIR="$REPO/.cron"
LOG_FILE="$LOG_DIR/research_guard.log"
STATE_FILE="$LOG_DIR/research_guard.state"
BLOCK_FILE="$LOG_DIR/research_guard.block_count"
LOCK_FILE="/tmp/${PROJECT}_research_guard.lock"
SCHEDULER_LOCK_FILE="/tmp/${PROJECT}_research_guard.scheduler.lock"
CLAIM_LOCK_FILE="/tmp/${PROJECT}_research_guard.claim.lock"
WRITE_LOCK_FILE="/tmp/${PROJECT}_research_guard.write.lock"
CLAIMS_DIR="$LOG_DIR/research_claims"
CHECKLIST_FILE="$REPO/Docs/researches/blueprint_checklist.md"
AUTO_CLEANUP_ON_COMPLETE="${AUTO_CLEANUP_ON_COMPLETE:-0}"
KIMI_EXEC_TIMEOUT_SECONDS="${KIMI_EXEC_TIMEOUT_SECONDS:-1200}"
AUTO_PUSH_ON_CHECKPOINT="${AUTO_PUSH_ON_CHECKPOINT:-0}"
MAX_BATCH_BYTES="${MAX_BATCH_BYTES:-102400}"
TMUX_WRAP_ENABLED="${TMUX_WRAP_ENABLED:-1}"
TMUX_SESSION_NAME="${TMUX_SESSION_NAME:-$PROJECT}"
WORKER_MODE="${RESEARCH_GUARD_WORKER:-0}"
WORKER_SLOT="${WORKER_SLOT:-0}"
MAX_PARALLEL_RESEARCH="${MAX_PARALLEL_RESEARCH:-4}"
KIMI_MODEL="${KIMI_MODEL:-k2p5}"
KIMI_BASE_URL="${KIMI_BASE_URL:-https://api.kimi.com/coding/v1}"
KIMI_KEYS_FILE="${KIMI_KEYS_FILE:-$HOME/kimi_keys.txt}"
KIMI_KEY_INDEX_FILE="$LOG_DIR/research_guard.kimi_key_index"
CLAIM_TTL_SECONDS="${CLAIM_TTL_SECONDS:-7200}"

mkdir -p "$LOG_DIR" "$REPO/Docs/researches" "$CLAIMS_DIR"

TS_NOW() { date '+%F %T %z'; }
log() { echo "[$(TS_NOW)] $*" >> "$LOG_FILE"; }
set_state() { printf '%s\n' "$1" > "$STATE_FILE"; }
set_block() { printf '%s\n' "$1" > "$BLOCK_FILE"; }

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

to_repo_rel() {
  local p="$1"
  p="${p#$REPO/}"
  printf '%s' "$p"
}

item_key() {
  local type="$1"
  local path="$2"
  printf '%s:%s' "$type" "$path"
}

claim_file_for_key() {
  local key="$1"
  local hash
  hash="$(printf '%s' "$key" | sha1sum | awk '{print $1}')"
  printf '%s/%s.claim' "$CLAIMS_DIR" "$hash"
}

cleanup_stale_claims_under_lock() {
  local now f owner pid created key age
  now="$(date +%s)"
  shopt -s nullglob
  for f in "$CLAIMS_DIR"/*.claim; do
    owner=""
    pid=""
    created=""
    key=""
    IFS=$'\t' read -r owner pid created key < "$f" || true
    [[ "$created" =~ ^[0-9]+$ ]] || created=0
    age=$((now - created))
    if (( age > CLAIM_TTL_SECONDS )); then
      rm -f "$f"
      log "warn: stale claim removed age=${age}s file=${f}"
      continue
    fi
    if [[ "$pid" =~ ^[0-9]+$ ]] && ! kill -0 "$pid" >/dev/null 2>&1; then
      if (( age > 60 )); then
        rm -f "$f"
        log "warn: dead-owner claim removed pid=${pid} age=${age}s file=${f}"
      fi
    fi
  done
  shopt -u nullglob
}

claim_exists_under_lock() {
  local key="$1"
  local claim_file
  claim_file="$(claim_file_for_key "$key")"
  [[ -f "$claim_file" ]]
}

claim_create_under_lock() {
  local key="$1"
  local token="$2"
  local claim_file
  claim_file="$(claim_file_for_key "$key")"
  [[ -f "$claim_file" ]] && return 1
  printf '%s\t%s\t%s\t%s\n' "$token" "$$" "$(date +%s)" "$key" > "$claim_file"
}

release_claims() {
  local token="$1"
  local keys_file="$2"
  local key claim_file owner

  [[ -f "$keys_file" ]] || return 0

  exec 7>"$CLAIM_LOCK_FILE"
  flock -x 7

  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    claim_file="$(claim_file_for_key "$key")"
    [[ -f "$claim_file" ]] || continue
    owner="$(awk -F '\t' 'NR==1{print $1}' "$claim_file" 2>/dev/null || true)"
    if [[ "$owner" == "$token" ]]; then
      rm -f "$claim_file"
    fi
  done < "$keys_file"

  flock -u 7 || true
  exec 7>&-
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

toml_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

write_kimi_config_file() {
  local cfg_file="$1"
  local model_esc base_url_esc
  model_esc="$(toml_escape "$KIMI_MODEL")"
  base_url_esc="$(toml_escape "$KIMI_BASE_URL")"
  cat > "$cfg_file" <<TOML
 default_model = "${model_esc}"
 default_thinking = false
 default_yolo = true

 [providers.kimi_for_coding]
 type = "kimi"
 base_url = "${base_url_esc}"
 api_key = "placeholder"

 [models."${model_esc}"]
 provider = "kimi_for_coding"
 model = "${model_esc}"
 max_context_size = 262144
TOML
}

run_research_with_kimi() {
  local task="$1"
  local rc idx key_count attempt slot key cfg_file attempt_log

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

    cfg_file="$(mktemp "$LOG_DIR/kimi_config.${PROJECT}.XXXXXX.toml")"
    attempt_log="$(mktemp "$LOG_DIR/kimi_attempt.${PROJECT}.XXXXXX.log")"
    write_kimi_config_file "$cfg_file"

    rc=0
    if [[ "$KIMI_EXEC_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] && (( KIMI_EXEC_TIMEOUT_SECONDS > 0 )); then
      (
        export KIMI_API_KEY="$key"
        timeout "$KIMI_EXEC_TIMEOUT_SECONDS" \
          "$KIMI_BIN" \
          --print \
          --yolo \
          --config-file "$cfg_file" \
          --model "$KIMI_MODEL" \
          --work-dir "$REPO" \
          --prompt "$task" > "$attempt_log" 2>&1
      ) || rc=$?
    else
      (
        export KIMI_API_KEY="$key"
        "$KIMI_BIN" \
          --print \
          --yolo \
          --config-file "$cfg_file" \
          --model "$KIMI_MODEL" \
          --work-dir "$REPO" \
          --prompt "$task" > "$attempt_log" 2>&1
      ) || rc=$?
    fi

    if [[ "$rc" -eq 0 ]] && grep -Eqi 'LLM not set|AUTH_REQUIRED|auth required|invalid api key|quota|insufficient quota|rate limit|401|403' "$attempt_log"; then
      rc=65
      log "warn: kimi output indicates auth/model error despite zero exit; rotating key"
    fi

    cat "$attempt_log" >> "$LOG_FILE"
    rm -f "$attempt_log" "$cfg_file"

    if [[ "$rc" -eq 0 ]]; then
      write_kimi_key_index "$slot"
      return 0
    fi

    log "warn: kimi exec failed rc=${rc} key_index=${slot}; rotating key"
  done

  write_kimi_key_index $(( (idx + 1) % key_count ))
  return "$rc"
}

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

dir_report_path() {
  local path="$1"
  if [[ "$path" == "." ]]; then
    printf '%s/Docs/researches/current_folder_research.md' "$REPO"
  else
    printf '%s/Docs/researches/%s/current_folder_research.md' "$REPO" "$path"
  fi
}

file_report_path() {
  local path="$1"
  local d b
  d="$(dirname "$path")"
  b="$(basename "$path")"
  if [[ "$d" == "." ]]; then
    printf '%s/Docs/researches/%s_research.md' "$REPO" "$b"
  else
    printf '%s/Docs/researches/%s/%s_research.md' "$REPO" "$d" "$b"
  fi
}

write_meta_file() {
  local meta_file="$1"
  local mode="$2"
  local target_desc="$3"
  local commit_title="$4"
  local batch_count="$5"
  local batch_total_bytes="$6"
  {
    printf 'MODE=%q\n' "$mode"
    printf 'TARGET_DESC=%q\n' "$target_desc"
    printf 'COMMIT_TITLE=%q\n' "$commit_title"
    printf 'BATCH_COUNT=%q\n' "$batch_count"
    printf 'BATCH_TOTAL_BYTES=%q\n' "$batch_total_bytes"
  } > "$meta_file"
}

claim_next_task() {
  local token="$1"
  local claims_out="$2"
  local items_out="$3"
  local meta_out="$4"

  local line line_no text type path key
  local target_dir cand_line cand_line_no cand_text cand_type cand_path cand_dir
  local cand_abs cand_size cand_key cand_report
  local batch_count batch_total_bytes oversize_single_allowed batch_label single_path

  : > "$claims_out"
  : > "$items_out"

  exec 7>"$CLAIM_LOCK_FILE"
  flock -x 7
  cleanup_stale_claims_under_lock

  mapfile -t PENDING_LINES < <(rg -n '^- \[ \] \[(DIR|FILE)\] ' "$CHECKLIST_FILE" || true)
  if (( ${#PENDING_LINES[@]} == 0 )); then
    flock -u 7 || true
    exec 7>&-
    return 1
  fi

  for line in "${PENDING_LINES[@]}"; do
    line_no="${line%%:*}"
    text="${line#*:}"
    if [[ "$text" =~ ^-\ \[\ \]\ \[(DIR|FILE)\]\ (.+)$ ]]; then
      type="${BASH_REMATCH[1]}"
      path="${BASH_REMATCH[2]}"
    else
      continue
    fi

    key="$(item_key "$type" "$path")"
    if claim_exists_under_lock "$key"; then
      continue
    fi

    if [[ "$type" == "DIR" ]]; then
      if ! claim_create_under_lock "$key" "$token"; then
        continue
      fi
      local report_path
      report_path="$(dir_report_path "$path")"
      mkdir -p "$(dirname "$report_path")"
      printf '%s\n' "$key" >> "$claims_out"
      printf '%s\tDIR\t%s\t%s\t0\n' "$line_no" "$path" "$report_path" >> "$items_out"
      write_meta_file "$meta_out" "DIR" "DIR $path" "DIR $path" "1" "0"
      flock -u 7 || true
      exec 7>&-
      return 0
    fi

    target_dir="$(dirname "$path")"
    batch_count=0
    batch_total_bytes=0
    oversize_single_allowed=0

    for cand_line in "${PENDING_LINES[@]}"; do
      cand_line_no="${cand_line%%:*}"
      cand_text="${cand_line#*:}"
      if [[ "$cand_text" =~ ^-\ \[\ \]\ \[(DIR|FILE)\]\ (.+)$ ]]; then
        cand_type="${BASH_REMATCH[1]}"
        cand_path="${BASH_REMATCH[2]}"
      else
        continue
      fi

      [[ "$cand_type" == "FILE" ]] || continue
      cand_dir="$(dirname "$cand_path")"
      [[ "$cand_dir" == "$target_dir" ]] || continue

      cand_key="$(item_key FILE "$cand_path")"
      if claim_exists_under_lock "$cand_key"; then
        continue
      fi

      cand_abs="$REPO/$cand_path"
      [[ -f "$cand_abs" ]] || continue

      cand_size="$(wc -c < "$cand_abs" | tr -d ' ')"
      if (( batch_count == 0 )) && (( cand_size > MAX_BATCH_BYTES )); then
        oversize_single_allowed=1
        log "info: single file exceeds batch limit but allowed: path=${cand_path} size=${cand_size} limit=${MAX_BATCH_BYTES}"
      fi

      if (( batch_count > 0 )) && (( batch_total_bytes + cand_size > MAX_BATCH_BYTES )); then
        break
      fi

      if ! claim_create_under_lock "$cand_key" "$token"; then
        continue
      fi

      cand_report="$(file_report_path "$cand_path")"
      mkdir -p "$(dirname "$cand_report")"

      printf '%s\n' "$cand_key" >> "$claims_out"
      printf '%s\tFILE\t%s\t%s\t%s\n' "$cand_line_no" "$cand_path" "$cand_report" "$cand_size" >> "$items_out"

      batch_count=$((batch_count + 1))
      batch_total_bytes=$((batch_total_bytes + cand_size))

      if (( oversize_single_allowed == 1 )); then
        break
      fi
    done

    if (( batch_count > 0 )); then
      if (( batch_count == 1 )); then
        single_path="$(awk -F '\t' 'NR==1{print $3}' "$items_out")"
        write_meta_file "$meta_out" "FILE_SINGLE" "FILE ${single_path}" "FILE ${single_path}" "$batch_count" "$batch_total_bytes"
      else
        batch_label="$target_dir"
        [[ "$batch_label" == "." ]] && batch_label="root"
        write_meta_file "$meta_out" "FILE_BATCH" "FILE_BATCH ${batch_label} (${batch_count} files, ${batch_total_bytes} bytes)" "FILE_BATCH ${batch_label} (${batch_count} files)" "$batch_count" "$batch_total_bytes"
      fi
      flock -u 7 || true
      exec 7>&-
      return 0
    fi
  done

  flock -u 7 || true
  exec 7>&-
  return 1
}

build_task_prompt() {
  local meta_file="$1"
  local items_file="$2"
  local prompt_file="$3"
  local mode target_desc
  local line_no type path report size
  local first_line batch_items

  # shellcheck disable=SC1090
  source "$meta_file"
  mode="$MODE"
  target_desc="$TARGET_DESC"

  if [[ "$mode" == "DIR" ]]; then
    first_line="$(head -n 1 "$items_file")"
    IFS=$'\t' read -r line_no type path report size <<< "$first_line"
    cat > "$prompt_file" <<PROMPT
请研究DIR ${path}。

你在项目仓库根目录工作。请完成以下任务并直接修改文件：
1) 深入阅读目标对象与其上下文依赖（调用方、被调用方、配置、测试、脚本、文档）。
2) 产出详尽研究文档到：${report}
   - 必须包含章节：
     - 场景与职责
     - 功能点目的
     - 具体技术实现（关键流程/数据结构/协议/命令）
     - 关键代码路径与文件引用
     - 依赖与外部交互
     - 风险、边界与改进建议

要求：
- 仅修改该研究文档及其必要目录。
- 不要修改 checklist / todo 文件。
- 不要执行 git commit / git push。
- 必须是实质研究，不要空文档或模板占位。
- 使用 kimi cli 非 REPL（print）模式执行本任务，模型使用 ${KIMI_MODEL}。
PROMPT
    return 0
  fi

  if [[ "$mode" == "FILE_SINGLE" ]]; then
    first_line="$(head -n 1 "$items_file")"
    IFS=$'\t' read -r line_no type path report size <<< "$first_line"
    cat > "$prompt_file" <<PROMPT
请研究FILE ${path}。

你在项目仓库根目录工作。请完成以下任务并直接修改文件：
1) 深入阅读目标对象与其上下文依赖（调用方、被调用方、配置、测试、脚本、文档）。
2) 产出详尽研究文档到：${report}
   - 必须包含章节：
     - 场景与职责
     - 功能点目的
     - 具体技术实现（关键流程/数据结构/协议/命令）
     - 关键代码路径与文件引用
     - 依赖与外部交互
     - 风险、边界与改进建议

要求：
- 仅修改该研究文档及其必要目录。
- 不要修改 checklist / todo 文件。
- 不要执行 git commit / git push。
- 必须是实质研究，不要空文档或模板占位。
- 使用 kimi cli 非 REPL（print）模式执行本任务，模型使用 ${KIMI_MODEL}。
PROMPT
    return 0
  fi

  batch_items=""
  while IFS=$'\t' read -r line_no type path report size; do
    batch_items+="- 行${line_no} | ${path} | ${report} | ${size} bytes"$'\n'
  done < "$items_file"

  cat > "$prompt_file" <<PROMPT
请按同目录批次研究 FILE（总大小上限 ${MAX_BATCH_BYTES} bytes）。

本批次文件如下（相近目录合并，避免过度零碎）：
${batch_items}

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

要求：
- 仅修改本批次对应的研究文档及其必要目录。
- 不要修改 checklist / todo 文件。
- 不要执行 git commit / git push。
- 本批次必须是实质研究，不要空文档或模板占位。
- 若单文件本身超过 ${MAX_BATCH_BYTES} bytes，允许作为单文件批次继续研究，不要跳过。
- 使用 kimi cli 非 REPL（print）模式执行本任务，模型使用 ${KIMI_MODEL}。
PROMPT

  return 0
}

verify_reports_nonempty() {
  local items_file="$1"
  local line_no type path report size

  while IFS=$'\t' read -r line_no type path report size; do
    if [[ ! -s "$report" ]]; then
      log "warn: expected report missing/empty: ${report}"
      return 1
    fi
  done < "$items_file"
  return 0
}

mark_claimed_items_done() {
  local claims_file="$1"
  local tmp_file

  [[ -f "$CHECKLIST_FILE" ]] || return 1
  tmp_file="$(mktemp "$LOG_DIR/checklist.${PROJECT}.XXXXXX.md")"

  awk -v key_file="$claims_file" '
    BEGIN {
      while ((getline k < key_file) > 0) {
        if (k != "") done[k] = 1
      }
      close(key_file)
    }
    {
      if (match($0, /^- \[[ xX]\] \[(DIR|FILE)\] (.+)$/, m)) {
        key = m[1] ":" m[2]
        if (key in done) {
          sub(/^- \[[ xX]\]/, "- [x]")
        }
      }
      print
    }
  ' "$CHECKLIST_FILE" > "$tmp_file"

  mv "$tmp_file" "$CHECKLIST_FILE"
}

commit_outputs_with_lock() {
  local items_file="$1"
  local todo_file="$2"
  local commit_title="$3"
  local target_desc="$4"
  local line_no type path report size rel

  while IFS=$'\t' read -r line_no type path report size; do
    if [[ -f "$report" ]]; then
      rel="$(to_repo_rel "$report")"
      git add -- "$rel" >/dev/null 2>&1 || true
    fi
  done < "$items_file"

  if [[ -f "$CHECKLIST_FILE" ]]; then
    git add -- "$(to_repo_rel "$CHECKLIST_FILE")" >/dev/null 2>&1 || true
  fi

  if [[ -n "$todo_file" && -f "$todo_file" ]]; then
    git add -- "$(to_repo_rel "$todo_file")" >/dev/null 2>&1 || true
  fi

  if ! git diff --cached --quiet; then
    if git commit -m "docs(research): ${commit_title}" >/dev/null 2>&1; then
      if [[ "$AUTO_PUSH_ON_CHECKPOINT" == "1" ]]; then
        auto_push_with_conflict_resolution || true
        log "checkpoint committed and push attempted: ${target_desc}"
      else
        log "checkpoint committed locally: ${target_desc}"
      fi
    fi
  fi
}

apply_success_updates_with_lock() {
  local claims_file="$1"
  local items_file="$2"
  local meta_file="$3"
  local todo_out pending_total

  # shellcheck disable=SC1090
  source "$meta_file"

  exec 8>"$WRITE_LOCK_FILE"
  flock -x 8

  if ! bash .ops/generate_research_blueprint_checklist.sh >> "$LOG_FILE" 2>&1; then
    flock -u 8 || true
    exec 8>&-
    return 1
  fi

  if ! mark_claimed_items_done "$claims_file"; then
    flock -u 8 || true
    exec 8>&-
    return 1
  fi

  todo_out="$(bash .ops/generate_daily_research_todo.sh 2>>"$LOG_FILE" | tail -n 1 || true)"
  log "today_todo=${todo_out}"

  commit_outputs_with_lock "$items_file" "$todo_out" "$COMMIT_TITLE" "$TARGET_DESC"

  pending_total="$( (rg -n '^- \[ \] \[(DIR|FILE)\] ' "$CHECKLIST_FILE" || true) | wc -l | tr -d ' ')"
  if [[ "$pending_total" == "0" ]]; then
    set_state "completed"
    set_block 0
    log "all research checklist items completed"
    if [[ "$AUTO_CLEANUP_ON_COMPLETE" == "1" && -x .ops/cleanup_research_cron.sh ]]; then
      .ops/cleanup_research_cron.sh --execute >> "$LOG_FILE" 2>&1 || true
    fi
  fi

  flock -u 8 || true
  exec 8>&-
  return 0
}

run_worker_once() {
  local token="$1"
  local claims_file items_file meta_file prompt_file task
  local run_rc apply_rc

  if ! bash .ops/generate_research_blueprint_checklist.sh >> "$LOG_FILE" 2>&1; then
    set_state "failed_blueprint"
    log "error: failed to generate research blueprint checklist"
    return 1
  fi

  claims_file="$(mktemp "$LOG_DIR/claims.${PROJECT}.XXXXXX.list")"
  items_file="$(mktemp "$LOG_DIR/items.${PROJECT}.XXXXXX.tsv")"
  meta_file="$(mktemp "$LOG_DIR/meta.${PROJECT}.XXXXXX.env")"
  prompt_file="$(mktemp "$LOG_DIR/prompt.${PROJECT}.XXXXXX.txt")"

  if ! claim_next_task "$token" "$claims_file" "$items_file" "$meta_file"; then
    rm -f "$claims_file" "$items_file" "$meta_file" "$prompt_file"
    set_state "completed"
    set_block 0
    log "no available pending item for worker slot=${WORKER_SLOT}"
    return 2
  fi

  build_task_prompt "$meta_file" "$items_file" "$prompt_file"
  task="$(cat "$prompt_file")"

  set_state "running_exec"
  set_block 0

  run_rc=0
  run_research_with_kimi "$task" || run_rc=$?

  if [[ "$run_rc" -eq 0 ]]; then
    if ! verify_reports_nonempty "$items_file"; then
      run_rc=67
    fi
  fi

  apply_rc=0
  if [[ "$run_rc" -eq 0 ]]; then
    apply_success_updates_with_lock "$claims_file" "$items_file" "$meta_file" || apply_rc=$?
  fi

  release_claims "$token" "$claims_file"
  rm -f "$claims_file" "$items_file" "$meta_file" "$prompt_file"

  if [[ "$run_rc" -eq 0 && "$apply_rc" -eq 0 ]]; then
    set_state "exec_completed"
    return 0
  fi

  if [[ "$run_rc" -eq 124 ]]; then
    set_state "exec_timeout"
    log "warn: research exec timeout"
  else
    set_state "exec_failed"
    log "warn: research exec failed rc=${run_rc} apply_rc=${apply_rc}"
  fi
  set_block 1
  return 1
}

run_worker_loop() {
  local token
  token="${PROJECT}-slot${WORKER_SLOT}-$$-$(date +%s)"

  cd "$REPO"

  if [[ ! -x "$KIMI_BIN" ]]; then
    if command -v kimi >/dev/null 2>&1; then
      KIMI_BIN="$(command -v kimi)"
    else
      set_state "failed_no_kimi"
      log "error: kimi binary not found"
      return 1
    fi
  fi

  while true; do
    if ! run_worker_once "$token"; then
      rc=$?
      if [[ "$rc" -eq 2 ]]; then
        return 0
      fi
      return 1
    fi
  done
}

ensure_tmux_workers() {
  local i window_name cmd pane_dead

  exec 9>"$SCHEDULER_LOCK_FILE"
  if ! flock -n 9; then
    log "skip: scheduler lock busy"
    return 0
  fi

  if ! command -v tmux >/dev/null 2>&1; then
    log "warn: tmux not found; fallback single worker"
    TMUX_WRAP_ENABLED=0
    WORKER_MODE=1
    WORKER_SLOT=1
    run_worker_loop || true
    flock -u 9 || true
    exec 9>&-
    return 0
  fi

  if ! [[ "$MAX_PARALLEL_RESEARCH" =~ ^[0-9]+$ ]] || (( MAX_PARALLEL_RESEARCH < 1 )); then
    MAX_PARALLEL_RESEARCH=4
  fi

  for ((i=1; i<=MAX_PARALLEL_RESEARCH; i++)); do
    window_name="research-worker-${i}"
    cmd="cd \"$REPO\" && TMUX_WRAP_ENABLED=0 RESEARCH_GUARD_WORKER=1 WORKER_SLOT=${i} bash .ops/research_guard.sh"

    if ! tmux has-session -t "$TMUX_SESSION_NAME" 2>/dev/null; then
      if tmux new-session -d -s "$TMUX_SESSION_NAME" -n "$window_name" "$cmd" >/dev/null 2>&1; then
        log "delegated to new tmux session=${TMUX_SESSION_NAME} window=${window_name}"
      else
        log "warn: tmux new-session failed for session=${TMUX_SESSION_NAME}"
      fi
      continue
    fi

    if tmux list-windows -t "$TMUX_SESSION_NAME" -F '#{window_name}' | rg -Fxq "$window_name"; then
      pane_dead="$(tmux list-panes -t "$TMUX_SESSION_NAME:$window_name" -F '#{pane_dead}' 2>/dev/null | head -n 1 || true)"
      if [[ "$pane_dead" == "1" ]]; then
        if tmux respawn-pane -k -t "$TMUX_SESSION_NAME:$window_name" "$cmd" >/dev/null 2>&1; then
          log "respawned dead worker window=${window_name}"
        else
          log "warn: failed to respawn dead worker window=${window_name}"
        fi
      else
        log "worker already running window=${window_name}"
      fi
    else
      if tmux new-window -d -t "$TMUX_SESSION_NAME" -n "$window_name" "$cmd" >/dev/null 2>&1; then
        log "started worker window=${window_name} in session=${TMUX_SESSION_NAME}"
      else
        log "warn: failed to start worker window=${window_name} in session=${TMUX_SESSION_NAME}"
      fi
    fi
  done

  flock -u 9 || true
  exec 9>&-
  return 0
}

main() {
  cd "$REPO"

  if [[ "$TMUX_WRAP_ENABLED" == "1" && "$WORKER_MODE" != "1" ]]; then
    ensure_tmux_workers
    return 0
  fi

  if [[ "$WORKER_MODE" != "1" ]]; then
    exec 6>"$LOCK_FILE"
    if ! flock -n 6; then
      log "skip: previous local worker still active"
      return 0
    fi
  fi

  run_worker_loop || true
  return 0
}

main "$@"
