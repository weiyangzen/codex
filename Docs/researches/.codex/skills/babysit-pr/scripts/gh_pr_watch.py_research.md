# gh_pr_watch.py 深度研究文档

## 1. 场景与职责

### 1.1 核心定位

`gh_pr_watch.py` 是 **babysit-pr Skill** 的核心执行脚本，负责实现 GitHub Pull Request 的持续监控与自动化处理。它是连接 Codex Agent 与 GitHub 生态系统的关键桥梁，使 Agent 能够自主监控 PR 生命周期，直到达成明确的终止条件。

### 1.2 业务场景

该脚本服务于以下典型场景：

| 场景 | 描述 |
|------|------|
| **CI 监控** | 持续轮询 PR 的 CI 检查状态，识别失败、挂起或成功的状态变化 |
| **Review 反馈处理** | 捕获 PR 上的新评论、代码审查意见，支持人机协作流程 |
| **Flaky 失败自动重试** | 对疑似偶发性失败的 CI 任务进行有限次数的自动重试（默认最多3次） |
| **合并就绪检测** | 综合判断 CI 通过、Review 清理、无合并冲突等条件，确定 PR 是否可合并 |
| **状态持久化** | 通过本地状态文件维护监控会话的连续性，支持跨会话恢复 |

### 1.3 职责边界

- **负责**：PR 状态采集、CI 检查汇总、Review 活动识别、失败工作流重试、状态持久化
- **不负责**：实际代码修复、自动合并操作、Git 分支管理、冲突解决

### 1.4 调用模式

脚本支持三种运行模式，对应不同的使用场景：

```
--once      : 单次快照模式，用于诊断或手动检查
--watch     : 持续监控模式，流式输出 JSONL 事件流
--retry-failed-now : 立即触发失败任务重试
```

---

## 2. 功能点目的

### 2.1 功能模块总览

```
┌─────────────────────────────────────────────────────────────────┐
│                     gh_pr_watch.py                              │
├─────────────────────────────────────────────────────────────────┤
│  参数解析 (parse_args)                                          │
│  ├── PR 解析 (parse_pr_spec)                                    │
│  │   ├── auto: 从当前分支推断                                   │
│  │   ├── number: 数字 PR 号                                     │
│  │   └── url: 完整 PR URL                                       │
│  ├── 状态文件管理                                               │
│  └── 运行模式选择                                               │
├─────────────────────────────────────────────────────────────────┤
│  GitHub CLI 封装 (gh_text/gh_json)                              │
│  ├── 命令执行与错误处理                                         │
│  └── JSON 解析与验证                                            │
├─────────────────────────────────────────────────────────────────┤
│  PR 信息获取 (resolve_pr)                                       │
│  ├── PR 基础元数据                                              │
│  ├── 仓库信息提取                                               │
│  └── 合并状态判断                                               │
├─────────────────────────────────────────────────────────────────┤
│  CI 检查监控                                                    │
│  ├── PR Checks 获取 (get_pr_checks)                             │
│  ├── 检查状态汇总 (summarize_checks)                            │
│  └── 工作流运行追踪                                             │
│      ├── 获取 SHA 对应运行 (get_workflow_runs_for_sha)          │
│      └── 失败运行筛选 (failed_runs_from_workflow_runs)          │
├─────────────────────────────────────────────────────────────────┤
│  Review 活动监控                                                │
│  ├── 三类评论获取                                               │
│  │   ├── Issue 评论                                             │
│  │   ├── Review 行内评论                                        │
│  │   └── Review 提交                                            │
│  ├── 作者信任判断                                               │
│  │   ├── 人类作者: OWNER/MEMBER/COLLABORATOR                    │
│  │   └── Bot 作者: 仅信任含 "codex" 关键词的 Bot                │
│  └── 新评论去重                                                 │
├─────────────────────────────────────────────────────────────────┤
│  决策引擎 (recommend_actions)                                   │
│  ├── 终止条件判断                                               │
│  │   ├── PR 已关闭/合并                                         │
│  │   ├── 就绪可合并                                             │
│  │   └── 重试次数耗尽                                           │
│  ├── 行动建议                                                   │
│  │   ├── process_review_comment: 处理 Review 反馈               │
│  │   ├── diagnose_ci_failure: 诊断 CI 失败                      │
│  │   ├── retry_failed_checks: 重试失败检查                      │
│  │   └── idle: 等待中                                           │
│  └── 合并就绪判断 (is_pr_ready_to_merge)                        │
├─────────────────────────────────────────────────────────────────┤
│  失败重试机制 (retry_failed_now)                                │
│  ├── 前置条件检查                                               │
│  ├── 触发 gh run rerun --failed                               │
│  └── 重试计数更新                                               │
├─────────────────────────────────────────────────────────────────┤
│  状态持久化                                                     │
│  ├── 加载状态 (load_state)                                      │
│  ├── 保存状态 (save_state)                                      │
│  └── 原子写入保证                                               │
├─────────────────────────────────────────────────────────────────┤
│  持续监控循环 (run_watch)                                       │
│  ├── 自适应轮询间隔                                             │
│  │   ├── 非绿色状态: 固定间隔 (默认30秒)                        │
│  │   └── 绿色状态: 指数退避 (最大1小时)                         │
│  ├── 变化检测                                                   │
│  └── 事件流输出 (JSONL)                                         │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 关键功能详解

#### 2.2.1 PR 解析与识别

支持三种 PR 指定方式：

| 模式 | 示例 | 处理逻辑 |
|------|------|----------|
| `auto` | `--pr auto` | 依赖 `gh pr view` 自动检测当前分支关联的 PR |
| `number` | `--pr 123` | 直接使用 PR 数字编号 |
| `url` | `--pr https://github.com/owner/repo/pull/123` | 解析 URL 提取 owner/repo 和 PR 号 |

