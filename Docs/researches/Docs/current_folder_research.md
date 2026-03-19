# DIR `Docs` 研究报告

- 研究对象：`/home/sansha/Github/codex/Docs`
- 目标类型：`DIR`
- 研究日期：2026-03-19

## 场景与职责

`Docs/`（大写）在本仓库中不是对外产品文档目录，而是“研究流水线产物根目录”。当前它只包含 `researches/` 子目录，承载由 `.ops` 脚本和 `codex --yolo exec` 生成的研究报告、全量 checklist、每日 todo 快照。

该目录在整体流程中的职责是：

1. 作为研究状态与成果的持久化落盘位置。
2. 为自动化调度（`research_guard.sh`）提供可读写目标路径。
3. 为人工审阅提供统一入口（按仓库路径镜像归档研究文档）。

与其相邻但职责不同的目录是 `docs/`（小写，用户文档目录）；两者在命名上容易混淆，但用途完全不同（`Docs/researches/blueprint_checklist.md:32,508`）。

## 功能点目的

围绕 `Docs/` 的核心功能点可归纳为 4 类：

1. 研究基线清单（Blueprint）承载  
`Docs/researches/blueprint_checklist.md` 记录全仓库目录/文件研究覆盖率，格式为 `- [ ] [DIR|FILE] path`，用于“下一步研究目标”的确定（`.ops/generate_research_blueprint_checklist.sh:5-7,10-25,44-66`）。

2. 每日执行视图承载  
`Docs/researches/todos_YYYYMMDD.md` 抽取 checklist 的 pending 项，提供当天任务快照和统计（`.ops/generate_daily_research_todo.sh:5-8,15-39`）。

3. 研究报告归档  
针对目录目标统一落盘为 `Docs/researches/<target>/current_folder_research.md`；针对文件目标统一落盘为 `Docs/researches/<dirname>/<basename>_research.md`（`.ops/research_guard.sh:190-208`）。

4. 研究流程可恢复性  
`research_guard` 每轮都会刷新 checklist/todo，并通过 `.cron` 状态文件记录执行状态，使 `Docs/researches` 与调度状态具备持续推进能力（`.ops/research_guard.sh:9-14,165-178,211-271`）。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程（调用方 -> `Docs/` -> 被调用方）

1. `bash .ops/research_guard.sh` 启动后先生成/刷新 checklist（`.ops/research_guard.sh:165-169`）。
2. 再生成当天 todo，并记录 todo 路径到日志（`.ops/research_guard.sh:171-173`）。
3. 从 checklist 中抓取第一个 pending 项并解析 `TARGET_TYPE`、`TARGET_PATH`（`.ops/research_guard.sh:174-188`）。
4. 计算报告路径并创建目录：若目标是 `DIR Docs`，路径即 `Docs/researches/Docs/current_folder_research.md`（`.ops/research_guard.sh:192-210`）。
5. 组装中文任务模板，调用 `codex --yolo exec "$TASK"` 非 REPL 执行（`.ops/research_guard.sh:214-246`）。
6. 执行结束后按返回码写入状态，并可做 checkpoint 提交（`.ops/research_guard.sh:248-271`）。

### 2) 数据结构与文本协议

`Docs/` 目录中的研究状态文件是“Markdown + 正则协议”：

1. Checklist 条目协议  
`- [ ] [DIR] path` / `- [x] [FILE] path`。  
脚本通过正则提取 mark/kind/path 并恢复历史状态（`.ops/generate_research_blueprint_checklist.sh:13-23`）。

2. 状态保持结构  
`generate_research_blueprint_checklist.sh` 使用 `declare -A STATUS`，key 为 `DIR:path` 或 `FILE:path`，避免重生成时丢失完成标记（`.ops/generate_research_blueprint_checklist.sh:10-25,55-64`）。

3. Todo 派生协议  
每日 todo 直接复用 checklist 正则筛选 pending 行（`.ops/generate_daily_research_todo.sh:15-18,33-38`）。

4. 目录命名协议  
目录研究报告固定为 `current_folder_research.md`；文件研究报告固定为 `<原文件名>_research.md`（`.ops/research_guard.sh:198,207,227-229`）。

### 3) 关键命令

1. `bash .ops/generate_research_blueprint_checklist.sh`
2. `bash .ops/generate_daily_research_todo.sh`
3. `bash .ops/research_guard.sh`
4. `codex --yolo exec "<任务模板>"`

这些命令共同驱动 `Docs/researches/*` 的产出与更新（`.ops/research_guard.sh:165-173,243-246`）。

## 关键代码路径与文件引用

### 目录内关键文件

