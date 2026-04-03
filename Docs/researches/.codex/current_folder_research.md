# `.codex` 目录深度研究文档

> 研究对象：`.codex/` 目录  
> 研究时间：2026-03-22  
> 项目：OpenAI Codex CLI  

---

## 一、场景与职责

### 1.1 定位与作用

`.codex/` 目录是 **Kimi Code CLI (codex-cli)** 项目的 **Skill System（技能系统）** 存储目录。它存放着可被 AI Agent 动态加载和执行的领域特定技能（Skills），用于扩展 Codex 的能力边界。

### 1.2 核心职责

| 职责 | 说明 |
|------|------|
| **技能定义存储** | 存放 YAML/MD 格式的技能定义文件 |
| **脚本托管** | 存放技能所需的辅助脚本（如 Python、Shell） |
| **Agent 配置** | 定义技能的 Agent 接口和提示词模板 |
| **参考文档** | 存放技能的参考材料、启发式规则、API 文档等 |

### 1.3 使用场景

1. **PR 自动化看护** (`babysit-pr`): 监控 GitHub PR 的 CI 状态、Review 评论、合并冲突，自动修复问题或重试 flaky 测试
2. **TUI 交互测试** (`test-tui`): 指导如何以交互方式测试 Codex TUI 应用

---

## 二、功能点目的

### 2.1 Skill: `babysit-pr` - PR 自动化看护

#### 目的
解决开发者在提交 PR 后需要持续监控 CI 状态、处理 Review 反馈的繁琐工作。通过自动化轮询和智能决策，减少人工干预。

#### 核心功能

| 功能模块 | 目的 |
|---------|------|
| **CI 状态监控** | 持续轮询 GitHub Actions 检查状态，识别失败/通过/ pending |
| **失败分类** | 区分"分支相关失败"（代码问题）vs "flaky/基础设施失败" |
| **自动重试** | 对 flaky 失败自动重试（最多3次），避免人工干预 |
| **Review 处理** | 监控 PR 评论、Review 评论、Review 提交，识别可操作的反馈 |
| **合并就绪检测** | 综合判断 CI 通过 + Review 清理 + 可合并状态 |

#### 终端状态判定

```
停止条件（严格）：
├── PR 已合并或关闭
├── PR 就绪可合并（CI 通过 + 无未处理 Review + 无冲突 + 非 Draft）
└── 需要用户干预（基础设施问题、重试预算耗尽、权限问题）
```

### 2.2 Skill: `test-tui` - TUI 测试指导

#### 目的
为开发者提供标准化的 Codex TUI 交互测试指南，确保测试环境配置正确。

#### 核心要点
- 必须设置 `RUST_LOG="trace"` 进行调试
- 使用 `-c log_dir=<temp_dir>` 指定日志目录
- 程序化发送消息时需分两次写入（文本 + Enter）
- 使用 `just codex` 目标运行

---

## 三、具体技术实现

### 3.1 文件组织结构

```
.codex/
├── skills/
│   ├── babysit-pr/
│   │   ├── SKILL.md              # 技能主定义文档（YAML Front Matter + Markdown）
│   │   ├── agents/
│   │   │   └── openai.yaml       # Agent 接口定义（显示名称、描述、默认提示词）
│   │   ├── references/
│   │   │   ├── github-api-notes.md   # GitHub CLI/API 使用说明
│   │   │   └── heuristics.md         # CI/Review 启发式决策规则
│   │   └── scripts/
│   │       └── gh_pr_watch.py    # 核心实现：PR 监控脚本（805行 Python）
│   └── test-tui/
│       └── SKILL.md              # TUI 测试指南
```

### 3.2 `gh_pr_watch.py` 关键技术实现

#### 3.2.1 核心常量定义

```python
# 失败运行结论集合
FAILED_RUN_CONCLUSIONS = {
    "failure", "timed_out", "cancelled", 
    "action_required", "startup_failure", "stale"
}

# Pending 状态集合
PENDING_CHECK_STATES = {
    "QUEUED", "IN_PROGRESS", "PENDING", 
    "WAITING", "REQUESTED"
}

# 可信作者关联（用于 Review 过滤）
TRUSTED_AUTHOR_ASSOCIATIONS = {"OWNER", "MEMBER", "COLLABORATOR"}

# 合并阻塞性 Review 决策
MERGE_BLOCKING_REVIEW_DECISIONS = {"REVIEW_REQUIRED", "CHANGES_REQUESTED"}

# 绿色状态最大轮询间隔（秒）
GREEN_STATE_MAX_POLL_SECONDS = 60 * 60  # 1小时
```

#### 3.2.2 状态数据结构

