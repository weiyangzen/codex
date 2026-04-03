# .codex/skills 目录深度研究文档

## 目录结构概览

```
.codex/skills/
├── babysit-pr/              # PR 监控与自动修复技能
│   ├── SKILL.md            # 技能定义与使用指南
│   ├── agents/
│   │   └── openai.yaml     # UI 元数据配置
│   ├── references/         # 参考文档
│   │   ├── github-api-notes.md
│   │   └── heuristics.md
│   └── scripts/
│       └── gh_pr_watch.py  # 核心监控脚本
└── test-tui/               # TUI 测试技能
    └── SKILL.md            # 技能定义
```

---

## 一、场景与职责

### 1.1 定位与用途

`.codex/skills` 目录是 **Codex 项目级技能（Repo-scoped Skills）** 的存储位置，用于存放与特定代码仓库绑定的领域知识、工作流和工具脚本。这些技能仅在该仓库内可用，不会被其他项目继承。

### 1.2 核心职责

| 技能名称 | 职责描述 | 触发场景 |
|---------|---------|---------|
| `babysit-pr` | 持续监控 GitHub PR 的 CI 状态、审查评论和合并不冲突状态，自动诊断失败、重试 flaky 测试、处理审查反馈 | 用户要求"监控 PR"、"看护 PR"、"处理审查评论" |
| `test-tui` | 指导如何交互式测试 Codex TUI（终端用户界面） | 需要手动验证 TUI 功能时 |

### 1.3 与系统技能的关系

- **系统技能**（`codex-rs/skills/src/assets/samples/`）：随 Codex 二进制分发，所有项目可用
- **用户技能**（`~/.codex/skills/` 或 `~/.agents/skills`）：用户级全局技能
- **项目技能**（`.codex/skills/`）：当前仓库专属技能（本研究对象）

---

## 二、功能点目的

### 2.1 babysit-pr 技能

#### 2.1.1 目标
实现 PR 全生命周期的自动化看护，减少人工干预，提高合并效率。

#### 2.1.2 核心功能

1. **CI 状态监控**
   - 轮询 GitHub Actions 检查状态
   - 区分 pending/running/queued/failed/passed 状态
   - 自适应轮询频率（失败时 1 分钟，成功后指数退避至 1 小时）

2. **失败诊断与分类**
   - 分支相关失败：编译错误、测试失败、lint 错误等代码问题
   - Flaky/外部失败：网络超时、runner 故障、基础设施问题
   - 自动提取失败日志进行分析

3. **自动修复**
   - 分支相关失败：本地修复 → 提交 → 推送
   - Flaky 失败：自动重试（最多 3 次）

4. **审查评论处理**
   - 监控新的 issue comments、inline review comments、review submissions
   - 信任作者过滤（OWNER/MEMBER/COLLABORATOR + 当前用户 + Codex bot）
   - 可操作的评论自动修复

5. **合并就绪检测**
   - CI 全绿
   - 无未处理的审查评论
   - 无合并冲突（mergeable 状态）
   - 非 DRAFT 状态

#### 2.1.3 终止条件

| 条件类型 | 说明 |
|---------|------|
| PR merged/closed | PR 已合并或关闭 |
| Ready to merge | CI 成功 + 审查干净 + 可合并 |
| 需要用户帮助 | 基础设施问题、重试用尽、权限问题、模糊请求 |

### 2.2 test-tui 技能

#### 2.2.1 目标
提供 TUI 交互式测试的标准流程，确保测试环境一致性。

#### 2.2.2 核心要点
- 始终使用 `RUST_LOG="trace"` 启动
- 使用 `-c log_dir=<temp_dir>` 指定日志目录
- 程序化发送消息时，文本和 Enter 分开发送
- 使用 `just codex` 目标运行

---

## 三、具体技术实现

### 3.1 技能文件格式（SKILL.md）

所有技能遵循标准格式：

```yaml
---
name: skill-name
description: 技能描述，包含功能说明和触发条件
metadata:
  short-description: 简短描述（可选）
---

# 技能标题

## 章节内容
...
```

