# babysit-pr Skill 深度研究文档

## 概述

`babysit-pr` 是 OpenAI Codex 项目中的一个核心 Skill，用于自动化监控和管理 GitHub Pull Request (PR) 的生命周期。该 Skill 通过持续轮询 PR 状态、CI 检查结果、Review 评论等，实现 PR 的自动化看护，直到 PR 达到可合并状态或需要人工介入。

---

## 一、场景与职责

### 1.1 核心场景

| 场景 | 描述 |
|------|------|
| **PR 创建后监控** | 用户创建 PR 后，需要持续监控 CI 状态、Review 反馈、合并冲突等 |
| **CI 失败诊断与修复** | 自动诊断 CI 失败原因，区分分支相关问题和 flaky 测试，尝试自动修复或重试 |
| **Review 评论处理** | 监控 Reviewer 的评论和反馈，自动处理可执行的修改建议 |
| **合并准备状态跟踪** | 持续检查 PR 是否满足合并条件（CI 通过、Review 批准、无冲突） |

### 1.2 核心职责

1. **状态监控**：持续轮询 PR 的 CI 状态、Review 状态、合并状态
2. **失败诊断**：分析 CI 失败日志，区分分支相关问题 vs flaky/基础设施问题
3. **自动修复**：对于分支相关问题，本地修复后提交并推送
4. **Flaky 重试**：对于 flaky 失败，自动重试（最多 3 次）
5. **Review 处理**：处理可执行的 Review 评论
6. **终止判断**：在满足条件时停止监控，或识别需要人工介入的情况

### 1.3 终端状态定义

监控在以下情况终止：
- PR 已合并或关闭
- PR 准备就绪：CI 成功 + 无未处理 Review 评论 + Review 批准 + 可合并
- 需要人工帮助（基础设施问题、flaky 重试耗尽、权限问题、模糊的阻塞情况）

---

## 二、功能点目的

### 2.1 核心功能模块

#### 2.1.1 PR 状态解析 (`resolve_pr`)

**目的**：将用户输入的 PR 标识（auto/number/URL）解析为标准化的 PR 信息结构

**功能**：
- 支持 `--pr auto` 自动推断当前分支的 PR
- 支持 PR 数字编号
- 支持完整 PR URL
- 提取 PR 基础信息：number, url, repo, head_sha, head_branch, state, merged, closed, mergeable, merge_state_status, review_decision

#### 2.1.2 CI 检查监控 (`get_pr_checks` / `summarize_checks`)

**目的**：获取并汇总 PR 的 CI 检查状态

**功能**：
- 调用 `gh pr checks` 获取检查列表
- 分类统计：pending_count, failed_count, passed_count
- 判断是否所有检查都已终止 (all_terminal)

#### 2.1.3 工作流运行监控 (`get_workflow_runs_for_sha` / `failed_runs_from_workflow_runs`)

**目的**：获取特定 commit SHA 的工作流运行状态，识别失败的运行

**功能**：
- 调用 GitHub Actions API 获取工作流运行列表
- 筛选当前 HEAD SHA 的失败运行
- 提取 run_id, workflow_name, status, conclusion, html_url

#### 2.1.4 Review 评论监控 (`fetch_new_review_items`)

**目的**：获取新的 Review 评论、Issue 评论和 Review 提交

**功能**：
- 分页获取三类评论数据：
  - Issue comments: `repos/{repo}/issues/{pr_number}/comments`
  - Review comments: `repos/{repo}/pulls/{pr_number}/comments`
  - Reviews: `repos/{repo}/pulls/{pr_number}/reviews`
- 标准化评论格式（kind, id, author, author_association, created_at, body, path, line, url）
- 作者信任度验证：
  - 信任的人类作者：OWNER, MEMBER, COLLABORATOR 或当前认证用户
  - 信任的 Bot：包含 "codex" 关键词的 bot（如 `chatgpt-codex-connector[bot]`）
