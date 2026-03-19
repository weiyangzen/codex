# DIR `.codex/skills/babysit-pr/references` 研究报告

- 研究对象：`/home/sansha/Github/codex/.codex/skills/babysit-pr/references`
- 研究日期：2026-03-19
- 研究范围：`heuristics.md`、`github-api-notes.md` 及其调用上下文（技能指令、watcher 脚本、skills 加载与通知链路、相关测试与文档）

## 场景与职责

`references` 目录是 `babysit-pr` 技能的“操作决策参考层”，不直接被运行时代码自动解析，而是由 `SKILL.md` 显式引导在人工/Agent 决策时使用。

该目录承载两个互补职责：

1. `heuristics.md`：定义“失败分类与动作决策”的判断基线（修复 vs 重试 vs 停止求助）。
2. `github-api-notes.md`：定义 watcher 依赖的 GitHub CLI/API 命令与关键字段清单，降低排障时命令漂移与字段误读风险。

在整体链路中的位置：

- 上游：用户触发 `babysit-pr` 技能，技能正文在 `SKILL.md` 中要求优先 `--watch` 持续监控，并在诊断阶段参考本目录。
- 中游：执行脚本 `scripts/gh_pr_watch.py` 产出标准化快照与动作建议（`actions`），Agent 结合本目录进行“解释与下一步动作”决策。
- 下游：skills 基础设施（loader/injection/app-server）负责技能发现、注入与变更通知；`references` 本身不被 loader 结构化消费。

## 功能点目的

### 1) CI 失败分类标准化（`heuristics.md`）

目的：将“branch-related”与“flaky/unrelated”区分具体化，避免误把真实回归当成 flaky 重试，或把基础设施抖动当成本地改代码。

文档明确：

- branch-related 典型信号：改动区域内编译/测试/lint/snapshot 确定性失败。
- flaky/unrelated 典型信号：网络/runner/GitHub infra/限流等瞬态问题。
- 不确定时先查一次失败日志再决策。

### 2) 动作决策树压缩（`heuristics.md`）

目的：把长流程压缩成可执行顺序：

1. PR 关闭即停止。
2. 失败先诊断，再决定修复或 rerun。
3. 同 SHA 超过重试预算（默认 3）则停止并上报。
4. review 评论与 CI 处理并行考虑。

### 3) GitHub 交互面清单化（`github-api-notes.md`）

目的：固定 babysitter 观察/重试所需命令集，避免在不同会话中临时拼接命令导致输出字段不一致。

文档覆盖：

- PR 元数据：`gh pr view --json ...`
- checks 汇总：`gh pr checks --json ...`
- runs 查询：`gh api repos/{owner}/{repo}/actions/runs ...`
- 失败诊断：`gh run view ... --json` + `--log-failed`
- 失败重跑：`gh run rerun <run-id> --failed`
- review 三路 endpoint（issue comments / review comments / reviews）

### 4) 与技能规范对齐（`SKILL.md`）

目的：作为 `SKILL.md` 的外部参考补充，支撑以下强约束：

- 监控任务默认 `--watch`，非 strict stop 条件不得中止。
- review 修复与 flaky rerun 冲突时，优先 review 修复（避免对旧 SHA 无效重跑）。
- push 后同一轮会话立即恢复 watch。

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. “文档 -> 策略 -> 脚本动作”闭环

1. `SKILL.md` 输出操作框架与停止条件。
2. `gh_pr_watch.py` 周期性采样并输出 `snapshot/actions`。
3. Agent 使用 `references` 中的分类规则解释 `actions`，决定“修复、重试、继续等待或停止求助”。

这意味着 `references` 的实现形态是“人类可读策略协议”，而不是 Python/Rust 可执行配置。

### B. watcher 的机读协议（由脚本实现，references 为其解释层）

`gh_pr_watch.py` 三种模式：

- `--once`：单次快照
- `--watch`：JSONL 连续事件（`snapshot` / `stop`）
- `--retry-failed-now`：在策略允许下即时重跑失败 jobs

