# jsonrpc_lite.rs 研究文档

## 场景与职责

`jsonrpc_lite.rs` 定义了 Codex App Server Protocol 的底层 JSON-RPC 消息格式。这是整个协议栈的基础层，负责客户端与服务器之间的请求/响应/通知消息序列化和反序列化。

### 主要使用场景
1. **WebSocket/STDIO 传输层**：作为消息格式基础，承载在 WebSocket 或标准输入输出之上
2. **消息分派**：服务器根据消息类型（Request/Notification/Response/Error）进行路由
3. **类型安全通信**：通过 Rust 类型系统确保消息格式正确性
4. **分布式追踪**：支持 W3C Trace Context 传递

### 设计约束
- **非标准 JSON-RPC 2.0**：明确不发送也不期望 `"jsonrpc": "2.0"` 字段（见文件顶部注释）
- **简洁性**：仅保留必要字段，减少传输开销
- **灵活性**：使用 `serde_json::Value` 作为 params/result 容器，支持任意结构化数据

## 功能点目的

### 1. 请求 ID 类型 (`RequestId`)
- 支持字符串和整数两种格式的请求标识
- 用于匹配请求与响应
- 实现 `Display` trait 便于日志记录

### 2. 消息信封 (`JSONRPCMessage`)
- 统一的顶层消息枚举，包含四种变体：
  - `Request`: 需要响应的请求
  - `Notification`: 单向通知，无需响应
  - `Response`: 成功响应
  - `Error`: 错误响应

### 3. 请求结构 (`JSONRPCRequest`)
- 包含请求 ID、方法名、可选参数
- 支持可选的 W3C Trace Context 用于分布式追踪

### 4. 通知结构 (`JSONRPCNotification`)
- 无 ID 字段的单向消息
- 用于服务器向客户端推送事件

### 5. 响应结构 (`JSONRPCResponse`, `JSONRPCError`)
- 成功响应包含结果数据
- 错误响应包含错误码、消息和可选数据

## 具体技术实现

### 类型定义详解

#### RequestId (L13-30)
```rust
#[derive(Debug, Clone, PartialEq, PartialOrd, Ord, Deserialize, Serialize, Hash, Eq, JsonSchema, TS)]
#[serde(untagged)]  // 无标签序列化，根据内容自动选择变体
pub enum RequestId {
    String(String),
    #[ts(type = "number")]  // TypeScript 中映射为 number
    Integer(i64),
}
```
- 使用 `#[serde(untagged)]` 实现自动类型推断
- TypeScript 生成时整数变体映射为 `number` 类型

#### JSONRPCMessage (L35-42)
```rust
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize, JsonSchema, TS)]
#[serde(untagged)]
pub enum JSONRPCMessage {
    Request(JSONRPCRequest),
    Notification(JSONRPCNotification),
    Response(JSONRPCResponse),
    Error(JSONRPCError),
}
```
- 无标签枚举，根据字段内容自动反序列化为正确变体
- 这是消息接收时的入口类型

#### JSONRPCRequest (L45-56)
```rust
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize, JsonSchema, TS)]
pub struct JSONRPCRequest {
    pub id: RequestId,
    pub method: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub params: Option<serde_json::Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub trace: Option<W3cTraceContext>,
}
```
- `params` 使用 `Option<serde_json::Value>` 支持任意 JSON 对象
- `trace` 字段支持 W3C Trace Context 标准

#### JSONRPCNotification (L59-65)
```rust
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize, JsonSchema, TS)]
pub struct JSONRPCNotification {
    pub method: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub params: Option<serde_json::Value>,
}
```
- 无 ID 字段，表示单向通知
- 结构与 Request 类似但语义不同

#### JSONRPCResponse (L68-72)
```rust
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize, JsonSchema, TS)]
pub struct JSONRPCResponse {
    pub id: RequestId,
    pub result: Result,  // 即 serde_json::Value
}
```
- `id` 字段与对应请求的 ID 匹配
- `result` 包含任意 JSON 结果数据

#### JSONRPCError (L75-88)
```rust
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize, JsonSchema, TS)]
pub struct JSONRPCError {
    pub error: JSONRPCErrorError,
    pub id: RequestId,
}

#[derive(Debug, Clone, PartialEq, Deserialize, Serialize, JsonSchema, TS)]
pub struct JSONRPCErrorError {
    pub code: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub data: Option<serde_json::Value>,
    pub message: String,
}
```
- 嵌套结构分离错误元数据和请求 ID
- 错误码使用 `i64` 支持标准 JSON-RPC 错误码范围

### 序列化行为

由于使用 `#[serde(untagged)]`，序列化/反序列化行为如下：

**序列化示例：**
```rust
// Request
{
    "id": 1,
    "method": "thread/start",
    "params": { "model": "gpt-4" }
}

// Notification
{
    "method": "thread/started",
    "params": { "threadId": "thr_123" }
}

// Response
{
    "id": 1,
    "result": { "thread": { ... } }
}

// Error
{
    "id": 1,
    "error": {
        "code": -32600,
        "message": "Invalid Request"
    }
}
```

**反序列化规则：**
- 有 `error` 字段 → `JSONRPCMessage::Error`
- 有 `result` 字段 → `JSONRPCMessage::Response`
- 有 `id` 字段 → `JSONRPCMessage::Request`
- 无 `id` 字段 → `JSONRPCMessage::Notification`

## 关键代码路径与文件引用

