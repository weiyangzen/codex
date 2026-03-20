# DIR `codex-rs/backend-client/tests/fixtures` 研究报告

- 研究对象：`/home/sansha/Github/codex/codex-rs/backend-client/tests/fixtures`
- 目标类型：`DIR`
- 研究日期：2026-03-20
- 所属 crate：`codex-backend-client`
- 目录内容：
  - `task_details_with_diff.json`
  - `task_details_with_error.json`

## 场景与职责

该目录不是独立测试入口，而是 `codex-backend-client` 的“任务详情响应语料库（fixtures）”。其职责是给手写任务详情模型提供稳定、可回归的协议样本，确保 `CodeTaskDetailsResponseExt` 的提取行为不会在后续修改中发生无感退化。

核心场景：

1. 任务详情里存在多种 diff 载体，需要统一抽取
- 显式 diff item：`output_items[].type = output_diff` + `diff`
- PR diff item：`output_items[].type = pr` + `output_diff.diff`

2. 文本内容有多种形态，需要统一抽取
- 结构化文本分片：`{"content_type":"text","text":"..."}`
- 裸字符串片段（`ContentFragment::Text`）
- worklog 内 assistant 消息补充文本

3. 错误信息需要形成稳定展示文案
- `error.code + error.message` 组合为单一摘要文本

本目录 fixture 通过 `include_str!` 在编译期读取，主要服务 `src/types.rs` 的单测；并间接保障 `cloud-tasks-client` / `cloud-tasks` 的任务详情展示、diff 应用入口和失败提示链路。

## 功能点目的

### 1) `task_details_with_diff.json` 的目的

该样本用于覆盖“正常成功路径 + 显式 diff turn”的主流程。

它验证：

1. `unified_diff()` 会优先从 `current_diff_task_turn` 提取 unified diff。
2. `assistant_text_messages()` 可从 `current_assistant_turn.output_items[type=message]` 中提取文本。
3. `user_text_prompt()` 可拼接 `current_user_turn.input_items[type=message, role=user]` 的多段文本，并使用空行分隔。

### 2) `task_details_with_error.json` 的目的

该样本用于覆盖“无 diff turn、仅 PR diff + 错误对象”的退化路径。

它验证：

1. `unified_diff()` 在没有 `output_diff` item 时，会回退到 `pr.output_diff.diff`。
2. `assistant_error_message()` 能将 `code/message` 合成为 `"CODE: message"`。

### 3) fixture 在系统中的语义定位

该目录相当于 `backend-client` 与上层调用方之间的“协议形态锚点”。

当后端 task details 响应字段发生变化时，最先暴露问题的通常是这里对应的单测；其失败可以提前阻止问题扩散到：

- `cloud-tasks-client` 的 `get_task_diff/get_task_messages/get_task_text`
- `cloud-tasks` TUI 的详情面板与 apply 逻辑

## 具体技术实现（关键流程/数据结构/协议/命令）

### A. 关键流程：fixture -> 反序列化 -> 扩展提取 -> 上层消费

1. fixture 装载
- `codex-rs/backend-client/src/types.rs:326-333`
- `fixture("diff" | "error")` 通过 `include_str!("../tests/fixtures/...")` 编译期读取 JSON。

2. 反序列化模型
- `CodeTaskDetailsResponse` 手写结构位于 `codex-rs/backend-client/src/types.rs:20-27`。
- `Turn/TurnItem/Worklog/TurnError` 位于 `types.rs:29-116`。
- `deserialize_vec`（`types.rs:307-313`）把缺失数组字段归一为空 `Vec`，避免上层额外 `Option<Vec<_>>` 分支。

3. 语义提取规则
- Diff 抽取：`TurnItem::diff_text`（`types.rs:152-167`）
  - `type=output_diff` 读取 `item.diff`
  - `type=pr` 读取 `item.output_diff.diff`
- 优先级：`CodeTaskDetailsResponseExt::unified_diff`（`types.rs:272-280`）
  - 先 `current_diff_task_turn`
  - 后 `current_assistant_turn`
- 文本抽取：
  - `ContentFragment::text`（`types.rs:118-141`）
  - `Turn::message_texts`（`types.rs:175-192`）
  - `WorklogMessage::text_values`（`types.rs:233-244`）
