# openai.yaml 深度研究文档

## 文件位置
`.codex/skills/babysit-pr/agents/openai.yaml`

---

## 1. 场景与职责

### 1.1 功能定位

`openai.yaml` 是 **PR Babysitter Skill** 的 **Agent 配置接口定义文件**，用于向 Kimi Code CLI (OpenAI/Codex 协议兼容层) 声明该 Skill 的元数据、展示名称、功能描述和默认提示词。

该文件本身不包含可执行逻辑，而是作为 Skill 的"入口契约"，定义了：
- **人机交互界面**：用户在 CLI 中看到的 Skill 名称和描述
- **默认行为指令**：激活 Skill 时自动注入的系统提示词
- **功能范围边界**：明确该 Skill 负责监控 PR 的 CI、Review 和合并冲突状态

### 1.2 使用场景

| 场景 | 说明 |
|------|------|
| **PR 创建后持续监控** | 开发者提交 PR 后，需要自动化工具持续跟踪 CI 状态、Review 反馈，直到 PR 可合并 |
| **CI 失败自动诊断与修复** | 检测到 CI 失败后，自动分类失败原因（分支相关 vs 偶发故障），尝试修复或重试 |
| **Review 评论自动处理** | 监控新的 Review 评论，自动判断是否需要代码修改并提交修复 |
| **合并冲突预警** | 监控 PR 的合并能力状态，及时发现冲突 |

### 1.3 角色职责

该 Agent 配置定义的 Skill 承担以下职责：

1. **监控者 (Watcher)**：通过 `--watch` 模式持续轮询 PR 状态
2. **诊断者 (Diagnoser)**：分析 CI 失败日志，区分分支相关故障 vs 偶发故障
3. **修复者 (Fixer)**：对分支相关问题自动提交代码修复
4. **重试调度者 (Retry Scheduler)**：对偶发故障触发 GitHub Actions 重试（最多 3 次）
5. **评论处理者 (Review Handler)**：处理 Review 反馈，必要时提交修改

---

## 2. 功能点目的

### 2.1 配置字段解析

```yaml
interface:
  display_name: "PR Babysitter"                    # 用户界面显示名称
  short_description: "Watch PR CI, reviews, and merge conflicts"  # 简短描述
  default_prompt: "..."                            # 默认系统提示词
```

#### 2.1.1 `display_name`: "PR Babysitter"
- **目的**：在 Kimi CLI 的 Skill 列表中提供友好的可读名称
- **设计意图**：使用通俗易懂的"Babysitter"（保姆）隐喻，暗示该 Skill 会"照看"PR 直到成熟（可合并）

#### 2.1.2 `short_description`
- **目的**：快速告知用户该 Skill 的核心能力范围
- **覆盖范围**：CI 检查、Review 评论、合并冲突三大维度

#### 2.1.3 `default_prompt` 核心指令解析

默认提示词包含以下关键行为约束：

| 指令片段 | 功能目的 |
|---------|---------|
| `monitor CI, reviewer comments, and merge-conflict status` | 明确监控范围 |
| `prefer the watcher's --watch mode for live monitoring` | 优先使用持续监控模式而非单次检查 |
| `fix valid issues, push updates` | 授权自动修复和推送 |
| `rerun flaky failures up to 3 times` | 定义偶发故障重试上限 |
| `Keep exactly one watcher session active` | 防止重复监控进程 |
| `restart --watch yourself immediately after the push` | 确保修复后监控不中断 |
| `task is still in progress: keep consuming watcher output` | 明确定义"任务完成"的边界条件 |

### 2.2 功能边界定义

该配置通过 `default_prompt` 隐式定义了以下边界：