关键输出结构：

- `snapshot.pr`：PR 状态（`head_sha/mergeable/review_decision` 等）
- `snapshot.checks`：`pending_count/failed_count/passed_count/all_terminal`
- `snapshot.failed_runs`：可重跑的失败 workflow runs
- `snapshot.new_review_items`：增量 review 项
- `snapshot.actions`：动作建议集合（`process_review_comment`、`diagnose_ci_failure`、`retry_failed_checks`、`stop_*`、`idle`）
- `snapshot.retry_state`：当前 SHA 已用重试次数/预算

### C. 数据结构与状态持久化

脚本状态文件默认：`/tmp/codex-babysit-pr-<owner-repo>-pr<number>.json`。

核心 state 字段：

- `retries_by_sha`：按 SHA 限流 retry
- `seen_issue_comment_ids / seen_review_comment_ids / seen_review_ids`：review 去重
- `last_seen_head_sha / last_snapshot_at / started_at`：监控会话元信息

写入使用临时文件 + `os.replace` 原子替换，降低中断时损坏概率。

### D. 命令与协议映射（references 与脚本的一致性）

`github-api-notes.md` 中列出的命令与脚本函数基本一一对应：

- PR 元数据：`resolve_pr()` -> `gh pr view --json ...`
- checks 汇总：`get_pr_checks()` + `summarize_checks()` -> `gh pr checks --json ...`
- runs 拉取：`get_workflow_runs_for_sha()` -> `gh api repos/{repo}/actions/runs ...`
- review 拉取：`gh_api_list_paginated()` + `comment_endpoints()` -> 3 路评论 API
- rerun 执行：`retry_failed_now()` -> `gh run rerun <run-id> --failed`

### E. 轮询与退避

`run_watch()` 的轮询策略：

- CI 非绿：回到基础轮询间隔（默认 30s）。
- CI 绿且状态未变化：指数退避（最多 1h）。
- 命中 `stop_pr_closed/stop_exhausted_retries/stop_ready_to_merge` 输出 `stop` 事件并退出。

`references/heuristics.md` 与该策略在“失败诊断优先、预算上限后停止”上保持一致。

## 关键代码路径与文件引用

### 目标目录文件

- `.codex/skills/babysit-pr/references/heuristics.md`
- `.codex/skills/babysit-pr/references/github-api-notes.md`

### 直接调用方与同级上下文

- `.codex/skills/babysit-pr/SKILL.md`
  - 在 CI 分类章节显式引用 `heuristics.md`
  - 在 References 章节列出两个 reference 文件
- `.codex/skills/babysit-pr/scripts/gh_pr_watch.py`
  - 实际产出 `actions` 与 watch 事件协议
  - references 文档对应其命令/字段/决策语义
- `.codex/skills/babysit-pr/agents/openai.yaml`
  - `default_prompt` 强化 watch 单会话与 push 后恢复监控约束

### skills 基础设施（间接上下文）

- `codex-rs/core/src/skills/loader.rs`
  - 扫描 `SKILL.md`，并读取 `agents/openai.yaml` 元数据
  - 不解析 `references` 目录内容（即 references 为人工决策材料）
- `codex-rs/core/src/skills/injection.rs`
  - turn 时只注入 `SKILL.md` 内容，不注入 `references/*.md`
- `codex-rs/core/src/skills/manager.rs`
  - 管理 skills roots 与缓存
- `codex-rs/core/src/file_watcher.rs` + `thread_manager.rs` + `codex.rs`
  - 监听技能文件变化，触发 `SkillsUpdateAvailable`
- `codex-rs/app-server/src/bespoke_event_handling.rs`
  - 将 `SkillsUpdateAvailable` 转为 `skills/changed` 通知
- `codex-rs/app-server/README.md`
  - 说明 `skills/list` 与 `skills/changed` 客户端行为契约

