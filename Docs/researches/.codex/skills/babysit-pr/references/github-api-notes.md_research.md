# 研究文档: github-api-notes.md

## 场景与职责

本文档是 `babysit-pr` Skill 的技术参考文档，专门记录 PR 监控过程中使用的 GitHub CLI (`gh`) 命令和 API 端点。它为自动化 PR 看护工作流提供底层数据获取能力支撑，是连接高层业务逻辑（CI 诊断、评论处理）与 GitHub 平台的具体技术桥梁。

职责定位：
- 作为 Skill 实现者和使用者的命令速查手册
- 定义与 GitHub 平台交互的数据契约（字段、格式、返回值）
- 规范 watcher 脚本 (`gh_pr_watch.py`) 调用的外部接口

## 功能点目的

### 1. PR 元数据获取
**目的**: 解析 PR 的基本信息，建立监控上下文

**命令**: `gh pr view --json number,url,state,mergedAt,closedAt,headRefName,headRefOid,headRepository,headRepositoryOwner`

**关键字段用途**:
| 字段 | 用途 |
|------|------|
| `number` | PR 标识符，用于后续 API 调用 |
| `url` | 提取仓库信息 (`owner/repo`) |
| `state`/`mergedAt`/`closedAt` | 判断 PR 是否已终止（合并/关闭） |
| `headRefName` | 本地分支名，用于 `git push` |
| `headRefOid` | 当前 HEAD SHA，CI 关联和重试计数的关键 |
| `headRepository`/`headRepositoryOwner` | 确定目标仓库 |

**代码路径**: `gh_pr_watch.py:146-193` (`pr_view_fields()`, `resolve_pr()`)

### 2. PR 检查摘要
**目的**: 获取 CI 检查状态，计算通过/失败/待处理数量

**命令**: `gh pr checks --json name,state,bucket,link,workflow,event,startedAt,completedAt`

**关键字段用途**:
| 字段 | 用途 |
|------|------|
| `bucket` | 核心状态分类 (`pass`/`fail`/`pending`/`skipping`) |
| `state` | 详细状态，用于判断是否为 pending |
| `name`/`workflow` | 识别具体检查项 |
| `link` | 失败时提供给用户的链接 |

**代码路径**: `gh_pr_watch.py:153-155`, `265-276` (`checks_fields()`, `get_pr_checks()`)

**状态处理逻辑**:
```python
# PENDING_CHECK_STATES 定义 (gh_pr_watch.py:23-29)
{"QUEUED", "IN_PROGRESS", "PENDING", "WAITING", "REQUESTED"}

# 判断 pending (gh_pr_watch.py:279-282)
def is_pending_check(check):
    bucket = str(check.get("bucket") or "").lower()
    state = str(check.get("state") or "").upper()
    return bucket == "pending" or state in PENDING_CHECK_STATES
```

### 3. Workflow Runs 查询
**目的**: 发现失败的 workflow runs，获取可重试的 run ID

**命令**: `gh api repos/{owner}/{repo}/actions/runs -X GET -f head_sha=<sha> -f per_page=100`

**关键字段用途**:
| 字段 | 用途 |
|------|------|
| `id` | run ID，用于重试命令 |
| `name`/`display_title` | 显示用名称 |
| `status` | 运行状态 |
| `conclusion` | 最终结论，判断是否失败 |
| `html_url` | 链接展示 |
| `head_sha` | 过滤当前 SHA 的 runs |

**失败结论集合** (gh_pr_watch.py:15-22):
```python
FAILED_RUN_CONCLUSIONS = {
    "failure", "timed_out", "cancelled", "action_required",
    "startup_failure", "stale",
}
```

**代码路径**: `gh_pr_watch.py:305-339` (`get_workflow_runs_for_sha()`, `failed_runs_from_workflow_runs()`)

### 4. 失败日志检查
**目的**: 人工/自动诊断失败原因，区分 branch-related vs flaky

**命令**:
- `gh run view <run-id> --json jobs,name,workflowName,conclusion,status,url,headSha`
- `gh run view <run-id> --log-failed`

**使用场景**: 当 `actions` 包含 `diagnose_ci_failure` 时，由上层逻辑调用这些命令获取日志进行分类（参考 `heuristics.md` 的分类标准）

### 5. 失败任务重试
**目的**: 对 flaky 失败进行自动重试

**命令**: `gh run rerun <run-id> --failed`

**行为**: 仅重试失败的 jobs（及其依赖），而非整个 workflow

**代码路径**: `gh_pr_watch.py:685-689` (`retry_failed_now()` 函数内)

**重试限制**: 通过 `--max-flaky-retries` 参数控制（默认 3 次），按 SHA 记录重试次数

### 6. Review 相关端点
**目的**: 获取 PR 评论和审查信息，处理 reviewer 反馈

**端点**:
| 类型 | 端点 | 用途 |
|------|------|------|
| Issue 评论 | `repos/{owner}/{repo}/issues/<pr_number>/comments` | PR 页面的一般评论 |
| 行内评论 | `repos/{owner}/{repo}/pulls/<pr_number>/comments` | 代码审查行内评论 |
| Review 提交 | `repos/{owner}/{repo}/pulls/<pr_number>/reviews` | 完整的 review 记录 |

**代码路径**: `gh_pr_watch.py:349-354` (`comment_endpoints()`), `468-524` (`fetch_new_review_items()`)

**去重机制**: 使用 `seen_issue_comment_ids`, `seen_review_comment_ids`, `seen_review_ids` 在 state 文件中追踪已处理的评论

## 具体技术实现