- 用户 prompt：`Turn::user_prompt`（`types.rs:194-217`）
- 错误摘要：`TurnError::summary`（`types.rs:247-257`）+ `assistant_error_message`（`types.rs:300-304`）

4. 单测断言
- `unified_diff_prefers_current_diff_task_turn`（`types.rs:335-340`）
- `unified_diff_falls_back_to_pr_output_diff`（`types.rs:342-347`）
- `assistant_text_messages_extracts_text_content`（`types.rs:349-354`）
- `user_text_prompt_joins_parts_with_spacing`（`types.rs:356-366`）
- `assistant_error_message_combines_code_and_message`（`types.rs:368-375`）

### B. 关键数据结构

1. fixture 对应的核心字段
- `current_user_turn.input_items[].content[]`
- `current_assistant_turn.output_items[]`
- `current_diff_task_turn.output_items[]`
- `current_assistant_turn.error`

2. 结构化与非结构化文本并存
- `ContentFragment` 为 `#[serde(untagged)]`（`types.rs:63-68`）
- 可接受对象和字符串两种文本表示

3. 生成模型与手写模型边界
- 生成模型 `code_task_details_response.rs` 将 turn 表示为 `HashMap<String, Value>`（`codex-rs/codex-backend-openapi-models/src/models/code_task_details_response.rs:19-30`）
- 手写模型在 `backend-client/types.rs` 提供更强语义约束与提取 API（`types.rs:16-19` 注释明确说明生成模型“pretty bad”）

### C. 协议与命令

1. 对应后端协议端点
- `GET /api/codex/tasks/{task_id}`
- `GET /wham/tasks/{task_id}`

端点选择由 `backend-client::PathStyle` 与 `Client::new` 决定：
- `codex-rs/backend-client/src/client.rs:90-98`
- `codex-rs/backend-client/src/client.rs:111-123`
- `codex-rs/backend-client/src/client.rs:313-316`

2. 构建系统约束（Bazel）
- `codex-rs/backend-client/BUILD.bazel:6`
- `compile_data = glob(["tests/fixtures/**"])` 是 `include_str!` 在 Bazel 下可见的关键。

3. 本目录相关常用命令
- 仅跑该 crate 单测：`cargo test -p codex-backend-client`
- 研究任务脚本：`bash .ops/generate_daily_research_todo.sh`

## 关键代码路径与文件引用

### 目标目录与直接引用

1. `codex-rs/backend-client/tests/fixtures/task_details_with_diff.json`
2. `codex-rs/backend-client/tests/fixtures/task_details_with_error.json`
3. `codex-rs/backend-client/src/types.rs:326-333`（fixture 装载）
4. `codex-rs/backend-client/src/types.rs:335-375`（fixture 驱动单测）
5. `codex-rs/backend-client/BUILD.bazel:3-7`（Bazel compile_data）

### 调用方路径（谁消费了该语义）

1. `codex-rs/cloud-tasks-client/src/http.rs:17-18`
- 引入 `codex_backend_client::CodeTaskDetailsResponseExt`。

2. `codex-rs/cloud-tasks-client/src/http.rs:249-259`
- `get_task_diff` 直接消费 `details.unified_diff()`。

3. `codex-rs/cloud-tasks-client/src/http.rs:261-285`
- `get_task_messages` 先用 `assistant_text_messages()`，无结果再回退解析 raw body，并在存在错误时使用 `assistant_error_message()`。

4. `codex-rs/cloud-tasks-client/src/http.rs:287-313`
- `get_task_text` 组合 `user_text_prompt()` 与 `assistant_text_messages()`，并返回 turn 级元信息。

5. `codex-rs/cloud-tasks-client/src/http.rs:427-443`
- apply 路径无覆盖 diff 时，依赖 `get_task_details + unified_diff()`。

### 被调用方路径（被 fixture 所在逻辑依赖）

1. `codex-rs/backend-client/src/client.rs:304-320`
- task details HTTP 拉取与反序列化入口。

2. `codex-rs/codex-backend-openapi-models/src/models/code_task_details_response.rs:15-31`
- 生成模型的弱类型边界（HashMap），对应手写模型补位动机。

