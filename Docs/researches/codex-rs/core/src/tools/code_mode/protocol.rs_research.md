# protocol.rs 研究文档

## 场景与职责

`protocol.rs` 是 Code Mode 的**消息协议定义模块**，负责定义 Rust 与 Node.js 运行时之间的所有通信消息类型。它提供了结构化、类型安全的消息传递机制，是两端协作的基础契约。

**核心定位**：
- 定义 Host（Rust）到 Node（JavaScript）的消息类型（`HostToNodeMessage`）
- 定义 Node（JavaScript）到 Host（Rust）的消息类型（`NodeToHostMessage`）
- 定义工具相关的数据结构（`EnabledTool`, `CodeModeToolCall`, `CodeModeNotify`）
- 提供源码构建工具（`build_source`）
- 提供消息辅助函数（`message_request_id`, `unexpected_tool_call_error`）

## 功能点目的

### 1. 工具类型枚举
```rust
#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub(super) enum CodeModeToolKind {
    Function,
    Freeform,
}
```
- 区分函数式工具（接收 JSON 对象参数）和自由格式工具（接收字符串参数）
- 使用 snake_case 序列化（`"function"`, `"freeform"`）

### 2. 启用工具结构
```rust
#[derive(Clone, Debug, Serialize)]
pub(super) struct EnabledTool {
    pub(super) tool_name: String,      // 原始工具名（如 "exec_command"）
    pub(super) global_name: String,    // JS 全局名（如 "exec_command"）
    #[serde(rename = "module")]
    pub(super) module_path: String,    // 模块路径（如 "tools.js"）
    pub(super) namespace: Vec<String>, // 命名空间（如 ["mcp", "server_name"]）
    pub(super) name: String,           // 工具键名
    pub(super) description: String,    // 工具描述
    pub(super) kind: CodeModeToolKind, // 工具类型
}
```
- 描述可在 JavaScript 环境中使用的工具
- 序列化后传递给 Node.js 运行时使用

### 3. 工具调用结构
```rust
#[derive(Debug, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(super) struct CodeModeToolCall {
    pub(super) request_id: String,  // 关联的请求 ID
    pub(super) id: String,          // 调用唯一 ID
    pub(super) name: String,        // 工具名称
    #[serde(default)]
    pub(super) input: Option<JsonValue>, // 调用参数
}
```
- Node.js 发起工具调用时使用
- 包含完整的调用上下文信息

### 4. 通知结构
```rust
#[derive(Clone, Debug, Deserialize)]
pub(super) struct CodeModeNotify {
    pub(super) cell_id: String,   // 所属 cell ID
    pub(super) call_id: String,   // 调用 ID
    pub(super) text: String,      // 通知内容
}
```
- 用于 JavaScript 向模型发送即时通知
- 通过 `notify()` 函数触发

### 5. Host 到 Node 的消息
```rust
#[derive(Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub(super) enum HostToNodeMessage {
    Start { ... },      // 启动新执行
    Poll { ... },       // 轮询执行状态
    Terminate { ... },  // 终止执行
    Response { ... },   // 工具调用响应
}
```

**Start 消息**：
- `request_id`: 请求唯一标识
- `cell_id`: cell 唯一标识
- `tool_call_id`: 原始工具调用 ID
- `default_yield_time_ms`: 默认让出时间
- `enabled_tools`: 可用工具列表
- `stored_values`: 存储的键值对
- `source`: 完整的 JavaScript 源码
- `yield_time_ms`: 自定义让出时间（可选）
- `max_output_tokens`: 最大输出 token 数（可选）

**Poll 消息**：
- 用于 `wait` 工具轮询运行中的 cell
- 可指定新的 `yield_time_ms`

**Terminate 消息**：
- 用于 `wait` 工具强制终止 cell

**Response 消息**：
- 响应 JavaScript 发起的工具调用
- 包含 `code_mode_result` 或 `error_text`

### 6. Node 到 Host 的消息
```rust
#[derive(Debug, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub(super) enum NodeToHostMessage {
    ToolCall { tool_call: CodeModeToolCall },
    Yielded { request_id, content_items },
    Terminated { request_id, content_items },
    Notify { notify: CodeModeNotify },
    Result { request_id, content_items, stored_values, error_text, max_output_tokens_per_exec_call },
}
```

