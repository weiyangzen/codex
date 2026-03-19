# .ops 目录研究

## 场景与职责

`.ops/` 是仓库内“研究任务自动化运维层”，围绕 `Docs/researches/` 的研究产物提供三类能力：

1. 基线清单生成：把仓库目录/文件扫描为可打勾的研究 checklist。
2. 每日待办派生：把 checklist 的未完成项按日期生成 todo 快照。
3. 守护执行与收尾：自动挑选下一个待研究目标，调用 `codex --yolo exec` 非 REPL 执行，并在完成时清理 cron。

该目录不承载业务功能（如 CLI/TUI/protocol 逻辑），而是支撑“文档化研究流水线”的操作面。

## 功能点目的

### 1) `generate_research_blueprint_checklist.sh`

目的：生成/刷新 `Docs/researches/blueprint_checklist.md`，并保留已有勾选状态。

关键点：
- 启动时读取旧 checklist，并把 `- [x] [DIR|FILE] path` 解析到内存映射 `STATUS`，避免重建后丢失进度（`.ops/generate_research_blueprint_checklist.sh:10-25`）。
- `find` 扫描目录与文件，并排除 `.git/`、`.cron/`、`Docs/researches/`（`.ops/generate_research_blueprint_checklist.sh:27-42`）。
- 最后输出统计（dirs/files/pending/done），供 guard 日志与人工确认（`.ops/generate_research_blueprint_checklist.sh:68-73`）。

### 2) `generate_daily_research_todo.sh`

目的：按当天日期生成 `Docs/researches/todos_YYYYMMDD.md`，用于当天执行视图。

关键点：
- 若 checklist 不存在，先调用 blueprint 生成（`.ops/generate_daily_research_todo.sh:11-13`）。
- 基于 `rg` 正则统计 pending/done/dirs/files，并把 pending 项完整抄录进 todo（`.ops/generate_daily_research_todo.sh:15-39`）。
- 输出 todo 路径到 stdout，供上游脚本捕获（`.ops/generate_daily_research_todo.sh:41-42`）。

### 3) `research_guard.sh`

目的：持续/定时地推进研究任务，从 checklist 自动派单给 codex 执行。

关键点：
- 通过 `flock` + `/tmp/<project>_research_guard.lock` 防重入（`.ops/research_guard.sh:13,147-151`）。
- 支持 tmux 包裹模式：优先把真实执行委托到 tmux session/window，避免 cron 启动进程随终端生命周期中断（`.ops/research_guard.sh:29-58`）。
- 每轮执行顺序固定：刷新 checklist -> 刷新 todo -> 取首个 pending（`.ops/research_guard.sh:165-188`）。
- 根据目标类型拼接研究文档路径规则：
  - 目录目标：`Docs/researches/<target>/current_folder_research.md`
  - 文件目标：`Docs/researches/<dirname>/<basename>_research.md`
  （`.ops/research_guard.sh:190-208`）
- 内嵌中文任务模板，并明确“使用 codex exec 非 REPL 模式”（`.ops/research_guard.sh:214-239`）。
- 以 `timeout` 约束 `codex --yolo exec` 最大时长（默认 5400 秒），结束后根据返回码写状态（`.ops/research_guard.sh:242-271`）。
- 执行后若工作区有变化，会 `git add -A` 并尝试 checkpoint 提交（`.ops/research_guard.sh:248-261`）。

### 4) `cleanup_research_cron.sh`

目的：在研究全部完成时，从 crontab 移除研究相关定时任务。

关键点：
- 仅接受 `--execute` 参数（`.ops/cleanup_research_cron.sh:14-17`）。
- 过滤包含 `.ops/generate_daily_research_todo.sh` 或 `.ops/research_guard.sh` 的 cron 行并重写 crontab（`.ops/cleanup_research_cron.sh:19-23`）。
- 记录清理状态与日志（`.ops/cleanup_research_cron.sh:24-26`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 关键流程（端到端）

1. `research_guard.sh` 启动并抢锁，确保单实例。
2. 调用 `generate_research_blueprint_checklist.sh`：
   - 扫描仓库 -> 产出 `blueprint_checklist.md`。
3. 调用 `generate_daily_research_todo.sh`：
   - 从 checklist 派生 `todos_YYYYMMDD.md`。
4. 从 checklist 取第一个 `- [ ] [DIR|FILE] ...`。
5. 按目标类型构造研究文档路径。
6. 组装标准化中文 Prompt，调用 `codex --yolo exec`。
7. 根据返回码更新 `.cron/research_guard.state`，必要时做 checkpoint commit。
8. 若无 pending 且 `AUTO_CLEANUP_ON_COMPLETE=1`，执行 `cleanup_research_cron.sh --execute`。

### B. 核心“数据结构”与状态文件

虽然是 shell 脚本，但有明确状态模型：

- Checklist 条目语法：`- [ ] [DIR] path` / `- [x] [FILE] path`（`.ops/generate_research_blueprint_checklist.sh:13-23`）。
- `STATUS` 关联数组：key=`DIR:path` 或 `FILE:path`，value=`x`/` `（`.ops/generate_research_blueprint_checklist.sh:10,17-22`）。
- Guard 状态文件：
  - `.cron/research_guard.state`：`running_exec/completed/exec_failed/...`
  - `.cron/research_guard.block_count`：阻塞计数
  - `.cron/research_guard.log`：全量执行日志
  （`.ops/research_guard.sh:10-13,26-27`）

### C. 协议与命令约定