1. `Docs/researches/blueprint_checklist.md`  
- 研究覆盖清单主文件，`Docs` 目录项在第 32 行（`Docs/researches/blueprint_checklist.md:32`）。

2. `Docs/researches/todos_20260319.md`  
- 当日 pending 快照；在本次勾选 `DIR Docs` 后，第一项已推进为 `DIR codex-cli`（`Docs/researches/todos_20260319.md:14`）。

3. `Docs/researches/*.md`（已完成研究报告集合）  
- 采用“路径镜像 + 固定命名”归档，如 `.ops/.github/.codex` 等目录研究结果。

### 上游调用方（写入 `Docs/`）

1. `.ops/generate_research_blueprint_checklist.sh`（创建/覆盖 checklist）
2. `.ops/generate_daily_research_todo.sh`（创建/覆盖每日 todo）
3. `.ops/research_guard.sh`（派发研究任务、创建报告文件、写日志状态）

### 下游被调用方（被上游脚本间接调用）

1. `codex` 可执行程序（非 REPL 执行研究任务）  
（`.ops/research_guard.sh:155-163,243-246`）
2. `git`（提交研究产物）  
（`.ops/research_guard.sh:248-254`）
3. `tmux`/`flock`/`timeout`（守护执行控制）  
（`.ops/research_guard.sh:29-58,147-151,242-243`）

## 依赖与外部交互

### 1) 配置与环境变量

`Docs/` 研究流程行为受以下变量影响：

1. `CODEX_BIN`：指定 codex 可执行路径（`.ops/research_guard.sh:8,155-163`）。
2. `CODEX_EXEC_TIMEOUT_SECONDS`：单次研究执行超时（`.ops/research_guard.sh:16,242-246`）。
3. `TMUX_WRAP_ENABLED` / `TMUX_SESSION_NAME` / `RESEARCH_GUARD_WORKER`：是否通过 tmux 包裹（`.ops/research_guard.sh:18-20,29-58`）。
4. `AUTO_CLEANUP_ON_COMPLETE`：全部完成后是否清理 cron（`.ops/research_guard.sh:15,179-181`）。
5. `AUTO_PUSH_ON_CHECKPOINT`：checkpoint 提交后是否尝试 push（`.ops/research_guard.sh:17,253-255`）。

### 2) 外部系统交互

1. 文件系统：读写 `Docs/researches/*` 与 `.cron/*`。
2. 进程/并发：`flock` 锁文件 `/tmp/<project>_research_guard.lock`（`.ops/research_guard.sh:13,147-151`）。
3. 计划任务：可通过 `cleanup_research_cron.sh` 重写 crontab（`.ops/cleanup_research_cron.sh:19-23`）。
4. 版本控制：`git add -A` / `git commit`；可选 `git fetch/push`（`.ops/research_guard.sh:60-145,248-254`）。

### 3) 测试与校验现状

截至当前代码，未发现针对 `Docs/researches` 生成链路的专门自动化测试入口；流程主要依赖 shell 脚本执行结果与人工审阅。  
可见引用集中在 `.ops/*.sh` 与 `Docs/researches/*.md`，未见进入 `.github/workflows/ci.yml` 的显式校验步骤（`.github/workflows/ci.yml:14-66`）。

## 风险、边界与改进建议

### 风险

1. 误提交风险  
`research_guard` 的 checkpoint 使用 `git add -A`，可能把研究目标之外的改动一起提交（`.ops/research_guard.sh:248-252`）。

2. 文档目录命名混淆风险  
`Docs/`（研究产物）与 `docs/`（产品文档）并存，协作者容易误操作路径（`Docs/researches/blueprint_checklist.md:32,508`）。

3. 规模膨胀风险  
全仓库条目很大（当前 pending 数量高），`Docs/researches` 体量会持续增长，审阅与检索成本上升（`Docs/researches/todos_20260319.md:8-11`）。

4. 自动化健壮性风险  
当前链路缺少测试兜底，正则/路径协议一旦变更，可能静默破坏流程。

### 边界

1. `Docs/` 不承载业务可执行逻辑，只承载研究过程文档与状态快照。
2. 该目录是内部流程产物层，不是对外 API 或 SDK 稳定契约。
3. 研究质量依赖执行者与评审流程，不由脚本自动保证。

### 改进建议

1. 为研究脚本增加最小测试（如 Bats）：覆盖 checklist 解析、路径命名、todo 统计。
2. 将 checkpoint 提交范围从 `git add -A` 收敛为白名单（仅 `Docs/researches/**`、必要 `.ops` 文件）。
3. 在仓库文档补充“`Docs/` vs `docs/`”说明，降低协作误解。
4. 给 `Docs/researches` 增加索引/分层归档（按日期或域分目录）以降低长期维护成本。
