# DIR `codex-rs/cloud-tasks/src` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/cloud-tasks/src`
- 代码规模：8 个源文件，约 3752 LoC（`lib.rs` 2385 行，`ui.rs` 1046 行）
- 上游入口：`codex-rs/cli/src/main.rs` 的 `cloud` 子命令路由
- 直接下游核心：`codex-rs/cloud-tasks-client`（CloudBackend trait + HTTP/mock + 本地 apply）

## 场景与职责

`codex-rs/cloud-tasks/src` 是 `codex cloud` 功能的主编排层，承担两种使用场景：

1. 命令式场景（非 TUI）
- `codex cloud exec/status/list/diff/apply`
- 目标是快速提交任务、查询状态、导出 diff、执行本地 apply。

2. 交互式场景（TUI）
- `codex cloud`（无子命令）
- 目标是浏览任务列表、环境筛选、查看 diff/对话、切换 attempts、预检并应用补丁、创建新任务。

职责边界（本目录负责）：

- CLI 子命令参数模型（`cli.rs`）
- 运行时 backend 初始化（mock/online）、鉴权装配、环境解析
- TUI 状态机、事件循环、异步任务编排、键盘交互与视图渲染
- 文本封装（相对时间、错误信息整形、滚动换行视图）

职责边界（本目录不负责）：

- Cloud API 的底层 HTTP 细节与数据回退解析（在 `cloud-tasks-client/src/http.rs`）
- 后端统一模型提取（`backend-client`）
- 真正 git apply 引擎（`codex_git::apply_git_patch`）
- 登录流程本身（`codex login` 由 `codex-login`/`codex-core` 体系负责）

## 功能点目的

### 1) 子命令参数与输入约束

- `Exec/Status/List/Apply/Diff` 五类子命令统一在 `src/cli.rs`。
- `attempts` 限制为 1..=4，`list --limit` 限制为 1..=20，避免调用端传递无界参数。
- `exec` 支持 `QUERY` 参数或 stdin；`-` 强制 stdin 模式。

目的：
- 让 cloud 任务能力可脚本化（CI/自动化）并保持参数边界稳定。

### 2) Backend 初始化与鉴权

- `init_backend`：读取 `CODEX_CLOUD_TASKS_MODE` 决定 `MockClient` 或 `HttpClient`。
- 默认 base URL：`https://chatgpt.com/backend-api`。
- online 模式下加载本地 AuthManager，读取 token/account id，拼装 `Authorization` 与 `ChatGPT-Account-Id`。
- 缺少登录态时直接提示 `codex login` 并退出。

目的：
- 让 cloud 功能可在 mock 与真实后端间切换。
- 与 ChatGPT Web API（wham path）兼容，同时允许 codex-api 风格路径。

### 3) 环境（Environment）识别与筛选

- `resolve_environment_id`：支持用环境 id 或 label 指定，处理 label 歧义。
- `env_detect::autodetect_environment_id`：优先基于 git origin（GitHub owner/repo）查 by-repo，再回退全量环境列表。
- `env_detect::list_environments`：合并 by-repo 与全量列表，去重、排序（pinned 优先）。

目的：
- 减少用户手动找环境 id 的成本，支持仓库上下文自动贴合。

### 4) 任务列表、详情、多 attempt 展示

- `app::load_tasks`：拉取列表并过滤 `is_review` 任务。
- `DiffOverlay + AttemptView`：统一管理 diff/prompt 两视图与 attempt 切换。
- `collect_attempt_diffs`：组合 base attempt + sibling attempts，按 placement/time 排序。

目的：
- 让 best-of-N 结果可浏览、可选择，并在 TUI 内完成“看 + 选 + 应用”。

### 5) Apply 预检与执行

- 两阶段：`apply_task_preflight`（不改工作区）+ `apply_task`（实际落盘）。
- TUI 中 `a` 会先触发 preflight，再进入确认 modal（`y/p/n`）。
- CLI `apply` 支持 `--attempt` 选择某次候选 diff。

目的：
- 降低误应用风险，先暴露冲突/跳过路径，再决定是否执行。

### 6) 新任务创建（含 best-of）

