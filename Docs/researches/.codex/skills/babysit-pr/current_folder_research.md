# babysit-pr Skill 深度研究文档

## 1. 场景与职责

### 1.1 核心场景

`babysit-pr` 是一个 Kimi CLI Skill，用于**自动化监控和协助 GitHub Pull Request 的生命周期管理**。它解决的核心问题是：开发者在提交 PR 后需要持续关注 CI 状态、审查反馈、合并冲突等，这个过程繁琐且耗时。

### 1.2 职责边界

该 Skill 的职责包括：

| 职责领域 | 具体内容 |
|---------|---------|
| **CI 监控** | 持续轮询 PR 的 CI checks 状态，检测失败、挂起或成功 |
| **失败诊断** | 分析 CI 失败原因，区分"分支相关失败"vs" flaky/基础设施失败" |
| **自动修复** | 对分支相关失败自动本地修复、提交并推送 |
| **审查反馈处理** | 监控 PR 评论、行内审查评论、审查提交，识别可操作的反馈 |
| **Flaky 重试** | 对 flaky 失败自动重试（默认最多 3 次） |
| **合并就绪检测** | 检测 PR 是否满足合并条件（CI 通过 + 无未处理审查 + 可合并） |

### 1.3 终端状态定义

Skill 在以下情况会停止监控：
1. PR 被合并或关闭
2. PR 完全就绪（CI 通过 + 审查清理完毕 + 可合并 + 无阻塞审查决策）
3. 需要用户介入（基础设施问题、重试预算耗尽、权限问题、模糊情况）

---

## 2. 功能点目的

### 2.1 功能模块划分

```
┌─────────────────────────────────────────────────────────────┐
│                    babysit-pr Skill                         │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │  PR 解析器   │  │  CI 监控器   │  │   审查反馈处理器     │  │
│  │  (resolve)  │  │  (checks)   │  │   (review items)    │  │
│  └──────┬──────┘  └──────┬──────┘  └──────────┬──────────┘  │
│         │                │                    │             │
│         └────────────────┼────────────────────┘             │
│                          ▼                                  │
│              ┌─────────────────────┐                        │
│              │    决策引擎 (recommend_actions)              │
│              └──────────┬──────────┘                        │
│                         ▼                                   │
│              ┌─────────────────────┐                        │
│              │   动作执行器 (actions)  │                     │
│              │  - diagnose_ci_failure│                     │
│              │  - retry_failed_checks│                     │
│              │  - process_review_comment                   │
│              └─────────────────────┘                        │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 各功能点详细目的

#### 2.2.1 PR 解析 (`resolve_pr`)
- **目的**：支持多种 PR 标识方式（auto/number/URL），统一解析为内部结构
- **输入**：`--pr auto` 或 PR 号或 PR URL
- **输出**：标准化的 PR 信息字典（含 repo、head_sha、branch、state 等）

#### 2.2.2 CI 状态聚合 (`get_pr_checks` + `summarize_checks`)
- **目的**：将 GitHub 分散的 check 数据聚合为可决策的摘要
- **关键指标**：pending_count、failed_count、passed_count、all_terminal

#### 2.2.3 Workflow Run 追踪 (`get_workflow_runs_for_sha`)
- **目的**：获取与当前 head SHA 关联的所有 workflow runs，用于后续重试
- **API**：`repos/{owner}/{repo}/actions/runs?head_sha={sha}`

#### 2.2.4 审查反馈去重 (`fetch_new_review_items`)
- **目的**：只向 Agent 报告"新的"审查反馈，避免重复处理
- **状态管理**：通过 `seen_issue_comment_ids`、`seen_review_comment_ids`、`seen_review_ids` 追踪

#### 2.2.5 智能决策 (`recommend_actions`)
- **目的**：根据当前状态推荐下一步动作
- **输出 actions 列表**：
  - `idle`：等待中
  - `diagnose_ci_failure`：需要诊断 CI 失败
  - `retry_failed_checks`：可以重试 flaky 失败
  - `process_review_comment`：有新审查反馈待处理
  - `stop_pr_closed`：PR 已关闭，停止
  - `stop_ready_to_merge`：PR 就绪，停止
  - `stop_exhausted_retries`：重试预算耗尽，停止

#### 2.2.6 自适应轮询 (`run_watch`)
- **目的**：在 CI 未通过时高频轮询（1分钟），CI 通过后指数退避（最高1小时）
- **触发重置**：SHA 变化、check 状态变化、新审查评论、合并状态变化

---

## 3. 具体技术实现

### 3.1 关键流程

#### 3.1.1 主监控循环 (`run_watch`)

```python
def run_watch(args):
    poll_seconds = args.poll_seconds  # 默认 30s
    last_change_key = None
    while True:
        snapshot, state_path = collect_snapshot(args)  # 采集状态
        print_event("snapshot", {...})  # 输出 JSONL 事件
        
        actions = set(snapshot.get("actions") or [])
        if 有终止动作:
            print_event("stop", {...})
            return 0
        
        # 自适应调整轮询间隔
        if not green:
            poll_seconds = args.poll_seconds  # 重置为 1m
        elif changed:
            poll_seconds = args.poll_seconds  # 有变化，重置
        else:
            poll_seconds = min(poll_seconds * 2, GREEN_STATE_MAX_POLL_SECONDS)  # 指数退避
        
        time.sleep(poll_seconds)
