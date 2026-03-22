# DynamicToolCallParams.json 研究文档

## 场景与职责

`DynamicToolCallParams` 是 Codex App-Server 协议中用于**动态工具调用**的参数结构。当服务器需要客户端执行一个动态注册的工具时，通过此结构传递调用参数。

该类型属于 **Server → Client** 的请求流，对应 JSON-RPC 方法为 `item/tool/call`。

### 使用场景

1. **动态工具执行**：执行在运行时动态注册的工具（而非内置工具）
2. **客户端侧工具**：工具实现在客户端，服务器仅发送调用请求
3. **多模态输入**：支持文本和图像等多种输入类型的工具调用

---

## 功能点目的

### 核心字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `threadId` | string | ✅ | 所属线程标识 |
| `turnId` | string | ✅ | 所属回合标识 |
| `callId` | string | ✅ | 工具调用唯一标识 |
| `tool` | string | ✅ | 工具名称 |
| `arguments` | any | ✅ | 工具参数（任意 JSON 值） |

### 字段设计意图

- **`callId`**：用于关联工具调用的请求和响应，以及相关的开始/结束事件
- **`arguments`**：使用 `true` 类型在 JSON Schema 中表示允许任意 JSON 值（`"type": true` 是 draft-07 中表示任意类型的方式）

---

## 具体技术实现

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/protocol/v2.rs
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct DynamicToolCallParams {
    pub thread_id: String,
    pub turn_id: String,
    pub call_id: String,
    pub tool: String,
    pub arguments: JsonValue,
}
```

### 响应类型

对应的响应类型为 `DynamicToolCallResponse`：

```rust
pub struct DynamicToolCallResponse {
    pub content_items: Vec<DynamicToolCallOutputContentItem>,
    pub success: bool,
}

pub enum DynamicToolCallOutputContentItem {
    InputText { text: String },
    InputImage { image_url: String },
}
```

### ServerRequest 注册

```rust
// codex-rs/app-server-protocol/src/protocol/common.rs
server_request_definitions! {
    DynamicToolCall => "item/tool/call" {
        params: v2::DynamicToolCallParams,
        response: v2::DynamicToolCallResponse,
    },
}
```

---

## 关键代码路径与文件引用

### 协议定义

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 主类型定义（行 5596-5602） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ServerRequest 注册（行 767-770） |

### 使用方

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/src/outgoing_message.rs` | 服务器构造动态工具调用请求 |
| `codex-rs/app-server/src/bespoke_event_handling.rs` | 事件处理 |
| `codex-rs/tui_app_server/src/app/app_server_requests.rs` | TUI 处理动态工具调用 |
| `codex-rs/app-server/tests/suite/v2/dynamic_tools.rs` | 动态工具测试 |

---

## 依赖与外部交互

### 依赖类型

```rust
use serde_json::Value as JsonValue;
```

### 与 Core 类型的转换

```rust
// DynamicToolCallOutputContentItem 与 Core 类型的转换
impl From<DynamicToolCallOutputContentItem>
    for codex_protocol::dynamic_tools::DynamicToolCallOutputContentItem
{
    fn from(item: DynamicToolCallOutputContentItem) -> Self {
        match item {
            DynamicToolCallOutputContentItem::InputText { text } => Self::InputText { text },
            DynamicToolCallOutputContentItem::InputImage { image_url } => {
                Self::InputImage { image_url }
            }
        }
    }
}
```

---

## 风险、边界与改进建议

### 已知风险

1. **任意参数风险**：`arguments` 字段接受任意 JSON 值，服务器和客户端需要自行验证参数格式

2. **工具名称冲突**：动态工具名称可能与内置工具冲突，需要命名空间隔离机制

### 边界情况

1. **空参数**：`arguments` 可以为 `null` 或空对象 `{}`
2. **无效工具名称**：服务器可能请求不存在的工具，客户端需要优雅处理
3. **大型参数**：`arguments` 可能包含大型数据（如 base64 编码的图像），需要考虑传输限制

### 改进建议

1. **参数 Schema 验证**：考虑在协议层添加工具参数的 JSON Schema 验证
   ```json
   {
     "tool": "image_processor",
     "arguments": {...},
     "argumentsSchema": {...}  // 新增：参数验证 schema
   }
   ```

2. **工具版本控制**：添加可选的 `toolVersion` 字段，支持工具版本管理

3. **超时控制**：添加 `timeoutMs` 字段，允许服务器指定工具调用的超时时间

4. **批量调用**：考虑支持批量动态工具调用，减少往返开销

5. **调用上下文**：添加可选的 `context` 字段，传递调用的附加上下文信息
