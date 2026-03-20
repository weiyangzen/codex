# DIR `codex-rs/cloud-tasks-client/src` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/cloud-tasks-client/src`
- 代码文件：`api.rs`、`http.rs`、`mock.rs`、`lib.rs`
- crate：`codex-cloud-tasks-client`
- 直接上游调用方：`codex-rs/cloud-tasks`（CLI + TUI）
- 关键下游依赖：`codex-backend-client`、`codex-git`

## 场景与职责

`cloud-tasks-client/src` 是 Codex Cloud 任务能力的“领域接口 + 传输适配 + 本地补丁应用”层，位于 UI/命令编排（`codex-rs/cloud-tasks`）和后端协议客户端（`codex-rs/backend-client`）之间。

核心职责：
1. 定义稳定领域模型与后端抽象接口（`CloudBackend`），供上游统一调用。
2. 提供 online 实现（`HttpClient`），把任务列表、任务详情、attempt、建任务等行为映射到后端 HTTP API。
3. 提供 mock 实现（`MockClient`），支持无网络场景与上游测试。
4. 承担任务 diff 的本地应用/预检（通过 `codex-git::apply_git_patch`），向上游返回结构化结果（`ApplyOutcome`）。

职责边界（明确不做）：
- 不负责登录态管理与 token 获取（在 `cloud-tasks/src/lib.rs::init_backend` + `cloud-tasks/src/util.rs`）。
- 不负责环境自动探测与选择策略（在 `cloud-tasks/src/env_detect.rs`）。
- 不负责 CLI 参数解析和 TUI 交互（在 `cloud-tasks/src/cli.rs`、`cloud-tasks/src/lib.rs`、`cloud-tasks/src/ui.rs`）。

## 功能点目的

### 1) 统一领域契约（`api.rs`）
- 目的：让上游只依赖 `CloudBackend` trait 与领域对象，不耦合 HTTP 字段细节。
- 关键对象：
  - 任务视图：`TaskSummary`、`TaskListPage`、`TaskStatus`。
  - 详情视图：`TaskText`、`TurnAttempt`、`AttemptStatus`。
  - 应用结果：`ApplyOutcome`、`ApplyStatus`。
  - 错误统一：`CloudTaskError`（`Http/Io/Msg/Unimplemented`）。

### 2) 在线后端访问（`http.rs`）
- 目的：将 `CloudBackend` 调用翻译为后端 API 请求，并处理返回 JSON 的兼容解析。
- 覆盖能力：`list/summary/diff/messages/task_text/list_sibling_attempts/create/apply/preflight`。

### 3) 本地 mock（`mock.rs`）
- 目的：脱离真实后端仍可跑通 `cloud-tasks` 主流程和关键测试。
- 特点：按环境返回不同任务集合，支持 mock diff、attempt 与 apply/preflight 返回。

### 4) Feature 出口与实现切换（`lib.rs`）
- 目的：通过 feature gate 暴露在线/离线实现：
  - `online` -> `HttpClient`
  - `mock` -> `MockClient`

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 分层结构与 trait 派发
- `HttpClient` 内部按职责拆为 `Tasks` / `Attempts` / `Apply` 三组 API 适配器，`CloudBackend` 实现仅做委派，保持入口薄。
- `TaskId` 使用透明序列化包装（`#[serde(transparent)]`），调用方与序列化边界都保持 `String`。

### B. 列表与摘要流程
1. `list_tasks(env, limit, cursor)`：
   - `i64 -> i32` 安全降级（失败则不传 limit）。
   - 调 `backend.list_tasks(limit_i32, Some("current"), env, cursor)`。
   - 将 `TaskListItem` 映射到 `TaskSummary`，并记录分页日志（`error.log`）。
2. `get_task_summary(id)`：
   - 调 `get_task_details_with_body` 同时拿结构化对象 + 原始 body。
   - 先解析 `task/task_status_display` 字段，再用 `CodeTaskDetailsResponseExt` 的 `unified_diff()` 做 diff 统计兜底。
   - `updated_at` 兜底链：`task.updated_at -> task.created_at -> latest_turn_timestamp -> Utc::now()`。

### C. 详情文本与 attempt 流程
1. `get_task_diff`：优先 `details.unified_diff()`，无则 `None`。
2. `get_task_messages`：
   - 先 `details.assistant_text_messages()`。
   - 空时回退到 body 级解析 `current_assistant_turn.worklog.messages`。
   - 再无内容且有错误则返回 `Task failed: <err>`。
