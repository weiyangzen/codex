# DIR `codex-rs/cloud-tasks` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/cloud-tasks`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 关联 crate：`codex-cloud-tasks`

## 场景与职责

`codex-rs/cloud-tasks` 是 `codex cloud` 子命令的实现核心，承担“云端任务浏览 + 本地应用”的桥接职责，覆盖两类运行形态：

1. 非交互 CLI 模式
- `exec`：创建云任务并输出任务 URL。
- `status/list`：查询任务状态与列表。
- `diff/apply`：读取任务 diff，并支持按 attempt 选择后应用。

2. 交互式 TUI 模式（`codex cloud` 无子命令时）
- 列表浏览任务，异步加载详情。
- 展示 prompt / assistant 输出 / diff。
- 支持 environment 选择、best-of-N 新任务提交、preflight/apply。

3. 统一运行上下文
- 从登录态读取 ChatGPT token/account 信息，构建 `CloudBackend`。
- 通过 `cloud-tasks-client` 访问后端协议与本地 git apply 引擎。

## 功能点目的

### 1) 命令面定义与参数约束
- 目的：保证 `codex cloud` 子命令参数语义稳定、错误尽早暴露。
- 实现：`cli.rs` 定义 `Exec/Status/List/Apply/Diff`，并约束：
  - `attempts` 仅允许 `1..=4`。
  - `list --limit` 仅允许 `1..=20`。

### 2) 后端初始化与鉴权兜底
- 目的：在 mock/online 两种后端间切换，并对未登录场景给出明确错误。
- 实现：`init_backend` 读取 `CODEX_CLOUD_TASKS_MODE` 与 `CODEX_CLOUD_TASKS_BASE_URL`，构建 `MockClient` 或 `HttpClient`；若无有效登录态则直接提示 `codex login`。

### 3) 环境解析与自动选择
- 目的：让 `--env` 既可传 id 也可传 label，并在 TUI 启动时自动选取最相关环境。
- 实现：
  - 显式解析：先按 id，再按 label（含“label 冲突”错误）。
  - 自动检测：优先 by-repo（根据 git remote 推导 GitHub owner/repo），再回退全量环境列表。

### 4) 多 attempt 详情与应用
- 目的：支持 best-of-N 任务查看与选择性 apply，避免只看“主 attempt”。
- 实现：
  - 拉取当前 turn + sibling turns。
  - 依据 `attempt_placement`/`created_at` 排序。
  - TUI 中用 `Tab`/`Shift-Tab`/`[ ]` 切换 attempt。

### 5) 安全应用链路（Preflight -> Apply）
- 目的：在真正改动工作区前先验证 patch 可应用性，并反馈冲突/跳过文件。
- 实现：`spawn_preflight` 与 `spawn_apply` 分离并行任务，结果通过 `AppEvent` 回传 UI；失败细节落 `error.log`。

### 6) 新任务创建体验
- 目的：在 TUI 内完成 prompt 输入、环境选择、attempt 设定与提交刷新闭环。
- 实现：`NewTaskPage + ComposerInput`，支持 `Ctrl+O` 选环境、`Ctrl+N` 设 best-of。

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 启动与后端构建流程

1. Backend 初始化
- 入口：`src/lib.rs:40-108`
- 关键点：
  - `CODEX_CLOUD_TASKS_MODE=mock` 切换 `MockClient`。
  - base URL 默认 `https://chatgpt.com/backend-api`。
  - 注入 UA suffix（如 `codex_cloud_tasks_tui` / `..._list` / `..._apply`）。
  - token + `ChatGPT-Account-Id` 注入 `HttpClient`。

2. URL 归一化
- `src/util.rs:31-43`：去除尾斜杠，ChatGPT host 自动补 `/backend-api`。
- `src/util.rs:109-121`：任务 URL 映射为浏览器可打开形态（`/codex/tasks/{id}`）。

### B. 非交互命令执行链路

1. `exec`
- `src/lib.rs:158-181`
- 流程：解析 query（参数或 stdin）-> 解析 env -> 解析 git ref -> `create_task` -> 输出 URL。

2. `status`
- `src/lib.rs:494-508`
- 拉取 summary，格式化三行输出；状态非 `READY` 时返回非零退出码。