- 新评论去重：基于 state file 中已记录的评论 ID

#### 2.1.5 动作推荐 (`recommend_actions`)

**目的**：根据当前状态推荐下一步动作

**动作类型**：
| 动作 | 触发条件 | 含义 |
|------|----------|------|
| `stop_pr_closed` | PR 已关闭/合并 | 终止监控 |
| `stop_ready_to_merge` | PR 可合并 | 终止监控 |
| `stop_exhausted_retries` | flaky 重试次数耗尽 | 终止监控，需人工介入 |
| `process_review_comment` | 有新的 Review 评论 | 需要处理评论 |
| `diagnose_ci_failure` | 有失败的 CI 检查 | 需要诊断失败原因 |
| `retry_failed_checks` | 所有检查已终止且未超重试次数 | 可以重试失败检查 |
| `idle` | 无上述情况 | 继续等待 |

#### 2.1.6 Flaky 重试 (`retry_failed_now`)

**目的**：触发失败工作流的重新运行

**功能**：
- 验证重试条件：PR 未关闭、有失败检查、检查已终止、未超重试次数
- 调用 `gh run rerun <run_id> --failed` 重试每个失败运行
- 更新 state file 中的重试计数

#### 2.1.7 持续监控模式 (`run_watch`)

**目的**：持续轮询 PR 状态，直到满足终止条件

**功能**：
- 自适应轮询间隔：
  - CI 未通过：每 30 秒（默认）轮询
  - CI 通过后：指数退避（1m → 2m → 4m → 8m → 16m → 32m → 最大 1 小时）
  - 状态变化时重置为 1 分钟
- 输出 JSONL 格式事件流：`snapshot` 事件和 `stop` 事件

---

## 三、具体技术实现

### 3.1 关键数据结构

#### 3.1.1 PR 信息结构

```python
{
    "number": int,           # PR 编号
    "url": str,              # PR URL
    "repo": str,             # OWNER/REPO 格式
    "head_sha": str,         # HEAD commit SHA
    "head_branch": str,      # 分支名
    "state": str,            # PR 状态
    "merged": bool,          # 是否已合并
    "closed": bool,          # 是否已关闭
    "mergeable": str,        # MERGEABLE / CONFLICTING / UNKNOWN
    "merge_state_status": str,  # BLOCKED / DIRTY / DRAFT / etc.
    "review_decision": str,  # REVIEW_REQUIRED / CHANGES_REQUESTED / APPROVED
}
```

#### 3.1.2 CI 检查汇总结构

```python
{
    "pending_count": int,    # 待处理检查数
    "failed_count": int,     # 失败检查数
    "passed_count": int,     # 通过检查数
    "all_terminal": bool,    # 是否所有检查都已终止
}
```

#### 3.1.3 失败运行结构

```python
{
    "run_id": int,           # 工作流运行 ID
    "workflow_name": str,    # 工作流名称
    "status": str,           # 状态
    "conclusion": str,       # 结论 (failure, timed_out, cancelled, etc.)
    "html_url": str,         # 运行页面 URL
}
```

#### 3.1.4 Review 项目结构

```python
{
    "kind": str,             # issue_comment / review_comment / review
    "id": str,               # 评论 ID
    "author": str,           # 作者登录名
    "author_association": str,  # OWNER / MEMBER / COLLABORATOR / etc.
    "created_at": str,       # 创建时间
    "body": str,             # 评论内容
    "path": str | None,      # 文件路径（仅 review_comment）
    "line": int | None,      # 行号（仅 review_comment）
    "url": str,              # 评论 URL
}
```

#### 3.1.5 State File 结构

