# `.codex/skills` 目录研究（DIR）

## 场景与职责

`.codex/skills` 是仓库内（repo-scoped）的技能定义目录，主要承担两类职责：

1. 给 Codex 提供“可被识别并按规则执行”的本地技能包（以 `SKILL.md` 为入口）。
2. 把仓库运维流程沉淀为可复用操作协议（尤其是 PR 值守与 TUI 交互测试）。

当前目录下有两个技能：

- `babysit-pr`：持续监控并处理 GitHub PR 状态（CI、Review、mergeability）。
- `test-tui`：约束 Codex TUI 交互测试方法（启动参数、日志、输入节奏）。

从运行时看，它们并非孤立文档：会被 `codex-rs/core` 的 skills 子系统扫描、解析、渲染到 `<skills_instructions>`，并通过 `Op::ListSkills`/app-server `skills/list` 暴露给客户端。

## 功能点目的

### 1. `babysit-pr`（PR 自动值守技能）

目的：把“看一眼 PR 状态”升级为“持续值守直到终态”。

- 技能主文档定义了严格 stop condition、轮询节奏、重试预算、review 与 flaky retry 的优先级。
- `agents/openai.yaml` 提供面向 UI/agent 的接口元信息（显示名、短描述、默认提示词）。
- `scripts/gh_pr_watch.py` 提供机器可执行能力，输出标准化 JSON/JSONL 供 agent 循环消费。
- `references/heuristics.md` 与 `references/github-api-notes.md` 提供诊断准则与 GitHub CLI/API 字段映射，减少决策漂移。

### 2. `test-tui`（TUI 测试技能）

目的：统一 TUI 交互调试方法，降低“复现不一致”问题。

- 要求交互模式启动、固定 `RUST_LOG=trace`、明确 `log_dir` 输出。
- 强调“消息文本与 Enter 分开发送”，避免输入批处理导致测试行为偏差。

### 3. 目录级职责（`.codex/skills` 作为 repo 技能根）

目的：让仓库可自带技能，并与用户级/系统级技能一起参与技能集合。

- repo 工作区内技能可随代码版本演进，不依赖用户全局目录。
- 支持与 `$CODEX_HOME/skills`、`$HOME/.agents/skills`、`$CODEX_HOME/skills/.system` 协同。

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 技能加载主链路（从目录到会话）

1. 配置层识别项目 `.codex`
- `config_loader` 在 `cwd -> project_root` 及 repo root 路径寻找 `./.codex/config.toml`（可因 untrusted 而 disabled）。
- 对 skills 来说，这决定 repo 作用域技能根是否被纳入 roots 计算。

2. 技能根路径汇总
- `skills::loader::skill_roots` 组合 `Repo/User/System/Admin` roots。
- repo roots 既包含 `.codex/skills`，也包含 `.agents/skills`（位于 project root 与 cwd 之间的每层目录都可参与）。

3. 目录扫描与 `SKILL.md` 解析
- 固定入口文件：`SKILL.md`。
- 扫描约束：`MAX_SCAN_DEPTH=6`、每 root 最多扫描 `2000` 目录，避免极端目录树拖垮加载。
- 解析 frontmatter（`name/description/metadata.short-description`）并做长度与格式校验。
- 额外元数据从 `agents/openai.yaml` 读取（`interface/dependencies/policy/permissions`），失败时 fail-open（不阻断 `SKILL.md` 加载）。

4. 管理与缓存
- `SkillsManager` 按 config 语义缓存（`cache_by_config`）并按 cwd 缓存（`cache_by_cwd`）。
- `skills.config`（启停规则）会映射为 `disabled_paths` 并参与选择逻辑。
- `bundled` 关闭时过滤 system scope roots。

5. 会话注入与触发
- `render_skills_section` 将“技能清单 + 使用规则”注入 developer instructions。
- 显式触发：`$skill-name` 或结构化 `UserInput::Skill{name,path}`。
- 注入实现：`build_skill_injections` 读取对应 `SKILL.md`，封装为 `SkillInstructions` response item。
- 隐式触发统计：命令执行 `scripts/*` 或读取 `SKILL.md` 时，通过 `invocation_utils` 记录 implicit invocation telemetry。

