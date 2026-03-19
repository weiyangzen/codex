# DIR `.codex/skills/babysit-pr` 研究报告

- 研究对象：`/home/sansha/Github/codex/.codex/skills/babysit-pr`
- 研究日期：2026-03-19
- 研究类型：目录级（DIR）深度研究

## 场景与职责

`babysit-pr` 是一个“持续值守 Pull Request”技能包，不是单次诊断脚本。它的职责是把“看一眼 CI 状态”升级为“持续跟进到终态（可合并/已关闭/需要人介入）”。

该目录由 5 个部分协作构成：

1. `SKILL.md`
- 定义值守目标、严格 stop 条件、轮询节奏、review 与 flaky retry 的优先级、以及执行中的 git 安全规则。
- 规定“监控任务默认使用 `--watch` 且不中断地持续消费输出”，强调“push 后必须在同一轮会话立即重启 watch”。

2. `scripts/gh_pr_watch.py`
- 提供可执行的状态归一化与动作建议能力，输出机器可读 JSON/JSONL。
- 同时支持即时触发 failed jobs rerun（`--retry-failed-now`）。

3. `references/heuristics.md`
- 给出 CI 失败分类（branch-related vs flaky/unrelated）与 stop-and-ask 决策树。

4. `references/github-api-notes.md`
- 给出 watcher 依赖的 `gh` 命令与 API 字段映射，降低诊断时的命令漂移。

5. `agents/openai.yaml`
- 定义展示名、简述、默认提示词，确保 agent 侧行为与 `SKILL.md` 的“单 watcher + 持续轮询”一致。

目录在系统中的位置是“技能实现层”：被 core skills 子系统加载并暴露给会话；实际执行中再由 `gh_pr_watch.py` 对接 GitHub CLI/API。

## 功能点目的

从目标目录视角，核心功能点与目的如下：

1. PR 状态标准化快照（`--once`）
- 把 PR 元数据、检查状态、失败 workflow run、review 增量、重试计数合并成一个统一 JSON 结构，供 agent 决策。

2. 连续监控流（`--watch`）
- 按轮询间隔持续产出 `snapshot` 事件，并在命中严格终态时输出 `stop` 事件后退出。
- 在 CI 全绿且状态无变化时做指数退避，降低无效轮询频率。

3. 失败重试执行（`--retry-failed-now`）
- 在满足策略条件（当前 SHA、检查终态、未超预算）时仅 rerun failed jobs。
- 记录每个 SHA 的重试次数，避免无限重试。

4. Review 增量发现与去重
- 聚合 issue comments / review comments / reviews 三路反馈。
- 基于可信作者规则筛选，且通过 state 文件持久化“已见 comment/review ID”实现增量处理。

5. 动作建议器（`actions`）
- 输出 `process_review_comment`、`diagnose_ci_failure`、`retry_failed_checks`、`stop_*` 或 `idle`。
- 将“是否该停、该修、该重试”从自然语言流程下沉为稳定机读协议。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 运行模式与参数协议

脚本入口：`.codex/skills/babysit-pr/scripts/gh_pr_watch.py`

参数解析由 `parse_args()` 完成，关键约束：

- `--pr` 支持 `auto` / PR 编号 / PR URL。
- 运行模式三选：
  - `--once`
  - `--watch`
  - `--retry-failed-now`
- `--watch` 与 `--retry-failed-now` 互斥。
- 未显式指定模式时默认 `--once`。
- `--max-flaky-retries` 默认 3，`--poll-seconds` 默认 30。

### 2) PR 解析与仓库定位

关键函数：

- `parse_pr_spec()`：识别 `auto`、数字、URL。
- `resolve_pr()`：
  - 调 `gh pr view --json ...` 取 `number/url/state/head sha/mergeable/reviewDecision`。
  - repo 解析优先级：
    - `--repo` 显式值
    - 从 PR URL 提取
    - 从 `headRepository/headRepositoryOwner` 提取
  - 统一输出 `pr` 对象，含 `merged/closed` 布尔值。