#### 2.2.2 CI 状态机

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   QUEUED    │───▶│  IN_PROGRESS│───▶│   COMPLETED │
│   PENDING   │    │   WAITING   │    │             │
│   REQUESTED │    │             │    │             │
└─────────────┘    └─────────────┘    └──────┬──────┘
                                             │
                    ┌────────────────────────┼────────────────────────┐
                    ▼                        ▼                        ▼
              ┌─────────┐              ┌─────────┐              ┌──────────┐
              │ success │              │ failure │              │  others  │
              │   pass  │              │   fail  │              │ cancelled│
              └─────────┘              └─────────┘              │ timed_out│
                                                                │  stale   │
                                                                └──────────┘
```

#### 2.2.3 Review 评论过滤策略

采用分层过滤机制确保只向 Agent 呈现有价值的反馈：

```
所有评论
    │
    ▼
┌─────────────────────────────────────┐
│ 1. 作者身份过滤                      │
│    - Bot: 仅保留含 "codex" 关键词   │
│    - 人类: 仅保留 TRUSTED 关联      │
└─────────────────────────────────────┘
    │
    ▼
┌─────────────────────────────────────┐
│ 2. 已读去重                          │
│    - 对比状态文件中的已见 ID 列表   │
│    - 全新状态文件特殊处理：展示已有 │
└─────────────────────────────────────┘
    │
    ▼
新评论列表 → 返回给 Agent
```

**信任作者关联** (`TRUSTED_AUTHOR_ASSOCIATIONS`): `OWNER`, `MEMBER`, `COLLABORATOR`

**可信任 Bot 识别** (`REVIEW_BOT_LOGIN_KEYWORDS`): 登录名包含 `codex` 且以 `[bot]` 结尾

#### 2.2.4 自适应轮询策略

```python
if not green:
    poll_seconds = args.poll_seconds  # 固定短间隔
elif changed or last_change_key is None:
    poll_seconds = args.poll_seconds  # 状态变化，重置间隔
else:
    poll_seconds = min(poll_seconds * 2, GREEN_STATE_MAX_POLL_SECONDS)  # 指数退避