3. `get_task_text`：返回 prompt/messages/turn_id/sibling_turn_ids/attempt_placement/attempt_status，用于上游构造详情页与 attempt 切换。
4. `list_sibling_attempts(task, turn_id)`：
   - 调 `/turns/{turn}/sibling_turns`。
   - 从 `output_items` 解析 `output_diff`/`pr.output_diff.diff` 及 message 文本。
   - 按 `attempt_placement`、`created_at`、`turn_id` 排序，保证展示稳定。

### D. 创建任务协议
`create_task(env_id, prompt, git_ref, qa_mode, best_of_n)` 构造 JSON：
- `new_task.environment_id`
- `new_task.branch`
- `new_task.run_environment_in_qa_mode`
- `input_items`（首项为 user message）
- 若环境变量 `CODEX_STARTING_DIFF` 非空，追加 `pre_apply_patch` 输入项
- 若 `best_of_n > 1`，追加 `metadata.best_of_n`

### E. Apply / Preflight 执行流程
1. diff 来源：`diff_override` 优先，否则回查 task details。
2. 先做格式门禁 `is_unified_diff`，非 unified 直接返回 `ApplyStatus::Error`。
3. 调 `codex_git::apply_git_patch`：
   - 请求参数：`cwd=current_dir`、`revert=false`、`preflight`。
   - `preflight=true` 对应 `git apply --check`，不改工作树。
4. 状态映射：
   - `exit_code == 0` -> `Success`
   - 否则若有 applied/conflict -> `Partial`
   - 否则 `Error`
5. 日志策略：`Partial/Error`（及 preflight 非成功）会落 `error.log`，包含：命令摘要、stdout/stderr tail、patch 摘要、patch 原文。

### F. 路径风格协议（Codex API vs ChatGPT WHAM）
- `codex-backend-client::Client` 通过 base_url 推断 `PathStyle`：
  - `.../backend-api` -> `/wham/...`
  - 其他 -> `/api/codex/...`
- `cloud-tasks-client` 依赖此能力发起：
  - `GET tasks/list`
  - `GET tasks/{id}`
  - `GET tasks/{id}/turns/{turn}/sibling_turns`
  - `POST tasks`

### G. 关键命令与运行形态
- 从仓库 CLI 入口：`codex-rs/cli/src/main.rs` 路由到 `codex_cloud_tasks::run_main(...)`。
- 运行子命令（上游调用本目录能力）：
  - `codex cloud list`
  - `codex cloud status <TASK_ID>`
  - `codex cloud diff <TASK_ID> [--attempt N]`
  - `codex cloud apply <TASK_ID> [--attempt N]`
  - `codex cloud exec --env <ENV_ID> [--attempts N] [QUERY|-]`

## 关键代码路径与文件引用

### 目标目录（`cloud-tasks-client/src`）
- `codex-rs/cloud-tasks-client/src/api.rs`
  - 错误与领域模型：6-131
  - 后端抽象 trait：133-170
- `codex-rs/cloud-tasks-client/src/http.rs`
  - `HttpClient` 与 trait 实现：20-124
  - 任务接口（list/summary/diff/messages/task_text/create）：132-385
  - attempt 接口：388-413
  - apply/preflight：416-558
  - JSON/body 兜底解析与状态映射：561-892
  - 统一错误日志落盘：895-905
- `codex-rs/cloud-tasks-client/src/mock.rs`
  - `MockClient` 全接口实现：14-158
  - mock diff 与统计：160-200
- `codex-rs/cloud-tasks-client/src/lib.rs`
  - feature 出口与 re-export：1-30

### 关键调用方（上游）
- `codex-rs/cloud-tasks/src/lib.rs`
  - 后端初始化、鉴权头注入、mock/online 切换：40-108
  - CLI 子命令调用 client trait：158-605
  - TUI 详情加载/attempt 读取/apply 触发：1126-1215, 1838-1972
  - TUI 新建任务提交：1492-1514
- `codex-rs/cloud-tasks/src/app.rs`
  - `load_tasks` 通过 trait 拉取并过滤 `is_review`：121-134
  - 测试专用 `FakeBackend` 实现：353-512
- `codex-rs/cloud-tasks/tests/env_filter.rs`
  - 验证 `MockClient` 按 env 返回差异数据：1-27
