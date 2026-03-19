# DIR `.codex/skills/babysit-pr/scripts` 研究报告

- 研究对象：`/home/sansha/Github/codex/.codex/skills/babysit-pr/scripts`
- 研究日期：2026-03-19
- 目录内容：`gh_pr_watch.py`（目录内唯一执行脚本）

## 场景与职责

该目录是 `babysit-pr` 技能的“执行引擎层”。`SKILL.md` 负责行为规范与流程约束，`references/*.md` 负责诊断启发和命令说明，而 `scripts/gh_pr_watch.py` 负责把 GitHub PR 的状态采样、动作建议、重试执行统一成机器可读输出。

在完整链路中的职责边界：

1. 上游调用方
- 人工/Agent 按 `SKILL.md` 命令触发该脚本（`--once` / `--watch` / `--retry-failed-now`）。
- `agents/openai.yaml` 的 `default_prompt` 强化“优先 `--watch` 且持续监控”的使用方式。

2. 中游执行职责
- 聚合 PR 元信息、checks、workflow runs、review 增量。
- 依据规则输出动作建议（如 `diagnose_ci_failure`、`retry_failed_checks`）。
- 在策略允许时直接执行 failed jobs rerun。

3. 下游消费方
- babysit 工作流（同一会话中的 Agent）消费 JSON/JSONL 输出，决定是否修复代码、push、继续 watch 或停机求助。

结论：该目录不是“技能被动文档”，而是 babysit 流程唯一可执行自动化组件。

## 功能点目的

### 1) 一次性快照（`--once`）

目的：为决策提供单次全量状态切片，输出结构包含：

- `pr`：PR 状态、head SHA、mergeability、review decision
- `checks`：pending/failed/passed 计数
- `failed_runs`：当前 head SHA 上失败 workflow runs
- `new_review_items`：去重后的新评论/评审项
- `actions`：建议动作集合
- `retry_state`：重试预算使用情况

### 2) 连续监控（`--watch`）

目的：持续输出 JSONL 事件，直到进入严格 stop 条件：

- `event=snapshot`：周期性状态+下次轮询秒数
- `event=stop`：命中 `stop_pr_closed` / `stop_exhausted_retries` / `stop_ready_to_merge`

并在“CI 全绿且状态未变化”时指数退避，降低轮询频率。

### 3) 失败重试执行（`--retry-failed-now`）

目的：仅在策略允许时触发 `gh run rerun <run-id> --failed`，并按 SHA 计数防止无限重跑。执行结果返回结构化 `reason`（如 `rerun_triggered`、`retry_budget_exhausted`）。

### 4) review 增量与作者信任过滤

目的：减少噪声并避免重复处理：

- 三路采集：issue comments / review comments / reviews
- 信任人类作者：`OWNER`/`MEMBER`/`COLLABORATOR` + 当前认证操作者
- 信任 bot：`login` 命中 `codex` 关键词的 bot
- 通过 state 文件中的 seen ID 集合去重

### 5) 动作建议协议（`actions`）

目的：把 babysit 语义从自然语言收敛到固定动作枚举，降低流程歧义。核心动作：

- `process_review_comment`
- `diagnose_ci_failure`
- `retry_failed_checks`
- `stop_pr_closed`
- `stop_ready_to_merge`
- `stop_exhausted_retries`
- `idle`

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 参数与运行模式

`parse_args()` 定义 3 个主要模式并做互斥/合法性校验：

- `--once`：单次快照（默认模式）
- `--watch`：连续 JSONL
- `--retry-failed-now`：即时重试 failed jobs

关键配置参数：

- `--pr`：`auto` / PR number / PR URL
- `--repo`：可选仓库覆盖
- `--poll-seconds`：基础轮询间隔（默认 30）
- `--max-flaky-retries`：同 SHA 最大重试次数（默认 3）
- `--state-file`：状态文件路径（不传则使用 `/tmp/codex-babysit-pr-...`）

### B. 采样主流程（`collect_snapshot`）

执行顺序：