### 3.2 babysit-pr 技术实现

#### 3.2.1 核心脚本架构（gh_pr_watch.py）

**命令行接口：**
```python
parser.add_argument("--pr", default="auto", help="auto, PR number, or PR URL")
parser.add_argument("--repo", help="Optional OWNER/REPO override")
parser.add_argument("--poll-seconds", type=int, default=30)
parser.add_argument("--max-flaky-retries", type=int, default=3)
parser.add_argument("--state-file", help="Path to state JSON file")
parser.add_argument("--once", action="store_true")      # 单次快照
parser.add_argument("--watch", action="store_true")     # 持续监控
parser.add_argument("--retry-failed-now", action="store_true")  # 立即重试
```

**状态管理：**
```python
state = {
    "pr": {},
    "started_at": None,
    "last_seen_head_sha": None,
    "retries_by_sha": {},        # 每个 SHA 的重试次数
    "seen_issue_comment_ids": [],
    "seen_review_comment_ids": [],
    "seen_review_ids": [],
    "last_snapshot_at": None,
}
```

**关键数据结构：**

1. **PR 信息**（`resolve_pr`）
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
       "mergeable": str,          # MERGEABLE, CONFLICTING, etc.
       "merge_state_status": str,
       "review_decision": str,    # APPROVED, CHANGES_REQUESTED, etc.
   }
   ```

2. **检查摘要**（`summarize_checks`）
   ```python
   {
       "pending_count": int,
       "failed_count": int,
       "passed_count": int,
       "all_terminal": bool,      # 是否所有检查都已结束
   }
   ```

3. **失败运行**（`failed_runs_from_workflow_runs`）
   ```python
   {
       "run_id": int,
       "workflow_name": str,
       "status": str,
       "conclusion": str,         # failure, timed_out, cancelled, etc.
       "html_url": str,
   }
   ```

4. **审查项目**（`fetch_new_review_items`）
   ```python
   {
       "kind": "issue_comment" | "review_comment" | "review",
       "id": str,
       "author": str,
       "author_association": str,  # OWNER, MEMBER, COLLABORATOR
       "created_at": str,
       "body": str,
       "path": str | None,         # 文件路径（inline comment）
       "line": int | None,         # 行号（inline comment）
       "url": str,
   }
   ```

5. **推荐动作**（`recommend_actions`）
   - `idle`: 等待中
   - `diagnose_ci_failure`: 诊断 CI 失败
   - `retry_failed_checks`: 重试失败检查
   - `process_review_comment`: 处理审查评论
   - `stop_pr_closed`: PR 已关闭，停止
   - `stop_ready_to_merge`: 可合并，停止
   - `stop_exhausted_retries`: 重试用尽，停止

#### 3.2.2 GitHub API 调用

| 用途 | 命令 |
|-----|------|
| PR 元数据 | `gh pr view --json number,url,state,mergedAt,closedAt,headRefName,headRefOid,...` |
| 检查状态 | `gh pr checks --json name,state,bucket,link,workflow,...` |
| 工作流运行 | `gh api repos/{owner}/{repo}/actions/runs -f head_sha=<sha>` |
| 失败日志 | `gh run view <run-id> --log-failed` |
| 重试失败 | `gh run rerun <run-id> --failed` |
| Issue 评论 | `gh api repos/{owner}/{repo}/issues/<pr>/comments` |
| Review 评论 | `gh api repos/{owner}/{repo}/pulls/<pr>/comments` |
| Review 提交 | `gh api repos/{owner}/{repo}/pulls/<pr>/reviews` |
| 当前用户 | `gh api user` |

#### 3.2.3 轮询策略

```python
GREEN_STATE_MAX_POLL_SECONDS = 60 * 60  # 1 小时上限

