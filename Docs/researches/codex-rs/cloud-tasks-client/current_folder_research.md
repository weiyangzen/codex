# DIR `codex-rs/cloud-tasks-client` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/cloud-tasks-client`
- 代码规模：5 个源码文件（`src/lib.rs`、`src/api.rs`、`src/http.rs`、`src/mock.rs`、构建清单）
- crate：`codex-cloud-tasks-client`
- 直接调用方：`codex-rs/cloud-tasks`
- 主要下游依赖：`codex-rs/backend-client`、`codex-rs/utils/git`（crate 名 `codex-git`）

## 场景与职责

`cloud-tasks-client` 是 `codex cloud` 功能的“后端协议适配 + 本地 apply 执行”中间层。它把调用方（`codex-rs/cloud-tasks`）从以下细节中解耦：

1. 远端 Cloud Tasks API 细节
- 任务列表、任务详情、兄弟尝试（best-of-N）查询。
- 任务创建请求体组装。
- 路径风格兼容（`/api/codex/*` 与 `/wham/*` 由下游 `backend-client` 处理）。

2. 任务详情结果整形
- 将异构 JSON 字段映射为统一领域模型：`TaskSummary`、`TaskText`、`TurnAttempt`、`DiffSummary` 等。
- 对 assistant 文本与 diff 提供多层回退提取逻辑。

3. 本地 patch 应用入口
- `apply_task_preflight`：仅验证可应用性（不改工作区）。
- `apply_task`：真正执行 `git apply`（通过 `codex-git`）。

4. 可替换后端抽象
- 用 trait `CloudBackend` 统一 `HttpClient`（online）与 `MockClient`（mock）实现。

职责边界上，本 crate 不负责：登录态获取、token 刷新、CLI 参数解析、TUI 交互、环境自动探测；这些由 `cloud-tasks` 侧承担。

## 功能点目的

### 1) 统一领域模型与接口契约
- 文件：`codex-rs/cloud-tasks-client/src/api.rs`
- 目的：为上层提供稳定 API，避免上层直接依赖后端 JSON。
- 关键模型：
  - `TaskSummary`：列表/状态页核心字段（含 `environment_*`、`attempt_total`、`is_review`）。
  - `TaskText`：prompt + assistant messages + 当前尝试上下文。
  - `TurnAttempt`：best-of-N sibling attempt 数据载体。
  - `ApplyOutcome`：apply/preflight 统一结果（含跳过与冲突路径）。

### 2) 在线实现（HttpClient）
- 文件：`codex-rs/cloud-tasks-client/src/http.rs`
- 目的：把 `CloudBackend` 映射到后端 HTTP 协议和本地 patch apply。
- 包含三类子 API：
  - `Tasks`：`list/summary/diff/messages/task_text/create`
  - `Attempts`：`list`（兄弟尝试）
  - `Apply`：`run`（preflight/apply）

### 3) 离线/测试实现（MockClient）
- 文件：`codex-rs/cloud-tasks-client/src/mock.rs`
- 目的：让 `cloud-tasks` 在不依赖后端情况下可运行/可测。
- 特点：
  - 根据 env 返回不同任务集合。
  - 提供固定 diff 和 sibling attempt，覆盖 best-of 展示路径。

### 4) 特性开关与导出面
- 文件：`codex-rs/cloud-tasks-client/src/lib.rs`、`Cargo.toml`
- 目的：按 feature 分离 online/mock 依赖与实现。
- `default = ["online"]`，`mock` 可额外启用。

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 调用链总览
1. CLI 入口 `codex cloud`（`codex-rs/cli/src/main.rs:138-140, 779-786`）
2. 业务编排 `codex-rs/cloud-tasks/src/lib.rs` 初始化后端（`init_backend`）
3. 调用 `CloudBackend` trait 方法
4. `cloud-tasks-client` 执行 HTTP 读取/创建，或本地 `git apply`

### B. 列表与详情读取

#### list_tasks
- `HttpClient::list_tasks` -> `Tasks::list`（`http.rs:63-70`, `145-178`）
- 调用下游：`backend::Client::list_tasks(limit, Some("current"), env, cursor)`。
- 返回映射：`TaskListItem -> TaskSummary`（`map_task_list_item_to_summary`）。
- 细节：列表映射阶段 `environment_id` 固定 `None`（来自列表响应形态限制），`environment_label`/`attempt_total` 走 `task_status_display`。

#### get_task_summary
- 路径：`Tasks::summary`（`http.rs:180-247`）
- 数据来源：`get_task_details_with_body` 返回 `(parsed, raw_body, content_type)`。
- 逻辑：
  - 优先从 raw JSON 中解析 `task`、`task_status_display`。
  - `status` 由 `latest_turn_status_display.turn_status` / `state` 推导。
  - `DiffSummary` 优先 `diff_stats`，为空时回退 `unified_diff` 行统计。
  - `updated_at` 回退链：`task.updated_at -> task.created_at -> latest_turn_timestamp -> Utc::now()`。

