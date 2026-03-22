# output_schema.rs 深入研究文档

## 场景与职责

`output_schema.rs` 是 Codex App Server v2 协议测试套件中的输出 Schema 测试模块。该模块测试了 `turn/start` API 的 `output_schema` 参数功能，验证客户端如何指定 AI 响应的 JSON Schema 格式约束，确保模型输出符合预期的结构。

该测试文件确保 Codex 能够正确将 `output_schema` 转换为 OpenAI Responses API 的 `text.format` 参数，并且该配置是按回合 (per-turn) 生效的。

## 功能点目的

### 1. 输出 Schema 接受与传递 (`turn_start_accepts_output_schema_v2`)
验证：
- `turn/start` 请求接受 `output_schema` 参数
- Schema 被正确转换为 Responses API 的 `text.format` 字段
- 格式类型为 `json_schema`，启用严格模式 (`strict: true`)
- Schema 名称固定为 `codex_output_schema`

### 2. 按回合隔离 (`turn_start_output_schema_is_per_turn_v2`)
验证：
- 第一个回合使用 `output_schema`，请求包含 `text.format`
- 第二个回合不使用 `output_schema`，请求不包含 `text.format`
- 确认 `output_schema` 是按回合配置，不会跨回合泄漏

## 具体技术实现

### 关键流程

#### 带 Output Schema 的回合流程
```
Client -> Server: turn/start
         Params: {
           thread_id: "...",
           input: [UserInput::Text { text: "Hello", text_elements: [] }],
           output_schema: {
             type: "object",
             properties: { answer: { type: "string" } },
             required: ["answer"],
             additionalProperties: false
           }
         }
Server -> Responses API: POST /v1/responses
         Body: {
           text: {
             format: {
               name: "codex_output_schema",
               type: "json_schema",
               strict: true,
               schema: { ... }  // 客户端提供的 schema
             }
           }
         }
```

#### 不带 Output Schema 的回合流程
```
Client -> Server: turn/start
         Params: {
           thread_id: "...",
           input: [UserInput::Text { ... }],
           output_schema: None
         }
Server -> Responses API: POST /v1/responses
         Body: {
           text: {}  // 无 format 字段
         }
```

### 数据结构

#### TurnStartParams (相关字段)
```rust
pub struct TurnStartParams {
    pub thread_id: String,
    pub input: Vec<UserInput>,
    // ... 其他字段
    pub output_schema: Option<serde_json::Value>,  // JSON Schema 对象
    // ... 其他字段
}
```

#### Responses API 请求格式
```rust
// 当 output_schema 存在时
text: {
  format: {
    name: "codex_output_schema",
    type: "json_schema",
    strict: true,
    schema: { /* 用户提供的 JSON Schema */ }
  }
}

// 当 output_schema 为 None 时
text: {}  // 或省略 format
```

### 测试 Schema 示例
```json
{
  "type": "object",
  "properties": {
    "answer": { "type": "string" }
  },
  "required": ["answer"],
  "additionalProperties": false
}
```

### 验证逻辑

#### 测试 1: Schema 传递验证
```rust
let request = response_mock.single_request();
let payload = request.body_json();
let format = payload.pointer("/text/format").unwrap();

assert_eq!(format, &serde_json::json!({
    "name": "codex_output_schema",
    "type": "json_schema",
    "strict": true,
    "schema": output_schema,  // 原始 schema
}));
```

#### 测试 2: 按回合隔离验证
```rust
// 第一个回合有 schema
let payload1 = response_mock1.single_request().body_json();
assert_eq!(payload1.pointer("/text/format"), Some(&expected_format));

// 第二个回合无 schema
let payload2 = response_mock2.single_request().body_json();
assert_eq!(payload2.pointer("/text/format"), None);
```

