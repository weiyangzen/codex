# DIR `codex-rs/cloud-tasks/tests` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/cloud-tasks/tests`
- 目录内容：1 个集成测试文件 `env_filter.rs`
- 研究结论摘要：该目录承担“环境筛选参数在 CloudBackend 层可观察且稳定”的最小回归保障，核心验证对象是 `MockClient` 在不同 `env` 输入下返回不同任务集合。

## 场景与职责

`codex-rs/cloud-tasks/tests` 是 `codex-cloud-tasks` crate 的集成测试目录，当前只有 `env_filter.rs` 一项测试（`codex-rs/cloud-tasks/tests/env_filter.rs:1-27`）。

它对应的业务场景是：
- 用户在 `codex cloud list --env <ENV_ID>` 或 TUI 环境筛选中指定环境。
- 应用把环境参数透传到 `CloudBackend::list_tasks(env, ...)`。
- backend（mock/online）返回按环境隔离的任务视图。

该目录职责不是覆盖完整 cloud 流程，而是用一个小而快的测试确认“环境参数产生可见数据差异”。

上下文职责边界：
- 调用方（上游）
  - `codex` 顶层子命令路由到 `cloud`（`codex-rs/cli/src/main.rs:138-140,779-786`）。
  - `run_list_command` 与 TUI `load_tasks` 最终都会调用 `CloudBackend::list_tasks`（`codex-rs/cloud-tasks/src/lib.rs:510-523`，`codex-rs/cloud-tasks/src/app.rs:121-133`）。
- 被调用方（下游）
  - trait 抽象：`CloudBackend`（`codex-rs/cloud-tasks-client/src/api.rs:133-170`）。
  - mock 实现：`MockClient::list_tasks`（`codex-rs/cloud-tasks-client/src/mock.rs:19-70`）。
  - online 实现：`HttpClient::Tasks::list` -> `backend::Client::list_tasks(..., environment_id, ...)`（`codex-rs/cloud-tasks-client/src/http.rs:145-178`，`codex-rs/backend-client/src/client.rs:268-302`）。

## 功能点目的

该目录当前功能点只有一个，但目的很明确：

1. 验证 mock backend 的环境分流契约
- `None`（全局视图）应返回默认任务集合，且包含 README 相关条目。
- `Some("env-A")` 应返回 1 条任务，标题 `A: First`。
- `Some("env-B")` 应返回 2 条任务，且标题前缀为 `B: `。
- 对应断言位于 `codex-rs/cloud-tasks/tests/env_filter.rs:8-26`。

2. 为上层功能提供稳定测试基线
- `cloud-tasks` 依赖 `cloud-tasks-client` 同时开启 `mock + online` feature（`codex-rs/cloud-tasks/Cargo.toml:19-22`），所以本地/CI 在无远端依赖时仍可跑出有意义结果。
- 该测试通过 mock 数据变化来证明 `env` 参数链路没被无意删改。

## 具体技术实现（关键流程/数据结构/协议/命令）

### 1) 关键流程

1. 测试入口
- `#[tokio::test]` 异步测试函数 `mock_backend_varies_by_env`（`codex-rs/cloud-tasks/tests/env_filter.rs:4-5`）。

2. 测试执行
- 构造 `MockClient`（`codex-rs/cloud-tasks/tests/env_filter.rs:6`）。
- 通过 trait UFCS 方式调用：
  - `CloudBackend::list_tasks(&client, None, None, None)`
  - `CloudBackend::list_tasks(&client, Some("env-A"), None, None)`
  - `CloudBackend::list_tasks(&client, Some("env-B"), None, None)`
  （`codex-rs/cloud-tasks/tests/env_filter.rs:8-24`）
- 断言返回任务集合大小与标题模式（`codex-rs/cloud-tasks/tests/env_filter.rs:12,18-19,25-26`）。

3. mock 数据来源
- `MockClient::list_tasks` 根据 `_env` 走 `match`：
  - `env-A` -> `[("T-2000", "A: First", Ready)]`
  - `env-B` -> 两条 `B: ...`
  - 其他/None -> 默认三条全局任务
  （`codex-rs/cloud-tasks-client/src/mock.rs:25-37`）。

### 2) 关键数据结构

- `TaskListPage { tasks, cursor }`：列表分页返回（`codex-rs/cloud-tasks-client/src/api.rs:91-95`）。
- `TaskSummary`：每条任务元信息，含 `environment_id/environment_label`（`codex-rs/cloud-tasks-client/src/api.rs:30-48`；mock 赋值见 `codex-rs/cloud-tasks-client/src/mock.rs:38-57`）。
- `CloudBackend` trait：统一 mock/online 行为入口（`codex-rs/cloud-tasks-client/src/api.rs:133-170`）。

### 3) 协议与参数透传

- `cloud-tasks` 命令层在 list 场景会把环境筛选透传给 backend：
  - `run_list_command` 调用 `CloudBackend::list_tasks(..., env_filter.as_deref(), ...)`（`codex-rs/cloud-tasks/src/lib.rs:510-523`）。