```python
# 状态文件结构（JSON）
{
    "pr": {"repo": "owner/repo", "number": 123},
    "started_at": 1711094400,
    "last_seen_head_sha": "abc123...",
    "retries_by_sha": {"abc123...": 2},  # 每个 SHA 的重试计数
    "seen_issue_comment_ids": ["123", "456"],
    "seen_review_comment_ids": ["789"],
    "seen_review_ids": ["101112"],
    "last_snapshot_at": 1711094500
}
```

#### 3.2.3 快照数据结构

```python
{
    "pr": {
        "number": 123,
        "url": "https://github.com/owner/repo/pull/123",
        "repo": "owner/repo",
        "head_sha": "abc123...",
        "head_branch": "feature-branch",
        "state": "OPEN",
        "merged": False,
        "closed": False,
        "mergeable": "MERGEABLE",
        "merge_state_status": "CLEAN",
        "review_decision": ""
    },
    "checks": {
        "pending_count": 2,
        "failed_count": 1,
        "passed_count": 30,
        "all_terminal": False  # 是否所有检查都已结束
    },
    "failed_runs": [
        {
            "run_id": 123456789,
            "workflow_name": "CI",
            "status": "completed",
            "conclusion": "failure",
            "html_url": "..."
        }
    ],
    "new_review_items": [
        {
            "kind": "issue_comment|review_comment|review",
            "id": "123",
            "author": "username",
            "author_association": "MEMBER",
            "created_at": "2024-03-22T10:00:00Z",
            "body": "评论内容",
            "path": "src/file.rs",  # review_comment 特有
            "line": 42,             # review_comment 特有
            "url": "..."
        }
    ],
    "actions": [
        "idle|diagnose_ci_failure|retry_failed_checks|process_review_comment|"
        "stop_pr_closed|stop_ready_to_merge|stop_exhausted_retries"
    ],
    "retry_state": {
        "current_sha_retries_used": 2,
        "max_flaky_retries": 3
    }
}
```

#### 3.2.4 GitHub CLI 调用封装

```python
def gh_text(args, repo=None):
    """执行 gh 命令，返回文本输出"""
    cmd = ["gh"]
    if repo and args[0] != "api":  # gh api 不接受 -R 参数
        cmd.extend(["-R", repo])
    cmd.extend(args)
    proc = subprocess.run(cmd, check=True, capture_output=True, text=True)
    return proc.stdout

def gh_json(args, repo=None):
    """执行 gh 命令，返回解析后的 JSON"""
    raw = gh_text(args, repo=repo).strip()
    return json.loads(raw) if raw else None
```

#### 3.2.5 关键 API 调用

| 功能 | 命令 |
|------|------|
| PR 元数据 | `gh pr view --json number,url,state,mergedAt,closedAt,headRefName,headRefOid,...` |
| 检查摘要 | `gh pr checks --json name,state,bucket,link,workflow,event,startedAt,completedAt` |
| 工作流运行 | `gh api repos/{owner}/{repo}/actions/runs -X GET -f head_sha=<sha>` |
| 失败日志 | `gh run view <run-id> --log-failed` |
| 重试失败任务 | `gh run rerun <run-id> --failed` |
| Issue 评论 | `gh api repos/{owner}/{repo}/issues/<pr_number>/comments` |
| Review 评论 | `gh api repos/{owner}/{repo}/pulls/<pr_number>/comments` |
| Review 提交 | `gh api repos/{owner}/{repo}/pulls/<pr_number>/reviews` |

#### 3.2.6 自适应轮询算法

```python
def run_watch(args):
    poll_seconds = args.poll_seconds  # 默认 30 秒
    last_change_key = None
    
    while True:
        snapshot, state_path = collect_snapshot(args)
        print_event("snapshot", {...})
        
        actions = set(snapshot.get("actions") or [])
        if any(stop_action in actions for stop_action in 
               ["stop_pr_closed", "stop_exhausted_retries", "stop_ready_to_merge"]):
            print_event("stop", {...})
            return 0
        
        current_change_key = snapshot_change_key(snapshot)
        changed = current_change_key != last_change_key
        green = is_ci_green(snapshot)
        
        # 自适应调整轮询间隔
        if not green:
            poll_seconds = args.poll_seconds  # CI 未通过：保持短间隔
        elif changed or last_change_key is None:
            poll_seconds = args.poll_seconds  # 状态变化：重置短间隔
        else:
            # CI 通过且状态无变化：指数退避，最大 1 小时
            poll_seconds = min(poll_seconds * 2, GREEN_STATE_MAX_POLL_SECONDS)
        
        last_change_key = current_change_key
        time.sleep(poll_seconds)
```