```
┌─────────────────────────────────────────────────────────────┐
│                    PR Babysitter 功能边界                    │
├─────────────────────────────────────────────────────────────┤
│  ✅ 负责：                                                   │
│     - CI 状态监控 (pending/running/failed/success)          │
│     - Review 评论监控 (issue comments, inline comments)     │
│     - 合并能力监控 (mergeable, conflict detection)          │
│     - 分支相关 CI 失败的自动修复                             │
│     - 偶发 CI 失败的自动重试 (最多3次)                       │
│     - Review 反馈的自动处理                                  │
├─────────────────────────────────────────────────────────────┤
│  ❌ 不负责：                                                 │
│     - 自动合并 PR (仅监控到"可合并"状态即停止)               │
│     - 处理非信任作者的评论 (仅处理 OWNER/MEMBER/COLLABORATOR)│
│     - 无限重试 (3次上限后停止并请求用户帮助)                 │
│     - 处理已关闭/已合并的 PR (立即停止)                      │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. 具体技术实现

### 3.1 架构关系

```
┌─────────────────────────────────────────────────────────────────┐
│                     Kimi Code CLI                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Skill Registry (读取 .codex/skills/*/agents/openai.yaml)│   │
│  └────────────────────┬────────────────────────────────────┘   │
└───────────────────────┼─────────────────────────────────────────┘
                        │ interface 配置
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│                    PR Babysitter Skill                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────────┐ │
│  │ openai.yaml │  │  SKILL.md   │  │  gh_pr_watch.py         │ │
│  │ (本文件)    │  │ (行为文档)   │  │  (核心执行脚本)          │ │
│  └─────────────┘  └─────────────┘  └─────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                        │
                        ▼ 调用 GitHub CLI (gh)
┌─────────────────────────────────────────────────────────────────┐
│                      GitHub Platform                            │
│         PR API / Checks API / Actions API / Review API          │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 核心执行流程

#### 3.2.1 状态收集流程 (`collect_snapshot`)

```python
# 伪代码流程，源自 gh_pr_watch.py

def collect_snapshot(args):
    # 1. 解析 PR 标识符 (auto/number/URL)
    pr = resolve_pr(args.pr, repo_override=args.repo)
    
    # 2. 加载或初始化状态文件
    state, fresh_state = load_state(state_path)
    
    # 3. 获取 PR 检查 (CI) 状态
    checks = get_pr_checks(str(pr["number"]), repo=pr["repo"])
    checks_summary = summarize_checks(checks)
    
    # 4. 获取工作流运行记录
    workflow_runs = get_workflow_runs_for_sha(pr["repo"], pr["head_sha"])
    failed_runs = failed_runs_from_workflow_runs(workflow_runs, pr["head_sha"])
    
    # 5. 获取认证用户身份 (用于评论作者过滤)
    authenticated_login = get_authenticated_login()
    
    # 6. 获取新的 Review 项目
    new_review_items = fetch_new_review_items(pr, state, fresh_state, authenticated_login)
    
    # 7. 计算重试次数
    retries_used = current_retry_count(state, pr["head_sha"])
    
    # 8. 推荐下一步动作
    actions = recommend_actions(pr, checks_summary, failed_runs, new_review_items, retries_used, max_retries)
    
    # 9. 保存状态
    save_state(state_path, state)
    
    return snapshot, state_path
```

#### 3.2.2 动作推荐决策树 (`recommend_actions`)

```
输入: PR状态, CI汇总, 失败运行, 新评论, 已用重试次数, 最大重试次数
│
├─ PR 已关闭/已合并?
│  ├─ 是 → actions = ["process_review_comment"(如有), "stop_pr_closed"]
│  └─ 否 → 继续
│
├─ PR 可合并? (CI全绿 + 无新评论 + mergeable状态 + 非阻塞Review)
│  ├─ 是 → actions = ["stop_ready_to_merge"]
│  └─ 否 → 继续
│
├─ 有新评论?
│  └─ 是 → actions += ["process_review_comment"]
│
├─ CI 有失败?
│  ├─ 是 → 检查重试预算
│  │        ├─ 已用尽 → actions += ["stop_exhausted_retries"]
│  │        └─ 未用尽 → actions += ["diagnose_ci_failure", "retry_failed_checks"]
│  └─ 否 → actions += ["idle"]
│
返回: 去重后的 actions 列表
```

#### 3.2.3 持续监控循环 (`run_watch`)

```python
def run_watch(args):
    poll_seconds = args.poll_seconds  # 默认 30 秒
    last_change_key = None
    
    while True:
        snapshot, state_path = collect_snapshot(args)
        
        # 输出当前状态 (JSONL 格式)
        print_event("snapshot", {...})
        
        actions = set(snapshot.get("actions") or [])
        
        # 检查停止条件
        if {"stop_pr_closed", "stop_exhausted_retries", "stop_ready_to_merge"} & actions:
            print_event("stop", {...})
            return 0
        
        # 自适应轮询间隔调整
        current_change_key = snapshot_change_key(snapshot)
        changed = current_change_key != last_change_key
        green = is_ci_green(snapshot)
        
        if not green:
            poll_seconds = args.poll_seconds  # CI 未绿: 保持短间隔
        elif changed or last_change_key is None:
            poll_seconds = args.poll_seconds  # 状态变化: 重置短间隔
        else:
            poll_seconds = min(poll_seconds * 2, GREEN_STATE_MAX_POLL_SECONDS)  # 指数退避, 最大1小时
        
        last_change_key = current_change_key
        time.sleep(poll_seconds)
```

### 3.3 关键数据结构

#### 3.3.1 PR 信息结构 (`pr_view_fields`)

```python
pr_view_fields = (
    "number,url,state,mergedAt,closedAt,headRefName,headRefOid,"
    "headRepository,headRepositoryOwner,mergeable,mergeStateStatus,reviewDecision"
)

# 解析后结构:
pr = {
    "number": int,           # PR 编号
    "url": str,              # PR URL
    "repo": str,             # OWNER/REPO 格式
    "head_sha": str,         # 当前 HEAD commit SHA
    "head_branch": str,      # 分支名
    "state": str,            # open/closed
    "merged": bool,          # 是否已合并
    "closed": bool,          # 是否已关闭
    "mergeable": str,        # MERGEABLE/CONFLICTING/UNKNOWN
    "merge_state_status": str,  # BLOCKED/DIRTY/DRAFT/etc
    "review_decision": str,  # REVIEW_REQUIRED/APPROVED/CHANGES_REQUESTED
}
```

#### 3.3.2 Checks 汇总结构 (`checks_fields`)

```python
checks_fields = "name,state,bucket,link,workflow,event,startedAt,completedAt"

# 汇总后结构:
checks_summary = {
    "pending_count": int,    # 待处理检查数
    "failed_count": int,     # 失败检查数
    "passed_count": int,     # 通过检查数
    "all_terminal": bool,    # 所有检查是否都已结束
}
```

#### 3.3.3 失败运行结构

```python
failed_run = {
    "run_id": int,           # GitHub Actions 运行 ID
    "workflow_name": str,    # 工作流名称
    "status": str,           # 状态
    "conclusion": str,       # failure/timed_out/cancelled/etc
    "html_url": str,         # 运行详情页 URL
}
```

#### 3.3.4 Review 项目结构

```python
review_item = {
    "kind": str,             # issue_comment / review_comment / review
    "id": str,               # 评论/审查 ID
    "author": str,           # 作者登录名
    "author_association": str,  # OWNER/MEMBER/COLLABORATOR/CONTRIBUTOR
    "created_at": str,       # 创建时间 ISO 格式
    "body": str,             # 评论内容
    "path": str|None,        # 文件路径 (inline comment)
    "line": int|None,        # 行号 (inline comment)
    "url": str,              # 评论 URL
}
```

#### 3.3.5 状态文件结构

```python
state = {
    "pr": {},                      # PR 基本信息
    "started_at": int|None,        # 监控开始时间戳
    "last_seen_head_sha": str|None,  # 上次看到的 HEAD SHA
    "retries_by_sha": {            # 各 SHA 的重试次数记录
        "<sha>": int,
    },
    "seen_issue_comment_ids": [],    # 已处理的 issue 评论 ID
    "seen_review_comment_ids": [],   # 已处理的 review 评论 ID
    "seen_review_ids": [],           # 已处理的 review ID
    "last_snapshot_at": int|None,    # 上次快照时间戳
}
```

#### 3.3.6 输出快照结构

```python
snapshot = {
    "pr": pr,                              # PR 信息
    "checks": checks_summary,              # CI 检查汇总
    "failed_runs": [failed_run, ...],      # 失败运行列表
    "new_review_items": [review_item, ...], # 新评论列表
    "actions": [str, ...],                 # 推荐动作列表
    "retry_state": {
        "current_sha_retries_used": int,   # 当前 SHA 已用重试次数
        "max_flaky_retries": int,          # 最大重试次数配置
    },
}
```

### 3.4 协议与命令

#### 3.4.1 GitHub CLI 命令映射

| 功能 | CLI 命令 | API 端点 |
|------|---------|---------|
| PR 元数据 | `gh pr view --json <fields>` | GraphQL (gh 内部) |
| PR 检查 | `gh pr checks --json <fields>` | GraphQL (gh 内部) |
| 工作流运行 | `gh api repos/{owner}/{repo}/actions/runs` | REST API |
| 失败日志 | `gh run view <run-id> --log-failed` | REST API |
| 重试失败作业 | `gh run rerun <run-id> --failed` | REST API |
| Issue 评论 | `gh api repos/{owner}/{repo}/issues/<n>/comments` | REST API |
| Review 评论 | `gh api repos/{owner}/{repo}/pulls/<n>/comments` | REST API |
| Review 提交 | `gh api repos/{owner}/{repo}/pulls/<n>/reviews` | REST API |
| 当前用户 | `gh api user` | REST API |

#### 3.4.2 命令行接口

```bash
# 单次快照 (默认)
python3 .codex/skills/babysit-pr/scripts/gh_pr_watch.py --pr auto --once

# 持续监控 (JSONL 流式输出)
python3 .codex/skills/babysit-pr/scripts/gh_pr_watch.py --pr auto --watch

# 立即重试失败作业
python3 .codex/skills/babysit-pr/scripts/gh_pr_watch.py --pr auto --retry-failed-now

# 显式指定 PR
python3 .codex/skills/babysit-pr/scripts/gh_pr_watch.py --pr <number-or-url> --once
```

#### 3.4.3 JSONL 输出协议

**Snapshot 事件** (`--watch` 模式):
```json
{
  "event": "snapshot",
  "payload": {
    "snapshot": {...},
    "state_file": "/tmp/codex-babysit-pr-...",
    "next_poll_seconds": 30
  }
}
```

**Stop 事件** (监控结束):
```json
{
  "event": "stop",
  "payload": {
    "actions": ["stop_ready_to_merge"],
    "pr": {...}
  }
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 文件依赖图

```
openai.yaml
    │
    ├── 引用/依赖 ───────────────────────┐
    │                                    │
    ├──► SKILL.md (行为文档)              │
    │      │                             │
    │      ├──► references/heuristics.md │
    │      │      - CI 分类启发式规则     │
    │      │      - 决策树                │
    │      │      - 评论处理标准          │
    │      │                             │
    │      └──► references/github-api-notes.md
    │             - GitHub CLI 命令参考   │
    │             - JSON 字段说明         │
    │                                    │
    └──► scripts/gh_pr_watch.py (核心执行脚本)
           - 所有实际逻辑实现
           - GitHub CLI 调用封装
           - 状态管理
           - 动作推荐算法
```

### 4.2 核心代码路径

| 路径 | 职责 | 关键函数/类 |
|------|------|------------|
| `.codex/skills/babysit-pr/agents/openai.yaml` | Agent 接口定义 | `interface.*` 配置项 |
| `.codex/skills/babysit-pr/SKILL.md` | 行为规范和用户文档 | 工作流程、命令参考 |
| `.codex/skills/babysit-pr/scripts/gh_pr_watch.py` | 核心执行逻辑 | `main()`, `run_watch()`, `collect_snapshot()` |
| `.codex/skills/babysit-pr/references/heuristics.md` | CI 分类启发式 | 决策规则文档 |
| `.codex/skills/babysit-pr/references/github-api-notes.md` | API 参考 | GitHub CLI 命令说明 |

### 4.3 gh_pr_watch.py 关键代码段

#### 4.3.1 常量定义 (行 15-48)

```python
FAILED_RUN_CONCLUSIONS = {
    "failure", "timed_out", "cancelled", "action_required",
    "startup_failure", "stale",
}
PENDING_CHECK_STATES = {
    "QUEUED", "IN_PROGRESS", "PENDING", "WAITING", "REQUESTED",
}
REVIEW_BOT_LOGIN_KEYWORDS = {"codex"}
TRUSTED_AUTHOR_ASSOCIATIONS = {"OWNER", "MEMBER", "COLLABORATOR"}
MERGE_BLOCKING_REVIEW_DECISIONS = {"REVIEW_REQUIRED", "CHANGES_REQUESTED"}
MERGE_CONFLICT_OR_BLOCKING_STATES = {"BLOCKED", "DIRTY", "DRAFT", "UNKNOWN"}
GREEN_STATE_MAX_POLL_SECONDS = 60 * 60  # 1小时
```

#### 4.3.2 PR 可合并性检查 (行 554-569)

```python
def is_pr_ready_to_merge(pr, checks_summary, new_review_items):
    if pr["closed"] or pr["merged"]:
        return False
    if not checks_summary["all_terminal"]:
        return False
    if checks_summary["failed_count"] > 0 or checks_summary["pending_count"] > 0:
        return False
    if new_review_items:
        return False
    if str(pr.get("mergeable") or "") != "MERGEABLE":
        return False
    if str(pr.get("merge_state_status") or "") in MERGE_CONFLICT_OR_BLOCKING_STATES:
        return False
    if str(pr.get("review_decision") or "") in MERGE_BLOCKING_REVIEW_DECISIONS:
        return False
    return True
```

#### 4.3.3 评论作者信任检查 (行 447-465)

```python
def is_bot_login(login):
    return bool(login) and login.endswith("[bot]")

def is_actionable_review_bot_login(login):
    if not is_bot_login(login):
        return False
    lower_login = login.lower()
    return any(keyword in lower_login for keyword in REVIEW_BOT_LOGIN_KEYWORDS)

def is_trusted_human_review_author(item, authenticated_login):
    author = str(item.get("author") or "")
    if not author:
        return False
    if authenticated_login and author == authenticated_login:
        return True
    association = str(item.get("author_association") or "").upper()
    return association in TRUSTED_AUTHOR_ASSOCIATIONS
```

#### 4.3.4 状态持久化 (行 222-262)

```python
def load_state(path):
    if path.exists():
        data = json.loads(path.read_text())
        return data, False  # (state, is_fresh)
    return {
        "pr": {},
        "started_at": None,
        "last_seen_head_sha": None,
        "retries_by_sha": {},
        "seen_issue_comment_ids": [],
        "seen_review_comment_ids": [],
        "seen_review_ids": [],
        "last_snapshot_at": None,
    }, True

def save_state(path, state):
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(state, indent=2, sort_keys=True) + "\n"
    # 原子写入: 先写临时文件再替换
    fd, tmp_name = tempfile.mkstemp(...)
    ...
    os.replace(tmp_path, path)
```

---

## 5. 依赖与外部交互

### 5.1 外部依赖

| 依赖 | 类型 | 用途 |
|------|------|------|
| `gh` (GitHub CLI) | 必需 | 所有 GitHub API 调用 |
| `python3` | 必需 | 脚本执行环境 |
| `/tmp` 目录 | 必需 | 状态文件存储 |
| GitHub API | 网络 | PR/Checks/Actions/Review 数据获取 |

### 5.2 认证要求

- `gh` CLI 必须已登录 (`gh auth status`)
- 需要以下权限范围：
  - `repo` - 读取仓库数据
  - `workflow` - 读取和重新运行 Actions
  - `read:user` - 获取当前用户信息

### 5.3 状态文件位置

```
/tmp/codex-babysit-pr-{OWNER}-{REPO}-pr{NUMBER}.json
```

示例:
```
/tmp/codex-babysit-pr-openai-codex-cli-pr123.json
```

### 5.4 交互时序图

```
┌──────────┐     ┌──────────────┐     ┌─────────────┐     ┌──────────────┐
│  Kimi CLI │     │ gh_pr_watch  │     │  gh CLI     │     │ GitHub API   │
└────┬─────┘     └──────┬───────┘     └──────┬──────┘     └──────┬───────┘
     │                  │                    │                   │
     │ 激活 Skill        │                    │                   │
     │─────────────────>│                    │                   │
     │                  │                    │                   │
     │                  │ 解析 PR 标识符      │                   │
     │                  │───────────────────>│                   │
     │                  │                    │ 调用 pr view      │
     │                  │                    │──────────────────>│
     │                  │                    │<──────────────────│
     │                  │<───────────────────│                   │
     │                  │                    │                   │
     │                  │ 获取 CI 状态        │                   │
     │                  │───────────────────>│                   │
     │                  │                    │ 调用 pr checks    │
     │                  │                    │──────────────────>│
     │                  │                    │<──────────────────│
     │                  │<───────────────────│                   │
     │                  │                    │                   │
     │                  │ 获取工作流运行      │                   │
     │                  │───────────────────>│                   │
     │                  │                    │ 调用 api actions  │
     │                  │                    │──────────────────>│
     │                  │                    │<──────────────────│
     │                  │<───────────────────│                   │
     │                  │                    │                   │
     │                  │ 获取评论数据        │                   │
     │                  │───────────────────>│                   │
     │                  │                    │ 调用 api comments │
     │                  │                    │──────────────────>│
     │                  │                    │<──────────────────│
     │                  │<───────────────────│                   │
     │                  │                    │                   │
     │                  │ 计算动作推荐        │                   │
     │                  │─────┐              │                   │
     │                  │     │              │                   │
     │                  │<────┘              │                   │
     │                  │                    │                   │
     │ 返回 JSON 快照    │                    │                   │
     │<─────────────────│                    │                   │
     │                  │                    │                   │
     │ [如需重试]        │                    │                   │
     │─────────────────>│                    │                   │
     │                  │ 触发 rerun         │                   │
     │                  │───────────────────>│                   │
     │                  │                    │ 调用 run rerun    │
     │                  │                    │──────────────────>│
     │                  │                    │<──────────────────│
     │                  │<───────────────────│                   │
     │                  │                    │                   │
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 安全风险

| 风险 | 描述 | 缓解措施 |
|------|------|---------|
| **状态文件污染** | `/tmp` 中的状态文件可能被篡改 | 使用原子写入 (tempfile + os.replace) |
| **Token 泄露** | `gh` CLI 依赖环境 token | 不存储 token，完全依赖 gh 的认证 |
| **恶意评论执行** | 评论中包含代码指令 | 仅处理信任作者的评论，Bot 仅处理含 "codex" 关键字的 |

#### 6.1.2 功能风险

| 风险 | 描述 | 影响 |
|------|------|------|
| **无限循环** | `--watch` 模式下未正确停止 | 已实现严格停止条件检查 |
| **重复重试** | 同一 SHA 可能触发超过 3 次重试 | `retries_by_sha` 跟踪每个 SHA 的重试次数 |
| **评论丢失** | 新状态文件可能丢失历史评论 | 首次运行时标记为 fresh_state，会展示所有现有评论 |
| **并发冲突** | 多个 watcher 进程同时运行 | 提示用户保持单一 watcher 会话 |

#### 6.1.3 外部依赖风险

| 风险 | 描述 | 缓解措施 |
|------|------|---------|
| **GitHub API 限流** | 高频轮询可能触发 rate limit | 自适应轮询间隔，CI 绿后指数退避 |
| **gh CLI 版本差异** | 不同版本 CLI 参数行为可能不同 | 使用标准参数，避免实验性功能 |
| **网络中断** | 监控过程中网络故障 | 异常抛出后由上层处理 |

### 6.2 边界条件

#### 6.2.1 输入边界

```python
# PR 标识符解析边界
parse_pr_spec("auto")      # → {"mode": "auto", "value": None}
parse_pr_spec("123")       # → {"mode": "number", "value": "123"}
parse_pr_spec("https://github.com/owner/repo/pull/123")  # → {"mode": "url", ...}
# 其他值 → ValueError
```

#### 6.2.2 状态边界

- **空状态文件**: 首次运行时创建，所有 `seen_*_ids` 为空
- **SHA 变化**: 新提交后 `retries_by_sha` 对新 SHA 计数从 0 开始
- **PR 切换**: 状态文件与当前 PR 不匹配时会重新初始化

#### 6.2.3 时间边界

- **轮询间隔**: 最小 1 秒 (通过参数验证)，CI 绿后最大 1 小时
- **状态文件 TTL**: 无显式过期，依赖 `/tmp` 目录清理策略

### 6.3 改进建议

#### 6.3.1 功能性改进

| 优先级 | 建议 | 理由 |
|--------|------|------|
| **高** | 添加 `--state-file` 自定义路径支持 | 已支持，但文档可更明确 |
| **中** | 支持 Webhook 模式替代轮询 | 减少 API 调用，实时性更好 |
| **中** | 添加 Slack/邮件通知集成 | PR 就绪时主动通知用户 |
| **低** | 支持多 PR 同时监控 | 当前设计为单 PR 会话 |

#### 6.3.2 可靠性改进

| 优先级 | 建议 | 理由 |
|--------|------|------|
| **高** | 添加指数退避重试机制应对 API 失败 | 当前直接抛出异常 |
| **中** | 状态文件加密或签名 | 防止恶意篡改 |
| **中** | 添加监控指标导出 (Prometheus 格式) | 便于运维观测 |
| **低** | 支持配置文件 (.babysit-pr.yaml) | 减少命令行参数 |

#### 6.3.3 可观测性改进

| 优先级 | 建议 | 理由 |
|--------|------|------|
| **中** | 添加结构化日志 (JSON Lines) | 便于日志分析 |
| **中** | 添加 `--dry-run` 模式 | 测试配置不实际执行操作 |
| **低** | 添加详细诊断模式 (-v/-vv) | 调试时输出更多上下文 |

#### 6.3.4 代码质量改进

| 优先级 | 建议 | 当前状态 |
|--------|------|---------|
| **低** | 添加类型注解 (Python typing) | 当前无类型提示 |
| **低** | 拆分 monolithic 脚本为模块 | 当前单文件 805 行 |
| **低** | 添加单元测试和集成测试 | 当前无测试文件 |

### 6.4 配置优化建议

当前 `openai.yaml` 较为简洁，可考虑扩展：

```yaml
# 建议的扩展配置
interface:
  display_name: "PR Babysitter"
  short_description: "Watch PR CI, reviews, and merge conflicts"
  default_prompt: "..."
  # 新增:
  parameters:
    - name: pr
      type: string
      default: "auto"
      description: "PR number, URL, or 'auto' for current branch"
    - name: max_flaky_retries
      type: integer
      default: 3
      description: "Maximum retry attempts for flaky failures"
    - name: poll_interval
      type: integer
      default: 30
      description: "Polling interval in seconds"
```

---

## 7. 总结

`openai.yaml` 作为 PR Babysitter Skill 的 Agent 接口定义文件，虽然代码量极小（仅 4 行），但承载了整个 Skill 的元数据契约。它与 `SKILL.md` 的行为规范文档和 `gh_pr_watch.py` 的执行逻辑共同构成了一个完整的自动化 PR 监控解决方案。

该 Skill 的核心价值在于：
1. **自动化**: 减少开发者手动检查 PR 状态的负担
2. **智能化**: 区分分支相关故障和偶发故障，采取不同策略
3. **持续性**: 通过 `--watch` 模式提供长时间运行的监控能力
4. **安全性**: 通过信任作者机制和重试上限防止滥用

理解该文件需要结合整个 Skill 的上下文，特别是 `gh_pr_watch.py` 中实现的状态机、决策树和 GitHub API 交互逻辑。