3. `list`
- `src/lib.rs:510-575`
- 支持 JSON 输出和 cursor 翻页提示；文本模式下按状态/时间/diff summary 渲染。

4. `diff`
- `src/lib.rs:577-584`
- 先收集所有 attempt diff，再按 `--attempt` 选中并输出。

5. `apply`
- `src/lib.rs:586-605`
- 与 `diff` 同样支持 attempt 选择；调用 backend `apply_task`，非 success 以非零退出。

### C. TUI 事件循环与并发模型

1. 主循环结构
- `src/lib.rs:732-2011`
- 使用 `crossterm EventStream` + `tokio::select!` 处理：
  - 键盘/粘贴事件。
  - 后台任务事件（`AppEvent` channel）。
  - 合并后的 redraw 信号（frame coalescing）。

2. 后台任务通信
- `AppEvent` 定义：`src/app.rs:300-350`
- 主要事件：`TasksLoaded`、`Details*`、`AttemptsLoaded`、`ApplyPreflightFinished`、`ApplyFinished`、`EnvironmentsLoaded`、`EnvironmentAutodetected`。

3. 重绘节流
- `src/lib.rs:872-921`
- 通过 deadline 合并重绘请求，避免固定 tick 带来的无效刷新；仅在 inflight 状态推进 spinner。

### D. 详情/attempt 数据结构

1. 应用状态机
- `App`：`src/app.rs:47-75`（任务列表、模态框、inflight 标记、环境缓存等）
- `DiffOverlay`：`src/app.rs:136-150`（当前任务详情面板）
- `AttemptView`：`src/app.rs:152-161`（每个 attempt 的 diff/text/prompt/status）

2. attempt 切换与视图切换
- `DiffOverlay::step_attempt`：`src/app.rs:229-242`
- `DiffOverlay::set_view/apply_selection_to_fields`：`src/app.rs:205-288`
- 保持 `Prompt` / `Diff` 双视图共享同一滚动容器。

### E. Environment 自动检测与筛选协议

1. 自动检测算法
- `src/env_detect.rs:25-108`
- 优先 by-repo：`/wham/environments/by-repo/github/{owner}/{repo}`（或 `/api/codex/...`）
- 回退全量：`/wham/environments`（或 `/api/codex/environments`）
- 选择策略：label 精确匹配 -> 单项 -> pinned -> task_count 最大。

2. git remote 推断
- `src/env_detect.rs:171-252`
- 兼容 `git@github.com:owner/repo`、`https://github.com/owner/repo(.git)` 等形态。

3. TUI 环境列表
- `src/env_detect.rs:256-362` 返回 `EnvironmentRow`，去重合并、pinned 优先排序。

### F. Apply 实际执行协议（经 cloud-tasks-client）

1. 入口调用
- `spawn_preflight/spawn_apply`：`src/lib.rs:615-725`
- 后端 trait：`codex-rs/cloud-tasks-client/src/api.rs:133-170`

2. 执行引擎
- `cloud-tasks-client` `Apply::run`：`codex-rs/cloud-tasks-client/src/http.rs:427-558`
- 核心步骤：
  - 校验 unified diff。
  - 构建 `codex_git::ApplyGitRequest`（`preflight`/`revert=false`）。
  - 基于 `exit_code` + 路径统计映射 `Success/Partial/Error`。
  - 返回 `ApplyOutcome`（message + skipped/conflict paths）。

### G. UI 渲染实现

1. 总体布局
- `src/ui.rs:28-57`
- 主区 + 两行 footer；可叠加 diff/env/best-of/apply 模态。

2. 列表与详情
- 列表：`src/ui.rs:176-234`
- 详情 overlay：`src/ui.rs:312-467`
- conversation/diff 样式：`src/ui.rs:558-786`

3. 滚动与换行
- `src/scrollable_diff.rs:26-176`
- 维护 raw->wrapped 映射、支持 Unicode 宽度、分页滚动与滚动百分比。

### H. 命令与环境变量清单