#### 3.2.7 Review 项目过滤逻辑

```python
def fetch_new_review_items(pr, state, fresh_state, authenticated_login=None):
    # 1. 获取所有评论数据（分页）
    issue_payload = gh_api_list_paginated(endpoints["issue_comment"])
    review_comment_payload = gh_api_list_paginated(endpoints["review_comment"])
    review_payload = gh_api_list_paginated(endpoints["review"])
    
    # 2. 标准化为统一格式
    all_items = normalize_issue_comments(issue_payload) + \
                normalize_review_comments(review_comment_payload) + \
                normalize_reviews(review_payload)
    
    # 3. 过滤逻辑
    for item in all_items:
        author = item.get("author") or ""
        
        # 过滤 Bot：只保留特定关键词的 Bot（如 codex）
        if is_bot_login(author):
            if not is_actionable_review_bot_login(author):
                continue
        # 过滤人类作者：只保留 OWNER/MEMBER/COLLABORATOR 或当前用户
        elif not is_trusted_human_review_author(item, authenticated_login):
            continue
        
        # 去重：跳过已见过的项目
        if item_id in seen_set:
            continue
            
        new_items.append(item)
```

### 3.3 Agent 配置 (`openai.yaml`)

```yaml
interface:
  display_name: "PR Babysitter"
  short_description: "Watch PR CI, reviews, and merge conflicts"
  default_prompt: "Babysit the current PR: monitor CI, reviewer comments, 
                   and merge-conflict status (prefer the watcher's --watch mode 
                   for live monitoring); fix valid issues, push updates, and 
                   rerun flaky failures up to 3 times..."
```

### 3.4 启发式决策规则 (`heuristics.md`)

#### CI 失败分类

| 分类 | 特征 |
|------|------|
| **分支相关** | 编译/类型检查失败、lint 错误、确定性测试失败、快照变化、静态分析违规、构建脚本错误 |
| **Flaky/无关** | DNS/网络超时、Runner 配置失败、GitHub Actions 基础设施错误、云服务限流、已知 flaky 测试 |

#### 决策树

```
1. PR 已合并/关闭？→ 停止
2. 有失败检查？
   ├── 诊断日志
   ├── 分支相关？→ 本地修复 → 提交 → 推送
   ├── Flaky/无关？→ 重试失败任务
   └── 检查仍在运行？→ 等待
3. 重试次数超限？→ 停止并报告
4. 处理新的 Review 评论
```

---

## 四、关键代码路径与文件引用

### 4.1 核心文件清单

| 文件路径 | 类型 | 行数 | 说明 |
|---------|------|------|------|
| `.codex/skills/babysit-pr/SKILL.md` | Markdown | 185 | 技能主文档，定义工作流、命令、规则 |
| `.codex/skills/babysit-pr/agents/openai.yaml` | YAML | 4 | Agent 接口配置 |
| `.codex/skills/babysit-pr/scripts/gh_pr_watch.py` | Python | 805 | 核心监控脚本 |
| `.codex/skills/babysit-pr/references/heuristics.md` | Markdown | 58 | CI/Review 启发式规则 |
| `.codex/skills/babysit-pr/references/github-api-notes.md` | Markdown | 72 | GitHub CLI/API 使用说明 |
| `.codex/skills/test-tui/SKILL.md` | Markdown | 14 | TUI 测试指南 |

### 4.2 关键函数索引

#### `gh_pr_watch.py`

| 函数 | 行号 | 功能 |
|------|------|------|
| `parse_args()` | 55-94 | 参数解析 |
| `resolve_pr()` | 157-192 | 解析 PR 规格（auto/number/url） |
| `get_pr_checks()` | 265-276 | 获取 PR 检查状态 |
| `summarize_checks()` | 285-302 | 汇总检查状态 |
| `get_workflow_runs_for_sha()` | 305-316 | 获取指定 SHA 的工作流运行 |
| `failed_runs_from_workflow_runs()` | 319-339 | 提取失败运行 |
| `fetch_new_review_items()` | 468-524 | 获取新的 Review 项目 |
| `recommend_actions()` | 572-598 | 推荐操作动作 |
| `collect_snapshot()` | 601-649 | 收集完整快照 |
| `retry_failed_now()` | 652-704 | 立即重试失败任务 |
| `run_watch()` | 747-781 | 持续监控循环 |
| `main()` | 784-801 | 入口函数 |

---

## 五、依赖与外部交互

### 5.1 外部依赖

