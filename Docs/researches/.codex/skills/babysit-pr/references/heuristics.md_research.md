# 研究文档: heuristics.md

## 场景与职责

本文档是 `babysit-pr` Skill 的决策逻辑参考，定义了 CI 失败分类、评论处理策略和停止条件的启发式规则。它是连接原始数据（CI 状态、评论内容）与具体行动（修复、重试、停止）的业务规则层。

职责定位：
- 为 AI Agent 提供可操作的判断准则
- 规范 CI 失败的分类标准（branch-related vs flaky）
- 定义评论处理的同意/拒绝标准
- 明确停止自动化的安全边界

## 功能点目的

### 1. CI 失败分类检查表

**目的**: 将 CI 失败归类为 "branch-related"（需要代码修复）或 "likely flaky/unrelated"（可以重试）

**Branch-related 特征**（需要本地修复）:
| 类型 | 示例 | 判断依据 |
|------|------|----------|
| 编译/类型检查失败 | `cargo build` 失败, `tsc` 错误 | 失败文件在 PR 修改范围内 |
| 确定性测试失败 | 单元测试、集成测试稳定失败 | 失败测试与修改模块相关 |
| Snapshot 变化 | UI 测试截图不匹配 | 文本/UI 变更是 PR 引入的 |
| 静态分析违规 | lint 错误、clippy warning | 违规代码由 PR 新增 |
| 构建配置错误 | `Cargo.toml` 语法错误 | 配置文件在 PR 中修改 |

**Flaky/Unrelated 特征**（可以重试）:
| 类型 | 示例 | 判断依据 |
|------|------|----------|
| 网络超时 | DNS 解析失败、registry 连接超时 | 错误信息包含 timeout、connection refused |
| Runner 问题 | 镜像配置失败、启动失败 | 日志显示 "runner" 相关错误 |
| GitHub 服务中断 | Actions 服务降级 | GitHub Status 页面确认 |
| 外部服务限流 | API rate limit、云服务中断 | 错误码 429、503 |
| 已知 flaky 测试 | 不稳定的集成测试 | 历史记录显示非确定性失败 |

**代码实现**: 这些规则在 `gh_pr_watch.py` 中通过 `recommend_actions()` 函数应用，但具体分类由上层 AI 根据日志内容判断。

### 2. 决策树（Decision Tree）

**目的**: 根据当前状态确定下一步行动

**决策流程**:
```
1. PR merged/closed?
   └─ Yes ──▶ STOP (stop_pr_closed)
   
2. Failed checks exist?
   ├─ Yes ──▶ Diagnose first
   │          ├─ Branch-related? ──▶ Fix locally, commit, push
   │          └─ Flaky/unrelated? ──▶ Check all terminal?
   │                                     ├─ Yes ──▶ Retry failed jobs
   │                                     └─ No  ──▶ Wait
   │
3. Flaky retry limit reached? (default: 3)
   └─ Yes ──▶ STOP (stop_exhausted_retries)
   
4. New review comments?
   └─ Yes ──▶ Process review comments

5. All green + no comments + mergeable?
   └─ Yes ──▶ STOP (stop_ready_to_merge)
```

**代码实现**: `gh_pr_watch.py:572-598` (`recommend_actions()`)

```python
def recommend_actions(pr, checks_summary, failed_runs, new_review_items, retries_used, max_retries):
    actions = []
    if pr["closed"] or pr["merged"]:
        actions.append("stop_pr_closed")
        return actions

    if is_pr_ready_to_merge(pr, checks_summary, new_review_items):
        actions.append("stop_ready_to_merge")
        return actions

    if new_review_items:
        actions.append("process_review_comment")

    if checks_summary["failed_count"] > 0:
        if checks_summary["all_terminal"] and retries_used >= max_retries:
            actions.append("stop_exhausted_retries")
        else:
            actions.append("diagnose_ci_failure")
            if checks_summary["all_terminal"] and failed_runs and retries_used < max_retries:
                actions.append("retry_failed_checks")

    if not actions:
        actions.append("idle")
    return actions
```

### 3. Review 评论同意标准

**目的**: 确定哪些评论需要自动处理，哪些应该忽略或询问用户