3. `codex-rs/cloud-tasks/src/lib.rs:40-107`
- 初始化 `HttpClient`，设置 token 与 `ChatGPT-Account-Id`，决定任务详情请求能否成功。

4. `codex-rs/cloud-tasks/src/util.rs:31-43`
- 与 backend-client 一致的 base URL 归一化策略，避免 `/backend-api` 差异导致路径错配。

### 相关配置、测试、脚本、文档

1. 配置
- `CODEX_CLOUD_TASKS_BASE_URL`：`codex-rs/cloud-tasks/src/lib.rs:45-46`
- `CODEX_CLOUD_TASKS_MODE`：`cloud-tasks/src/lib.rs:41-44`

2. 测试
- 本目录样本用于 `backend-client/src/types.rs` 内部单测（见上）。
- `cloud-tasks-client` 还有 body 级回退解析函数（`http.rs:571-693`），说明上层对后端形态漂移做了第二层容错。

3. 脚本
- `.ops/generate_daily_research_todo.sh` 基于 `Docs/researches/blueprint_checklist.md` 重新生成当日 TODO。

4. 文档
- 当前仓库没有专门描述 `backend-client/tests/fixtures` 的独立 README。
- 该目录的事实契约主要体现在 `types.rs` 的注释与单测。

## 依赖与外部交互

### 内部依赖

1. `serde/serde_json`
- fixture JSON 反序列化基础能力。

2. `pretty_assertions`
- 用于更清晰的断言 diff（`types.rs` 测试模块）。

3. `codex-backend-openapi-models`
- 虽然 fixture 测试面向手写 task-details 结构，但 crate 其他 API 仍复用生成模型类型。

### 外部交互

1. 目录本身
- 无网络访问、无进程外调用、无文件写入副作用（静态 JSON 输入）。

2. 目录所模拟的外部协议
- ChatGPT/Codex backend task details 响应体。
- 对应真实 HTTP 接口由 `backend-client::Client` 发起（`client.rs:309-320`）。

3. 认证与请求头链路（间接）
- `Authorization: Bearer ...` 与 `ChatGPT-Account-Id` 由 `Client::headers` 注入（`client.rs:169-189`）。
- fixture 不直接覆盖请求头逻辑，但其语义结果被认证后请求路径消费。

## 风险、边界与改进建议

### 风险

1. 样本数量少，覆盖面有限
- 当前仅覆盖 `output_diff` 和 `pr.output_diff` 两种 diff 场景。
- 未覆盖：
  - `worklog` 仅有文本、无 `output_items` 的场景
  - 混合大小写 `content_type`、空字符串与空白字符串
  - `current_diff_task_turn` 与 `current_assistant_turn` 同时含 diff 且冲突
  - `error` 仅 code/仅 message/均为空的三种分支

2. 单测断言偏“包含性”
- diff 断言用 `contains("diff --git")`，对格式细节漂移不敏感。

3. fixture 与线上形态漂移风险
- 后端字段形态演化时，如果不及时补样本，可能出现“测试仍通过但线上解析质量下降”。

### 边界

1. 本目录不测试 HTTP 行为
- 不覆盖状态码、content-type、header 注入、URL 拼装。

2. 本目录不测试 git apply
- apply 行为属于 `cloud-tasks-client` 与 `codex_git` 链路。

3. 本目录不验证 UI 渲染
- 仅验证数据提取，不涉及 TUI 展示快照。

### 改进建议

1. 扩展 fixture 矩阵
- 增加至少以下样本：
  - `task_details_with_worklog_only.json`
  - `task_details_with_empty_or_whitespace_text.json`
  - `task_details_with_both_diff_sources.json`
  - `task_details_with_partial_error_fields.json`

2. 增加更完整断言
- 对 `assistant_text_messages()` 与 `user_text_prompt()` 做全量等值断言（目前已部分做到了，可再覆盖更多边界输入）。

3. 把同一批 fixture 复用到 `cloud-tasks-client` 测试
- 让“下层提取 API”与“上层业务回退逻辑”共享语料，减少层间语义偏移。

4. 在目录加简短说明文档（可选）
- 说明这是 fixture-only 目录，测试代码位于 `src/types.rs`；提高新贡献者可发现性。