- online 模式下：
  - `HttpClient::Tasks::list` 调用 `backend.list_tasks(limit, task_filter=current, env, cursor)`（`codex-rs/cloud-tasks-client/src/http.rs:151-156`）。
  - `backend-client` 最终拼接查询参数 `environment_id`（`codex-rs/backend-client/src/client.rs:295-297`）。

### 4) 本地可执行命令

- 仅跑目标测试：
```bash
cargo test -p codex-cloud-tasks --test env_filter
```
- 若要看 crate 内环境参数相关单测（`app.rs` 内 `load_tasks_uses_env_parameter`）：
```bash
cargo test -p codex-cloud-tasks load_tasks_uses_env_parameter
```

## 关键代码路径与文件引用

测试主体与直接依赖：
- `codex-rs/cloud-tasks/tests/env_filter.rs:1-27`
- `codex-rs/cloud-tasks-client/src/mock.rs:19-70`
- `codex-rs/cloud-tasks-client/src/api.rs:133-170`

同主题的相邻测试（同一语义链）：
- `codex-rs/cloud-tasks/src/app.rs:121-133`（生产 `load_tasks`）
- `codex-rs/cloud-tasks/src/app.rs:490-511`（单测 `load_tasks_uses_env_parameter`）

调用链与协议透传：
- `codex-rs/cli/src/main.rs:138-140,779-786`（`cloud` 子命令入口）
- `codex-rs/cloud-tasks/src/lib.rs:510-523`（list 命令透传 env）
- `codex-rs/cloud-tasks-client/src/http.rs:145-178`（HTTP list）
- `codex-rs/backend-client/src/client.rs:268-302`（`environment_id` query）

配置与构建：
- `codex-rs/cloud-tasks/Cargo.toml:19-22`（开启 `mock + online`）
- `codex-rs/cloud-tasks-client/Cargo.toml:14-17`（feature 定义）
- `codex-rs/cloud-tasks/BUILD.bazel:1-6`

研究流程脚本/清单：
- `.ops/generate_daily_research_todo.sh:1-42`
- `Docs/researches/blueprint_checklist.md:181`

## 依赖与外部交互

### 1) 代码依赖

- 编译期依赖
  - `codex-cloud-tasks` 依赖 `codex-cloud-tasks-client`，并开启 mock/online 双 feature（`codex-rs/cloud-tasks/Cargo.toml:19-22`）。
  - `codex-cloud-tasks-client` 的 `online` feature 才会引入 `codex-backend-client`（`codex-rs/cloud-tasks-client/Cargo.toml:16,27`）。

- 测试运行时依赖
  - `env_filter.rs` 只触达 `MockClient`，不依赖网络、鉴权、远端 API。
  - 因此它属于低成本、稳定、可离线执行的回归用例。

### 2) 外部交互（间接）

虽然当前测试本身不发请求，但它验证的是一条最终会走到远端 API 的参数链路：
- online list 使用 `/wham/tasks/list` 或 `/api/codex/tasks/list`。
- `environment_id` 作为 query 参数附加到请求。

### 3) 文档与脚本交互

- 研究任务状态由 `Docs/researches/blueprint_checklist.md` 标记。
- 当天 TODO 由 `.ops/generate_daily_research_todo.sh` 基于 checklist 自动生成。
- 当前仓库中未见专门面向最终用户的 `codex cloud --env` 详细文档（主要说明在源码注释与 CLI help 中，如 `codex-rs/cloud-tasks/src/cli.rs:83-85`）。

## 风险、边界与改进建议

1. 风险：断言过于依赖 mock 标题文案
- 现有断言依赖 `"Update README"`、`"A: First"`、`"B: "` 文本（`env_filter.rs:12,19,26`）。
- 若未来仅调整 mock 文案（非真实语义变更），测试会误报失败。

2. 风险：未校验 `environment_id/environment_label`
- mock 已填充 `TaskSummary.environment_id/environment_label`（`mock.rs:38-57`），但当前测试只看标题和数量。
- 可能出现“标题分流正确但环境元数据错误”而漏检。

3. 边界：未覆盖 `limit/cursor` 与未知环境
- `list_tasks` 还有 `limit/cursor` 参数（`api.rs:135-140`），此测试未覆盖分页路径。
- 未校验 `Some("unknown-env")` 退化为 default 分支行为（`mock.rs:32-37`）。

4. 边界：未验证 online 层 query 透传
- 当前只证明 mock 分支行为；未直接断言 HTTP 请求里确实携带 `environment_id`（虽然代码路径存在，见 `backend-client/src/client.rs:295-297`）。

5. 改进建议（按投入优先级）
- 建议 A（低成本）：在 `env_filter.rs` 增加对 `environment_id` 的断言，减少“只看标题”的假阳性。
- 建议 B（低成本）：增加未知 env 与 limit/cursor 的用例，补足参数边界。
- 建议 C（中成本）：在 `cloud-tasks-client` 增加 HTTP 层单元/集成测试，直接断言请求 query 包含 `environment_id`。
- 建议 D（中成本）：将 `env-A/env-B` 与标题样例提取为共享 fixture 常量，降低文案变更造成的测试脆弱性。
- 建议 E（文档）：在用户文档中补充 `codex cloud list --env` 示例与“label/id 解析规则”，减少行为认知偏差。