```

#### 3.1.2 状态采集流程 (`collect_snapshot`)

```python
def collect_snapshot(args):
    pr = resolve_pr(args.pr, repo_override=args.repo)
    state, fresh_state = load_state(state_path)
    
    checks = get_pr_checks(str(pr["number"]), repo=pr["repo"])
    checks_summary = summarize_checks(checks)
    
    workflow_runs = get_workflow_runs_for_sha(pr["repo"], pr["head_sha"])
    failed_runs = failed_runs_from_workflow_runs(workflow_runs, pr["head_sha"])
    
    authenticated_login = get_authenticated_login()
    new_review_items = fetch_new_review_items(pr, state, fresh_state, authenticated_login)
    
    retries_used = current_retry_count(state, pr["head_sha"])
    actions = recommend_actions(pr, checks_summary, failed_runs, new_review_items, retries_used, args.max_flaky_retries)
    
    save_state(state_path, state)  # 持久化 seen IDs 等
    return snapshot, state_path
```

#### 3.1.3 Flaky 重试流程 (`retry_failed_now`)

```python
def retry_failed_now(args):
    snapshot, state_path = collect_snapshot(args)
    
    # 前置检查
    if pr["closed"] or pr["merged"]: return {"reason": "pr_closed"}
    if checks_summary["failed_count"] <= 0: return {"reason": "no_failed_pr_checks"}
    if not checks_summary["all_terminal"]: return {"reason": "checks_still_pending"}
    if retries_used >= max_retries: return {"reason": "retry_budget_exhausted"}
    
    # 执行重试
    for run in failed_runs:
        gh_text(["run", "rerun", str(run_id), "--failed"], repo=pr["repo"])
    
    # 更新重试计数
    set_retry_count(state, pr["head_sha"], current_retry_count(state, pr["head_sha"]) + 1)
    save_state(state_path, state)
