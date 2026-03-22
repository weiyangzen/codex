# RequestId.json 研究文档

## 场景与职责

`RequestId` 是 Codex App-Server 协议中用于**标识 JSON-RPC 请求**的类型。它是一个联合类型，支持字符串或整数形式的请求标识。

该类型是 JSON-RPC 2.0 协议请求标识的 Codex 实现，用于请求和响应的关联。

### 使用场景

1. **请求-响应关联**：通过 `id` 字段将响应与请求匹配
2. **并发请求管理**：同时处理多个请求时区分不同请求
3. **客户端/服务器标识**：双方都可以生成请求 ID

---

## 功能点目的

### 类型定义

`RequestId` 是一个 `anyOf` 联合类型，支持以下形式：

| 类型 | 格式 | 示例 |
|------|------|------|
| string | 字符串 | `"req-123"`, `"uuid-string"` |
| integer | 整数（int64） | `42`, `12345` |

### 使用位置

- `JSONRPCRequest.id` - 请求标识
- `JSONRPCResponse.id` - 响应标识（与请求对应）
- `JSONRPCError.id` - 错误响应标识（与请求对应）

---

## 具体技术实现

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/jsonrpc_lite.rs
#[derive(
    Debug, Clone, PartialEq, PartialOrd, Ord, Deserialize, Serialize, Hash, Eq, JsonSchema, TS,
)]
#[serde(untagged)]
pub enum RequestId {
    String(String),
    #[ts(type = "number")]
    Integer(i64),
}

impl fmt::Display for RequestId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::String(value) => f.write_str(value),
            Self::Integer(value) => write!(f, "{value}"),
        }
    }
}
```

### 序列化示例

```json
// 字符串形式
{ "id": "req-abc-123", "method": "thread/start", ... }

// 整数形式
{ "id": 42, "method": "thread/start", ... }
```

### JSON Schema 定义

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "anyOf": [
    { "type": "string" },
    { "format": "int64", "type": "integer" }
  ],
  "title": "RequestId"
}
```

---

## 关键代码路径与文件引用

### 协议定义

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/jsonrpc_lite.rs` | 主类型定义（行 13-21） |

### 使用位置

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/jsonrpc_lite.rs` | JSONRPCRequest, JSONRPCResponse, JSONRPCError 中使用 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ClientRequest, ServerRequest 中使用 |

---

## 依赖与外部交互

### 序列化特性

- 使用 `#[serde(untagged)]` 实现无标签联合类型
- 整数在 TypeScript 中映射为 `number` 类型
- 实现了 `Display` trait 便于日志输出

### 比较和哈希

```rust
// RequestId 实现了 Eq, Ord, Hash
let id1 = RequestId::Integer(42);
let id2 = RequestId::String("42".to_string());
// id1 != id2（类型不同，即使显示值相同）
```

---

## 风险、边界与改进建议

### 已知风险

1. **类型不匹配**：`RequestId::Integer(42)` 和 `RequestId::String("42".to_string())` 被视为不同 ID，但可能导致混淆

2. **整数精度**：JavaScript 的 `number` 类型只能安全表示 `-2^53` 到 `2^53` 范围内的整数，超出此范围的 `i64` 值可能丢失精度

3. **空字符串**：`RequestId::String("")` 是合法的，但可能引发问题

### 边界情况

1. **负数 ID**：整数 ID 可以为负数
2. **零 ID**：`RequestId::Integer(0)` 是合法的
3. **大字符串**：字符串 ID 没有长度限制

### 改进建议

1. **统一 ID 格式**：建议统一使用字符串 UUID 格式，避免类型混淆：
   ```rust
   pub struct RequestId(Uuid);  // 使用 UUID
   ```

2. **ID 生成器**：提供内置的 ID 生成器：
   ```rust
   impl RequestId {
       pub fn generate() -> Self {
           Self::String(uuid::Uuid::new_v4().to_string())
       }
       
       pub fn next_sequence() -> Self {
           static COUNTER: AtomicI64 = AtomicI64::new(0);
           Self::Integer(COUNTER.fetch_add(1, Ordering::SeqCst))
       }
   }
   ```

3. **验证**：添加 ID 格式验证：
   ```rust
   impl RequestId {
       pub fn is_valid(&self) -> bool {
           match self {
               Self::String(s) => !s.is_empty() && s.len() <= 256,
               Self::Integer(n) => *n >= 0,
           }
       }
   }
   ```

4. **类型安全**：考虑使用新类型模式避免与原始类型混淆：
   ```rust
   pub struct RequestId(RequestIdInner);
   
   enum RequestIdInner {
       String(String),
       Integer(i64),
   }
   ```

5. **文档约定**：明确推荐客户端和服务器使用哪种 ID 格式，减少互操作问题