### B. `.codex/skills/babysit-pr/scripts/gh_pr_watch.py` 关键机制

脚本是该目录最核心的执行体（805 行），本质是“PR 状态归一化 + 动作建议器 + 可选重试执行器”。

1. 三种运行模式
- `--once`：单次快照。
- `--watch`：持续 JSONL 流。
- `--retry-failed-now`：在策略允许时触发 failed jobs rerun。

2. 关键数据源
- `gh pr view --json ...`：PR 元数据（state/head SHA/mergeability/reviewDecision）。
- `gh pr checks --json ...`：检查项统计（pending/failed/passed）。
- `gh api repos/{owner}/{repo}/actions/runs?...`：workflow runs 级别失败定位。
- review 三路聚合：issue comments、review comments、review submissions。

3. 状态模型
- state 文件默认落盘 `/tmp/codex-babysit-pr-<repo>-pr<n>.json`。
- 保存字段包括：已见 review/comment id、每个 SHA 的 flaky 重试计数、last seen SHA。
- 通过原子写（临时文件 + `os.replace`）降低写入中断风险。

4. 动作决策
- `recommend_actions` 输出：`process_review_comment`、`diagnose_ci_failure`、`retry_failed_checks`、`stop_*`、`idle`。
- `is_pr_ready_to_merge` 同时约束：CI 全终态且无失败、无新 review item、`mergeable=MERGEABLE`、`merge_state_status` 非阻塞、`review_decision` 非阻塞。

5. 轮询策略
- 非绿态按基础间隔轮询。
- 绿态无变化采用指数退避，封顶 1h；任何状态变化都会重置到基础间隔。

### C. 协议与命令面

1. Core 协议
- `Op::ListSkills` -> `ListSkillsResponseEvent{skills}`。
- 每个技能项包含 `name/description/interface/dependencies/path/scope/enabled`。

2. app-server 协议
- `skills/list`：支持 `cwds`、`forceReload`、`perCwdExtraUserRoots`。
- `skills/changed`：文件变化失效通知，客户端需按自身参数重新调用 `skills/list`。
- `skills/config/write`：按 path 写入启停配置（`[[skills.config]]`）。

3. 本目录定义的操作命令
- `python3 .codex/skills/babysit-pr/scripts/gh_pr_watch.py --pr auto --watch`
- `python3 ... --once`
- `python3 ... --retry-failed-now`
- `just codex -c log_dir=<tmp> ...`（`test-tui` 推荐）。

## 关键代码路径与文件引用

### 目标目录本体

- `.codex/skills/babysit-pr/SKILL.md`
- `.codex/skills/babysit-pr/agents/openai.yaml`
- `.codex/skills/babysit-pr/references/heuristics.md`
- `.codex/skills/babysit-pr/references/github-api-notes.md`
- `.codex/skills/babysit-pr/scripts/gh_pr_watch.py`
- `.codex/skills/test-tui/SKILL.md`

### 调用方（谁消费 `.codex/skills`）

- `codex-rs/core/src/skills/loader.rs`
  - `skill_roots(...)`
  - `repo_agents_skill_roots(...)`
  - `discover_skills_under_root(...)`
- `codex-rs/core/src/skills/manager.rs`
  - `skills_for_config(...)`
  - `skills_for_cwd_with_extra_user_roots(...)`
- `codex-rs/core/src/codex.rs`
  - `render_skills_section(...)`
  - `collect_explicit_skill_mentions(...)`
  - `build_skill_injections(...)`
  - `handlers::list_skills(...)`
- `codex-rs/app-server/src/codex_message_processor.rs`
  - `skills_list(...)`
- `codex-rs/app-server/src/bespoke_event_handling.rs`
  - `EventMsg::SkillsUpdateAvailable -> skills/changed`

### 被调用方（`.codex/skills` 内脚本调用什么）

- `gh` CLI 与 GitHub REST API（在 `gh_pr_watch.py` 内通过 `subprocess` 统一封装）。

### 配置与策略关联