### 测试与验证路径（与目标目录关联）

- `codex-rs/core/src/skills/loader_tests.rs`
  - 校验 `openai.yaml` interface 解析与容错
- `codex-rs/core/src/skills/injection_tests.rs`
  - 校验技能显式提及解析逻辑
- `codex-rs/core/tests/suite/live_reload.rs`
  - 校验技能文件变更触发刷新并影响注入内容
- `codex-rs/app-server/tests/suite/v2/skills_list.rs`
  - 校验 `skills/list` 行为与 `skills/changed` 通知

结论：当前仓库中没有针对 `.codex/skills/babysit-pr/references/*.md` 的自动化一致性测试；它们通过 `SKILL.md` 的人工流程被消费。

## 依赖与外部交互

### 运行依赖（babysit 行为）

1. 系统命令依赖：`gh`、`python3`。
2. GitHub API/CLI 权限依赖：
- 读取 PR/checks/runs/reviews 需要对应 repo 访问权限。
- rerun failed jobs 需要 Actions 重跑权限。
3. 本地文件系统依赖：
- watcher state 文件写入 `/tmp/codex-babysit-pr-*.json`。

### 协议/数据依赖

1. GitHub 返回字段稳定性：`mergeable`、`mergeStateStatus`、`reviewDecision`、`workflow_runs`、comment/review IDs。
2. 技能发现协议：skills loader 识别 `SKILL.md` + `agents/openai.yaml`，不识别 references 为结构化字段。
3. app-server 协议：技能变更通过 `skills/changed` 通知客户端刷新 `skills/list`。

### 文档依赖

- `SKILL.md` 的流程说明依赖本目录两份 reference 文档作为“诊断细则与命令字典”。
- `openai.yaml` 的默认提示词语义应与 `SKILL.md` + references 保持一致。

## 风险、边界与改进建议

### 1) 风险：references 与实现漂移

表现：`github-api-notes.md` 仍只列到 `gh pr view` 的部分字段，而脚本已消费 `mergeable/mergeStateStatus/reviewDecision`。当脚本继续演进时，文档可能滞后。

建议：

- 增加轻量校验脚本（lint）比对 `gh_pr_watch.py` 中 CLI 字段清单与 `github-api-notes.md` 是否一致。
- 将字段表分为“最小必需字段/可选诊断字段”。

### 2) 风险：references 不参与自动注入

表现：运行时仅注入 `SKILL.md`，若操作者未阅读 references，可能在模糊场景下做出不一致判断。

建议：

- 在 `SKILL.md` 的关键步骤中加入更强制提示（例如 diagnose 阶段必须对照 heuristics checklist）。
- 可选：在 `SKILL.md` 内嵌最小版 decision table，references 放扩展说明。

### 3) 边界：review 作者过滤较保守

脚本只自动采纳可信人类作者（OWNER/MEMBER/COLLABORATOR + 当前操作者）与命中关键字的 bot；外部贡献者反馈可能被忽略。

建议：

- 在 `heuristics.md` 增加“定期人工抽查全量 review 线程”提醒。
- 或在 watcher 增加可选宽松模式参数（例如 `--include-external-reviewers`）。

### 4) 风险：重试预算语义分散

`heuristics.md`、`SKILL.md`、`openai.yaml` 都提到“最多 3 次”，但分布在不同文件，后续调整时容易漏改。

建议：

- 统一把“默认预算”定义在脚本参数文档中（单一事实源），其余文件引用该定义。
- 为三处文本增加简单一致性检查（例如 CI grep+assert）。

### 5) 测试边界：reference 文档缺少直接测试

现有测试覆盖技能加载、注入、热更新与 app-server skills 协议，但没有测试验证 references 与 watcher 的同步性。

建议：

- 增加 docs-contract 测试：校验 `github-api-notes.md` 中关键命令字段与脚本函数常量的一致性。
- 增加面向维护者的“变更清单”脚本，在改动 watcher 时提示同步更新 references。