```

- **非绿色状态**（CI 运行中/失败）：保持高频轮询（默认30秒）
- **绿色状态无变化**：指数退避，最大间隔 1 小时
- **任何状态变化**：立即重置为短间隔

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 PR 信息结构 (`resolve_pr` 返回)

```python
{
    "number": int,              # PR 编号
    "url": str,                 # PR URL
    "repo": str,                # OWNER/REPO 格式
    "head_sha": str,            # 当前 HEAD commit SHA
    "head_branch": str,         # 分支名
    "state": str,               # PR 状态 (OPEN/CLOSED)
    "merged": bool,             # 是否已合并
    "closed": bool,             # 是否已关闭
    "mergeable": str,           # 合并可行性 (MERGEABLE/CONFLICTING/UNKNOWN)
    "merge_state_status": str,  # 合并状态 (BLOCKED/CLEAN/DIRTY等)
    "review_decision": str,     # Review 决策 (APPROVED/CHANGES_REQUESTED/REVIEW_REQUIRED)
}
```

#### 3.1.2 Checks 汇总结构 (`summarize_checks` 返回)

```python
{
    "pending_count": int,   # 待执行/执行中的检查数
    "failed_count": int,    # 失败的检查数
    "passed_count": int,    # 通过的检查数
    "all_terminal": bool,   # 是否所有检查都已结束
}
```

#### 3.1.3 失败运行结构 (`failed_runs_from_workflow_runs` 返回)

```python
[
    {
        "run_id": int,          # GitHub Actions Run ID
        "workflow_name": str,   # 工作流名称
        "status": str,          # 运行状态
        "conclusion": str,      # 结论 (failure/timed_out/cancelled等)
        "html_url": str,        # 运行详情页 URL
    }
]
```

#### 3.1.4 Review 项目结构 (统一格式)

```python
{
    "kind": str,                    # "issue_comment" | "review_comment" | "review"
    "id": str,                      # 评论/Review ID
    "author": str,                  # 作者登录名
    "author_association": str,      # 作者与仓库关系
    "created_at": str,              # ISO 8601 时间戳
    "body": str,                    # 内容
    "path": str | None,             # 文件路径（仅行内评论）
    "line": int | None,             # 行号（仅行内评论）
    "url": str,                     # 评论 URL
}
```

#### 3.1.5 状态文件结构

```python
{
    "pr": {                         # 当前监控的 PR
        "repo": str,
        "number": int
    },
    "started_at": int | None,       # 监控开始时间戳
    "last_seen_head_sha": str,      # 上次看到的 HEAD SHA
    "retries_by_sha": {             # 各 SHA 的重试次数
        "<sha>": int
    },
    "seen_issue_comment_ids": [str],    # 已见 Issue 评论 ID
    "seen_review_comment_ids": [str],   # 已见 Review 评论 ID
    "seen_review_ids": [str],           # 已见 Review ID
    "last_snapshot_at": int,            # 上次快照时间戳
}
```

#### 3.1.6 快照输出结构 (`collect_snapshot` 返回)

```python
{
    "pr": {...},                    # PR 信息
    "checks": {...},                # Checks 汇总
    "failed_runs": [...],           # 失败运行列表
    "new_review_items": [...],      # 新 Review 项目
    "actions": [str],               # 建议行动列表
    "retry_state": {                # 重试状态
        "current_sha_retries_used": int,
        "max_flaky_retries": int
    }
}
```

### 3.2 关键流程实现

#### 3.2.1 状态文件原子写入

```python
def save_state(path, state):
    # 1. 确保目录存在
    path.parent.mkdir(parents=True, exist_ok=True)
    
    # 2. 序列化 JSON
    payload = json.dumps(state, indent=2, sort_keys=True) + "\n"
    
    # 3. 创建临时文件（同目录，保证原子重命名）
    fd, tmp_name = tempfile.mkstemp(
        prefix=f"{path.name}.", 
        suffix=".tmp", 
        dir=path.parent
    )
    
    # 4. 写入并刷新
    with os.fdopen(fd, "w", encoding="utf-8") as tmp_file:
        tmp_file.write(payload)
    
    # 5. 原子替换
    os.replace(tmp_path, path)
```

**设计考量**：
- 使用 `mkstemp` 在同目录创建临时文件，确保 `os.replace` 是原子操作
- 异常时清理临时文件，避免残留
- JSON 按 key 排序，保证输出确定性

#### 3.2.2 分页 API 获取

```python
def gh_api_list_paginated(endpoint, repo=None, per_page=100):
    items = []
    page = 1
    while True:
        # 构建带分页参数的 URL
        sep = "&" if "?" in endpoint else "?"
        page_endpoint = f"{endpoint}{sep}per_page={per_page}&page={page}"
        
        payload = gh_json(["api", page_endpoint], repo=repo)
        if payload is None:
            break
        if not isinstance(payload, list):
            raise GhCommandError(...)
        
        items.extend(payload)
        
        # 不足一页说明已到末尾
        if len(payload) < per_page:
            break
        page += 1
    return items