### 3) 状态文件与去重模型

默认 state 文件：`/tmp/codex-babysit-pr-<owner-repo>-pr<number>.json`

持久化字段（核心）：

- `retries_by_sha`：按 SHA 记录 flaky retry 次数。
- `seen_issue_comment_ids` / `seen_review_comment_ids` / `seen_review_ids`：review 去重索引。
- `last_seen_head_sha`、`last_snapshot_at`、`started_at`：监控会话状态。

写入策略：

- `save_state()` 使用临时文件 + `os.replace` 原子替换，减少写入中断导致的损坏窗口。

### 4) 数据采集链路

脚本通过 `gh_text()/gh_json()` 封装 CLI 调用，统一错误格式为 `GhCommandError`。

采集链路：

1. PR 元数据
- `gh pr view --json number,url,state,mergedAt,closedAt,headRefName,headRefOid,headRepository,headRepositoryOwner,mergeable,mergeStateStatus,reviewDecision`

2. PR checks 概览
- `gh pr checks --json name,state,bucket,link,workflow,event,startedAt,completedAt`
- `summarize_checks()` 计算 `pending_count/failed_count/passed_count/all_terminal`。

3. Workflow runs（按 head SHA）
- `gh api repos/{owner}/{repo}/actions/runs -X GET -f head_sha=<sha> -f per_page=100`
- `failed_runs_from_workflow_runs()` 仅保留失败结论集合（`failure/timed_out/...`）。

4. Review 三路聚合
- issue comments：`repos/{repo}/issues/{pr}/comments`
- inline review comments：`repos/{repo}/pulls/{pr}/comments`
- review submissions：`repos/{repo}/pulls/{pr}/reviews`
- `gh_api_list_paginated()` 自动分页。
- 统一归一化后进入 `fetch_new_review_items()`。

### 5) Review 过滤与可信作者策略

过滤规则：

- bot 账号仅允许“可行动 bot”（当前关键字包含 `codex`）。
- 人类作者仅允许：
  - 当前认证用户自己
  - `OWNER/MEMBER/COLLABORATOR`
- 非可信作者评论被忽略，不进入 `new_review_items`。

这使 watcher 关注“更可能可执行”的反馈，但也意味着外部贡献者评论可能被过滤（详见风险章节）。

### 6) 动作决策引擎

核心函数：`recommend_actions(...)`

决策优先级：

1. PR 关闭/合并
- 输出 `stop_pr_closed`（如有新 review 同时输出 `process_review_comment`）。

2. Ready to merge
- `is_pr_ready_to_merge()` 同时要求：
  - checks 全终态且无失败无 pending
  - 无 `new_review_items`
  - `mergeable == MERGEABLE`
  - `merge_state_status` 不在阻塞集合
  - `review_decision` 不在阻塞集合
- 满足则输出 `stop_ready_to_merge`。

3. review 优先
- 有新 review 则输出 `process_review_comment`。

4. CI 失败处理
- 失败且超重试预算：`stop_exhausted_retries`
- 否则：`diagnose_ci_failure`
- 若 checks 已终态且有 failed runs 且预算未超：附加 `retry_failed_checks`

5. 无动作
- 输出 `idle`。

输出先经过 `unique_actions()` 去重。

### 7) 即时重试执行逻辑

`retry_failed_now()` 会先采样一次快照，然后按门槛判断：

- PR 未关闭
- `failed_count > 0`
- 存在 failed runs
- checks 已全终态
- 当前 SHA 重试次数 < `max_flaky_retries`

满足时对每个 run 执行：

- `gh run rerun <run-id> --failed`

成功后更新 state：

- 当前 SHA 计数 `+1`
- 返回 `rerun_attempted/rerun_count/rerun_run_ids/reason`

### 8) Watch 事件协议与退避策略