```python
{
    "pr": {},                # PR 信息
    "started_at": int,       # 监控开始时间戳
    "last_seen_head_sha": str,  # 上次看到的 HEAD SHA
    "retries_by_sha": {      # 每个 SHA 的重试次数
        "<sha>": int
    },
    "seen_issue_comment_ids": [str],    # 已见 Issue 评论 ID
    "seen_review_comment_ids": [str],   # 已见 Review 评论 ID
    "seen_review_ids": [str],           # 已见 Review ID
    "last_snapshot_at": int,  # 上次快照时间戳
}
```

#### 3.1.6 Snapshot 输出结构

```python
{
    "pr": {...},             # PR 信息
    "checks": {...},         # CI 检查汇总
    "failed_runs": [...],    # 失败运行列表
    "new_review_items": [...],  # 新 Review 项目
    "actions": [...],        # 推荐动作列表
    "retry_state": {         # 重试状态
        "current_sha_retries_used": int,
        "max_flaky_retries": int,
    },
}
```

### 3.2 关键流程

#### 3.2.1 单次快照流程 (`collect_snapshot`)

```
1. 解析 PR 标识 → resolve_pr()
2. 加载或初始化 state file → load_state()
3. 获取 PR 检查状态 → get_pr_checks()
4. 汇总检查状态 → summarize_checks()
5. 获取工作流运行 → get_workflow_runs_for_sha()
6. 提取失败运行 → failed_runs_from_workflow_runs()
7. 获取认证用户 → get_authenticated_login()
8. 获取新 Review 项目 → fetch_new_review_items()
9. 计算当前重试次数 → current_retry_count()
10. 推荐动作 → recommend_actions()
11. 更新 state → save_state()
12. 返回 snapshot
```

#### 3.2.2 Review 项目获取流程 (`fetch_new_review_items`)

```
1. 分页获取三类评论数据（issue comments, review comments, reviews）
2. 标准化为统一格式
3. 加载已见评论 ID 集合
4. 对每个评论：
   - 跳过无 ID 或无作者的评论
   - 验证作者信任度：
     - Bot：仅接受包含 "codex" 关键词的 bot
     - 人类：仅接受 OWNER/MEMBER/COLLABORATOR 或当前用户
   - 跳过已记录的评论
   - 添加到新评论列表并记录 ID
5. 按时间排序新评论
6. 更新 state 中的已见 ID 列表
7. 返回新评论列表
```

#### 3.2.3 动作推荐决策流程 (`recommend_actions`)

```
1. 如果 PR 已关闭/合并：
   - 添加 stop_pr_closed
   - 如有新评论，添加 process_review_comment
   - 返回

2. 如果 PR 可合并（is_pr_ready_to_merge）：
   - 添加 stop_ready_to_merge
   - 返回

3. 如果有新评论：
   - 添加 process_review_comment

4. 如果有失败检查：
   - 如果所有检查已终止且重试次数已耗尽：
     - 添加 stop_exhausted_retries
   - 否则：
     - 添加 diagnose_ci_failure
     - 如果所有检查已终止且有失败运行且未超重试次数：
       - 添加 retry_failed_checks

5. 如无动作：
   - 添加 idle
```

#### 3.2.4 持续监控流程 (`run_watch`)

```
1. 初始化 poll_seconds = args.poll_seconds (默认 30)
2. 初始化 last_change_key = None
3. 循环：
   a. 收集快照 → collect_snapshot()
   b. 输出 snapshot 事件
   c. 检查是否有终止动作：
      - stop_pr_closed / stop_exhausted_retries / stop_ready_to_merge
      - 如有，输出 stop 事件并退出
   d. 计算当前 change_key
   e. 判断是否变化：changed = (current_change_key != last_change_key)
   f. 判断 CI 是否通过：green = is_ci_green()
   g. 调整轮询间隔：
      - 如果 CI 未通过：poll_seconds = args.poll_seconds
      - 如果 CI 通过且变化：poll_seconds = args.poll_seconds
      - 如果 CI 通过且无变化：poll_seconds = min(poll_seconds * 2, GREEN_STATE_MAX_POLL_SECONDS)
   h. 更新 last_change_key
   i. 睡眠 poll_seconds
```