1. `resolve_pr()`：`gh pr view --json ...` 解析 PR 和 repo。
2. `get_pr_checks()` + `summarize_checks()`：获取 checks 统计。
3. `get_workflow_runs_for_sha()` + `failed_runs_from_workflow_runs()`：提取当前 SHA 的失败 runs。
4. `get_authenticated_login()` + `fetch_new_review_items()`：获取 review 增量并过滤噪声。
5. `recommend_actions()`：生成动作建议。
6. 更新并原子写入 state 文件。

### C. 状态模型（state file）

默认 state 结构要点：

- `pr`: `{repo, number}`
- `started_at`, `last_snapshot_at`, `last_seen_head_sha`
- `retries_by_sha`: `{sha: count}`
- `seen_issue_comment_ids`, `seen_review_comment_ids`, `seen_review_ids`

实现细节：

- `save_state()` 采用临时文件 + `os.replace` 原子替换，降低中断损坏概率。
- `load_state()` 对 JSON 非对象格式直接报错，避免脏状态污染判断。

### D. 动作判定逻辑

`recommend_actions()` 的优先级：

1. PR 已关闭/合并：`stop_pr_closed`（如有新 review 同时带 `process_review_comment`）。
2. `is_pr_ready_to_merge()` 为真：`stop_ready_to_merge`。
3. 有新 review：`process_review_comment`。
4. checks 失败：
- 终态且超预算：`stop_exhausted_retries`
- 否则：`diagnose_ci_failure`
- 且终态 + 有 failed runs + 未超预算：附加 `retry_failed_checks`
5. 无动作：`idle`

其中 `is_pr_ready_to_merge()` 同时要求：

- checks 全终态且无 pending/failed
- 无 `new_review_items`
- `mergeable == MERGEABLE`
- `merge_state_status` 不在阻塞集合
- `review_decision` 不在阻塞集合（如 `REVIEW_REQUIRED` / `CHANGES_REQUESTED`）

### E. watch 事件协议与轮询退避

`run_watch()` 行为：

- 每轮输出 `snapshot` 事件，载荷含 `{snapshot,state_file,next_poll_seconds}`。
- 命中 stop 动作后输出 `stop` 事件并退出。
- 非绿状态：轮询恢复到基础间隔。
- 绿状态且无变化：指数退避，最大 `3600s`。
- 变化判定由 `snapshot_change_key()` 统一对 SHA/mergeability/review/checks/actions/new items 做 tuple 比较。

### F. 对外命令面（GitHub CLI/API）

脚本通过 `gh_text()/gh_json()` 封装外部命令，核心命令包括：

- `gh pr view --json ...`
- `gh pr checks --json ...`
- `gh api repos/{owner}/{repo}/actions/runs ...`
- `gh api repos/{owner}/{repo}/issues/{pr}/comments...`
- `gh api repos/{owner}/{repo}/pulls/{pr}/comments...`
- `gh api repos/{owner}/{repo}/pulls/{pr}/reviews...`
- `gh run rerun <run-id> --failed`（仅 retry 模式触发）

若 `gh` 缺失或命令失败，统一抛 `GhCommandError` 并 stderr 返回可诊断信息。

## 关键代码路径与文件引用

### 目标目录与同级依赖

- `.codex/skills/babysit-pr/scripts/gh_pr_watch.py`
- `.codex/skills/babysit-pr/SKILL.md`（调用方式与流程规则）
- `.codex/skills/babysit-pr/references/heuristics.md`（失败分类决策）
- `.codex/skills/babysit-pr/references/github-api-notes.md`（命令字段清单）
- `.codex/skills/babysit-pr/agents/openai.yaml`（默认提示词约束）

### 关键函数路径（`gh_pr_watch.py`）

- 参数与入口：`parse_args()`、`main()`
- 命令封装：`gh_text()`、`gh_json()`
- PR 解析：`parse_pr_spec()`、`resolve_pr()`
- checks/runs：`get_pr_checks()`、`summarize_checks()`、`get_workflow_runs_for_sha()`
- review 增量：`comment_endpoints()`、`gh_api_list_paginated()`、`fetch_new_review_items()`
- 决策与重试：`recommend_actions()`、`retry_failed_now()`
- 持续监控：`run_watch()`