### 常量定义
```rust
const DEFAULT_READ_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(10);
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/app-server/tests/suite/v2/output_schema.rs`: 本测试文件
- `codex-rs/app-server/tests/suite/v2/mod.rs`: v2 测试模块入口

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs`:
  - `TurnStartParams.output_schema` (在 `TurnStartParams` 结构体中)

- `codex-rs/app-server-protocol/src/protocol/common.rs`:
  - `ClientRequest::TurnStart` (line 351)

### 测试支持
- `codex-rs/app-server/tests/common/mcp_process.rs`:
  - `McpProcess::send_turn_start_request()`: 发送回合启动请求
  - `McpProcess::send_thread_start_request()`: 发送线程启动请求

- `core_test_support::responses`:
  - `start_mock_server()`: 启动模拟 Responses API 服务器
  - `mount_sse_once()`: 挂载单次 SSE 响应
  - `sse()`, `ev_response_created()`, `ev_assistant_message()`, `ev_completed()`: SSE 事件构造

### 核心实现
- `codex-rs/core/src/turn/...`: Turn 处理逻辑，将 `output_schema` 转换为 API 请求

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|------|------|
| `tempfile::TempDir` | 创建临时测试目录 |
| `tokio::time::timeout` | 异步操作超时控制 |
| `serde_json::json!` | JSON 构造宏 |
| `pretty_assertions::assert_eq` | 测试断言美化 |

### 内部依赖
| 模块 | 用途 |
|------|------|
| `app_test_support::McpProcess` | MCP 客户端进程管理 |
| `app_test_support::to_response` | 响应解析 |
| `codex_app_server_protocol::*` | 协议类型定义 |
| `core_test_support::responses` | 模拟 Responses API |
| `core_test_support::skip_if_no_network` | 网络可用性检查 |

### 测试架构
```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Test Client   │────▶│  codex-app-server │────▶│  Mock Responses │
│  (McpProcess)   │◀────│   (MCP Server)    │◀────│   API Server    │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                               │
                               │ 验证请求体中的
                               │ text.format 字段
                               ▼
                        ┌──────────────────┐
                        │   Assertions     │
                        │ (output_schema   │
                        │  -> text.format) │
                        └──────────────────┘
```

## 风险、边界与改进建议

### 已知风险

1. **网络依赖**
   - 测试使用 `skip_if_no_network!` 宏
   - 在无网络环境下测试被跳过
   - 可能掩盖某些网络相关的 bug

2. **Schema 复杂性**
   - 当前测试使用简单的 object schema
   - 复杂的嵌套 schema、array schema、ref schema 未测试

3. **严格模式硬编码**
   - `strict: true` 是硬编码行为
   - 如果未来需要支持非严格模式，需要新增测试

### 边界情况

1. **无效 Schema**
   - 未测试无效 JSON Schema 的错误处理
   - 未测试 Responses API 拒绝 schema 时的行为

2. **超大 Schema**
   - 未测试大型 schema 的处理
   - 未测试 schema 大小限制

3. **并发回合**
   - 未测试多个并发回合使用不同 schema 的场景

4. **Schema 缓存**
   - 未测试相同 schema 的缓存行为

### 改进建议

1. **增加 Schema 类型覆盖**
   ```rust
   // 建议添加
   async fn turn_start_with_array_output_schema()
   async fn turn_start_with_nested_object_schema()
   async fn turn_start_with_enum_schema()
   ```

2. **错误场景测试**
   ```rust
   // 建议添加
   async fn turn_start_rejects_invalid_output_schema()
   async fn turn_start_handles_api_schema_rejection()
   ```

3. **并发测试**
   ```rust
   // 建议添加
   async fn concurrent_turns_with_different_schemas()
   ```

4. **Schema 演进测试**
   ```rust
   // 建议添加
   async fn turn_start_schema_modification_between_turns()
   ```

5. **离线测试支持**
   - 考虑使用完全本地的 mock，移除网络依赖
   - 或添加专门的离线测试变体

6. **文档完善**
   - 补充 `output_schema` 的完整文档
   - 提供常见 schema 模式的示例
