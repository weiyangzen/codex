# plan_item.rs 深入研究文档

## 场景与职责

`plan_item.rs` 是 Codex App Server v2 协议测试套件中的计划项 (Plan Item) 测试模块。该模块测试了协作模式 (Collaboration Mode) 中的 Plan 模式功能，特别是当 AI 响应包含 `<proposed_plan>` 标签时，系统如何提取计划内容并生成专门的 `ThreadItem::Plan` 项。

该测试文件确保 Codex 能够正确解析 AI 生成的计划内容，将其与常规消息分离，并通过专门的 `item/plan/delta` 通知流式传输计划内容。

## 功能点目的

### 1. Plan 模式计划项生成 (`plan_mode_uses_proposed_plan_block_for_plan_item`)
验证：
- 当 AI 响应包含 `<proposed_plan>...</proposed_plan>` 标签时
- 系统提取标签内的内容作为计划文本
- 生成 `ThreadItem::Plan` 类型的完成项
- 通过 `item/plan/delta` 通知流式传输计划增量
- 计划项 ID 格式为 `{turn_id}-plan`
- 同时保留原始的 `ThreadItem::AgentMessage` 项

### 2. 无计划标签处理 (`plan_mode_without_proposed_plan_does_not_emit_plan_item`)
验证：
- 当 AI 响应不包含 `<proposed_plan>` 标签时
- 不生成 `ThreadItem::Plan` 项
- 不发送 `item/plan/delta` 通知
- 仅生成常规的 `ThreadItem::AgentMessage` 项

## 具体技术实现

### 关键流程

#### Plan 模式流程（含计划标签）
```
1. 启动 Plan 模式回合
   Client -> Server: turn/start
           Params: {
             thread_id: "...",
             input: [UserInput::Text { text: "Plan this" }],
             collaboration_mode: CollaborationMode {
               mode: ModeKind::Plan,
               settings: Settings { model: "mock-model", ... }
             }
           }

2. AI 响应（SSE 流）
   Responses API -> Server: "Preface\n<proposed_plan>\n# Final plan\n- first\n- second\n</proposed_plan>\nPostscript"

3. 流式通知
   Server -> Client: item/started { item: AgentMessage { ... } }
   Server -> Client: item/plan/delta { item_id: "{turn_id}-plan", delta: "# Final plan\n" }
   Server -> Client: item/plan/delta { item_id: "{turn_id}-plan", delta: "- first\n" }
   Server -> Client: item/plan/delta { item_id: "{turn_id}-plan", delta: "- second\n" }
   Server -> Client: item/completed { item: AgentMessage { ... } }
   Server -> Client: item/completed { item: Plan { id: "{turn_id}-plan", text: "..." } }
   Server -> Client: turn/completed { turn: { id, status: Completed } }
```

#### Plan 模式流程（无计划标签）
```
1. 启动 Plan 模式回合
   Client -> Server: turn/start (同上)

2. AI 响应（SSE 流）
   Responses API -> Server: "Done"

3. 流式通知
   Server -> Client: item/started { item: AgentMessage { ... } }
   Server -> Client: item/completed { item: AgentMessage { ... } }
   Server -> Client: turn/completed { ... }
   (无 item/plan/delta 通知)
```

### 数据结构

#### CollaborationMode
```rust
pub struct CollaborationMode {
    pub mode: ModeKind,      // Plan, Auto, Ask
    pub settings: Settings,
}

pub enum ModeKind {
    Plan,
    Auto,
    Ask,
}

pub struct Settings {
    pub model: String,
    pub reasoning_effort: Option<ReasoningEffort>,
    pub developer_instructions: Option<String>,
}
```

#### ThreadItem (Plan 变体)
```rust
pub enum ThreadItem {
    Plan {
        id: String,      // 格式: "{turn_id}-plan"
        text: String,    // 提取的计划内容
    },
    AgentMessage { ... },
    // ... 其他变体
}
```

#### PlanDeltaNotification
```rust
pub struct PlanDeltaNotification {
    pub thread_id: String,
    pub turn_id: String,
    pub item_id: String,  // "{turn_id}-plan"
    pub delta: String,    // 计划内容增量
}
```

#### ItemStartedNotification / ItemCompletedNotification
```rust
pub struct ItemStartedNotification {
    pub item: ThreadItem,
    pub thread_id: String,
    pub turn_id: String,
}

pub struct ItemCompletedNotification {
    pub item: ThreadItem,
    pub thread_id: String,
    pub turn_id: String,
}
```

### 测试辅助函数

#### start_plan_mode_turn
启动 Plan 模式的回合：
```rust
async fn start_plan_mode_turn(mcp: &mut McpProcess) -> Result<codex_app_server_protocol::Turn> {
    // 1. 发送 thread/start 请求
    // 2. 获取 thread 响应
    // 3. 发送 turn/start 请求，指定 collaboration_mode = Plan
    // 4. 返回 turn 信息
}
```