```

#### 3.2.3 变化检测机制

```python
def snapshot_change_key(snapshot):
    """生成用于检测状态变化的不可变 key"""
    pr = snapshot.get("pr") or {}
    checks = snapshot.get("checks") or {}
    review_items = snapshot.get("new_review_items") or []
    
    return (
        str(pr.get("head_sha") or ""),           # 代码变化
        str(pr.get("state") or ""),               # PR 状态变化
        str(pr.get("mergeable") or ""),           # 可合并性变化
        str(pr.get("merge_state_status") or ""),  # 合并状态变化
        str(pr.get("review_decision") or ""),     # Review 决策变化
        int(checks.get("passed_count") or 0),     # 通过数变化
        int(checks.get("failed_count") or 0),     # 失败数变化
        int(checks.get("pending_count") or 0),    # 挂起数变化
        tuple(                                     # Review 项目变化
            (str(item.get("kind") or ""), str(item.get("id") or ""))
            for item in review_items
        ),
        tuple(snapshot.get("actions") or []),     # 行动建议变化
    )
```

### 3.3 决策逻辑详解

#### 3.3.1 合并就绪判断 (`is_pr_ready_to_merge`)

```python
def is_pr_ready_to_merge(pr, checks_summary, new_review_items):
    # 1. PR 必须处于开放状态
    if pr["closed"] or pr["merged"]:
        return False
    
    # 2. 所有检查必须已结束
    if not checks_summary["all_terminal"]:
        return False
    
    # 3. 无失败或挂起的检查
    if checks_summary["failed_count"] > 0 or checks_summary["pending_count"] > 0:
        return False
    
    # 4. 无未处理的 Review 反馈
    if new_review_items:
        return False
    
    # 5. GitHub 报告可合并
    if str(pr.get("mergeable") or "") != "MERGEABLE":
        return False
    
    # 6. 无合并阻塞状态
    if str(pr.get("merge_state_status") or "") in MERGE_CONFLICT_OR_BLOCKING_STATES:
        return False
    
    # 7. 无阻塞性 Review 决策
    if str(pr.get("review_decision") or "") in MERGE_BLOCKING_REVIEW_DECISIONS:
        return False
    
    return True
```

#### 3.3.2 行动建议生成 (`recommend_actions`)

```
┌─────────────────────────────────────────────────────────────────┐
│                      recommend_actions                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  PR 已关闭/合并? ──Yes──▶ ["process_review_comment?", "stop_pr_closed"] │
│       │                                                         │
│       No                                                        │
│       ▼                                                         │
│  PR 就绪可合并? ──Yes──▶ ["stop_ready_to_merge"]               │
│       │                                                         │
│       No                                                        │
│       ▼                                                         │
│  有新 Review 项目? ──Yes──▶ 添加 "process_review_comment"      │
│       │                                                         │
│       ▼                                                         │
│  有失败检查? ──No──▶ ["idle"]                                  │
│       │                                                         │
│       Yes                                                       │
│       ▼                                                         │
│  所有检查已结束且重试次数 >= 最大限制? ──Yes──▶ ["stop_exhausted_retries"] │
│       │                                                         │
│       No                                                        │
│       ▼                                                         │
│  添加 ["diagnose_ci_failure"]                                  │
│  如果所有检查已结束且有失败运行且重试次数 < 限制:              │
│      添加 ["retry_failed_checks"]                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心代码路径

| 路径 | 行号范围 | 功能描述 |
|------|----------|----------|
| `gh_pr_watch.py` | 55-94 | 参数解析与验证 |
| `gh_pr_watch.py` | 108-133 | GitHub CLI 命令封装层 |
| `gh_pr_watch.py` | 157-193 | PR 信息解析与仓库提取 |
| `gh_pr_watch.py` | 265-303 | CI 检查获取与状态汇总 |
| `gh_pr_watch.py` | 305-340 | 工作流运行查询与失败筛选 |
| `gh_pr_watch.py` | 349-525 | Review 评论分页获取与过滤 |
| `gh_pr_watch.py` | 554-599 | 合并就绪判断与行动建议 |
| `gh_pr_watch.py` | 601-650 | 快照收集主流程 |
| `gh_pr_watch.py` | 652-705 | 失败重试执行逻辑 |
| `gh_pr_watch.py` | 747-782 | 持续监控循环实现 |