### 3.3 协议与命令

#### 3.3.1 GitHub CLI 命令

| 功能 | 命令 |
|------|------|
| 获取 PR 信息 | `gh pr view [<pr>] --json <fields>` |
| 获取 PR 检查 | `gh pr checks [<pr>] --json <fields>` |
| 获取工作流运行 | `gh api repos/{owner}/{repo}/actions/runs -f head_sha=<sha>` |
| 查看运行详情 | `gh run view <run-id> --json <fields>` |
| 查看失败日志 | `gh run view <run-id> --log-failed` |
| 重试失败作业 | `gh run rerun <run-id> --failed` |
| 获取当前用户 | `gh api user` |

#### 3.3.2 GitHub API 端点

| 功能 | 端点 |
|------|------|
| Issue 评论 | `repos/{owner}/{repo}/issues/{pr_number}/comments` |
| Review 评论 | `repos/{owner}/{repo}/pulls/{pr_number}/comments` |
| Reviews | `repos/{owner}/{repo}/pulls/{pr_number}/reviews` |
| 工作流运行 | `repos/{owner}/{repo}/actions/runs` |
| 当前用户 | `user` |

#### 3.3.3 常量定义

```python
# 失败运行的结论状态
FAILED_RUN_CONCLUSIONS = {
    "failure", "timed_out", "cancelled", "action_required",
    "startup_failure", "stale"
}

# 待处理检查状态
PENDING_CHECK_STATES = {
    "QUEUED", "IN_PROGRESS", "PENDING", "WAITING", "REQUESTED"
}

# Review Bot 关键词
REVIEW_BOT_LOGIN_KEYWORDS = {"codex"}

# 信任的作者关联
TRUSTED_AUTHOR_ASSOCIATIONS = {"OWNER", "MEMBER", "COLLABORATOR"}

# 阻塞合并的 Review 决策
MERGE_BLOCKING_REVIEW_DECISIONS = {"REVIEW_REQUIRED", "CHANGES_REQUESTED"}

# 合并冲突或阻塞状态
MERGE_CONFLICT_OR_BLOCKING_STATES = {"BLOCKED", "DIRTY", "DRAFT", "UNKNOWN"}

# 绿色状态最大轮询间隔（1小时）
GREEN_STATE_MAX_POLL_SECONDS = 60 * 60
```

---

## 四、关键代码路径与文件引用

### 4.1 文件结构

```
.codex/skills/babysit-pr/
├── SKILL.md                          # Skill 定义和使用文档
├── agents/
│   └── openai.yaml                   # OpenAI Agent 配置
├── references/
│   ├── heuristics.md                 # CI/Review 启发式规则
│   └── github-api-notes.md           # GitHub CLI/API 参考
└── scripts/
    └── gh_pr_watch.py                # 核心监控脚本 (805 行)
```

### 4.2 核心代码路径

#### 4.2.1 入口与参数解析 (gh_pr_watch.py:55-95)

```python
def parse_args():
    # --pr: PR 标识 (auto/number/URL)
    # --repo: 可选的 OWNER/REPO 覆盖
    # --poll-seconds: 轮询间隔 (默认 30)
    # --max-flaky-retries: 最大 flaky 重试次数 (默认 3)
    # --state-file: 状态文件路径
    # --once: 单次快照模式
    # --watch: 持续监控模式
    # --retry-failed-now: 立即重试失败检查
```

#### 4.2.2 PR 解析 (gh_pr_watch.py:135-193)

```python
def parse_pr_spec(pr_spec):           # 解析 PR 标识
def pr_view_fields():                 # PR 字段定义
def resolve_pr(pr_spec, repo_override):  # 解析 PR 信息
```

#### 4.2.3 状态管理 (gh_pr_watch.py:222-263)