- New Task 页面复用 `codex_tui::ComposerInput`，支持多行、粘贴 burst、快捷键。
- 支持 `Ctrl+N` 选择 attempts（1~4），`create_task` 时通过 metadata 传 `best_of_n`。
- 自动推断 git ref（优先当前分支，再 default 分支，再 `main`）。

目的：
- 在 cloud 入口直接完成提交，不必回到其它命令路径。

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 顶层调用链

1. `codex` 顶层命令解析：`cli/src/main.rs`
2. 命中 `Subcommand::Cloud` 后调用 `codex_cloud_tasks::run_main(...)`
3. `run_main` 分流：
- 有子命令 -> 走 exec/status/list/diff/apply
- 无子命令 -> 进入 TUI 事件循环

### B. 关键数据结构

1. `App`（`src/app.rs`）
- 统一 UI 状态：tasks、selection、env modal、new task、apply modal、overlay、spinner、inflight flags。

2. `DiffOverlay`
- 维护当前任务详情视图（Diff/Prompt）
- 维护 attempts 列表、当前选中 attempt、可 apply 判定、滚动状态。

3. `AppEvent`
- 后台异步结果统一回传通道（任务加载、详情加载、attempts 加载、preflight/apply 完成等）。

4. `ScrollableDiff`
- 本地缓存 raw/wrapped 行，按宽度重包裹，记录源行索引，支持分页和滚动百分比。

### C. TUI 主循环机制

核心在 `src/lib.rs:732-2011`：

- `crossterm` 进入 raw mode + alternate screen
- `tokio` 通道驱动：
  - `AppEvent` 处理业务结果
  - `frame_tx/redraw_rx` 做“最早截止时间”聚合重绘
- UI 不阻塞：
  - 首次列表加载、环境列表加载、环境自动检测并行启动
  - 详情加载并行请求 diff 与 messages
- 按键优先级：
  - modal > overlay > new task > env modal > base list

### D. Cloud 协议与路径风格

CloudBackend 实际实现来自 `cloud-tasks-client`，路径风格由 base_url 推断：

- ChatGPT 风格（包含 `/backend-api`）：`/wham/...`
- Codex API 风格：`/api/codex/...`

关键 HTTP 路径：

- 列表：`GET /wham/tasks/list` 或 `GET /api/codex/tasks/list`
- 详情：`GET /wham/tasks/{id}` 或 `GET /api/codex/tasks/{id}`
- sibling attempts：`GET .../tasks/{task}/turns/{turn}/sibling_turns`
- 创建：`POST /wham/tasks` 或 `POST /api/codex/tasks`

环境相关路径（`env_detect.rs` 直接 reqwest）：

- by-repo：`.../wham/environments/by-repo/github/{owner}/{repo}`（或 `/api/codex/...`）
- 全量：`.../wham/environments`（或 `/api/codex/environments`）

### E. Apply 技术细节（本地执行）

在 `cloud-tasks-client/src/http.rs::Apply::run`：

1. 取 diff（优先 `diff_override`，否则拉 task details）
2. 校验 unified diff 格式
3. 调 `codex_git::apply_git_patch`，参数包括：
- `cwd = current_dir()`
- `preflight = true/false`
- `revert = false`
4. 将返回映射为 `ApplyStatus::Success/Partial/Error`
5. 输出 `skipped_paths/conflict_paths` 与 message

说明：
- preflight 不改工作区，仅校验可应用性。
- apply/preflight 的失败细节会追加写入 `error.log`。

### F. 命令语义（用户面）

- `codex cloud`
- `codex cloud exec [QUERY] --env <ENV_ID> [--attempts N] [--branch BRANCH]`
- `codex cloud list [--env ...] [--limit ...] [--cursor ...] [--json]`
- `codex cloud status <TASK_ID>`
- `codex cloud diff <TASK_ID> [--attempt N]`
- `codex cloud apply <TASK_ID> [--attempt N]`

### G. 配置与环境变量

1. `CODEX_CLOUD_TASKS_MODE`
- `mock` 时走 `MockClient`。

2. `CODEX_CLOUD_TASKS_BASE_URL`
- 指定后端地址；`chatgpt.com/chat.openai.com` 会规范化到 `/backend-api`。

3. `CODEX_CLOUD_TASKS_FORCE_INTERNAL`
- 当前仅写 startup log，不影响实际请求参数（代码中无行为分支）。