def run_watch(args):
    poll_seconds = args.poll_seconds
    last_change_key = None
    while True:
        snapshot, state_path = collect_snapshot(args)
        # 输出 JSONL 格式事件
        print_event("snapshot", {...})
        
        # 检查终止条件
        if stop_condition_met(actions):
            print_event("stop", {...})
            return 0
        
        # 自适应轮询间隔
        if not green:
            poll_seconds = args.poll_seconds  # 重置为 1 分钟
        elif changed:
            poll_seconds = args.poll_seconds  # 有变化，重置
        else:
            poll_seconds = min(poll_seconds * 2, GREEN_STATE_MAX_POLL_SECONDS)
        
        time.sleep(poll_seconds)
```

#### 3.2.4 变化检测键

```python
def snapshot_change_key(snapshot):
    return (
        head_sha,
        pr_state,
        mergeable,
        merge_state_status,
        review_decision,
        passed_count,
        failed_count,
        pending_count,
        tuple((item_kind, item_id) for item in new_review_items),
        tuple(actions),
    )
```

### 3.3 技能加载系统（Rust 实现）

#### 3.3.1 技能扫描路径

```rust
// 优先级从高到低
1. Repo 技能: 项目根目录/.codex/skills/
2. 用户技能: ~/.codex/skills/
3. 用户技能: ~/.agents/skills/
4. 系统技能: ~/.codex/skills/.system/  (嵌入式缓存)
5. Admin 技能: /etc/codex/skills/
```

#### 3.3.2 技能加载流程（loader.rs）

```rust
pub(crate) fn load_skills_from_roots(roots: I) -> SkillLoadOutcome {
    // 1. 遍历每个根目录
    // 2. BFS 扫描（最大深度 6，最大目录数 2000）
    // 3. 解析 SKILL.md 文件
    // 4. 去重（按路径）
    // 5. 排序（按 scope 优先级 + 名称）
}
```

#### 3.3.3 SKILL.md 解析

```rust
fn parse_skill_file(path: &Path, scope: SkillScope) -> Result<SkillMetadata, SkillParseError> {
    // 1. 读取文件内容
    // 2. 提取 YAML frontmatter（--- 包围的部分）
    // 3. 解析 frontmatter: name, description, metadata.short-description
    // 4. 加载 agents/openai.yaml 元数据（可选）
    // 5. 验证字段长度限制
    // 6. 返回 SkillMetadata
}
```

#### 3.3.4 技能元数据结构

```rust
pub struct SkillMetadata {
    pub name: String,                    // 技能名称（64 字符限制）
    pub description: String,             // 描述（1024 字符限制）
    pub short_description: Option<String>,
    pub interface: Option<SkillInterface>,   // UI 元数据
    pub dependencies: Option<SkillDependencies>,  // 工具依赖
    pub policy: Option<SkillPolicy>,     // 调用策略
    pub permission_profile: Option<PermissionProfile>,  // 权限配置
    pub managed_network_override: Option<SkillManagedNetworkOverride>,
    pub path_to_skills_md: PathBuf,      // SKILL.md 路径
    pub scope: SkillScope,               // Repo/User/System/Admin
}
```

### 3.4 技能注入与触发

#### 3.4.1 显式触发

用户在输入中 `@skill-name` 显式引用技能。

#### 3.4.2 隐式触发

```rust
// invocation_utils.rs
pub(crate) fn maybe_emit_implicit_skill_invocation(
    path: &Path,
    outcome: &SkillLoadOutcome,
) -> Option<SkillMetadata> {
    // 1. 检查路径是否匹配技能的 scripts/ 目录
    // 2. 检查技能是否允许隐式调用（policy.allow_implicit_invocation）
    // 3. 返回匹配的技能元数据
}
```

#### 3.4.3 技能注入（injection.rs）

```rust
pub(crate) fn build_skill_injections(
    skills: &[SkillMetadata],
) -> SkillInjections {
    // 构建技能描述文本，注入到系统提示中
}
```

---

## 四、关键代码路径与文件引用

### 4.1 技能定义文件

| 文件 | 用途 |
|-----|------|
| `.codex/skills/babysit-pr/SKILL.md` | PR 看护技能定义（185 行） |
| `.codex/skills/babysit-pr/agents/openai.yaml` | UI 元数据（显示名称、默认提示） |
| `.codex/skills/babysit-pr/references/heuristics.md` | CI 分类启发式规则 |
| `.codex/skills/babysit-pr/references/github-api-notes.md` | GitHub API 使用笔记 |
| `.codex/skills/babysit-pr/scripts/gh_pr_watch.py` | 核心监控脚本（805 行） |
| `.codex/skills/test-tui/SKILL.md` | TUI 测试技能定义（14 行） |

### 4.2 Rust 技能系统实现

| 文件 | 用途 |
|-----|------|
| `codex-rs/core/src/skills/mod.rs` | 技能模块导出 |
| `codex-rs/core/src/skills/loader.rs` | 技能加载与解析（926 行） |
| `codex-rs/core/src/skills/model.rs` | 数据模型定义（117 行） |
| `codex-rs/core/src/skills/manager.rs` | 技能管理器（347 行） |
| `codex-rs/core/src/skills/injection.rs` | 技能注入系统 |
| `codex-rs/core/src/skills/invocation_utils.rs` | 隐式调用检测 |
| `codex-rs/core/src/skills/system.rs` | 系统技能安装/卸载 |
| `codex-rs/skills/src/lib.rs` | 嵌入式系统技能（195 行） |

### 4.3 协议定义

| 文件 | 用途 |
|-----|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | SkillsList、SkillMetadata、SkillSummary 等类型定义 |
| `codex-rs/protocol/src/protocol.rs` | 核心协议类型 |

---

## 五、依赖与外部交互

### 5.1 外部依赖

| 依赖 | 用途 |
|-----|------|
| `gh` (GitHub CLI) | babysit-pr 脚本的核心依赖，用于所有 GitHub 操作 |
| Python 3 | babysit-pr 脚本的运行环境 |
| `serde_yaml` | Rust 中解析 SKILL.md frontmatter |
| `toml` | 解析技能配置 |
| `include_dir` | 嵌入式系统技能 |

### 5.2 与其他模块的交互

```
.codex/skills/
    │
    ├──► gh_pr_watch.py ──► GitHub API (gh CLI)
    │
    ├──► SKILL.md ──► codex-rs/core/src/skills/loader.rs
    │                      │
    │                      ├──► model.rs (数据结构)
    │                      ├──► manager.rs (缓存管理)
    │                      ├──► injection.rs (提示注入)
    │                      └──► invocation_utils.rs (隐式调用)
    │
    └──► agents/openai.yaml ──► TUI 技能列表 UI