1. 主要命令
- `codex cloud`
- `codex cloud exec [QUERY] --env <ENV_ID> [--attempts N] [--branch BRANCH]`
- `codex cloud list [--env ...] [--limit ...] [--cursor ...] [--json]`
- `codex cloud status <TASK_ID>`
- `codex cloud diff <TASK_ID> [--attempt N]`
- `codex cloud apply <TASK_ID> [--attempt N]`

2. 环境变量
- `CODEX_CLOUD_TASKS_MODE`：mock/online 切换。
- `CODEX_CLOUD_TASKS_BASE_URL`：后端基地址。
- `CODEX_CLOUD_TASKS_FORCE_INTERNAL`：当前仅记录日志，不直接影响请求参数。
- `CODEX_STARTING_DIFF`：create_task 时可注入 `pre_apply_patch` 输入项（在 `cloud-tasks-client` 层）。

## 关键代码路径与文件引用

### 目标目录内（cloud-tasks）

1. crate 配置
- `codex-rs/cloud-tasks/Cargo.toml:1-46`
- `codex-rs/cloud-tasks/BUILD.bazel:1-6`

2. 命令定义
- `codex-rs/cloud-tasks/src/cli.rs:5-120`

3. 主调度与命令执行
- `codex-rs/cloud-tasks/src/lib.rs:40-108`（backend init）
- `codex-rs/cloud-tasks/src/lib.rs:158-605`（exec/status/list/diff/apply）
- `codex-rs/cloud-tasks/src/lib.rs:732-2011`（TUI 主循环）
- `codex-rs/cloud-tasks/src/lib.rs:2016-2120`（conversation/error 文本整形）

4. 应用状态机
- `codex-rs/cloud-tasks/src/app.rs:47-75`（`App`）
- `codex-rs/cloud-tasks/src/app.rs:136-289`（`DiffOverlay`/`AttemptView`）
- `codex-rs/cloud-tasks/src/app.rs:300-350`（`AppEvent`）

5. 环境检测
- `codex-rs/cloud-tasks/src/env_detect.rs:25-108`（autodetect）
- `codex-rs/cloud-tasks/src/env_detect.rs:256-362`（list_environments）

6. UI 与滚动
- `codex-rs/cloud-tasks/src/ui.rs:28-57`（主 draw）
- `codex-rs/cloud-tasks/src/ui.rs:312-467`（详情 overlay）
- `codex-rs/cloud-tasks/src/scrollable_diff.rs:26-176`

7. 公共工具
- `codex-rs/cloud-tasks/src/util.rs:31-43`（base_url normalize）
- `codex-rs/cloud-tasks/src/util.rs:74-106`（auth headers）

8. 新任务页面
- `codex-rs/cloud-tasks/src/new_task.rs:3-35`

9. 测试
- `codex-rs/cloud-tasks/tests/env_filter.rs:1-27`
- `codex-rs/cloud-tasks/src/app.rs:353-512`
- `codex-rs/cloud-tasks/src/lib.rs:2122-2385`

### 调用方（上游）

1. CLI 总入口路由
- `codex-rs/cli/src/main.rs:138-140`（定义 `cloud` 子命令）
- `codex-rs/cli/src/main.rs:779-786`（调用 `codex_cloud_tasks::run_main`）
- `codex-rs/cli/Cargo.toml:27`（依赖 `codex-cloud-tasks`）

### 被调用方（下游）

1. cloud-tasks-client 协议与实现
- `codex-rs/cloud-tasks-client/src/api.rs:133-170`（`CloudBackend`）
- `codex-rs/cloud-tasks-client/src/http.rs:62-124`（HttpClient 实现 trait）
- `codex-rs/cloud-tasks-client/src/http.rs:145-377`（list/summary/diff/text/create）
- `codex-rs/cloud-tasks-client/src/http.rs:399-413`（sibling attempts）
- `codex-rs/cloud-tasks-client/src/http.rs:427-558`（preflight/apply）

2. 关键基础组件
- `codex-core`（UA、git branch 推导、配置加载）
- `codex-login`（AuthManager）
- `codex-tui`（ComposerInput 与 markdown 渲染）
- `codex-git`（实际 patch apply）
- `codex-backend-client`（后端 HTTP 任务接口）

### 配置、脚本、文档上下文