**应该处理的条件**（必须同时满足）:
1. **技术上正确**: 评论指出的问题确实存在
2. **可操作**: 可以在当前分支完成修改
3. **不冲突**: 与用户意图或近期指导不矛盾
4. **安全**: 修改范围可控，不会引入无关重构

**不应该自动处理的情况**:
| 情况 | 处理方式 |
|------|----------|
| 评论模糊需要澄清 | 记录为已处理，等待后续明确反馈 |
| 与用户明确指令冲突 | 停止并询问用户 |
| 需要产品/设计决策 | 停止并询问用户 |
| 工作区状态不确定 | 停止并询问用户 |

**代码实现**: 这些规则在 `gh_pr_watch.py` 中通过评论过滤实现：

```python
# 可信作者检查 (gh_pr_watch.py:458-465)
TRUSTED_AUTHOR_ASSOCIATIONS = {"OWNER", "MEMBER", "COLLABORATOR"}

def is_trusted_human_review_author(item, authenticated_login):
    author = str(item.get("author") or "")
    if authenticated_login and author == authenticated_login:
        return True
    association = str(item.get("author_association") or "").upper()
    return association in TRUSTED_AUTHOR_ASSOCIATIONS

# Bot 过滤 (gh_pr_watch.py:447-455)
REVIEW_BOT_LOGIN_KEYWORDS = {"codex"}

def is_actionable_review_bot_login(login):
    if not is_bot_login(login):
        return False
    return any(keyword in login.lower() for keyword in REVIEW_BOT_LOGIN_KEYWORDS)
```

### 4. 停止询问条件（Stop-and-Ask）

**目的**: 定义自动化边界，在不确定或危险情况下寻求人工干预

**必须停止的情况**:
| 条件 | 原因 |
|------|------|
| 工作区有无关未提交更改 | 避免污染 PR |
| `gh` 认证/权限失败 | 无法继续 GitHub 操作 |
| PR 分支无法推送 | 权限或保护规则问题 |
| CI 失败后重试预算耗尽 | 可能存在深层问题 |
| 需要产品决策的 reviewer 反馈 | 超出自动化范围 |

**代码实现**: 这些条件在 `recommend_actions()` 中部分体现：
- `stop_exhausted_retries`: 重试预算耗尽
- `stop_pr_closed`: PR 已关闭
- `stop_ready_to_merge`: 成功完成

其他条件（如工作区状态、权限）由上层 AI 在执行前检查。

## 具体技术实现

### 重试计数机制

```python
# gh_pr_watch.py:527-542
def current_retry_count(state, head_sha):
    retries = state.get("retries_by_sha") or {}
    value = retries.get(head_sha, 0)
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0

def set_retry_count(state, head_sha, count):
    retries = state.get("retries_by_sha")
    if not isinstance(retries, dict):
        retries = {}
    retries[head_sha] = int(count)
    state["retries_by_sha"] = retries
```

**关键设计**: 按 SHA 记录重试次数，新 commit 会重置计数

### PR 就绪检查

```python
# gh_pr_watch.py:554-569
MERGE_BLOCKING_REVIEW_DECISIONS = {"REVIEW_REQUIRED", "CHANGES_REQUESTED"}
MERGE_CONFLICT_OR_BLOCKING_STATES = {"BLOCKED", "DIRTY", "DRAFT", "UNKNOWN"}

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

### 自适应轮询策略

```python
# gh_pr_watch.py:747-781
def run_watch(args):
    poll_seconds = args.poll_seconds  # 默认 30s
    last_change_key = None
    while True:
        snapshot, state_path = collect_snapshot(args)
        # ... 输出 snapshot ...
        
        actions = set(snapshot.get("actions") or [])
        if {"stop_pr_closed", "stop_exhausted_retries", "stop_ready_to_merge"} & actions:
            print_event("stop", {...})
            return 0

        current_change_key = snapshot_change_key(snapshot)
        changed = current_change_key != last_change_key
        green = is_ci_green(snapshot)

        if not green:
            poll_seconds = args.poll_seconds  # 保持高频
        elif changed or last_change_key is None:
            poll_seconds = args.poll_seconds  # 有变化，重置
        else:
            poll_seconds = min(poll_seconds * 2, GREEN_STATE_MAX_POLL_SECONDS)  # 指数退避

        last_change_key = current_change_key
        time.sleep(poll_seconds)