```

### 5.3 配置交互

技能系统读取以下配置：

```toml
[skills]
bundled.enabled = true  # 是否启用系统技能

[[skills.config]]
path = "/path/to/skill"
enabled = false  # 禁用特定技能
```

---

## 六、风险、边界与改进建议

### 6.1 风险分析

#### 6.1.1 babysit-pr 风险

| 风险 | 严重程度 | 说明 |
|-----|---------|------|
| 无限循环 | 中 | 如果 CI 持续失败且被误判为 flaky，可能浪费 Action 分钟数 |
| 误修复 | 高 | 自动修复可能引入新问题，特别是当失败分类错误时 |
| 权限问题 | 中 | `gh` CLI 需要适当的认证，脚本可能因权限失败 |
| 状态文件损坏 | 低 | `/tmp/codex-babysit-pr-*.json` 损坏可能导致状态丢失 |
| 竞态条件 | 中 | 多进程同时操作同一 PR 可能导致冲突 |

#### 6.1.2 技能系统风险

| 风险 | 严重程度 | 说明 |
|-----|---------|------|
| 路径遍历 | 低 | 技能路径验证已实施，但需持续审查 |
| 恶意技能 | 中 | 项目技能可被任何有写权限的人修改，需代码审查 |
| 缓存不一致 | 低 | 技能缓存可能未及时更新，force_reload 参数可缓解 |

### 6.2 边界条件

#### 6.2.1 babysit-pr 边界

```python
# 扫描限制
MAX_SCAN_DEPTH = 6                    # 技能扫描最大深度
MAX_SKILLS_DIRS_PER_ROOT = 2000       # 每个根目录最大目录数