### 4.2 关键常量定义

```python
# 行 15-48: 状态常量定义
FAILED_RUN_CONCLUSIONS = {      # 视为失败的运行结论
    "failure", "timed_out", "cancelled", "action_required", 
    "startup_failure", "stale"
}

PENDING_CHECK_STATES = {        # 视为挂起的检查状态
    "QUEUED", "IN_PROGRESS", "PENDING", "WAITING", "REQUESTED"
}

REVIEW_BOT_LOGIN_KEYWORDS = {   # 可信任的 Bot 关键词
    "codex"
}

TRUSTED_AUTHOR_ASSOCIATIONS = { # 可信任的人类作者关联
    "OWNER", "MEMBER", "COLLABORATOR"
}

MERGE_BLOCKING_REVIEW_DECISIONS = {     # 阻塞合并的 Review 决策
    "REVIEW_REQUIRED", "CHANGES_REQUESTED"
}

MERGE_CONFLICT_OR_BLOCKING_STATES = {   # 阻塞合并的状态
    "BLOCKED", "DIRTY", "DRAFT", "UNKNOWN"
}

GREEN_STATE_MAX_POLL_SECONDS = 60 * 60  # 绿色状态最大轮询间隔: 1小时
```

### 4.3 状态文件默认路径生成

```python
def default_state_file_for(pr):
    repo_slug = pr["repo"].replace("/", "-")
    return Path(f"/tmp/codex-babysit-pr-{repo_slug}-pr{pr['number']}.json")
```

示例: `/tmp/codex-babysit-pr-openai-codex-pr123.json`

---

## 5. 依赖与外部交互

### 5.1 外部依赖

| 依赖 | 类型 | 用途 |
|------|------|------|
| `gh` (GitHub CLI) | 外部命令 | 所有 GitHub API 交互 |
| `python3` | 运行时 | 脚本执行环境 |
| 标准库 (`argparse`, `json`, `subprocess`, etc.) | 内置 | 核心功能实现 |

### 5.2 GitHub CLI 命令调用矩阵

| 功能 | 命令 | 关键参数 |
|------|------|----------|
| PR 查看 | `gh pr view` | `--json number,url,state,mergedAt,closedAt,headRefName,headRefOid,...` |
| PR Checks | `gh pr checks` | `--json name,state,bucket,link,workflow,event,startedAt,completedAt` |
| Actions API | `gh api repos/{owner}/{repo}/actions/runs` | `-f head_sha={sha} -f per_page=100` |
| 运行重试 | `gh run rerun` | `{run_id} --failed` |
| 用户认证 | `gh api user` | - |
| Issue 评论 | `gh api repos/{owner}/{repo}/issues/{pr_number}/comments` | `per_page=100&page={n}` |
| Review 评论 | `gh api repos/{owner}/{repo}/pulls/{pr_number}/comments` | `per_page=100&page={n}` |
| Review 提交 | `gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews` | `per_page=100&page={n}` |

### 5.3 输出协议

脚本输出采用 **JSON Lines (JSONL)** 格式，每行一个独立 JSON 对象：

**快照事件** (`--watch` 模式):
```json
{"event": "snapshot", "payload": {"snapshot": {...}, "state_file": "...", "next_poll_seconds": 30}}
```

**停止事件** (`--watch` 模式):
```json
{"event": "stop", "payload": {"actions": [...], "pr": {...}}}
```

**单次输出** (`--once` 模式):
```json
{"pr": {...}, "checks": {...}, "failed_runs": [...], "new_review_items": [...], "actions": [...], "retry_state": {...}, "state_file": "..."}
```

**重试结果** (`--retry-failed-now` 模式):
```json
{"snapshot": {...}, "state_file": "...", "rerun_attempted": true/false, "rerun_count": N, "rerun_run_ids": [...], "reason": "..."}
```