- `codex-rs/cli/src/main.rs`
  - 顶层 `cloud` 子命令路由：779-786

### 关键被调用方（下游）
- `codex-rs/backend-client/src/client.rs`
  - base_url 规范化 + `PathStyle` 推断：82-133
  - tasks/sibling_turns/details/create API：268-377
- `codex-rs/backend-client/src/types.rs`
  - `CodeTaskDetailsResponse` 与扩展提取器：20-295
- `codex-rs/utils/git/src/apply.rs`
  - `apply_git_patch` 结构化执行与结果提取：18-122

## 依赖与外部交互

### 代码依赖
- 内部 crate
  - `codex-backend-client`：后端 HTTP 与 task details typed 解析。
  - `codex-git`：本地 `git apply` 执行器。
- 三方依赖
  - `serde/serde_json`：协议序列化与动态 body 兜底。
  - `chrono`：时间戳到 `DateTime<Utc>` 转换。
  - `async-trait`：异步 trait。
  - `thiserror`：错误声明。
  - `diffy`：mock diff 统计。

### 运行时输入/配置
- 由上游注入到本目录对象：
  - `CODEX_CLOUD_TASKS_MODE`（决定 mock/online）
  - `CODEX_CLOUD_TASKS_BASE_URL`（决定 path style 与服务地址）
  - Auth token / ChatGPT-Account-Id / User-Agent（由上游 `init_backend` 注入 `HttpClient`）
- 本目录直接读取：
  - `CODEX_STARTING_DIFF`（create_task 时注入 `pre_apply_patch`）
- 文件交互：
  - `error.log`（当前工作目录）

### 外部交互面
- 网络：通过 `codex-backend-client` 调后端 REST 接口。
- 本地进程：通过 `codex-git` 间接调用系统 `git apply`。

### 测试与脚本上下文
- 本目录无独立 `#[cfg(test)]` 测试；覆盖主要来自：
  - `cloud-tasks` 上游单测/集测（mock 行为、列表/attempt 流程）。
  - `backend-client` 的 task details fixture 测试（保障字段形态）。
- 工程脚本/构建：
  - `codex-rs/cloud-tasks-client/Cargo.toml`（feature: `online`/`mock`）
  - `codex-rs/cloud-tasks-client/BUILD.bazel`（Bazel crate 定义）

## 风险、边界与改进建议

### 风险与边界
1. 解析逻辑双轨，存在漂移风险
- `backend-client::CodeTaskDetailsResponseExt` 与 `http.rs` body 兜底并存；后端结构变化时，可能出现一处更新、另一处遗漏。

2. `AttemptStatus` 语义不一致
- enum 默认是 `Unknown`，但 `http.rs::attempt_status_from_str` 对未知值回落为 `Pending`，且 `cancelled` 未映射到 `Cancelled`，会影响 UI 状态准确性。

3. 时间戳转换容错有限
- 使用 `as f64` + 手工拆秒纳秒，异常/负值被裁到 epoch；对非标准时间字段兼容有限。

4. `error.log` 明文记录 patch
- 失败时会记录完整 patch，可能包含敏感代码；当前无脱敏/尺寸上限策略（除头部摘要与 stdout/stderr tail 截断外）。

5. 本目录直接测试缺失
- `apply` 分支、非 unified diff 门禁、body 兜底解析、attempt 排序等核心逻辑缺少 crate 内直测，回归主要依赖上游间接覆盖。

### 改进建议
1. 收敛 task details 解析入口
- 将 `http.rs` 的 body 兜底解析能力下沉或抽象到 `backend-client` 共用层，减少重复实现。

2. 统一并强化 `AttemptStatus` 映射
- 未知值回落为 `Unknown`；补齐 `cancelled -> Cancelled`，并在 UI 明确展示未知状态。

3. 增加 `cloud-tasks-client` 直测
- 覆盖建议：
  - `create_task` 请求体拼装（`best_of_n`、`CODEX_STARTING_DIFF`）
  - `apply` 状态映射与 preflight 语义
  - `turn_attempt_from_map` 排序与字段提取
  - `messages/task_text` 的 ext + body fallback 行为

4. 日志分级与敏感信息控制
- 为 patch logging 增加开关（默认关闭完整 patch）；默认只保留摘要与命令尾部信息。

5. 文档补充
- 在 `codex-rs/cloud-tasks` 或项目 docs 增加 cloud task 协议与环境变量约定，避免知识仅沉淀在研究文档中。
