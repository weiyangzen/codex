# `.codex` 目录研究（DIR）

## 场景与职责

`.codex` 在本仓库中承担“仓库内本地技能包（repo-scoped skills）”的角色，供 Codex 运行时动态发现并注入到会话提示中。当前目录结构很小但职责明确：

- `.codex/skills/babysit-pr/`：PR 值守（CI/Review/可合并性）自动化技能。
- `.codex/skills/test-tui/`：TUI 交互验证操作约定技能。

它不是 Rust 主业务代码目录，但会被 `codex-rs/core` 的技能发现链路加载，并影响：

1. 会话中的“可用技能列表”渲染与提示注入。
2. 用户显式/隐式技能触发行为。
3. app-server `skills/list` / `skills/changed` 对外协议输出。

关键入口：

- 技能目录扫描：`codex-rs/core/src/skills/loader.rs:218,231,309,388`
- `.codex` 配置层加载：`codex-rs/core/src/config_loader/mod.rs:102-103,114,792,819`
- 技能提示渲染：`codex-rs/core/src/skills/render.rs:5`

## 功能点目的

### 1) `babysit-pr` 技能

目标：把“PR 持续值守”从一次性查询变成持续循环流程（监控 -> 诊断 -> 修复/重试 -> 继续监控），直到严格终止条件达成。

- 技能定义与流程规范：`.codex/skills/babysit-pr/SKILL.md:1-185`
- UI/agent 卡片元信息与默认 prompt：`.codex/skills/babysit-pr/agents/openai.yaml:1-4`
- 决策参考：
  - `.codex/skills/babysit-pr/references/heuristics.md:1-58`
  - `.codex/skills/babysit-pr/references/github-api-notes.md:1-72`
- 可执行 watcher：`.codex/skills/babysit-pr/scripts/gh_pr_watch.py`

### 2) `test-tui` 技能

目标：给 TUI 交互测试提供统一、可复现的操作细则，避免调试时日志/输入时序不一致。

- 定义：`.codex/skills/test-tui/SKILL.md:1-14`
- 约束包括：`RUST_LOG=trace`、`-c log_dir=...`、输入与 Enter 分开发送。

### 3) `.codex` 作为 repo 技能根目录

目标：为当前仓库提供随代码同行的技能能力，不依赖用户全局目录。

- repo 层根路径识别与扫描：`.codex/skills`（由 loader 从项目配置层推导）
- 与 `~/.agents/skills`、`$CODEX_HOME/skills/.system` 共存并按 scope 排序。

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 技能发现与注入主流程

1. 配置层解析 `.codex`
- `load_config_layers_state` 会加载 cwd 到 project root 间各层 `.codex/config.toml`：`codex-rs/core/src/config_loader/mod.rs:102-103,114,205,243,792,819`
- project trust 不满足时层会保留但 disabled：`.../config_loader/mod.rs:599,633,663`

2. 计算 skills roots
- `skill_roots()` 组合 repo/user/system/admin roots：`codex-rs/core/src/skills/loader.rs:218-243`
- repo roots 包含 `.codex/skills` 与 `.agents/skills`：`.../loader.rs:309-320`

3. 扫描并解析 `SKILL.md`
- 遍历规则：`SKILL.md` 文件名固定、最大深度 6、最多 2000 目录：`.../loader.rs:133,149-150,388-521`
- Frontmatter 解析与校验：`.../loader.rs:527-600`
- 可选元数据 `agents/openai.yaml` 解析（interface/dependencies/policy/permissions）：`.../loader.rs:602-652,693-759`

4. 会话注入
- 会话启动加载技能：`codex-rs/core/src/codex.rs:441`
- 生成 `<skills_instructions>` 段落：`codex-rs/core/src/skills/render.rs:5-46`
- 常量标签定义：`codex-rs/protocol/src/protocol.rs:90-91`

