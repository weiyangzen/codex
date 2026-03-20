# DIR `codex-rs/backend-client/tests` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/backend-client/tests`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 关联 crate：`codex-backend-client`
- 目录现状：该目录不包含 Rust 测试源码，仅包含 `fixtures/` JSON 数据文件，供 `src/types.rs` 单测通过 `include_str!` 引用。

## 场景与职责

`codex-rs/backend-client/tests` 的职责是作为 `codex-backend-client` 中“任务详情提取逻辑”的稳定测试语料库（fixture 库），而不是传统的集成测试入口目录。

该目录主要服务以下场景：

1. 为手写任务详情模型提供可回归样本
- `backend-client` 在 `src/types.rs` 中使用手写结构 `CodeTaskDetailsResponse`，因为生成 OpenAPI 模型对 task details 的可用性不足。
- `tests/fixtures` 提供最小但关键的后端响应片段，验证 `CodeTaskDetailsResponseExt` 的四个高频提取能力：diff、assistant message、user prompt、assistant error。

2. 为 cloud tasks 链路提供“协议形态锚点”
- 这些 fixture 对应的字段形态（`output_diff.diff`、`pr.output_diff.diff`、`worklog.messages[*].content.parts`、`error.code/message`）与 `cloud-tasks-client` 在运行时解析行为直接相关。
- 当后端字段形态变化时，最先暴露风险的通常是这里的反序列化/提取单测。

3. 保证 Cargo/Bazel 双构建路径下 fixture 可见
- fixture 被 `include_str!("../tests/fixtures/...json")` 在编译期读取。
- `BUILD.bazel` 通过 `compile_data = glob(["tests/fixtures/**"])` 显式把该目录纳入构建输入，避免“Cargo 可跑、Bazel 找不到资源”的差异。

## 功能点目的

### 1) `task_details_with_diff.json`
目的：覆盖“正常产出 + 显式 diff turn”路径。

覆盖点：
- `current_diff_task_turn.output_items[type=output_diff].diff` 可被 `unified_diff()` 优先提取。
- `current_assistant_turn.output_items[type=message].content[]` 可被 `assistant_text_messages()` 提取。
- `current_user_turn.input_items[type=message, role=user].content[]` 可被 `user_text_prompt()` 提取，并按空行拼接多段文本。

### 2) `task_details_with_error.json`
目的：覆盖“无 diff turn，仅 PR diff + 错误信息”退化路径。

覆盖点：
- 当不存在 `output_diff` item 时，`unified_diff()` 需要回退到 `pr.output_diff.diff`。
- `assistant_error_message()` 需将 `error.code` 与 `error.message` 合成统一摘要文本（`CODE: message`）。

### 3) fixture 驱动单测在 `src/types.rs` 的定位
目的：在不依赖远端 API 的情况下，验证 task details 提取算法的契约。

对应单测：
- `unified_diff_prefers_current_diff_task_turn`
- `unified_diff_falls_back_to_pr_output_diff`
- `assistant_text_messages_extracts_text_content`
- `user_text_prompt_joins_parts_with_spacing`
- `assistant_error_message_combines_code_and_message`

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. fixture -> 反序列化 -> 语义提取 的测试流程

1. 测试入口
- `src/types.rs` 内部 `#[cfg(test)]` 模块定义 `fixture(name)`，通过 `include_str!` 编译期加载 JSON 文本。

2. 数据解码
- fixture 文本被反序列化为 `CodeTaskDetailsResponse`（手写结构）。
- `deserialize_vec` 统一处理可缺失数组字段，默认空 `Vec`，减少空值分支。

3. 语义提取
- `unified_diff()` 先查 `current_diff_task_turn`，后查 `current_assistant_turn`。
- item 级别支持两种 diff 载体：
  - `type=output_diff` + 顶层 `diff`
  - `type=pr` + `output_diff.diff`
- `assistant_text_messages()` 从 `output_items[type=message]` 与 `worklog.messages(author=assistant)` 汇总文本。
- `user_text_prompt()` 仅拼接 user role 的 message 内容，段间插入双换行。
- `assistant_error_message()` 输出 code/message 组合摘要。