### 7. 源码构建
```rust
pub(super) fn build_source(
    user_code: &str,
    enabled_tools: &[EnabledTool],
) -> Result<String, String>
```
- 将 `bridge.js` 模板与用户提供代码合并
- 替换 `__CODE_MODE_ENABLED_TOOLS_PLACEHOLDER__` 为工具列表 JSON
- 替换 `__CODE_MODE_USER_CODE_PLACEHOLDER__` 为用户代码

## 具体技术实现

### 序列化配置

**HostToNodeMessage**：
- `tag = "type"`：使用 `type` 字段作为判别标签
- `rename_all = "snake_case"`：字段名使用蛇形命名法

**示例序列化**：
```json
{
  "type": "start",
  "request_id": "uuid",
  "cell_id": "1",
  "tool_call_id": "call-1",
  "default_yield_time_ms": 10000,
  "enabled_tools": [...],
  "stored_values": {},
  "source": "...",
  "yield_time_ms": null,
  "max_output_tokens": null
}
```

### 消息 ID 提取
```rust
pub(super) fn message_request_id(message: &NodeToHostMessage) -> Option<&str> {
    match message {
        NodeToHostMessage::ToolCall { .. } => None,
        NodeToHostMessage::Yielded { request_id, .. }
        | NodeToHostMessage::Terminated { request_id, .. }
        | NodeToHostMessage::Result { request_id, .. } => Some(request_id),
        NodeToHostMessage::Notify { .. } => None,
    }
}
```
- 用于消息路由，将响应与请求关联
- `ToolCall` 和 `Notify` 是异步消息，无 request_id

### 源码构建流程
```rust
pub(super) fn build_source(user_code: &str, enabled_tools: &[EnabledTool]) -> Result<String, String> {
    let enabled_tools_json = serde_json::to_string(enabled_tools)
        .map_err(|err| format!("failed to serialize enabled tools: {err}"))?;
    
    Ok(CODE_MODE_BRIDGE_SOURCE
        .replace("__CODE_MODE_ENABLED_TOOLS_PLACEHOLDER__", &enabled_tools_json)
        .replace("__CODE_MODE_USER_CODE_PLACEHOLDER__", user_code))
}
```

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/protocol.rs`

### 调用方
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/execute_handler.rs`
  - `build_source()` - 构建执行源码
  - `HostToNodeMessage::Start` - 发送启动消息
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/wait_handler.rs`
  - `HostToNodeMessage::Poll` - 发送轮询消息
  - `HostToNodeMessage::Terminate` - 发送终止消息
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/process.rs`
  - `HostToNodeMessage` - 序列化并发送
  - `NodeToHostMessage` - 反序列化接收
  - `message_request_id()` - 消息路由
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/worker.rs`
  - `HostToNodeMessage::Response` - 发送工具响应
  - `NodeToHostMessage::ToolCall` - 处理工具调用
  - `NodeToHostMessage::Notify` - 处理通知
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/mod.rs`
  - `handle_node_message()` - 处理各种 NodeToHostMessage

### 相关常量
- `/home/sansha/Github/codex/codex-rs/core/src/tools/code_mode/mod.rs`
  - `CODE_MODE_BRIDGE_SOURCE` - bridge.js 模板

## 依赖与外部交互

### 外部 crate
| crate | 用途 |
|-------|------|
| `serde` | 序列化/反序列化 |
| `serde_json::Value` | JSON 值类型 |
| `std::collections::HashMap` | 存储值映射 |

### 与 runner.cjs 的协议对应

**Rust (protocol.rs) ↔ JavaScript (runner.cjs)**：

| Rust 消息 | JavaScript 处理 | JavaScript 发送 |
|-----------|----------------|-----------------|
| `Start` | `startSession()` | `started`, `result` |
| `Poll` | `rl.on('line', ...)` | `yielded` |
| `Terminate` | `rl.on('line', ...)` | `terminated` |
| `Response` | `rl.on('line', ...)` | - |
| - | `worker.on('message', ...)` | `tool_call`, `notify`, `content_item`, `yield`, `result` |