| 依赖 | 用途 | 必需 |
|------|------|------|
| `gh` (GitHub CLI) | 与 GitHub API 交互 | ✅ 必需 |
| `python3` | 执行监控脚本 | ✅ 必需 |
| Git 凭证 | 推送修复提交 | ⚠️ 条件 |

### 5.2 GitHub API 端点

```
GET /repos/{owner}/{repo}/actions/runs?head_sha={sha}
GET /repos/{owner}/{repo}/issues/{pr_number}/comments
GET /repos/{owner}/{repo}/pulls/{pr_number}/comments
GET /repos/{owner}/{repo}/pulls/{pr_number}/reviews
POST /repos/{owner}/{repo}/actions/runs/{run_id}/rerun  # 通过 gh run rerun
```

### 5.3 状态文件存储

```
/tmp/codex-babysit-pr-{repo_slug}-pr{pr_number}.json
```

### 5.4 与 Kimi Code CLI 的集成

`.codex/skills/` 目录是 Kimi Code CLI 的技能系统标准路径。当用户请求 "monitor PR"、"watch CI"、"babysit PR" 时，系统会：

1. 加载 `.codex/skills/babysit-pr/SKILL.md` 获取技能定义
2. 根据 `agents/openai.yaml` 配置 Agent 接口
3. 执行 `scripts/gh_pr_watch.py` 进行实际监控
4. 参考 `references/` 中的规则进行决策

---

## 六、风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| **GitHub API 限流** | 高频轮询可能触发 rate limit | 自适应轮询退避 |
| **权限不足** | `gh` 认证过期或权限不足 | 错误捕获并提示用户 |
| **状态文件冲突** | 多个进程同时写入状态文件 | 原子写入（tempfile + os.replace） |
| **误判 flaky** | 将真正的代码错误误判为 flaky | 启发式规则 + 人工确认 |
| **无限循环** | 持续轮询不停止 | 严格的停止条件检查 |

### 6.2 边界限制

| 边界 | 说明 |
|------|------|
| **重试预算** | 每个 SHA 最多 3 次 flaky 重试（可配置） |
| **Review 过滤** | 只处理 OWNER/MEMBER/COLLABORATOR/当前用户/特定 Bot 的评论 |
| **轮询间隔** | 最小 30 秒，最大 1 小时（CI 通过后） |
| **并发限制** | 同一 PR 不建议同时运行多个 `--watch` 进程 |

### 6.3 改进建议

#### 短期改进

1. **Webhook 支持**
   - 当前：主动轮询 GitHub API
   - 建议：支持 GitHub Webhook 推送事件，减少 API 调用和延迟

2. **更智能的 flaky 检测**
   - 当前：基于启发式规则 + 重试计数
   - 建议：引入历史数据分析，识别已知 flaky 测试模式

3. **配置化**
   - 当前：硬编码常量较多（如 `GREEN_STATE_MAX_POLL_SECONDS`）
   - 建议：支持 `.codexrc` 或环境变量覆盖默认配置

4. **通知机制**
   - 当前：仅输出到 stdout
   - 建议：支持 Slack/Email/桌面通知等外部通知渠道

#### 中期改进

5. **多 PR 监控**
   - 当前：单进程单 PR
   - 建议：支持同时监控多个 PR

6. **自动合并**
   - 当前：检测到就绪状态后停止
   - 建议：可选的自动合并功能（需配置合并策略）

7. **与 CI 系统深度集成**
   - 当前：仅支持 GitHub Actions
   - 建议：支持 CircleCI、Travis、Azure DevOps 等

#### 长期改进

8. **机器学习增强**
   - 使用历史 PR 数据训练模型，更准确地预测 CI 失败原因
   - 自动推荐修复方案

9. **可视化 Dashboard**
   - 提供 Web UI 展示 PR 状态、历史趋势、统计报告

---

## 七、附录

### 7.1 命令速查表

```bash
# 一次性快照
python3 .codex/skills/babysit-pr/scripts/gh_pr_watch.py --pr auto --once

# 持续监控
python3 .codex/skills/babysit-pr/scripts/gh_pr_watch.py --pr auto --watch

# 立即重试失败任务
python3 .codex/skills/babysit-pr/scripts/gh_pr_watch.py --pr auto --retry-failed-now

# 指定 PR
python3 .codex/skills/babysit-pr/scripts/gh_pr_watch.py --pr 123 --once
```

### 7.2 相关文档链接

- 项目根目录 `AGENTS.md`: 项目级 Agent 指南
- `docs/`: 项目文档目录
- `.github/workflows/`: CI 工作流定义（被监控对象）

---

*文档生成时间: 2026-03-22*  
*研究者: Kimi Code CLI*  
*模型: k2.5*