#### get_task_diff/get_task_messages/get_task_text
- 路径：`http.rs:249-314`
- 提取策略：
  - 优先 `CodeTaskDetailsResponseExt`（来自 `backend-client` 扩展 trait）。
  - 若消息为空，再从原始 body 执行 `extract_assistant_messages_from_body` 回退解析。
  - `TaskText` 带上 `turn_id/sibling_turn_ids/attempt_placement/attempt_status`，为 best-of 切换提供上下文。

### C. 尝试（best-of-N）读取
- 路径：`Attempts::list`（`http.rs:399-413`）
- 下游协议：`GET .../tasks/{task}/turns/{turn}/sibling_turns`（由 `backend-client` 组装）。
- 映射细节：
  - `turn_attempt_from_map` 提取 `turn_id`、`attempt_placement`、`turn_status`、`created_at`。
  - diff 支持两种 item 形态：`output_diff.diff` 与 `pr.output_diff.diff`。
  - 按 `attempt_placement -> created_at -> turn_id` 排序，保证 UI 稳定顺序。

### D. 任务创建 create_task
- 路径：`Tasks::create`（`http.rs:316-377`）
- 请求体核心结构：
  - `new_task.environment_id`
  - `new_task.branch`
  - `new_task.run_environment_in_qa_mode`
  - `input_items`（至少一个 user message）
- 特殊输入：
  - 当环境变量 `CODEX_STARTING_DIFF` 非空，附加 `pre_apply_patch` item。
  - 当 `best_of_n > 1`，写入 `metadata.best_of_n`。
- 返回：后端创建 ID 转为 `CreatedTask { id: TaskId }`。

### E. apply/preflight 执行
- 路径：`Apply::run`（`http.rs:427-558`）
- 流程：
  1. 获取 diff（优先 `diff_override`，否则拉 task details）。
  2. 校验是否为 unified diff（`is_unified_diff`）。
  3. 调 `codex_git::apply_git_patch`，参数：
     - `cwd = current_dir()`（失败回退 `temp_dir()`）
     - `revert = false`
     - `preflight = true/false`
  4. 根据 `exit_code/applied/skipped/conflicted` 生成 `ApplyStatus`。
  5. 返回 `ApplyOutcome`，并在失败/部分成功场景写 `error.log`（stdout/stderr tail + patch 摘要 + 原始 patch）。

### F. 错误与日志策略
- `CloudTaskError`：`Unimplemented/Http/Io/Msg`。
- `append_error_log`：固定写当前工作目录下 `error.log`（`http.rs:895-905`）。
- 日志内容包括：接口入参摘要、创建结果、apply 失败上下文、patch 头部摘要。

### G. 构建与特性
- Cargo feature：`online`（依赖 `codex-backend-client`）、`mock`。
- Bazel：`BUILD.bazel` 中 crate features 同时声明 `mock` 与 `online`。

## 关键代码路径与文件引用

### 目标目录内部
- `codex-rs/cloud-tasks-client/src/api.rs:6-170`
  - 错误类型、领域模型、`CloudBackend` trait 契约。
- `codex-rs/cloud-tasks-client/src/http.rs:20-124`
  - `HttpClient` 与 trait 实现入口。
- `codex-rs/cloud-tasks-client/src/http.rs:145-377`
  - tasks 读取/创建主逻辑。
- `codex-rs/cloud-tasks-client/src/http.rs:399-413`
  - sibling attempts 列表。
- `codex-rs/cloud-tasks-client/src/http.rs:427-558`
  - apply/preflight 到 `codex-git` 的桥接。
- `codex-rs/cloud-tasks-client/src/http.rs:561-893`
  - 回退解析、排序、diff 统计、patch 判定等工具函数。
- `codex-rs/cloud-tasks-client/src/mock.rs:14-200`
  - mock 后端行为与假数据。
- `codex-rs/cloud-tasks-client/src/lib.rs:1-30`
  - 对外导出与 feature 条件编译。

### 直接调用方（上游）
- `codex-rs/cloud-tasks/src/lib.rs:40-108`
  - 初始化 `HttpClient/MockClient` 与鉴权注入。
- `codex-rs/cloud-tasks/src/lib.rs:158-605`
  - `exec/list/status/diff/apply` 子命令调用 `CloudBackend`。
- `codex-rs/cloud-tasks/src/lib.rs:1110-1313`
  - TUI 详情加载、attempt 合并、apply 结果处理。
- `codex-rs/cloud-tasks/src/lib.rs:1427-1555,1593-1630,1840-1968`
  - 新任务提交、overlay apply/preflight、列表页 apply。
- `codex-rs/cloud-tasks/src/app.rs:121-134,300-350`
  - `load_tasks` 与事件模型消费 `cloud-tasks-client` 领域对象。

### 下游依赖（被调用）
- `codex-rs/backend-client/src/client.rs:268-393`
  - `list_tasks/get_task_details/list_sibling_turns/create_task` HTTP 协议实现。
- `codex-rs/backend-client/src/types.rs:20-305`
  - `CodeTaskDetailsResponse` 与 `CodeTaskDetailsResponseExt` 提取逻辑。