`run_watch()` 输出 JSONL 事件：

- `{"event":"snapshot","payload":{snapshot,state_file,next_poll_seconds}}`
- 命中 stop 动作后输出：
  - `{"event":"stop","payload":{"actions":[...],"pr":{...}}}`

轮询策略：

- CI 非绿：间隔重置为基础 `--poll-seconds`
- CI 绿且状态变化：重置为基础间隔
- CI 绿且状态无变化：指数退避翻倍，封顶 3600 秒

`snapshot_change_key()` 把 SHA、mergeability、reviewDecision、checks 计数、review item ID、actions 组合成“变化判据”。

## 关键代码路径与文件引用

目标目录关键文件：

- `.codex/skills/babysit-pr/SKILL.md`
- `.codex/skills/babysit-pr/agents/openai.yaml`
- `.codex/skills/babysit-pr/scripts/gh_pr_watch.py`
- `.codex/skills/babysit-pr/references/heuristics.md`
- `.codex/skills/babysit-pr/references/github-api-notes.md`

技能加载与调用方（上游）：

- `codex-rs/core/src/skills/loader.rs`
  - `skill_roots(...)`、`repo_agents_skill_roots(...)`
  - `discover_skills_under_root(...)` 扫描 `SKILL.md`
  - `load_skill_metadata(...)` 读取 `agents/openai.yaml`
- `codex-rs/core/src/skills/manager.rs`
  - `skills_for_config(...)`
  - `skills_for_cwd_with_extra_user_roots(...)`
  - cache 管理与 `bundled` 过滤
- `codex-rs/core/src/skills/render.rs`
  - `render_skills_section(...)` 将技能列表注入 instructions
- `codex-rs/core/src/skills/injection.rs`
  - `collect_explicit_skill_mentions(...)`
  - `build_skill_injections(...)` 读取 `SKILL.md` 内容注入 turn
- `codex-rs/core/src/codex.rs`
  - turn 构建时解析 skill mentions 并注入
  - `list_skills(...)` 对外返回技能清单

与 app-server 的协议路径：

- `codex-rs/app-server-protocol/src/protocol/v2.rs`
  - `SkillsListParams/Response`
  - `SkillsConfigWriteParams/Response`
  - `SkillsChangedNotification`
- `codex-rs/app-server/src/codex_message_processor.rs`
  - `skills_config_write(...)` -> `ConfigEdit::SetSkillConfig`
- `codex-rs/app-server/src/bespoke_event_handling.rs`
  - `EventMsg::SkillsUpdateAvailable` -> `skills/changed` 通知
- `codex-rs/app-server/README.md`
  - `skills/list`、`skills/changed`、`skills/config/write` 使用示例

文件变更监听链路（skills 热更新）：

- `codex-rs/core/src/file_watcher.rs`
  - 监听 skills roots 并广播 `FileWatcherEvent::SkillsChanged`
- `codex-rs/core/src/thread_manager.rs`
  - 收到变化后 `skills_manager.clear_cache()`
- `codex-rs/core/src/codex.rs`
  - 会话内转发 `EventMsg::SkillsUpdateAvailable`

配置路径：

- `codex-rs/core/src/config/types.rs`
  - `SkillsConfig { bundled, config }`
  - `SkillConfig { path, enabled }`
- `codex-rs/core/src/config/edit.rs`
  - `ConfigEdit::SetSkillConfig`
  - `set_skill_config(...)` 写入/移除 `[[skills.config]]`

测试路径（上下文系统级）：

- `codex-rs/core/src/skills/loader_tests.rs`
- `codex-rs/core/src/skills/manager_tests.rs`
- `codex-rs/core/src/skills/injection_tests.rs`
- `codex-rs/core/src/file_watcher_tests.rs`
- `codex-rs/app-server/tests/suite/v2/skills_list.rs`