5. 显式与隐式触发
- 显式：`$skill-name`、`UserInput::Skill{name,path}` 解析：`codex-rs/core/src/skills/injection.rs:100,235`
- `UserInput::Skill` 协议形态：`codex-rs/protocol/src/user_input.rs:30-35`
- 隐式：执行 `scripts/*.py|sh|...` 或读取 `SKILL.md` 时记录技能调用：`codex-rs/core/src/skills/invocation_utils.rs:13,56,177,204`

### B. 变更监听与缓存失效

- 线程启动时注册技能根目录 watcher：`codex-rs/core/src/thread_manager.rs:754`
- 文件事件节流聚合后发 `SkillsChanged`：`codex-rs/core/src/file_watcher.rs:42,146,193,314`
- 收到事件后清理 skills 缓存：`codex-rs/core/src/thread_manager.rs:104`
- 会话侧转发 `EventMsg::SkillsUpdateAvailable`：`codex-rs/core/src/codex.rs:1271-1277`
- app-server 再映射为 `skills/changed`：`codex-rs/app-server/src/bespoke_event_handling.rs:303-307`

### C. `babysit-pr` watcher 脚本核心机制

脚本：`.codex/skills/babysit-pr/scripts/gh_pr_watch.py`（805 行）

1. 输入模式
- `--once`、`--watch`、`--retry-failed-now`：`gh_pr_watch.py:55-93,785-793`

2. 采样数据源
- PR 元信息：`resolve_pr()` -> `gh pr view`：`gh_pr_watch.py:157`
- 检查项：`get_pr_checks()`：`gh_pr_watch.py:265`
- 工作流运行：`get_workflow_runs_for_sha()`：`gh_pr_watch.py:305`
- 评论/Review 聚合：`fetch_new_review_items()`：`gh_pr_watch.py:468`

3. 行为决策
- 终止/重试/诊断动作生成：`recommend_actions()`：`gh_pr_watch.py:572`
- “可合并”判定含 mergeable、merge_state_status、review_decision：`gh_pr_watch.py:553-569`

4. 状态持久化
- 默认 state 文件：`/tmp/codex-babysit-pr-<repo>-pr<n>.json`：`gh_pr_watch.py:260-263`
- 原子写 state：`save_state()`：`gh_pr_watch.py:243`

5. 重试与轮询策略
- flaky retry 上限（默认 3）：`parse_args` 与 `retry_failed_now`：`gh_pr_watch.py:64-69,652`
- 绿色态指数退避，上限 1h：`gh_pr_watch.py:48,747-780`

### D. app-server 协议与命令面

- `skills/list` 参数含 `cwds`、`forceReload`、`perCwdExtraUserRoots`：
  - 协议定义：`codex-rs/app-server-protocol/src/protocol/v2.rs:3065-3092`
  - 处理逻辑：`codex-rs/app-server/src/codex_message_processor.rs:5385-5454`
- `skills/changed` 通知定义：`.../v2.rs:4654-4656`
- README 对外示例：`codex-rs/app-server/README.md:1092-1146`

## 关键代码路径与文件引用

### `.codex` 目录自身

- `.codex/skills/babysit-pr/SKILL.md`
- `.codex/skills/babysit-pr/agents/openai.yaml`
- `.codex/skills/babysit-pr/references/heuristics.md`
- `.codex/skills/babysit-pr/references/github-api-notes.md`
- `.codex/skills/babysit-pr/scripts/gh_pr_watch.py`
- `.codex/skills/test-tui/SKILL.md`

### 上游调用方（who calls `.codex`）

- `.codex` 配置层发现：`codex-rs/core/src/config_loader/mod.rs:102-103,114,792,819`
- skills roots 构造：`codex-rs/core/src/skills/loader.rs:218-243,309-320`
- skills 扫描与解析：`codex-rs/core/src/skills/loader.rs:388-652`
- 会话注入：`codex-rs/core/src/codex.rs:441,3492`
- app-server 列举：`codex-rs/app-server/src/codex_message_processor.rs:5385-5454`