### 5.4 与 Skill 系统的集成

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Codex Agent   │────▶│   babysit-pr     │────▶│  gh_pr_watch.py │
│                 │     │   Skill (LLM)    │     │                 │
│                 │◀────│                  │◀────│                 │
└─────────────────┘     └──────────────────┘     └─────────────────┘
       │                         │                        │
       │                         ▼                        │
       │              ┌──────────────────┐               │
       │              │  SKILL.md        │               │
       │              │  (策略指导)       │               │
       │              └──────────────────┘               │
       │                                                 │
       ▼                                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                        GitHub Platform                          │
│  (PR API / Checks API / Actions API / Issues API / Reviews API) │
└─────────────────────────────────────────────────────────────────┘
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 认证与权限风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| `gh` 未认证 | 脚本依赖 `gh` CLI 的认证状态，未认证会导致所有 API 调用失败 | 调用前检查 `gh auth status`，失败时提供清晰错误信息 |
| 权限不足 | 某些仓库可能需要特定权限才能查看 Checks 或触发重试 | 错误信息中应包含权限不足的提示 |

#### 6.1.2 状态文件风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 并发写入 | 多个进程同时写入同一状态文件可能导致数据损坏 | 使用原子写入 (`os.replace`)，但无文件锁 |
| 磁盘空间 | `/tmp` 目录可能满或不可写 | 考虑使用 `$XDG_STATE_HOME` 或配置化路径 |
| 状态泄露 | 敏感信息（如 PR 内容）残留在临时文件 | 状态文件仅包含元数据，无敏感内容 |

#### 6.1.3 API 限制风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 速率限制 | 高频轮询可能触发 GitHub API 速率限制 | 自适应轮询退避，绿色状态降低频率 |
| 分页遗漏 | 超过 100 页的 Review 评论可能处理不全 | 使用分页获取，但极端情况可能遗漏 |

### 6.2 边界条件

#### 6.2.1 PR 状态边界

```
边界场景                          当前行为
─────────────────────────────────────────────────────────
PR 在监控期间被合并               下次轮询检测到，输出 stop_pr_closed
PR 在监控期间被关闭               同上
PR 从草稿转为就绪                 继续监控，merge_state_status 变化触发重置
PR HEAD SHA 变化（新提交）        检测到新 SHA，重试计数重置
PR 基础分支更新（无新提交）       mergeable 状态可能变化，触发重置
```

#### 6.2.2 CI 状态边界

```
边界场景                          当前行为
─────────────────────────────────────────────────────────
Checks 全部跳过                   all_terminal=True, passed=0, failed=0
部分 Checks 被跳过                仅统计实际运行的 Checks
Workflow 运行中但 Check 已报告    以 Check 状态为准（可能不一致）
同一 SHA 多次运行                 仅匹配 head_sha 的运行被考虑
```

#### 6.2.3 Review 边界

```
边界场景                          当前行为
─────────────────────────────────────────────────────────
评论被删除                        已见 ID 仍保留在状态文件中（无害）
评论被编辑                        不检测编辑，仅基于 ID 去重
Resolved 评论                     不特殊处理，仍可能展示（需 Agent 判断）
Bot 评论误判                      仅信任含 "codex" 的 Bot，其他被过滤
```

### 6.3 改进建议

#### 6.3.1 功能增强

| 优先级 | 建议 | 价值 |
|--------|------|------|
| 中 | 添加 `--state-dir` 参数支持自定义状态目录 | 支持多用户/多项目隔离 |
| 中 | 支持 Webhook 模式作为轮询替代 | 降低 API 调用频率，实时性更好 |
| 低 | 添加 `--dry-run` 模式，仅模拟不执行重试 | 便于测试和调试 |
| 低 | 支持配置文件（`.codex/babysit-pr.yaml`） | 项目级默认配置 |

#### 6.3.2 可靠性改进

| 优先级 | 建议 | 价值 |
|--------|------|------|
| 高 | 添加文件锁机制防止并发状态写入 | 避免多进程数据损坏 |
| 中 | 实现指数退避重试机制应对 API 失败 | 提高网络不稳定时的鲁棒性 |
| 中 | 添加状态文件版本字段，支持迁移 | 便于未来格式变更 |
| 低 | 添加日志文件输出（除 stderr 外） | 便于事后审计 |

#### 6.3.3 可观测性改进

| 优先级 | 建议 | 价值 |
|--------|------|------|
| 中 | 添加 Prometheus 指标导出 | 便于集中监控 |
| 低 | 添加结构化日志（JSON 格式） | 便于日志分析 |
| 低 | 添加监控会话统计（总轮询次数、总耗时等） | 便于性能分析 |