### 类型导出
| 类型 | 位置 | 导出路径 |
|------|------|----------|
| `RequestId` | L13 | 根目录 |
| `JSONRPCMessage` | L35 | 根目录 |
| `JSONRPCRequest` | L45 | 根目录 |
| `JSONRPCNotification` | L59 | 根目录 |
| `JSONRPCResponse` | L68 | 根目录 |
| `JSONRPCError` | L76 | 根目录 |
| `JSONRPCErrorError` | L81 | 根目录 |

### 使用位置

#### 在 protocol/common.rs 中
```rust
// L724-730: ServerRequest 从 JSONRPCRequest 转换
impl TryFrom<JSONRPCRequest> for ServerRequest {
    type Error = serde_json::Error;
    fn try_from(value: JSONRPCRequest) -> Result<Self, Self::Error> {
        serde_json::from_value(serde_json::to_value(value)?)
    }
}
```

#### 在 protocol/common.rs 中
```rust
// L678-684: ServerNotification 从 JSONRPCNotification 转换
impl TryFrom<JSONRPCNotification> for ServerNotification {
    type Error = serde_json::Error;
    fn try_from(value: JSONRPCNotification) -> Result<Self, Self::Error> {
        serde_json::from_value(serde_json::to_value(value)?)
    }
}
```

#### 在 export.rs 中
```rust
// L197-209: JSON Schema 生成包含这些类型
let envelope_emitters: Vec<JsonSchemaEmitter> = vec![
    |d| write_json_schema_with_return::<crate::RequestId>(d, "RequestId"),
    |d| write_json_schema_with_return::<crate::JSONRPCMessage>(d, "JSONRPCMessage"),
    |d| write_json_schema_with_return::<crate::JSONRPCRequest>(d, "JSONRPCRequest"),
    |d| write_json_schema_with_return::<crate::JSONRPCNotification>(d, "JSONRPCNotification"),
    |d| write_json_schema_with_return::<crate::JSONRPCResponse>(d, "JSONRPCResponse"),
    |d| write_json_schema_with_return::<crate::JSONRPCError>(d, "JSONRPCError"),
    |d| write_json_schema_with_return::<crate::JSONRPCErrorError>(d, "JSONRPCErrorError"),
    ...
];
```

## 依赖与外部交互

### 外部 Crate 依赖
| Crate | 用途 |
|-------|------|
| `serde` | 序列化/反序列化派生宏 |
| `serde_json` | JSON 值类型和序列化 |
| `schemars` | JSON Schema 生成 |
| `ts-rs` | TypeScript 类型导出 |
| `codex_protocol` | `W3cTraceContext` 类型 |

### 协议分层
```
应用层 (protocol/v1.rs, protocol/v2.rs)
    ↓ 使用
业务消息层 (protocol/common.rs: ClientRequest, ServerNotification 等)
    ↓ 转换自
传输层 (jsonrpc_lite.rs: JSONRPCMessage, JSONRPCRequest 等)
    ↓ 序列化为
JSON over WebSocket/STDIO
```

### 与核心协议的关系
- `codex_protocol::protocol::W3cTraceContext` 来自 `codex-protocol` crate
- 这是唯一的跨 crate 类型依赖

## 风险、边界与改进建议

### 已知风险

1. **无标签枚举的反序列化歧义**
   - `#[serde(untagged)]` 依赖字段存在性判断类型
   - 如果消息同时包含 `result` 和 `error`，行为未定义
   - 当前协议约定避免这种情况

2. **缺少 `"jsonrpc": "2.0"` 版本字段**
   - 与标准 JSON-RPC 2.0 不兼容
   - 第三方工具可能无法正确识别消息格式
   - 这是有意为之的设计决策，但限制了互操作性

3. **`serde_json::Value` 的性能开销**
   - params 和 result 使用 `Value` 导致动态分配
   - 高频消息场景下可能影响性能

### 边界条件

1. **RequestId 范围**
   - 整数 ID 使用 `i64`，支持完整 64 位有符号范围
   - 实际使用通常限制在 32 位正整数

2. **消息大小限制**
   - 无内置大小限制，依赖传输层限制
   - 大 params/result 可能导致内存压力

3. **并发请求处理**
   - 请求 ID 需全局唯一或至少连接内唯一
   - 重复 ID 可能导致响应匹配错误

### 改进建议

1. **添加协议版本协商**
   - 虽然省略了 `"jsonrpc": "2.0"`，可考虑添加自定义版本标识
   - 便于未来协议演进和兼容性检查

2. **引入类型化参数**
   - 当前 `Option<serde_json::Value>` 完全动态
   - 可考虑添加泛型版本 `JSONRPCRequest<T>` 用于特定方法

3. **添加消息验证**
   - 当前依赖 serde 的默认验证
   - 可添加自定义验证器检查必填字段和方法名格式

4. **性能优化**
   - 评估使用 `simd-json` 替代 `serde_json`
   - 对于高频小消息，考虑二进制编码（如 MessagePack）

5. **错误码标准化**
   - 当前 `JSONRPCErrorError` 的 `code` 只是 `i64`
   - 建议定义标准错误码枚举（如标准 JSON-RPC 错误码）

6. **添加消息 ID 生成辅助**
   - 当前 `RequestId` 只是容器
   - 可添加工厂方法生成唯一 ID（如 UUID 或自增整数）

### 测试建议

1. 添加模糊测试验证反序列化鲁棒性
2. 测试边界值（最大整数 ID、空方法名等）
3. 验证 W3cTraceContext 序列化/反序列化
4. 添加与 TypeScript 生成的互操作性测试