### 命令执行封装
```python
# gh_pr_watch.py:108-132
def gh_text(args, repo=None):
    cmd = ["gh"]
    if repo and (not args or args[0] != "api"):
        cmd.extend(["-R", repo])  # 非 api 命令使用 -R 指定仓库
    cmd.extend(args)
    # 执行并返回 stdout

def gh_json(args, repo=None):
    raw = gh_text(args, repo=repo).strip()
    return json.loads(raw) if raw else None
```

**注意**: `gh api` 命令不使用 `-R` 参数，而是通过完整端点路径指定仓库，这是为了兼容不同版本的 `gh` CLI。

### 分页处理
```python
# gh_pr_watch.py:357-372
def gh_api_list_paginated(endpoint, repo=None, per_page=100):
    items = []
    page = 1
    while True:
        sep = "&" if "?" in endpoint else "?"
        page_endpoint = f"{endpoint}{sep}per_page={per_page}&page={page}"
        payload = gh_json(["api", page_endpoint], repo=repo)
        # ...
        if len(payload) < per_page:
            break
        page += 1
    return items
```

## 关键代码路径与文件引用

| 功能 | 文件 | 行号 | 函数/代码块 |
|------|------|------|-------------|
| PR 解析 | `gh_pr_watch.py` | 146-193 | `pr_view_fields()`, `resolve_pr()` |
| 检查获取 | `gh_pr_watch.py` | 265-302 | `get_pr_checks()`, `summarize_checks()` |
| Workflow Runs | `gh_pr_watch.py` | 305-339 | `get_workflow_runs_for_sha()`, `failed_runs_from_workflow_runs()` |
| 评论获取 | `gh_pr_watch.py` | 349-524 | `comment_endpoints()`, `fetch_new_review_items()` |
| 重试执行 | `gh_pr_watch.py` | 652-704 | `retry_failed_now()` |
| 状态管理 | `gh_pr_watch.py` | 222-262 | `load_state()`, `save_state()` |
| 主监控循环 | `gh_pr_watch.py` | 747-781 | `run_watch()` |

## 依赖与外部交互

### 外部依赖
1. **GitHub CLI (`gh`)**: 必须安装并配置认证
2. **网络访问**: 需要访问 GitHub API (api.github.com)
3. **认证**: 依赖 `gh` 的认证状态（`gh auth status`）

### 数据流
```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   gh_pr_watch   │────▶│   GitHub CLI     │────▶│  GitHub API     │
│   (Python)      │◀────│   (gh)           │◀────│  (github.com)   │
└─────────────────┘     └──────────────────┘     └─────────────────┘
         │
         ▼
┌─────────────────┐
│  State File     │  (/tmp/codex-babysit-pr-{repo}-pr{number}.json)
│  (JSON)         │
└─────────────────┘
```

### State 文件结构
```json
{
  "pr": {"repo": "owner/repo", "number": 123},
  "started_at": 1234567890,
  "last_seen_head_sha": "abc123...",
  "retries_by_sha": {"abc123...": 1},
  "seen_issue_comment_ids": ["111", "222"],
  "seen_review_comment_ids": ["333"],
  "seen_review_ids": ["444"],
  "last_snapshot_at": 1234567900
}
```

## 风险、边界与改进建议

### 风险

1. **API 限流**
   - 风险: 频繁轮询可能触发 GitHub API 限流
   - 缓解: 使用 `--poll-seconds` 控制频率，默认 30 秒，CI 全绿后指数退避至 1 小时

2. **认证失效**
   - 风险: `gh` token 过期或权限不足
   - 表现: `GhCommandError` 异常
   - 处理: 属于 "stop-and-ask" 条件（见 `heuristics.md`）

3. **状态文件损坏**
   - 风险: 手动编辑或程序异常导致 JSON 损坏
   - 处理: `load_state()` 会抛出 `RuntimeError`，属于致命错误

4. **SHA 变更竞争条件**
   - 风险: 获取 workflow runs 后、重试前，PR 被推送了新 commit
   - 缓解: 每次操作前重新收集 snapshot，按 SHA 记录重试次数

### 边界

1. **评论作者过滤**
   - 只处理 `TRUSTED_AUTHOR_ASSOCIATIONS = {OWNER, MEMBER, COLLABORATOR}` 或当前登录用户的评论
   - Bot 评论只处理包含 "codex" 关键词的（如 `chatgpt-codex-connector[bot]`）

2. **重试限制**
   - 每个 SHA 默认最多 3 次重试（可配置）
   - 超过后触发 `stop_exhausted_retries` 动作

3. **分页限制**
   - 评论和 workflow runs 只获取前 100 页 × 100 条 = 10,000 条
   - 对于超大型 PR 可能遗漏早期评论

### 改进建议

1. **缓存优化**
   - 当前: 每次轮询都重新获取所有评论
   - 建议: 使用 GitHub API 的 `If-None-Match` 头进行条件请求，减少 API 调用

2. **GraphQL 迁移**
   - 当前: 使用 REST API，需要多次调用获取 PR、checks、runs、comments
   - 建议: 使用 GraphQL 批量查询，减少请求次数和延迟

3. **增量同步**
   - 当前: 评论使用全量分页获取
   - 建议: 使用 `since` 参数只获取新评论，或利用 webhook 替代轮询

4. **并发控制**
   - 当前: 顺序执行所有 API 调用
   - 建议: 对独立的 API 调用（如三种评论类型）使用并发请求

5. **错误重试**
   - 当前: API 调用失败直接抛出异常
   - 建议: 对网络超时等 transient 错误添加指数退避重试

6. **状态文件位置**
   - 当前: 固定使用 `/tmp`，在多用户环境可能冲突
   - 建议: 使用 `$XDG_STATE_HOME` 或项目本地 `.codex/` 目录