```python
def load_state(path):                 # 加载状态文件
def save_state(path, state):          # 保存状态文件（原子写入）
def default_state_file_for(pr):       # 默认状态文件路径
```

#### 4.2.4 CI 检查 (gh_pr_watch.py:265-303)

```python
def get_pr_checks(pr_spec, repo):     # 获取 PR 检查
def checks_fields():                  # 检查字段定义
def is_pending_check(check):          # 判断是否待处理
def summarize_checks(checks):         # 汇总检查状态
```

#### 4.2.5 工作流运行 (gh_pr_watch.py:305-340)

```python
def get_workflow_runs_for_sha(repo, head_sha):  # 获取工作流运行
def failed_runs_from_workflow_runs(runs, head_sha):  # 提取失败运行
```

#### 4.2.6 Review 处理 (gh_pr_watch.py:342-525)

```python
def get_authenticated_login():        # 获取当前用户
def comment_endpoints(repo, pr_number):  # 评论端点
def gh_api_list_paginated(endpoint):  # 分页获取 API 数据
def normalize_issue_comments(items):  # 标准化 Issue 评论
def normalize_review_comments(items): # 标准化 Review 评论
def normalize_reviews(items):         # 标准化 Reviews
def extract_login(user_obj):          # 提取用户登录名
def is_bot_login(login):              # 判断是否为 Bot
def is_actionable_review_bot_login(login):  # 判断可处理的 Bot
def is_trusted_human_review_author(item, authenticated_login):  # 判断信任的人类作者
def fetch_new_review_items(pr, state, fresh_state, authenticated_login):  # 获取新评论
```

#### 4.2.7 动作推荐 (gh_pr_watch.py:527-599)

```python
def current_retry_count(state, head_sha):  # 获取当前重试次数
def set_retry_count(state, head_sha, count):  # 设置重试次数
def unique_actions(actions):          # 去重动作列表
def is_pr_ready_to_merge(pr, checks_summary, new_review_items):  # 判断是否可合并
def recommend_actions(pr, checks_summary, failed_runs, new_review_items, retries_used, max_retries):  # 推荐动作
```

#### 4.2.8 快照收集 (gh_pr_watch.py:601-650)

```python
def collect_snapshot(args):           # 收集完整快照
```

#### 4.2.9 Flaky 重试 (gh_pr_watch.py:652-705)

```python
def retry_failed_now(args):           # 立即重试失败检查
```

#### 4.2.10 持续监控 (gh_pr_watch.py:707-782)

```python
def is_ci_green(snapshot):            # 判断 CI 是否通过
def snapshot_change_key(snapshot):    # 计算快照变化键
def run_watch(args):                  # 持续监控循环
```

#### 4.2.11 主入口 (gh_pr_watch.py:784-805)

```python
def main():                           # 主函数
```

---

## 五、依赖与外部交互

### 5.1 外部依赖

| 依赖 | 用途 | 必需 |
|------|------|------|
| `gh` (GitHub CLI) | 所有 GitHub 操作 | 是 |
| `python3` | 脚本运行环境 | 是 |
| GitHub API 访问权限 | 读取 PR/Checks/Actions/Review 数据 | 是 |
| GitHub Actions 权限 | 重试工作流运行 | 是（重试功能）|

### 5.2 环境变量

| 变量 | 用途 |
|------|------|
| `GH_TOKEN` 或 `GITHUB_TOKEN` | GitHub CLI 认证 |

### 5.3 文件系统交互

| 路径 | 用途 |
|------|------|
| `/tmp/codex-babysit-pr-{repo_slug}-pr{number}.json` | 默认状态文件路径 |
| 自定义 `--state-file` | 用户指定的状态文件 |

### 5.4 上游调用方

该 Skill 通过 `SKILL.md` 和 `agents/openai.yaml` 被 Kimi Code CLI 的 Skill 系统加载和调用：