### B. 关键数据结构（与 fixture 字段一一对应）

- `CodeTaskDetailsResponse`
  - `current_user_turn`
  - `current_assistant_turn`
  - `current_diff_task_turn`

- `Turn`
  - `id`, `attempt_placement`, `turn_status`, `sibling_turn_ids`
  - `input_items`, `output_items`
  - `worklog`, `error`

- `TurnItem`
  - `kind`（JSON `type`）
  - `content`（支持结构化文本与裸字符串）
  - `diff` / `output_diff.diff`

- `TurnError`
  - `code`, `message`

### C. 该目录与运行时协议的关系

虽然 `tests/` 本身不发起 HTTP 请求，但 fixture 字段直接映射以下 task details 响应协议形态：

- `GET /api/codex/tasks/{id}`
- `GET /wham/tasks/{id}`

`backend-client` 通过 `PathStyle` 在上述两类路径间切换，`cloud-tasks-client` 则依赖这些提取结果完成：
- 任务摘要 diff 统计 fallback
- 文本消息展示
- patch apply 的 diff 来源
- 失败时错误提示

### D. 关键命令与构建约束

- Cargo 侧：运行 `cargo test -p codex-backend-client` 会执行 `src/types.rs` 单测并读取 fixture。
- Bazel 侧：`backend-client/BUILD.bazel` 的 `compile_data` 必须包含 `tests/fixtures/**`，否则 `include_str!` 可能在 Bazel 构建中缺失输入。
- 研究流程侧：`bash .ops/generate_daily_research_todo.sh` 根据 `Docs/researches/blueprint_checklist.md` 重新生成当日 todo 清单。

## 关键代码路径与文件引用

### 目标目录内文件

1. `codex-rs/backend-client/tests/fixtures/task_details_with_diff.json`
- 提供“显式 diff turn + assistant message + user prompt”样本。

2. `codex-rs/backend-client/tests/fixtures/task_details_with_error.json`
- 提供“PR diff 回退 + assistant error”样本。

### 直接调用方（读取该目录 fixture）

1. `codex-rs/backend-client/src/types.rs:326-333`
- `fixture(name)` 使用 `include_str!("../tests/fixtures/...json")` 读取本目录文件。

2. `codex-rs/backend-client/src/types.rs:335-375`
- 五个单测断言基于 fixture 的语义输出。

### 上下文依赖（调用链）

1. `codex-rs/backend-client/src/client.rs:304-320`
- 任务详情 API 反序列化到 `CodeTaskDetailsResponse`，与 fixture 使用同一模型。

2. `codex-rs/cloud-tasks-client/src/http.rs:249-313`
- `details.unified_diff()/assistant_text_messages()/user_text_prompt()/assistant_error_message()` 为 cloud tasks 文本与 diff 读取核心。

3. `codex-rs/cloud-tasks-client/src/http.rs:437-443`
- apply 路径在无 override 时依赖 `unified_diff()` 输出。

4. `codex-rs/backend-client/BUILD.bazel:4-7`
- `compile_data` 将 `tests/fixtures` 纳入 Bazel 构建输入。

### 相关配置、测试、脚本、文档

1. 配置入口
- `codex-rs/cloud-tasks/src/lib.rs:45-59` 使用 `CODEX_CLOUD_TASKS_BASE_URL` 初始化 `HttpClient`，间接决定 task details 请求走 `/api/codex` 还是 `/wham`。
- `codex-rs/cloud-tasks/src/util.rs:31-43` 与 `backend-client::Client::new` 一样会规范化 ChatGPT URL（补 `/backend-api`）。

2. 关联测试（跨模块）
- `codex-rs/app-server/tests/suite/v2/thread_start.rs:334-340`
- `codex-rs/app-server/tests/suite/v2/thread_resume.rs:1425-1431`
- `codex-rs/app-server/tests/suite/v2/thread_fork.rs:228-234`
以上验证 ChatGPT 后端路径（`/backend-api/wham/...`）在 cloud requirements 场景可达，侧面确认 `PathStyle` 约定在真实测试中被依赖。