### 消息时序示例

```
Rust                                    Node.js
  │                                       │
  ├── HostToNodeMessage::Start ──────────>│
  │                                       ├── 启动 Worker
  │                                       │<── worker: started
  │                                       ├── 设置 initial_yield_timer
  │                                       │
  │<─ NodeToHostMessage::Yielded ─────────┤
  │                                       │
  ├── HostToNodeMessage::Poll ───────────>│
  │                                       ├── 重置 poll_yield_timer
  │                                       │
  │<─ NodeToHostMessage::Result ──────────┤
  │                                       │
```

## 风险、边界与改进建议

### 风险点

1. **序列化失败风险**
   ```rust
   let enabled_tools_json = serde_json::to_string(enabled_tools)
       .map_err(|err| format!("failed to serialize enabled tools: {err}"))?;
   ```
   - 如果 `EnabledTool` 包含不可序列化的数据，会失败
   - 当前所有字段都是基础类型，风险较低

2. **消息版本兼容性**
   - 没有显式的协议版本号
   - Rust 和 Node.js 代码必须同步更新

3. **字段名不一致风险**
   - `EnabledTool` 中的 `module_path` 序列化为 `"module"`
   - 这种重命名增加了理解成本

4. **Option 处理**
   - `max_output_tokens_per_exec_call` 使用 `Option<usize>`
   - 序列化为 JSON 时可能为 `null`，需要两端正确处理

### 边界情况

1. **空工具列表**
   - `enabled_tools: &[]` 是有效的
   - 序列化为 `"[]"`

2. **空存储值**
   - `stored_values: HashMap::new()` 是有效的
   - 序列化为 `"{}"`

3. **超长代码**
   - `user_code` 长度没有限制
   - 依赖下层处理大字符串

### 测试覆盖

当前测试仅覆盖 `message_request_id` 函数：
```rust
#[test]
fn message_request_id_absent_for_notify() { ... }

#[test]
fn message_request_id_present_for_result() { ... }
```

**未覆盖场景**：
- 消息序列化/反序列化
- `build_source` 函数
- 各种消息类型的构造

### 改进建议

1. **添加协议版本**
   ```rust
   #[derive(Serialize)]
   pub(super) struct ProtocolVersion {
       pub major: u16,
       pub minor: u16,
   }
   
   impl HostToNodeMessage {
       pub fn version() -> ProtocolVersion {
           ProtocolVersion { major: 1, minor: 0 }
       }
   }
   ```

2. **使用 Builder 模式**
   ```rust
   let start_msg = HostToNodeMessage::builder()
       .request_id("uuid")
       .cell_id("1")
       .source(user_code)
       .build()?;
   ```

3. **更严格的类型**
   - 使用 `Uuid` 类型替代 `String` 表示 ID
   - 使用 `Duration` 类型替代 `u64` 表示时间

4. **文档化字段约束**
   ```rust
   pub(super) struct EnabledTool {
       /// 原始工具名，如 "exec_command"
       pub(super) tool_name: String,
       /// JS 全局名，由 normalize_code_mode_identifier 生成
       pub(super) global_name: String,
       // ...
   }
   ```

5. **扩展测试**
   ```rust
   #[test]
   fn host_to_node_message_serialization() {
       let msg = HostToNodeMessage::Start { ... };
       let json = serde_json::to_string(&msg).unwrap();
       assert!(json.contains("\"type\":\"start\""));
   }
   
   #[test]
   fn node_to_host_message_deserialization() {
       let json = r#"{"type":"result","request_id":"r1","content_items":[],"stored_values":{}}"#;
       let msg: NodeToHostMessage = serde_json::from_str(json).unwrap();
       assert!(matches!(msg, NodeToHostMessage::Result { .. }));
   }
   ```

6. **源码构建优化**
   ```rust
   pub(super) fn build_source(
       user_code: &str,
       enabled_tools: &[EnabledTool],
   ) -> Result<String, String> {
       // 验证用户代码不包含占位符
       if user_code.contains("__CODE_MODE_") {
           return Err("User code contains reserved placeholder".to_string());
       }
       // ...
   }
   ```