- `codex-rs/core/src/config/types.rs`
  - `SkillsConfig`（`bundled` + `config`）
  - `SkillConfig { path, enabled }`
- `codex-rs/core/src/config/edit.rs`
  - `ConfigEdit::SetSkillConfig`

### 测试与验证路径

- `codex-rs/core/src/skills/loader_tests.rs`
  - repo/user/system/admin roots
  - `.codex/skills` 发现与排序
  - symlink、深度限制、重复名/重复路径
- `codex-rs/core/src/skills/manager_tests.rs`
  - cache 行为
  - `bundled` 过滤
  - session flags 覆盖启停
- `codex-rs/core/src/skills/injection_tests.rs`
  - 显式 mention 解析、歧义处理、禁用路径过滤
- `codex-rs/core/src/skills/invocation_utils_tests.rs`
  - 隐式技能调用识别
- `codex-rs/core/tests/suite/skills.rs`
  - turn 注入与 skills list 集成
- `codex-rs/core/tests/suite/skill_approval.rs`
  - skill permissions 对执行审批/沙箱生效
- `codex-rs/app-server/tests/suite/v2/skills_list.rs`
  - `skills/list`、`perCwdExtraUserRoots`、`skills/changed`

### 文档与脚本

- `docs/skills.md`（当前仅外链说明）
- `codex-rs/app-server/README.md`（`skills/list` / `skills/changed` / `skills/config/write` 示例）

## 依赖与外部交互

### 内部依赖

- `codex-rs/core`：skills 发现、注入、权限合并、事件分发。
- `codex-rs/skills`：system bundled skills 安装到 `$CODEX_HOME/skills/.system`。
- `config_loader`：决定 `.codex` 层是否可用（受 trust 与 project_root_markers 影响）。
- `file_watcher`：监听 skills roots 变化，清缓存并发通知。

### 外部依赖

- `gh` CLI：`babysit-pr` 必需（缺失直接报错）。
- GitHub API：PR/checks/reviews/runs 查询与 rerun。
- Python 3：执行 watcher 脚本。
- 本地 FS：state 文件读写、`SKILL.md` 读取、watcher 路径监听。

### 协议交互

- Core 事件：`ListSkillsResponse`、`SkillsUpdateAvailable`。
- App-server v2：`skills/list` 请求与 `skills/changed` 通知。

## 风险、边界与改进建议

1. `gh_pr_watch.py` 自动测试覆盖不足
- 风险：动作判定逻辑（尤其 `recommend_actions`/retry）未来回归难及时发现。
- 建议：增加脚本层单元测试（mock gh 输出）与最小端到端回归样例。

2. 并发 watcher 的 state 文件竞争
- 风险：同 PR 多 watcher 共享默认 state 文件，可能互相覆盖 seen IDs / retry 计数。
- 建议：在默认命名中引入 session 后缀或提供文件锁。

3. review 作者信任模型边界
- 当前允许 OWNER/MEMBER/COLLABORATOR 与包含 `codex` 关键词的 bot。
- 风险：组织权限变化或 bot 命名碰撞可能带来误筛选。
- 建议：将可行动 bot allowlist 配置化，并在输出中标注过滤依据。

4. `skills/list` 缓存与 extra roots 的易错点
- 现状：同 cwd 若未 `forceReload`，可能继续返回旧缓存（即便传入不同 extra roots）。
- 风险：客户端误判“extra roots 无效”。
- 建议：在 API 文档与返回中增加 cache 命中提示，或将 extra roots 纳入缓存键。

5. `docs/skills.md` 信息密度低
- 风险：仓库内贡献者难从本地文档直接理解技能目录约定与运行时行为。
- 建议：补充最小本地规范（目录结构、`SKILL.md` frontmatter、`agents/openai.yaml`、测试建议、常见坑）。

6. repo 技能与用户/系统技能同名冲突的认知成本
- 现状：允许同名并通过路径/scope 区分，文本 mention 在歧义下会保守跳过。
- 建议：在 UI/CLI `skills/list` 输出中强化“同名冲突”提示，并鼓励使用结构化 `UserInput::Skill`（path 精确指定）。