### 上下文代码路径（技能系统）

以下路径负责“发现与注入技能说明”，不是脚本直接调用链，但决定脚本如何被会话使用：

- `codex-rs/core/src/skills/loader.rs`（扫描 `SKILL.md` / `openai.yaml`）
- `codex-rs/core/src/skills/injection.rs`（按提及注入技能指令）
- `codex-rs/core/src/codex.rs`（会话中组装 skills 注入与事件）
- `codex-rs/app-server/README.md`（`skills/list`、`skills/changed` 协议说明）

### 测试与覆盖现状

目录级结论：

- 未发现 `gh_pr_watch.py` 的仓库内自动化单元/集成测试。
- 相关测试主要覆盖 skills 的“加载/注入/变更通知”基础设施，而不是 babysit 脚本运行行为本身。

## 依赖与外部交互

### 运行依赖

1. 可执行环境：`python3`
2. GitHub CLI：`gh`
3. GitHub 认证与权限：可读 PR/checks/reviews/runs，且重试需 Actions rerun 权限

### 文件系统与本地状态

1. 默认状态文件落在 `/tmp/codex-babysit-pr-<repo>-pr<n>.json`
2. 可通过 `--state-file` 显式重定向
3. 状态文件承担去重、重试预算、会话元数据持久化

### 协议与数据交互

1. 输入协议：CLI 参数（`--pr`/`--watch`/`--retry-failed-now` 等）
2. 输出协议：
- 单次 JSON（`--once`/`--retry-failed-now`）
- JSONL 事件流（`--watch`）
3. 远程协议：通过 `gh` 间接调用 GitHub REST/API 与 PR checks 命令

### 文档与流程依赖

1. `SKILL.md` 规定了该脚本的期望使用姿势（持续 watch、push 后恢复、严格 stop）
2. `heuristics.md` 与 `github-api-notes.md` 共同约束“如何解释 actions 并采取下一步”
3. `openai.yaml` 的 `default_prompt` 强化 watch 行为，减少“只看一次就结束”的误用

## 风险、边界与改进建议

### 1) 风险：脚本无自动化测试

- 现状：动作判定、重试门槛、review 过滤、watch 退避都依赖脚本逻辑，缺少仓内测试保护。
- 建议：补充最小 pytest/集成测试，重点覆盖：
  - `recommend_actions()` 分支矩阵
  - `retry_failed_now()` 的 reason 分支
  - review 去重与作者过滤
  - watch 退避与 stop 事件触发

### 2) 风险：作者过滤可能漏掉重要反馈

- 现状：非 trusted association 的人类评论默认被过滤。
- 边界：外部贡献者或临时 reviewer 可能未进入 `OWNER/MEMBER/COLLABORATOR`。
- 建议：提供可选开关（例如 `--include-external-reviewers`）或在输出中追加“被过滤评论计数”提示。

### 3) 风险：文档字段与实现可能漂移

- 现状：`github-api-notes.md` 的 `gh pr view` 字段示例未完全覆盖脚本已消费字段（如 mergeability 相关字段）。
- 建议：增加 docs-contract 检查，确保脚本字段清单与 references 同步。

### 4) 边界：`gh` 与权限失败直接终止

- 现状：脚本对权限/认证问题不做自动恢复。
- 建议：在错误输出中补充更明确 remediation 提示（如 `gh auth status`、所需 scopes）。

### 5) 边界：状态文件是单点会话记忆

- 现状：state 文件损坏会导致会话中断，或重复 surfacing 历史 review。
- 建议：损坏时可提供“备份后自动重建”模式，至少支持软恢复继续监控。

### 6) 边界：命令触发而非系统自动调度

- 现状：仓库内没有后台服务自动触发该脚本；其生效依赖用户/Agent 在正确时机执行命令。
- 建议：在技能使用入口增加一条“前置检查脚本”（验证 `gh`、仓库上下文、PR 可解析）以降低人工误操作。