```

### 3.2 核心数据结构

#### 3.2.1 PR 信息结构

```python
{
    "number": int,
    "url": str,
    "repo": "OWNER/REPO",
    "head_sha": str,
    "head_branch": str,
    "state": str,
    "merged": bool,
    "closed": bool,
    "mergeable": "MERGEABLE" | "CONFLICTING" | "UNKNOWN",
    "merge_state_status": str,
    "review_decision": "APPROVED" | "CHANGES_REQUESTED" | "REVIEW_REQUIRED" | ""
}
```

#### 3.2.2 Checks 摘要结构

```python
{
    "pending_count": int,
    "failed_count": int,
    "passed_count": int,
    "all_terminal": bool  # 是否所有 checks 都已结束（无 pending）
}
```

#### 3.2.3 审查反馈项结构

```python
{
    "kind": "issue_comment" | "review_comment" | "review",
    "id": str,
    "author": str,
    "author_association": "OWNER" | "MEMBER" | "COLLABORATOR" | "CONTRIBUTOR" | ...,
    "created_at": str,
    "body": str,
    "path": str | None,      # 文件路径（仅 review_comment）
    "line": int | None,      # 行号（仅 review_comment）
    "url": str
}
```

#### 3.2.4 状态文件结构

```python
{
    "pr": {"repo": str, "number": int},
    "started_at": int,           # 首次监控时间戳
    "last_seen_head_sha": str,   # 上次看到的 SHA
    "retries_by_sha": {          # 每个 SHA 的重试次数
        "sha1": 2,
        "sha2": 1
    },
    "seen_issue_comment_ids": [str],    # 已处理的 issue comment IDs
    "seen_review_comment_ids": [str],   # 已处理的 review comment IDs
    "seen_review_ids": [str],           # 已处理的 review IDs
    "last_snapshot_at": int
}
```

#### 3.2.5 Snapshot 输出结构

```python
{
    "pr": {...},
    "checks": {...},
    "failed_runs": [...],
    "new_review_items": [...],
    "actions": ["diagnose_ci_failure", "retry_failed_checks", ...],
    "retry_state": {
        "current_sha_retries_used": int,
        "max_flaky_retries": int
    }
}
```

### 3.3 协议与命令

#### 3.3.1 命令行接口

| 命令 | 用途 |
|-----|------|
| `--pr auto` | 从当前分支推断 PR |
| `--pr <number>` | 指定 PR 号 |
| `--pr <url>` | 指定 PR URL |
| `--once` | 单次快照，输出 JSON |
| `--watch` | 持续监控，输出 JSONL 流 |
| `--retry-failed-now` | 立即重试失败的 checks |
| `--poll-seconds 30` | 轮询间隔（默认 30s） |
| `--max-flaky-retries 3` | 最大重试次数 |
| `--state-file <path>` | 自定义状态文件路径 |

#### 3.3.2 输出协议

**单次模式 (`--once`)**：
```json
{
  "pr": {...},
  "checks": {...},
  "failed_runs": [...],
  "new_review_items": [...],
  "actions": [...],
  "retry_state": {...},
  "state_file": "/tmp/codex-babysit-pr-..."
}
```

**持续模式 (`--watch`)**：JSON Lines 流
```jsonl
{"event": "snapshot", "payload": {"snapshot": {...}, "state_file": "...", "next_poll_seconds": 30}}
{"event": "snapshot", "payload": {...}}
{"event": "stop", "payload": {"actions": [...], "pr": {...}}}
```

**重试模式 (`--retry-failed-now`)**：
```json
{
  "snapshot": {...},
  "state_file": "...",
  "rerun_attempted": true,
  "rerun_count": 2,
  "rerun_run_ids": [123456, 123457],
  "reason": "rerun_triggered"
}
```

### 3.4 GitHub API 调用

| 用途 | 命令/端点 |
|-----|----------|
| PR 元数据 | `gh pr view --json number,url,state,mergedAt,closedAt,headRefName,headRefOid,...` |
| PR Checks | `gh pr checks --json name,state,bucket,link,workflow,event,startedAt,completedAt` |
| Workflow Runs | `gh api repos/{owner}/{repo}/actions/runs -f head_sha={sha} -f per_page=100` |
| Issue Comments | `gh api repos/{owner}/{repo}/issues/{pr_number}/comments?per_page=100` |
| Review Comments | `gh api repos/{owner}/{repo}/pulls/{pr_number}/comments?per_page=100` |
| Reviews | `gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews?per_page=100` |
| 重试失败 Jobs | `gh run rerun {run_id} --failed` |
| 当前用户 | `gh api user` |

---

## 4. 关键代码路径与文件引用

### 4.1 文件结构

```
.codex/skills/babysit-pr/
├── SKILL.md                          # Skill 定义和使用指南
├── agents/
│   └── openai.yaml                   # Agent 接口定义（display_name, prompt）
├── references/
│   ├── github-api-notes.md           # GitHub CLI/API 使用笔记
│   └── heuristics.md                 # CI 分类启发式规则
└── scripts/
    └── gh_pr_watch.py                # 核心实现（805 行）