4. `CODEX_STARTING_DIFF`
- 在 create_task 时作为 `pre_apply_patch` 输入项注入（`cloud-tasks-client`）。

### H. 测试覆盖现状

目录内/直接相关测试：

- `cloud-tasks/src/app.rs`：`load_tasks` 环境参数行为
- `cloud-tasks/src/lib.rs`：
  - git ref 选择策略
  - task id 解析
  - attempt 选择边界
  - 文本格式化输出
- `cloud-tasks/tests/env_filter.rs`：mock backend 在不同 env 下返回差异

间接依赖测试：

- `backend-client/src/types.rs` 单测 + fixtures（task details diff/error 解析）

测试缺口：

- `env_detect.rs` 几乎无直接测试（git origin 解析、排序、回退策略）
- `ui.rs` 无 snapshot 测试（用户可见渲染未被视觉回归保护）

## 关键代码路径与文件引用

### 入口与路由

- `codex-rs/cli/src/main.rs:138-140`（`cloud` 子命令定义）
- `codex-rs/cli/src/main.rs:779-786`（调用 `codex_cloud_tasks::run_main`）

### 本目录主实现

- `codex-rs/cloud-tasks/src/cli.rs:15-120`（命令参数）
- `codex-rs/cloud-tasks/src/lib.rs:40-108`（backend 初始化与 auth）
- `codex-rs/cloud-tasks/src/lib.rs:158-605`（exec/status/list/diff/apply）
- `codex-rs/cloud-tasks/src/lib.rs:732-2011`（TUI 主循环）
- `codex-rs/cloud-tasks/src/lib.rs:2016-2120`（conversation/error 文本整形）
- `codex-rs/cloud-tasks/src/app.rs:47-75`（`App`）
- `codex-rs/cloud-tasks/src/app.rs:136-289`（`DiffOverlay`/`AttemptView`）
- `codex-rs/cloud-tasks/src/app.rs:300-350`（`AppEvent`）
- `codex-rs/cloud-tasks/src/ui.rs:28-57`（主 draw）
- `codex-rs/cloud-tasks/src/ui.rs:312-467`（详情 overlay）
- `codex-rs/cloud-tasks/src/ui.rs:893-1046`（环境 modal / attempts modal）
- `codex-rs/cloud-tasks/src/env_detect.rs:25-108`（autodetect）
- `codex-rs/cloud-tasks/src/env_detect.rs:256-362`（list_environments）
- `codex-rs/cloud-tasks/src/scrollable_diff.rs:26-176`
- `codex-rs/cloud-tasks/src/util.rs:31-43`（base_url normalize）
- `codex-rs/cloud-tasks/src/util.rs:74-106`（ChatGPT headers）

### 下游依赖关键实现

- `codex-rs/cloud-tasks-client/src/api.rs:133-170`（`CloudBackend` trait）
- `codex-rs/cloud-tasks-client/src/http.rs:145-377`（list/summary/diff/text/create）
- `codex-rs/cloud-tasks-client/src/http.rs:399-413`（sibling attempts）
- `codex-rs/cloud-tasks-client/src/http.rs:427-558`（apply/preflight）
- `codex-rs/backend-client/src/client.rs:268-393`（任务 API 请求）
- `codex-rs/backend-client/src/types.rs:260-305`（task details 扩展解析）

### 测试

- `codex-rs/cloud-tasks/tests/env_filter.rs:1-27`
- `codex-rs/cloud-tasks/src/app.rs:353-512`
- `codex-rs/cloud-tasks/src/lib.rs:2122-2385`
- `codex-rs/backend-client/src/types.rs:321-376`（间接相关）

### 构建/脚本/文档

- `codex-rs/cloud-tasks/Cargo.toml:1-46`
- `codex-rs/cloud-tasks/BUILD.bazel:1-6`
- `codex-rs/cloud-tasks-client/Cargo.toml:1-29`
- `codex-rs/cloud-tasks-client/BUILD.bazel:1-9`
- `.ops/generate_daily_research_todo.sh:1-42`
- `Docs/researches/blueprint_checklist.md:180`

## 依赖与外部交互

### 依赖关系（核心）

1. `codex-cloud-tasks-client`
- 提供 CloudBackend 抽象与 online/mock 双实现。