1. **Skill 系统**：Kimi Code CLI 读取 `.codex/skills/babysit-pr/SKILL.md` 获取 Skill 定义
2. **Agent 配置**：`.codex/skills/babysit-pr/agents/openai.yaml` 提供 Agent 接口配置
3. **用户触发**：用户通过自然语言指令（如 "monitor this PR", "babysit PR #123"）触发 Skill

### 5.5 下游被调用方

该 Skill 调用以下外部系统：

1. **GitHub CLI (`gh`)**：所有 GitHub 数据获取和操作
2. **GitHub REST API**：通过 `gh api` 调用
3. **GitHub Actions API**：工作流运行管理

---

## 六、风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 认证与权限风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| Token 过期 | GitHub Token 过期导致 API 调用失败 | 监控 `GhCommandError`，提示用户检查认证 |
| 权限不足 | 缺少 Actions 权限无法重试工作流 | 在重试前检查权限，失败时报告用户 |
| 私有仓库访问 | 无法访问私有仓库的 PR 数据 | 确保 Token 有相应权限 |

#### 6.1.2 状态一致性风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| State file 损坏 | JSON 解析失败 | `load_state` 捕获 `JSONDecodeError` 并抛出清晰错误 |
| 并发访问 | 多个进程同时写入 state file | 使用原子写入（`tempfile.mkstemp` + `os.replace`） |
| SHA 变化 | 推送新 commit 后 SHA 变化 | 基于 SHA 跟踪重试次数，避免跨 SHA 计数混淆 |

#### 6.1.3 评论处理风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 恶意 Bot 评论 | 恶意 Bot 伪装成 Codex Bot | 仅信任包含 "codex" 关键词的 Bot |
| 评论误处理 | 错误处理非 actionable 评论 | 启发式规则指导，人工最终确认 |
| 评论风暴 | 大量评论导致频繁触发 | 去重机制，批量处理 |

#### 6.1.4 CI 诊断风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 误判 flaky | 将分支相关问题误判为 flaky | 启发式 checklist，日志分析 |
| 误判分支问题 | 将 flaky 误判为分支问题 | 同上 |
| 无限重试循环 | 重试机制缺陷导致无限循环 | 严格重试次数限制（默认 3 次） |

### 6.2 边界条件

#### 6.2.1 输入边界

| 边界 | 行为 |
|------|------|
| `--pr auto` 无当前分支 PR | 抛出错误 |
| 无效的 PR URL | 抛出 `ValueError` |
| `--poll-seconds <= 0` | 参数错误 |
| `--max-flaky-retries < 0` | 参数错误 |
| `--watch` + `--retry-failed-now` | 参数错误（互斥） |

#### 6.2.2 运行时边界

| 边界 | 行为 |
|------|------|
| PR 在监控期间被删除 | 下次轮询时 `resolve_pr` 失败 |
| 网络中断 | `gh` 命令失败，抛出 `GhCommandError` |
| 磁盘满 | `save_state` 原子写入失败 |
| 大量评论/检查 | 分页处理，内存占用可控 |

#### 6.2.3 API 限制

| 限制 | 说明 |
|------|------|
| GitHub API 速率限制 | 未显式处理，依赖 `gh` 的错误处理 |
| 分页限制 | 每页 100 条，自动处理多页 |
| 工作流运行查询 | 限制最近 100 条运行 |

### 6.3 改进建议

#### 6.3.1 功能增强

1. **智能 CI 诊断**
   - 集成日志分析，自动识别常见失败模式
   - 基于历史数据学习 flaky 测试模式
   - 提供更详细的失败分类置信度

2. **Review 评论智能处理**
   - 集成 LLM 分析评论意图和可操作性
   - 支持代码建议的自动应用
   - 批量处理相关评论

3. **通知机制**
   - 支持 Slack/Email 通知重要状态变化
   - 可配置的告警规则

4. **多 PR 监控**
   - 同时监控多个 PR 的状态
   - 批量操作支持

#### 6.3.2 可靠性改进