```

### 4.2 核心代码路径

#### 4.2.1 入口与参数解析
- **文件**：`.codex/skills/babysit-pr/scripts/gh_pr_watch.py`
- **函数**：`parse_args()` (L55-94)
- **入口**：`main()` (L784-805)

#### 4.2.2 PR 解析
- **函数**：`resolve_pr()` (L157-192)
- **辅助**：`parse_pr_spec()` (L135-143), `extract_repo_from_pr_url()` (L214-219), `extract_repo_from_pr_view()` (L195-213)

#### 4.2.3 CI 监控
- **函数**：`get_pr_checks()` (L265-276), `summarize_checks()` (L285-302)
- **Workflow**：`get_workflow_runs_for_sha()` (L305-316), `failed_runs_from_workflow_runs()` (L319-339)
- **判断**：`is_pending_check()` (L279-282), `is_ci_green()` (L716-722)

#### 4.2.4 审查反馈处理
- **函数**：`fetch_new_review_items()` (L468-524)
- **标准化**：`normalize_issue_comments()` (L375-393), `normalize_review_comments()` (L396-417), `normalize_reviews()` (L420-438)
- **信任判断**：`is_trusted_human_review_author()` (L458-465), `is_actionable_review_bot_login()` (L451-455)

#### 4.2.5 决策引擎
- **函数**：`recommend_actions()` (L572-598)
- **就绪判断**：`is_pr_ready_to_merge()` (L554-569)

#### 4.2.6 状态管理
- **加载**：`load_state()` (L222-240)
- **保存**：`save_state()` (L243-258)
- **默认路径**：`default_state_file_for()` (L260-262)
- **重试计数**：`current_retry_count()` (L527-533), `set_retry_count()` (L536-541)

#### 4.2.7 主循环
- **单次采集**：`collect_snapshot()` (L601-649)
- **持续监控**：`run_watch()` (L747-781)
- **重试执行**：`retry_failed_now()` (L652-704)

### 4.3 关键常量定义

```python
# L15-48
FAILED_RUN_CONCLUSIONS = {"failure", "timed_out", "cancelled", "action_required", "startup_failure", "stale"}
PENDING_CHECK_STATES = {"QUEUED", "IN_PROGRESS", "PENDING", "WAITING", "REQUESTED"}
REVIEW_BOT_LOGIN_KEYWORDS = {"codex"}  # 信任包含 "codex" 的 bot
TRUSTED_AUTHOR_ASSOCIATIONS = {"OWNER", "MEMBER", "COLLABORATOR"}
MERGE_BLOCKING_REVIEW_DECISIONS = {"REVIEW_REQUIRED", "CHANGES_REQUESTED"}
MERGE_CONFLICT_OR_BLOCKING_STATES = {"BLOCKED", "DIRTY", "DRAFT", "UNKNOWN"}
GREEN_STATE_MAX_POLL_SECONDS = 60 * 60  # 1小时
```

---

## 5. 依赖与外部交互

### 5.1 外部依赖

| 依赖 | 用途 | 必需 |
|-----|------|-----|
| `gh` (GitHub CLI) | 所有 GitHub 操作 | 是 |
| Python 3 | 脚本运行环境 | 是 |
| `/tmp` 目录 | 状态文件存储 | 是（可自定义） |

### 5.2 GitHub CLI 命令依赖

脚本通过 `gh_text()` 和 `gh_json()` 函数封装所有 `gh` 调用：

```python
def gh_text(args, repo=None):
    cmd = ["gh"]
    if repo and (not args or args[0] != "api"):
        cmd.extend(["-R", repo])
    cmd.extend(args)
    # ...
```

### 5.3 状态文件持久化

- **默认路径**：`/tmp/codex-babysit-pr-{repo_slug}-pr{pr_number}.json`
- **格式**：JSON，包含 seen IDs、重试计数、时间戳
- **原子写入**：使用临时文件 + `os.replace()` 保证原子性

### 5.4 Agent 集成

通过 `agents/openai.yaml` 定义 Agent 接口：

```yaml
interface:
  display_name: "PR Babysitter"
  short_description: "Watch PR CI, reviews, and merge conflicts"
  default_prompt: "Babysit the current PR: monitor CI, reviewer comments..."