2. `codex-backend-client`
- 处理任务列表/详情/创建/sibling_turns 的 HTTP 封装。

3. `codex-core` + `codex-login` + `codex-client`
- 登录态加载、默认 UA、带自定义 CA 的 reqwest client。

4. `codex-tui`
- 复用 `ComposerInput` 和 markdown 渲染能力。

5. `ratatui` + `crossterm`
- 终端 UI 与输入事件。

6. `codex_git`
- 本地 diff 应用/预检执行引擎。

### 外部交互面

1. 网络
- Cloud Tasks API（`/wham` 或 `/api/codex`）
- Environments API（包括 by-repo）

2. 文件系统
- 在当前工作目录写 `error.log`
- apply/preflight 在 `current_dir` 执行 git patch

3. 进程/命令
- `env_detect` 通过 `git config --get-regexp remote\..*\.url`、`git remote -v` 读取 origin

4. 终端
- 启用 raw mode/alternate screen/bracketed paste/keyboard enhancement flags

### 配置与可运维性

- 主要依赖运行时环境变量 + 本地登录态。
- 文档层面：本 crate 内无独立 README，用户可见行为主要由 CLI help 与代码注释定义。

## 风险、边界与改进建议

### 1) 模块体积与耦合风险（高）

现状：`lib.rs` 达 2385 行，集成了命令分发、TUI 主循环、业务异步编排、键盘逻辑和文本整形。

风险：
- 小改动易引入事件竞态/交互回归。
- review 成本高，行为边界不清。

建议：
- 拆分 `run_main` 相关逻辑为 `tui_runtime/keyboard_handlers/background_jobs` 子模块。
- 将 apply/new-task/env-modal 键盘处理拆成独立 handler 文件。

### 2) 配置覆盖未贯通（高）

现状：`Cli.config_overrides` 进入 cloud 路由，但 cloud-tasks 内 `load_auth_manager` 仍调用 `Config::load_with_cli_overrides(Vec::new())`。

风险：
- 用户传入的配置覆盖对 cloud 链路可能不生效，行为与其它子命令不一致。

建议：
- 将 CLI overrides 显式传入 `run_main -> init_backend -> util::load_auth_manager`。
- 增加对应单测，覆盖“覆盖项影响 auth/base_url”的路径。

### 3) URL 规范化与日志写入重复（中）

现状：`cloud-tasks/src/util.rs` 与 `backend-client::Client::new` 均做 base_url 规范化；`error.log` 在 cloud-tasks 与 cloud-tasks-client 各写一套。

风险：
- 规则漂移导致路径风格不一致。
- 日志格式分叉、排障体验不统一。

建议：
- 抽取共享 URL/path-style helper；统一 `error.log` writer 或接入 tracing。

### 4) 环境探测边界（中）

现状：
- by-repo 仅支持 GitHub origin 形态。
- `git` 调用为同步命令；非 git 目录或非 GitHub 远端直接回退。

风险：
- 企业镜像域名/非 GitHub 平台无法自动探测。
- origin 解析失败时用户缺乏可见提示（除 error.log）。

建议：
- 扩展 host 匹配策略（可配置 allowlist）。
- 提升前台可见错误提示与调试输出（可选 verbose 模式）。

### 5) 测试覆盖缺口（中）

现状：
- `env_detect.rs`、`ui.rs` 缺少直接测试与 snapshot。
- 大量用户可见文案/布局仅靠人工验证。

建议：
- 为 `ui.rs` 增加 ratatui snapshot（尤其 overlay/modal/footer）。
- 为 `env_detect` 添加纯函数单测：origin 解析、排序、label 歧义处理、回退策略。

### 6) 状态字段与语义噪声（低）

现状：`CODEX_CLOUD_TASKS_FORCE_INTERNAL` 当前仅记录日志，不参与行为。

风险：
- 名称暗示功能开关，但实际无效，易误导。

建议：
- 要么接入真实逻辑，要么删除该变量与日志字段，减少认知负担。

### 7) 交互逻辑可读性风险（低）

现状：base list 的 `r` 分支包含 `if app.env_modal.is_some() { break 0; }`，在当前分支结构下几乎不可达，但语义上是“退出程序”。

风险：
- 后续重构分支时易触发意外退出。

建议：
- 删除该判断，或改为明确 no-op + 状态提示。