注：目标目录 `babysit-pr` 本身（尤其 `gh_pr_watch.py`）当前未发现同仓库自动化单测。

## 依赖与外部交互

### 1) 运行时依赖

- Python 3 运行脚本。
- GitHub CLI `gh`（强依赖，缺失即报错）。
- 本地文件系统（state 文件写入 `/tmp/...`）。

### 2) 外部服务与协议

- GitHub REST API（通过 `gh api` 间接调用）：
  - PR comments / reviews
  - Actions runs
- GitHub Actions rerun 能力（`gh run rerun --failed`）。

### 3) 与 Codex skill 基础设施的交互

- 通过 `SKILL.md` frontmatter + `agents/openai.yaml` 被 loader 解析为 `SkillMetadata`。
- 通过 explicit mentions 或技能注入机制进入 turn。
- 通过 app-server 的 `skills/list` 对客户端可见，可被 `skills/config/write` 按路径启停。

### 4) 文档与策略耦合

- `SKILL.md` 是行为主规范。
- `references/heuristics.md` 与 `references/github-api-notes.md` 是判定与命令面“辅助规范”。
- `agents/openai.yaml.default_prompt` 与 `SKILL.md` 的约束高度耦合，形成运行时提示对齐。

## 风险、边界与改进建议

### 风险

1. 文档与脚本默认轮询间隔存在偏差
- `SKILL.md` 描述“未绿时 1 分钟轮询”，脚本 `--poll-seconds` 默认是 30 秒。
- 风险是技能执行者按文档理解与脚本默认行为不一致，影响 API 频率与预期节奏。

2. `gh_pr_watch.py` 缺少仓库内自动化测试
- 动作决策与筛选规则较复杂（stop 条件、review 过滤、retry 预算），回归风险高于普通脚本。

3. 默认 state 文件缺少并发锁
- 同 PR 并发 watcher 会共享同一 `/tmp/...` 文件，可能造成 seen IDs 或 retry 计数互相覆盖。

4. Review 信任模型较保守
- 仅允许 OWNER/MEMBER/COLLABORATOR + 特定 bot。
- 对开源场景下外部贡献者（如 `CONTRIBUTOR`）的有效评论可能漏报。

5. 失败分类结果未结构化落盘
- 当前 `actions` 仅提示“该诊断/该重试”，但未输出脚本级“分类理由字段”，不利于后续审计与统计。

### 边界

1. watcher 不负责自动 merge PR
- “ready_to_merge” 只给 stop 建议，不执行合并动作。

2. watcher 不直接改代码
- 脚本只做状态与 rerun，代码修复、commit/push 由执行该 skill 的 agent 负责。

3. review“已解决线程”语义不在脚本内完整判定
- 当前主要基于评论流 + seen IDs 去重，不等价于线程级 resolved 状态机。

4. 对 GitHub 权限与网络可用性有前置依赖
- `gh` 认证失败、仓库权限不足或 GitHub 故障时只能停并上报，无法自治恢复。

### 改进建议

1. 增加 watcher 单测与快照样例
- 至少覆盖：
  - `recommend_actions()` 分支矩阵
  - `retry_failed_now()` 门槛矩阵
  - review 过滤规则与去重
  - green-state 退避逻辑

2. 引入 state 文件锁或会话隔离
- 可选：
  - 文件锁（flock）
  - state 文件名附加会话 ID
  - 或检测并拒绝同 PR 并发 watcher

3. 对齐文档与默认参数
- 二选一：
  - 将默认 `--poll-seconds` 改到 60
  - 或在 `SKILL.md` 明确默认 30 秒并解释原因

4. 扩展 review 信任策略配置化
- 把可信 association / bot allowlist 下沉到配置项，避免写死在脚本常量。

5. 输出更可审计的判定字段
- 在 snapshot 增加结构化字段，如：
  - `ci_failure_classification`
  - `classification_reason`
  - `review_filter_stats`
  便于后续自动汇总与行为回放。