```

## 关键代码路径与文件引用

| 功能 | 文件 | 行号 | 函数/代码块 |
|------|------|------|-------------|
| 行动推荐 | `gh_pr_watch.py` | 572-598 | `recommend_actions()` |
| PR 就绪检查 | `gh_pr_watch.py` | 554-569 | `is_pr_ready_to_merge()` |
| 重试计数 | `gh_pr_watch.py` | 527-542 | `current_retry_count()`, `set_retry_count()` |
| 评论过滤 | `gh_pr_watch.py` | 447-524 | `is_trusted_human_review_author()`, `fetch_new_review_items()` |
| 自适应轮询 | `gh_pr_watch.py` | 747-781 | `run_watch()` |
| 状态变更检测 | `gh_pr_watch.py` | 725-744 | `snapshot_change_key()` |
| 失败结论定义 | `gh_pr_watch.py` | 15-22 | `FAILED_RUN_CONCLUSIONS` |
| 合并阻塞状态 | `gh_pr_watch.py` | 42-47 | `MERGE_CONFLICT_OR_BLOCKING_STATES` |

## 依赖与外部交互

### 与 Skill 主文档的关联

```
SKILL.md (高层流程)
    │
    ├──▶ heuristics.md (本文档 - 决策规则)
    │         ├─ CI 分类标准
    │         ├─ 决策树
    │         ├─ 评论处理标准
    │         └─ 停止条件
    │
    └──▶ github-api-notes.md (底层命令)
              └─ gh 命令、API 端点、字段定义
```

### 与 watcher 脚本的交互

`gh_pr_watch.py` 将启发式规则编码为：
1. **常量定义**: 失败结论、阻塞状态、可信作者等集合
2. **判断函数**: `is_pr_ready_to_merge()`, `is_trusted_human_review_author()`
3. **决策函数**: `recommend_actions()` 返回 action 列表

上层 AI 根据返回的 actions 执行：
- `diagnose_ci_failure`: 调用 `gh run view --log-failed` 并应用 CI 分类规则
- `process_review_comment`: 应用评论同意标准决定是否修复
- `retry_failed_checks`: 调用 `gh run rerun --failed`
- `stop_*`: 终止监控

## 风险、边界与改进建议

### 风险

1. **误判 Branch-related 为 Flaky**
   - 风险: 导致无效重试，浪费时间和资源
   - 缓解: 要求 "logs clearly indicate"，不确定时先诊断一次

2. **误判 Flaky 为 Branch-related**
   - 风险: 在无辜代码上浪费修复时间
   - 缓解: 重试预算机制（3 次后停止）

3. **评论作者信任过于宽松**
   - 风险: 恶意或错误的 bot 评论被处理
   - 缓解: 只信任特定 bot（含 "codex" 关键词）

4. **自动修复引入新问题**
   - 风险: 修复 reviewer 评论时破坏其他功能
   - 缓解: 要求 "change can be made safely without unrelated refactors"

### 边界

1. **重试预算**
   - 默认 3 次，可配置但不可无限
   - 按 SHA 重置，新 commit 重新计数

2. **评论处理范围**
   - 只处理可信作者的评论
   - 已 resolved 的评论自动忽略
   - 首次启动时，已有评论会被视为 "new" 并处理

3. **合并检查**
   - 依赖 GitHub 的 `mergeable` 字段，可能有延迟
   - 不自动执行合并操作，只判断就绪状态

### 改进建议

1. **CI 分类机器学习**
   - 当前: 基于关键词和规则的启发式
   - 建议: 收集历史数据训练分类器，提高准确率

2. **评论情感分析**
   - 当前: 只基于作者身份过滤
   - 建议: 使用 NLP 识别建设性评论 vs 询问/讨论

3. **动态重试预算**
   - 当前: 固定 3 次
   - 建议: 根据失败类型、历史 flaky 率动态调整

4. **冲突检测增强**
   - 当前: 依赖 GitHub 的合并状态
   - 建议: 本地预检 `git merge-tree` 提前发现冲突

5. **评论线程追踪**
   - 当前: 按单个评论处理
   - 建议: 追踪评论线程，理解对话上下文

6. **可解释性日志**
   - 当前: 只输出最终 action
   - 建议: 记录每个决策的推理过程，便于调试