1. **断点续传**
   - 更 robust 的状态恢复机制
   - 支持监控中断后的无缝恢复

2. **API 容错**
   - 指数退避重试 API 调用
   - 更好的网络错误处理

3. **日志记录**
   - 结构化日志输出
   - 详细的调试信息

#### 6.3.3 性能优化

1. **增量更新**
   - 利用 GitHub API 的 ETag/If-None-Match 减少数据传输
   - Webhook 支持替代轮询（如可行）

2. **并行化**
   - 并行获取不同类型的评论数据
   - 异步 I/O 支持

#### 6.3.4 可观测性

1. **指标收集**
   - 监控轮询频率、API 调用次数
   - 成功率/失败率统计

2. **健康检查**
   - 内置健康检查端点
   - 状态报告命令

#### 6.3.5 安全增强

1. **Token 管理**
   - 支持 Token 轮换
   - Token 权限最小化检查

2. **审计日志**
   - 记录所有自动操作
   - 可追溯的决策路径

---

## 七、附录

### 7.1 命令行用法示例

```bash
# 单次快照
python3 .codex/skills/babysit-pr/scripts/gh_pr_watch.py --pr auto --once

# 持续监控
python3 .codex/skills/babysit-pr/scripts/gh_pr_watch.py --pr auto --watch

# 立即重试失败检查
python3 .codex/skills/babysit-pr/scripts/gh_pr_watch.py --pr auto --retry-failed-now

# 指定 PR 编号
python3 .codex/skills/babysit-pr/scripts/gh_pr_watch.py --pr 123 --once

# 指定 PR URL
python3 .codex/skills/babysit-pr/scripts/gh_pr_watch.py --pr https://github.com/owner/repo/pull/123 --once

# 自定义状态文件
python3 .codex/skills/babysit-pr/scripts/gh_pr_watch.py --pr auto --watch --state-file /path/to/state.json
```

### 7.2 输出示例

**单次快照输出（JSON）**：
```json
{
  "actions": ["diagnose_ci_failure", "retry_failed_checks"],
  "checks": {
    "all_terminal": true,
    "failed_count": 2,
    "passed_count": 15,
    "pending_count": 0
  },
  "failed_runs": [
    {
      "conclusion": "failure",
      "html_url": "https://github.com/owner/repo/actions/runs/123456789",
      "run_id": 123456789,
      "status": "completed",
      "workflow_name": "CI"
    }
  ],
  "new_review_items": [],
  "pr": {
    "closed": false,
    "head_branch": "feature-branch",
    "head_sha": "abc123def456",
    "merge_state_status": "BLOCKED",
    "mergeable": "MERGEABLE",
    "merged": false,
    "number": 123,
    "repo": "owner/repo",
    "review_decision": "REVIEW_REQUIRED",
    "state": "OPEN",
    "url": "https://github.com/owner/repo/pull/123"
  },
  "retry_state": {
    "current_sha_retries_used": 1,
    "max_flaky_retries": 3
  },
  "state_file": "/tmp/codex-babysit-pr-owner-repo-pr123.json"
}
```

**持续监控输出（JSONL）**：
```json
{"event": "snapshot", "payload": {"snapshot": {...}, "state_file": "...", "next_poll_seconds": 30}}
{"event": "snapshot", "payload": {"snapshot": {...}, "state_file": "...", "next_poll_seconds": 60}}
{"event": "stop", "payload": {"actions": ["stop_ready_to_merge"], "pr": {...}}}
```

### 7.3 相关文档引用

- **启发式规则**：`.codex/skills/babysit-pr/references/heuristics.md`
- **GitHub API 参考**：`.codex/skills/babysit-pr/references/github-api-notes.md`
- **Agent 配置**：`.codex/skills/babysit-pr/agents/openai.yaml`

---

*文档生成时间：2026-03-22*
*研究对象版本：基于当前仓库 HEAD*