#### 6.3.4 代码质量改进

| 优先级 | 建议 | 价值 |
|--------|------|------|
| 中 | 将常量提取到配置模块 | 便于自定义和测试 |
| 中 | 添加类型注解（Python 3.9+） | 提高代码可维护性 |
| 低 | 单元测试覆盖核心逻辑 | 提高可靠性 |
| 低 | 使用 `pydantic` 进行数据验证 | 增强输入输出安全性 |

### 6.4 相关文件清单

```
.codex/skills/babysit-pr/
├── SKILL.md                          # Skill 主文档，包含使用指南和工作流
├── agents/
│   └── openai.yaml                   # Agent 接口配置（提示词、描述）
├── references/
│   ├── heuristics.md                 # CI/Review 决策启发式规则
│   └── github-api-notes.md           # GitHub API 使用说明
└── scripts/
    └── gh_pr_watch.py                # 本研究文档目标文件
```

---

## 附录：关键代码片段

### A.1 评论过滤核心逻辑

```python
def fetch_new_review_items(pr, state, fresh_state, authenticated_login=None):
    # ... 获取所有评论 ...
    
    new_items = []
    for item in all_items:
        item_id = item.get("id")
        if not item_id:
            continue
        author = item.get("author") or ""
        if not author:
            continue
        
        # Bot 过滤：仅保留含 "codex" 关键词的 Bot
        if is_bot_login(author):
            if not is_actionable_review_bot_login(author):
                continue
        # 人类过滤：仅保留信任关联的作者或当前用户
        elif not is_trusted_human_review_author(item, authenticated_login):
            continue
        
        # 去重检查
        kind = item["kind"]
        if kind == "issue_comment" and item_id in seen_issue:
            continue
        # ... 其他类型去重 ...
        
        new_items.append(item)
        # 更新已见集合
        ...
    
    return new_items
```

### A.2 自适应轮询逻辑

```python
def run_watch(args):
    poll_seconds = args.poll_seconds
    last_change_key = None
    
    while True:
        snapshot, state_path = collect_snapshot(args)
        print_event("snapshot", {...})
        
        actions = set(snapshot.get("actions") or [])
        if {"stop_pr_closed", "stop_exhausted_retries", "stop_ready_to_merge"} & actions:
            print_event("stop", {...})
            return 0
        
        current_change_key = snapshot_change_key(snapshot)
        changed = current_change_key != last_change_key
        green = is_ci_green(snapshot)
        
        # 自适应间隔调整
        if not green:
            poll_seconds = args.poll_seconds
        elif changed or last_change_key is None:
            poll_seconds = args.poll_seconds
        else:
            poll_seconds = min(poll_seconds * 2, GREEN_STATE_MAX_POLL_SECONDS)
        
        last_change_key = current_change_key
        time.sleep(poll_seconds)
```

### A.3 失败重试前置检查

```python
def retry_failed_now(args):
    snapshot, state_path = collect_snapshot(args)
    ...
    
    # 前置条件链式检查
    if pr["closed"] or pr["merged"]:
        result["reason"] = "pr_closed"
        return result
    if checks_summary["failed_count"] <= 0:
        result["reason"] = "no_failed_pr_checks"
        return result
    if not failed_runs:
        result["reason"] = "no_failed_runs"
        return result
    if not checks_summary["all_terminal"]:
        result["reason"] = "checks_still_pending"
        return result
    if retries_used >= max_retries:
        result["reason"] = "retry_budget_exhausted"
        return result
    
    # 执行重试
    for run in failed_runs:
        run_id = run.get("run_id")
        if run_id:
            gh_text(["run", "rerun", str(run_id), "--failed"], repo=pr["repo"])
            result["rerun_run_ids"].append(run_id)
    
    # 更新重试计数
    if result["rerun_run_ids"]:
        state, _ = load_state(state_path)
        new_count = current_retry_count(state, pr["head_sha"]) + 1
        set_retry_count(state, pr["head_sha"], new_count)
        save_state(state_path, state)
        ...
    
    return result
```

---

*文档生成时间: 2026-03-22*
*研究对象版本: gh_pr_watch.py (805 lines)*