- 非 REPL 执行协议：`codex --yolo exec "$TASK"`（`.ops/research_guard.sh:243-246`）。
- 目标路径协议：由 `TARGET_TYPE + TARGET_PATH` 决定报告文件命名（`.ops/research_guard.sh:192-208`）。
- 提交协议：研究脚本与任务模板均约定 `git add Docs/researches .ops || true`、`git add -A`、`git commit ... || true`；guard 还会做 checkpoint commit（`.ops/research_guard.sh:231-234,248-252`）。

### D. 外部命令依赖

`.ops` 脚本依赖以下工具链：
- 基础：`bash`、`find`、`sed`、`awk`、`date`、`wc`、`tail`、`dirname`、`basename`。
- 检索：`rg`（ripgrep）。
- 并发与会话：`flock`、`tmux`、`timeout`。
- 版本控制：`git`。
- 任务执行：`codex`。
- 计划任务：`crontab`。

## 关键代码路径与文件引用

### 目录内主路径

- `.ops/generate_research_blueprint_checklist.sh:1-73`
- `.ops/generate_daily_research_todo.sh:1-42`
- `.ops/research_guard.sh:1-272`
- `.ops/cleanup_research_cron.sh:1-26`

### 目录外输入/输出与调用上下文

- Checklist 输出：`Docs/researches/blueprint_checklist.md:1-617`
- 每日 todo 输出：`Docs/researches/todos_20260319.md:1-599`
- Guard 运行时状态：`.cron/research_guard.state`、`.cron/research_guard.block_count`、`.cron/research_guard.log`
- 上下文文档引用（证明该流程在仓库研究体系中已被使用）：
  - `Docs/researches/current_folder_research.md:109-119`
  - `Docs/researches/.github/codex/current_folder_research.md:115-117`

### 调用关系（调用方 -> 被调用方）

- `research_guard.sh` -> `generate_research_blueprint_checklist.sh`
- `research_guard.sh` -> `generate_daily_research_todo.sh`
- `research_guard.sh` -> `cleanup_research_cron.sh`（条件触发）
- `generate_daily_research_todo.sh` -> `generate_research_blueprint_checklist.sh`（仅 checklist 缺失时）
- `research_guard.sh` -> `codex --yolo exec`（执行研究任务）

## 依赖与外部交互

### 配置输入（环境变量）

`research_guard.sh` 通过环境变量控制行为：
- `CODEX_BIN`：codex 可执行路径覆盖。
- `AUTO_CLEANUP_ON_COMPLETE`：完成时是否自动清理 cron。
- `CODEX_EXEC_TIMEOUT_SECONDS`：exec 超时时间。
- `AUTO_PUSH_ON_CHECKPOINT`：checkpoint 后是否尝试自动 push。
- `TMUX_WRAP_ENABLED` / `TMUX_SESSION_NAME`：tmux 包裹执行策略。
- `RESEARCH_GUARD_WORKER`：内部 worker 模式标记。
（见 `.ops/research_guard.sh:8,15-20`）

### 文件系统交互

- 读写研究产物：`Docs/researches/*`。
- 读写运行日志与状态：`.cron/*`。
- 使用 `/tmp/<project>_research_guard.lock` 做进程级互斥。

### Git 与远端交互

- 本地交互：`git add/commit/rebase`。
- 可选远端交互：`AUTO_PUSH_ON_CHECKPOINT=1` 时会 `git fetch` + `git push`，并在冲突时使用 `--ours` 自动解冲突（`.ops/research_guard.sh:60-145`）。

### 系统调度交互

- `cleanup_research_cron.sh` 直接读取并覆写用户 crontab，属于宿主机级变更（`.ops/cleanup_research_cron.sh:19-23`）。

## 风险、边界与改进建议

### 风险

1. 误提交风险：`git add -A` 可能把研究目标外的工作区改动一并提交（`.ops/research_guard.sh:248-252`）。
2. 自动冲突解决偏置：`auto_push_with_conflict_resolution` 在 rebase 冲突时偏向 `--ours`，有覆盖上游改动风险（`.ops/research_guard.sh:95-135`）。
3. 调度副作用：cron 清理是“整表重写”，若过滤规则误匹配，可能影响非研究 cron 项（`.ops/cleanup_research_cron.sh:20-23`）。
4. 可观测性边界：目前无结构化指标，主要依赖文本日志，跨天排障成本高。
5. 测试缺口：仓库内未见 `.ops` 脚本的自动化测试或 CI 校验路径，回归依赖人工执行。

### 边界

1. `.ops` 只编排研究流程，不负责评估研究内容质量。
2. `.ops` 依赖本机安装与权限（tmux/crontab/git/codex），不保证跨环境一致性。
3. 该目录和 `Docs/researches/` 相互耦合，属于仓库内部运维机制，不是对外发布 API。

### 改进建议

1. 收敛提交范围：把 `git add -A` 改为路径白名单（例如仅 `Docs/researches/**` 与必要状态文件）。
2. 增加 dry-run：为 `cleanup_research_cron.sh` 提供 `--dry-run` 与备份输出，降低误操作风险。
3. 增加幂等测试：为 4 个脚本补充最小 Bats/shellspec 测试（尤其是 checklist 保留状态、todo 统计、路径命名规则）。
4. 结构化日志：把关键状态写成 JSON 行（目标、耗时、退出码、提交 hash），便于后续统计与告警。
5. 提交策略可配置化：增加“只提交当前研究目标文件”的策略开关，降低并行协作冲突。