- `codex-rs/utils/git`（crate `codex-git`，调用点 `http.rs:462-469`）
  - 本地 `git apply` 执行引擎。

### 配置与命令入口
- `codex-rs/cloud-tasks/src/lib.rs:42-46`
  - `CODEX_CLOUD_TASKS_MODE`、`CODEX_CLOUD_TASKS_BASE_URL`。
- `codex-rs/cloud-tasks-client/src/http.rs:331-338`
  - `CODEX_STARTING_DIFF`。
- `codex-rs/cloud-tasks/src/cli.rs:15-120`
  - `codex cloud` 子命令参数面。
- `codex-rs/cli/src/main.rs:138-140,779-786`
  - 顶层 CLI 注册与派发。

### 测试与样例
- `codex-rs/cloud-tasks/tests/env_filter.rs:1-27`
  - 验证 mock 模式下按 env 过滤行为。
- `codex-rs/cloud-tasks/src/lib.rs:2122-2385`
  - attempt 选择、task id 解析、格式化等测试。
- `codex-rs/backend-client/src/types.rs:321-376`
  - 详情提取扩展 trait 的 fixture 单测。
- `codex-rs/backend-client/tests/fixtures/*.json`
  - `task_details_with_diff.json` / `task_details_with_error.json`。

## 依赖与外部交互

### 内部 crate 依赖
- `codex-backend-client`（online 可选依赖）
- `codex-git`（apply 引擎）
- `async-trait`、`serde/serde_json`、`chrono`、`diffy`、`thiserror`

### 外部 HTTP 交互（经 backend-client）
- `GET /api/codex/tasks/list` 或 `GET /wham/tasks/list`
- `GET /api/codex/tasks/{id}` 或 `GET /wham/tasks/{id}`
- `GET /api/codex/tasks/{task}/turns/{turn}/sibling_turns` 或对应 `/wham/...`
- `POST /api/codex/tasks` 或 `POST /wham/tasks`

### 本地副作用
- 写文件：`./error.log`（相对当前执行目录）。
- 执行 git apply：通过 `codex_git::apply_git_patch` 修改或预检工作树。
- 读取环境变量：`CODEX_STARTING_DIFF`。

### 与配置/脚本/文档关系
- 运行时配置主要来自 `cloud-tasks` 上游（base_url、auth header、mode）；本 crate 不直接读登录配置文件。
- 研究流程脚本关联：`.ops/generate_daily_research_todo.sh` 从 `Docs/researches/blueprint_checklist.md` 生成每日 todo。
- 业务说明文档在仓库通用 docs 中几乎缺位，当前可参考已有研究文档：
  - `Docs/researches/codex-rs/cloud-tasks/current_folder_research.md`
  - `Docs/researches/codex-rs/backend-client/current_folder_research.md`

## 风险、边界与改进建议

### 风险与边界
1. 日志敏感信息风险
- `error.log` 记录 raw body、patch 内容、stdout/stderr tail，可能包含敏感数据。

2. `TaskSummary.updated_at` 的兜底语义偏弱
- 当后端未给时间时直接 `Utc::now()`，会掩盖“未知时间”和“刚更新”差异。

3. `AttemptStatus` 映射不完全一致
- `AttemptStatus` 枚举有 `Unknown`，但 `attempt_status_from_str` 默认返回 `Pending`；可能误导 UI 状态。

4. 协议漂移防御分散
- 一部分在 `backend-client::CodeTaskDetailsResponseExt`，一部分在 `cloud-tasks-client` body 回退函数，维护点较多。

5. 测试覆盖空洞
- `cloud-tasks-client` 目录内无独立单测/集成测；关键逻辑主要靠上游和下游间接覆盖。

6. `error.log` 路径固定为 cwd
- 在不同执行目录下日志落点不稳定，可能造成排障困难或污染工作区。

### 改进建议
1. 增加 `cloud-tasks-client` 直测
- 为 `http.rs` 的关键纯函数（状态映射、diff 识别、attempt 排序、body 回退解析）补充单测。

2. 引入统一详情解析层
- 将 `backend-client` 与 `cloud-tasks-client` 对 task details 的两层解析策略整合为共享模块，减少双处漂移风险。

3. 改善时间字段语义
- 用 `Option<DateTime<Utc>>` 表达“未知时间”，由上层决定展示文案，避免默认 `now` 带来的排序/可观测偏差。

4. 对齐 `AttemptStatus` 默认分支
- 未知字符串映射 `Unknown` 而非 `Pending`，提升状态语义准确性。

5. 日志分级与脱敏
- 增加 debug 开关控制 raw body/patch 全量写入；默认仅写摘要并脱敏 token/path。

6. 统一日志落点
- 将 `error.log` 写入 `codex_home` 下固定子目录，避免 cwd 漂移。

7. 文档补齐
- 在 `codex-rs/docs` 或 `cloud-tasks` README 增加协议/环境变量说明，降低研究文档成为唯一知识源的风险。