1. 工作区注册
- `codex-rs/Cargo.toml:16-17`（workspace 成员）

2. 当日研究清单生成脚本
- `.ops/generate_daily_research_todo.sh:1-42`

3. 研究 checklist
- `Docs/researches/blueprint_checklist.md:177`（本次勾选项）

4. 文档现状
- 代码目录未见独立 README；当前行为主要由源码、测试与上层 CLI 文档语义共同定义。

## 依赖与外部交互

### 内部依赖

1. `codex-cloud-tasks-client`
- 提供统一 trait 和 mock/online 双实现；`cloud-tasks` 仅依赖 trait，不直接耦合 HTTP 细节。

2. `codex-core` / `codex-login`
- 读取本地配置、登录状态、token/account_id、分支信息。

3. `codex-tui` / `ratatui` / `crossterm`
- 负责终端 UI 交互、输入事件与渲染。

4. `tokio` / `tokio-stream`
- 负责异步任务并发与事件调度。

### 外部交互

1. HTTP 接口
- 列表：`GET /wham/tasks/list` 或 `GET /api/codex/tasks/list`
- 详情：`GET /wham/tasks/{id}` 或 `GET /api/codex/tasks/{id}`
- sibling：`GET /wham/tasks/{task}/turns/{turn}/sibling_turns` 或对应 `/api/codex`
- 创建：`POST /wham/tasks` 或 `POST /api/codex/tasks`
- 环境：`GET /wham/environments*` / `GET /api/codex/environments*`

2. 本地 git 与文件系统
- `env_detect` 调用 `git config --get-regexp remote\..*\.url` 与 `git remote -v`。
- apply/preflight 通过 `codex_git::apply_git_patch` 修改或验证当前工作区。
- 多处失败日志写入 `error.log`。

3. 终端能力
- 使用 alternate screen、raw mode、bracketed paste、增强键盘事件标志；退出时做 best-effort 恢复。

## 风险、边界与改进建议

1. 运行循环过大，维护风险高
- 现状：`run_main` 单函数体量极大（`src/lib.rs:732-2011`），事件分支深，回归风险高。
- 建议：拆分为 `event_handlers` / `commands` / `background_jobs` 模块，按视图状态机分层。

2. 错误日志策略较粗放
- 现状：`error.log` 固定写当前目录（`util.rs:16-26`），并记录较多原始响应体。
- 风险：目录权限不一致、日志泄露敏感内容、日志无限增长。
- 建议：改到 `codex_home/logs`，做轮转与敏感字段脱敏。

3. 环境检测仅 GitHub 导向
- 现状：`parse_owner_repo` 仅覆盖 GitHub URL 形态（`env_detect.rs:218-252`）。
- 边界：GitLab/Bitbucket 或自托管仓库无法利用 by-repo 优势。
- 建议：抽象 provider 并扩展 host 适配表。

4. `CODEX_CLOUD_TASKS_FORCE_INTERNAL` 仅记录日志
- 现状：读取后只写日志（`lib.rs:794-804`），未实际改变 API 请求。
- 风险：配置名与行为不一致，排障时易误导。
- 建议：要么落实参数透传，要么移除该 env 并保留文档解释。

5. TUI 键位分支存在可读性与边界问题
- 现状：键盘处理链很长，多模态互斥逻辑分散；例如 `r` 分支里仍有 `env_modal` 判断（`lib.rs:1796-1799`）可读性较差。
- 建议：采用“当前模式 -> keymap”表驱动，减少跨分支状态判断。

6. 测试覆盖仍偏功能片段
- 现状：已有参数/格式化/mock/env 等测试，但缺少多事件并发序列、真实失败恢复、apply 冲突 UI 展示的集成验证。
- 建议：补充 TUI 事件回放测试（含 `AppEvent` 序列）、以及 apply partial/error 的快照测试。

7. 协议路径风格分散
- 现状：`cloud-tasks` 与 `cloud-tasks-client` 各自做 base_url/path_style 推断。
- 风险：后端路径规则变化时需多点同步。
- 建议：下沉为共享 path-style 模块，统一 `backend-api/wham` 与 `api/codex` 选择逻辑。