### 下游被调用方（`.codex` calls what）

- `babysit-pr` 调用 GitHub CLI/API：`gh_pr_watch.py:100-124,305-317,652-700`
- `test-tui` 依赖 `just codex` 运行流程：`.codex/skills/test-tui/SKILL.md:14`

### 关键测试

- `.codex` skills root 解析与优先级：`codex-rs/core/src/skills/loader_tests.rs:144-193,1575-1754`
- `.codex` project layer 加载顺序/信任行为：`codex-rs/core/src/config_loader/tests.rs:768-811,910-939,1334-1384`
- watcher 对 `.codex/skills` 路径判定：`codex-rs/core/src/file_watcher_tests.rs:79-95`
- 显式技能解析与隐式调用：
  - `codex-rs/core/src/skills/injection_tests.rs:82-336`
  - `codex-rs/core/src/skills/invocation_utils_tests.rs:1-119`

## 依赖与外部交互

### 运行时依赖

- GitHub CLI：`babysit-pr` 强依赖 `gh`（无则报错）`gh_pr_watch.py:114-124`
- Python 3：脚本 shebang 与命令示例依赖 `python3`
- 本地文件系统：`/tmp` state 文件持久化

### 与 core/skills 子系统耦合

- 技能结构契约：必须有 `SKILL.md`，可选 `agents/openai.yaml`
- 技能配置依赖：
  - `[skills.bundled]`、`[[skills.config]]`：`codex-rs/core/src/config/types.rs:813-831`
- bundled system skills 与 repo skills 共存：
  - system skills 安装目标 `$CODEX_HOME/skills/.system`：`codex-rs/skills/src/lib.rs:22,47`

### 与 app-server/协议交互

- 客户端通过 `skills/list` 获取技能元信息、enabled 状态与错误列表。
- 文件变更触发 `skills/changed`，客户端需自行重新拉取。

### 与仓库运维脚本交互

- `.ops/research_guard.sh` 会自动读取 checklist 首个 pending 项，拼装任务并用 `codex --yolo exec` 执行：`.ops/research_guard.sh:140-212`
- `.ops/generate_daily_research_todo.sh` 从 checklist 生成当日待办：`.ops/generate_daily_research_todo.sh:15-42`

## 风险、边界与改进建议

1. 测试覆盖边界
- `gh_pr_watch.py` 当前未在仓库内发现直接自动化测试（仅有技能文本和参考文档）。
- 建议：为脚本增加最小单测（参数解析、action 判定、state 文件并发/损坏处理）。

2. 并发与状态文件冲突
- 默认 state 文件按 repo+PR 固定命名，多个 watcher 并行执行同一 PR 时可能互相覆盖。
- 建议：增加可选 session suffix 或文件锁策略。

3. bot 过滤策略可能误判
- action bot 判定依赖 `login` 包含 `codex` 关键词：`gh_pr_watch.py:30,455`。
- 风险：漏掉合法 bot 或引入同名噪声 bot。
- 建议：引入更明确 allowlist（可配置）与 repo 级策略。

4. 信任模型与可见性
- `.codex/config.toml` 在 untrusted project 中会被加载为 disabled layer，不会生效（但存在于栈中）。
- 建议：在 CLI/TUI 明确展示“已发现但因信任策略禁用”的技能来源，降低排障成本。

5. `test-tui` 技能信息偏轻
- 当前只有操作提示，无脚本化入口或验证 checklist。
- 建议：补 `scripts/`（例如自动启动+消息注入+日志抓取）并在 `SKILL.md` 中声明。

6. 文档一致性风险
- `SKILL.md`、`openai.yaml`、脚本实现三处需同步；目前主要依赖人工维护。
- 建议：新增 CI lint（校验 `default_prompt` 与技能目标关键词、命令存在性、引用文件有效性）。