```

Agent 通过执行 Python 脚本并解析 JSON/JSONL 输出与 Skill 交互。

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 状态文件冲突
- **风险**：多个进程同时监控同一 PR 可能导致状态文件竞争
- **现状**：脚本未实现文件锁，依赖用户不并发执行
- **缓解**：文档建议"保持单个 watcher 会话"

#### 6.1.2 GitHub API 限制
- **风险**：大规模仓库的 review comments 可能超过 100 条/页限制
- **现状**：使用分页但未实现 rate limit 处理
- **代码位置**：`gh_api_list_paginated()` (L357-372)

#### 6.1.3 认证过期
- **风险**：`gh` 认证过期会导致所有 API 调用失败
- **处理**：抛出 `GhCommandError`，Agent 需处理此错误

#### 6.1.4 Bot 评论误判
- **风险**：`REVIEW_BOT_LOGIN_KEYWORDS = {"codex"}` 可能漏判或误判
- **示例**：`some-other-codex-bot[bot]` 会被信任，但 `openai-bot[bot]` 不会

### 6.2 边界情况

| 场景 | 当前行为 |
|-----|---------|
| PR 被关闭后重新打开 | 视为新 PR，状态文件保留但会检测 state 变化 |
| Force push 后 SHA 变化 | `last_seen_head_sha` 检测变化，重试计数重置 |
| 审查评论被标记为 resolved | 脚本不追踪 resolved 状态，依赖 Agent 判断 |
| 新状态文件首次运行 | 所有现有 pending 评论都会被视为"新"（ intentional 设计） |
| 无 failed runs 但有 failed checks | `retry_failed_now` 返回 `"reason": "no_failed_runs"` |

### 6.3 改进建议

#### 6.3.1 高优先级

1. **添加文件锁机制**
   ```python
   import fcntl  # Unix
   # 或 portalocker 跨平台
   ```
   防止同一 PR 的多 watcher 竞争。

2. **Rate Limit 处理**
   ```python
   # 在 gh_json 中添加 403/429 重试逻辑
   if err.returncode == 403 or err.returncode == 429:
       # 读取 Retry-After header，指数退避
   ```

3. **Resolved 评论追踪**
   当前脚本不区分 resolved/unresolved review comments，建议：
   - 调用 `repos/{owner}/{repo}/pulls/{pr_number}/comments` 时包含 `?since=` 或检查 `resolved` 字段

#### 6.3.2 中优先级

4. **更智能的 Bot 检测**
   ```python
   # 可配置的信任 bot 列表
   TRUSTED_BOTS = {"codex", "openai", "github-actions"}
   ```

5. **状态文件压缩/轮转**
   长期监控同一 PR 可能导致状态文件累积大量 seen IDs。

6. **WebSocket/Webhook 支持**
   当前轮询模式效率较低，可考虑 GitHub Webhook 或 GraphQL Subscriptions（需要服务器支持）。

#### 6.3.3 低优先级

7. **Metrics 导出**
   输出监控时长、重试次数、发现的问题数等指标。

8. **多 PR 监控**
   当前设计为单 PR，扩展为多 PR 需要重新设计状态文件结构。

### 6.4 测试建议

当前脚本无单元测试，建议添加：

1. **Mock `gh` 命令** 的单元测试框架
2. **状态文件读写** 的边界测试
3. **决策逻辑表** 的完整覆盖测试
4. **分页逻辑** 的大数据量测试

---

## 7. 总结

`babysit-pr` 是一个设计精良的 PR 监控 Skill，通过清晰的职责分离（采集→决策→执行）和健壮的状态管理，实现了自动化的 PR 生命周期管理。其核心优势在于：

1. **自适应轮询**：平衡实时性和资源消耗
2. **智能去重**：避免重复处理相同的审查反馈
3. **Flaky 容忍**：自动重试机制减少人工干预
4. **安全边界**：明确的停止条件和用户介入点

主要改进空间在于并发安全（文件锁）、API 限制处理和更精细的审查评论状态追踪。