#### collect_turn_notifications
收集回合相关的所有通知：
```rust
async fn collect_turn_notifications(
    mcp: &mut McpProcess,
) -> Result<(
    Vec<ThreadItem>,      // started_items
    Vec<ThreadItem>,      // completed_items
    Vec<PlanDeltaNotification>, // plan_deltas
    TurnCompletedNotification,  // turn_completed
)> {
    // 循环读取通知直到 turn/completed
    // 分类收集 item/started, item/completed, item/plan/delta
}
```

#### wait_for_responses_request_count
等待指定数量的 Responses API 请求：
```rust
async fn wait_for_responses_request_count(
    server: &MockServer,
    expected_count: usize,
) -> Result<()> {
    // 轮询检查 /responses 端点的请求数
    // 超时: DEFAULT_READ_TIMEOUT
}
```

### 测试配置生成

```rust
fn create_config_toml(codex_home: &Path, server_uri: &str) -> std::io::Result<()> {
    // 生成包含 features.collaboration_modes = true 的配置
    // 使用 BTreeMap 构建 feature 配置
}
```

### 常量定义
```rust
const DEFAULT_READ_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(10);
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/app-server/tests/suite/v2/plan_item.rs`: 本测试文件
- `codex-rs/app-server/tests/suite/v2/mod.rs`: v2 测试模块入口

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs`:
  - `CollaborationMode`, `ModeKind`, `Settings`
  - `ThreadItem` (包含 Plan 变体)
  - `PlanDeltaNotification` (line 4845)
  - `ItemStartedNotification`, `ItemCompletedNotification`
  - `TurnCompletedNotification`

- `codex-rs/app-server-protocol/src/protocol/common.rs`:
  - `ServerNotification::PlanDelta` (line 899)
  - `ServerNotification::ItemStarted`, `ServerNotification::ItemCompleted`

### 核心实现
- `codex-rs/core/src/plan_tool.rs`: Plan 工具实现
  - `PlanItemArg`: Plan 项参数
  - `StepStatus`: 计划步骤状态
- `codex-rs/core/src/features.rs`: 功能标志定义
  - `Feature::CollaborationModes`

### 测试支持
- `codex-rs/app-server/tests/common/mcp_process.rs`:
  - `McpProcess` 相关方法

- `core_test_support::responses`:
  - `create_mock_responses_server_sequence_unchecked()`: 创建模拟服务器
  - `ev_message_item_added()`, `ev_output_text_delta()`, `ev_assistant_message()`: SSE 事件

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|------|------|
| `tempfile::TempDir` | 创建临时测试目录 |
| `tokio::time::{sleep, timeout}` | 异步超时和延迟 |
| `wiremock::MockServer` | 模拟 Responses API 服务器 |
| `pretty_assertions::assert_eq` | 测试断言美化 |

### 内部依赖
| 模块 | 用途 |
|------|------|
| `app_test_support::McpProcess` | MCP 客户端进程管理 |
| `app_test_support::create_mock_responses_server_sequence_unchecked` | 创建模拟服务器 |
| `app_test_support::to_response` | 响应解析 |
| `codex_app_server_protocol::*` | 协议类型定义 |
| `codex_core::features::{FEATURES, Feature}` | 功能标志 |
| `codex_protocol::config_types::{CollaborationMode, ModeKind, Settings}` | 协作模式配置 |
| `core_test_support::responses` | SSE 事件构造 |
| `core_test_support::skip_if_no_network` | 网络检查 |

### 功能标志
```rust
// 测试需要启用 CollaborationModes 功能
[features]
collaboration_modes = true
```

## 风险、边界与改进建议

### 已知风险

1. **网络依赖**
   - 测试使用 `skip_if_no_network!` 宏
   - 在无网络环境下被跳过

2. **多线程复杂性**
   - 使用 `#[tokio::test(flavor = "multi_thread", worker_threads = 4)]`
   - 涉及 SSE 流、通知处理和断言的时序协调

3. **硬编码标签格式**
   - `<proposed_plan>` 标签格式是硬编码的
   - 如果格式改变，测试需要同步更新

### 边界情况

1. **嵌套计划标签**
   - 未测试嵌套或重复的 `<proposed_plan>` 标签
   - 未测试标签属性（如 `<proposed_plan version="2">`）

2. **空计划内容**
   - 未测试 `<proposed_plan></proposed_plan>` 空标签的处理

3. **特殊字符**
   - 计划内容中的特殊字符（如 XML 实体、Unicode）处理未充分测试

4. **并发 Plan 模式回合**
   - 未测试多个线程同时进行 Plan 模式回合的场景

### 改进建议

1. **增加边界测试**
   ```rust
   // 建议添加
   async fn plan_mode_with_empty_proposed_plan()
   async fn plan_mode_with_nested_proposed_plan()
   async fn plan_mode_with_special_characters_in_plan()
   ```

2. **错误场景测试**
   ```rust
   // 建议添加
   async fn plan_mode_with_malformed_proposed_plan_tag()
   ```

3. **性能测试**
   ```rust
   // 建议添加
   async fn plan_mode_with_large_plan_content()
   ```

4. **协作模式切换**
   ```rust
   // 建议添加
   async fn switch_between_plan_and_auto_mode()
   ```

5. **离线测试支持**
   - 考虑移除网络依赖，使用完全本地的 mock

6. **标签格式可配置**
   - 考虑使计划标签格式可配置，而非硬编码