3. 文档
- `codex-rs/app-server/README.md` 描述了 rate limit 读取 RPC，但 `backend-client/tests` 目录本身暂无专属 README；其契约主要体现在 `src/types.rs` 单测与 fixture 内容。

4. 研究脚本
- `.ops/generate_daily_research_todo.sh` 按 checklist 状态生成 `Docs/researches/todos_YYYYMMDD.md`，本次勾选后会影响 pending 统计。

## 依赖与外部交互

### 内部依赖

1. `serde/serde_json`
- fixture JSON 反序列化依赖。

2. `pretty_assertions`
- `src/types.rs` 单测的断言输出更可读。

3. `codex-backend-openapi-models`（间接）
- 虽然 task details 用手写模型，但同 crate 其他 API 仍依赖生成模型，说明 fixture 所处测试层是“手写模型补丁层”。

### 外部交互

`tests/fixtures` 目录本身无网络/进程外部交互；但它模拟的是后端 REST `task details` 响应，属于协议契约样本：

- Codex API: `/api/codex/tasks/{id}`
- ChatGPT backend: `/wham/tasks/{id}`

### 与其他模块的契约关系

- 对 `cloud-tasks-client`：保证能够抽取 diff、消息、prompt、错误文本。
- 对 `cloud-tasks` CLI/TUI：保证 `diff/status/messages/apply` 功能在基础字段形态下可工作。
- 对 `app-server`/`cloud-requirements`：虽然不直接消费这两个 fixture，但共享 `backend-client` 的路径风格与鉴权约定。

## 风险、边界与改进建议

### 风险

1. fixture 覆盖面偏窄
- 当前仅 2 个样本，未覆盖：
  - `worklog` 中混合 `Text(String)` 与结构化文本的边界
  - `content_type` 大小写、空字符串、无效类型
  - `current_diff_task_turn` 与 `current_assistant_turn` 同时存在且冲突时的优先级细节
  - `sibling_turn_ids`、`attempt_placement`、`turn_status` 的更多组合

2. 断言粒度偏“包含/单字段”
- 部分测试使用 `contains`，对完整输出格式变化敏感度不足。

3. fixture 与真实响应漂移风险
- 后端 task details 字段可能演进；若 fixture 长期不更新，单测可能“稳定但脱离生产真实形态”。

4. 目录命名可能让读者误解
- `tests/` 下只有 fixture、没有 test harness，容易被误判为缺失测试。

### 边界

1. 本目录不验证 HTTP 行为
- 状态码处理、header 注入、URL 路由均不在此目录覆盖，属于 `client.rs` 与上层集成测试范围。

2. 本目录不覆盖 apply 行为
- `codex_git::apply_git_patch` 路径由 `cloud-tasks-client` 测试承担。

3. 本目录不承担 schema 兼容性测试
- 仅验证 hand-rolled `CodeTaskDetailsResponse` 的当前预期语义。

### 改进建议

1. 增加 fixture 矩阵
- 新增 `task_details_with_worklog_only.json`、`task_details_with_empty_fragments.json`、`task_details_with_conflicting_diffs.json` 等，覆盖更多实际退化场景。

2. 增加“整对象断言”或快照断言
- 对 `TaskText`/消息列表/错误摘要使用更完整断言，减少隐式行为回归。

3. 建立 fixture 来源注释
- 在每个 fixture 顶部注释其对应线上响应形态或 issue 链接，降低后续维护成本。

4. 将关键 fixture 复用到 `cloud-tasks-client` 单测
- 让同一份 task details 样本在 `backend-client` 与 `cloud-tasks-client` 两层都跑，减少“下层通过、上层破坏”的风险。

5. 在目录下补一段简短说明（可选）
- 用 `README.md` 标明“此目录为 fixture-only，测试代码在 `src/types.rs`”，提升可发现性。