# 字段长度限制
MAX_NAME_LEN = 64
MAX_DESCRIPTION_LEN = 1024
MAX_SHORT_DESCRIPTION_LEN = 1024
MAX_DEFAULT_PROMPT_LEN = 1024

# 轮询限制
GREEN_STATE_MAX_POLL_SECONDS = 3600   # 最大轮询间隔 1 小时
DEFAULT_MAX_FLAKY_RETRIES = 3         # 默认最大重试次数

# 信任作者
TRUSTED_AUTHOR_ASSOCIATIONS = {"OWNER", "MEMBER", "COLLABORATOR"}
REVIEW_BOT_LOGIN_KEYWORDS = {"codex"}
```

#### 6.2.2 技能加载边界

- 最大扫描深度：6 层
- 最大目录数：2000 个/根目录
- 符号链接：User/Repo/Admin 技能跟随，System 技能不跟随
- 隐藏文件/目录（以 `.` 开头）：跳过

### 6.3 改进建议

#### 6.3.1 babysit-pr 改进

1. **增强失败分类**
   - 引入机器学习模型或更复杂的启发式规则来区分分支相关失败和 flaky 失败
   - 维护 flaky 测试的历史数据库

2. **并发控制**
   - 添加文件锁防止多进程同时操作同一 PR
   - 支持多 PR 同时监控（当前设计是单 PR）

3. **通知机制**
   - 集成 Slack/Discord/Webhook 通知
   - 长时间无变化时发送心跳通知

4. **配置化**
   - 支持 `.codex/babysit-pr.toml` 配置文件
   - 允许自定义重试次数、轮询间隔、终止条件

5. **安全性增强**
   - 添加 `--dry-run` 模式，预览操作而不执行
   - 敏感操作（如 push）需要额外确认

#### 6.3.2 技能系统改进

1. **热重载**
   - 文件系统监听，SKILL.md 修改后自动重载
   - 当前已实现 `SkillsChangedNotification`，但可优化实时性

2. **技能版本控制**
   - 支持技能版本声明和兼容性检查
   - 依赖解析（技能 A 依赖技能 B）

3. **技能测试框架**
   - 提供技能单元测试工具
   - 验证 frontmatter 格式、元数据完整性

4. **性能优化**
   - 大型仓库的技能扫描优化（并行化、增量扫描）
   - 缓存持久化（当前仅内存缓存）

5. **文档生成**
   - 从 SKILL.md 自动生成用户文档
   - 技能使用统计和效果分析

---

## 七、附录

### 7.1 关键命令速查

```bash
# babysit-pr 单次快照
python3 .codex/skills/babysit-pr/scripts/gh_pr_watch.py --pr auto --once

# babysit-pr 持续监控
python3 .codex/skills/babysit-pr/scripts/gh_pr_watch.py --pr auto --watch

# babysit-pr 立即重试失败
python3 .codex/skills/babysit-pr/scripts/gh_pr_watch.py --pr auto --retry-failed-now

# 查看失败日志
gh run view <run-id> --log-failed
```

### 7.2 状态文件位置

```
/tmp/codex-babysit-pr-{REPO}-pr{NUMBER}.json
```

### 7.3 相关文档链接

- 项目级技能规范：`docs/skills.md`（指向外部文档）
- 技能创建指南：`codex-rs/skills/src/assets/samples/skill-creator/SKILL.md`
- 技能安装指南：`codex-rs/skills/src/assets/samples/skill-installer/SKILL.md`
- AGENTS.md 规范：`docs/agents_md.md`

---

*文档生成时间：2026-03-22*
*研究范围：.codex/skills/ 目录及其相关实现*
