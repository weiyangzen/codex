# JSONRPCErrorError.json 研究文档

## 场景与职责

`JSONRPCErrorError` 是 Codex App-Server 协议中用于**表示 JSON-RPC 错误详情**的结构。它是 `JSONRPCError` 的子结构，包含具体的错误代码、消息和可选数据。

该类型是 JSON-RPC 2.0 协议标准错误对象的 Codex 实现。

### 使用场景

1. **错误详情封装**：作为 `JSONRPCError.error` 字段的类型
2. **结构化错误信息**：提供机器可读的错误代码和人类可读的消息
3. **扩展错误数据**：通过 `data` 字段传递额外的错误上下文

---

## 功能点目的

### 核心字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `code` | integer | ✅ | 错误代码（int64 格式） |
| `message` | string | ✅ | 错误描述 |
| `data` | any | ❌ | 附加错误数据 |

### 字段设计意图

- **`code`**：机器可读的错误标识，遵循 JSON-RPC 2.0 标准错误代码范围
- **`message`**：人类可读的错误描述，应简洁明了
- **`data`**：可选的附加信息，格式由应用程序定义

---

## 具体技术实现

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/jsonrpc_lite.rs
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize, JsonSchema, TS)]
pub struct JSONRPCErrorError {
    pub code: i64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub data: Option<serde_json::Value>,
    pub message: String,
}
```

### JSON Schema 格式

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "code": {
      "format": "int64",
      "type": "integer"
    },
    "data": true,
    "message": {
      "type": "string"
    }
  },
  "required": ["code", "message"],
  "title": "JSONRPCErrorError",
  "type": "object"
}
```

### 使用示例

```json
{
  "error": {
    "code": -32602,
    "message": "Invalid params: missing required field 'threadId'",
    "data": {
      "missingField": "threadId"
    }
  },
  "id": 42
}
```

---

## 关键代码路径与文件引用

### 协议定义

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/jsonrpc_lite.rs` | 主类型定义（行 81-88） |

### 使用位置

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/jsonrpc_lite.rs` | JSONRPCError 中使用（行 76-79） |
| `codex-rs/app-server-protocol/src/jsonrpc_lite.rs` | JSONRPCMessage 定义中引用 |

---

## 依赖与外部交互

### 依赖类型

```rust
use serde_json::Value as JsonValue;
```

### 序列化特性

- `code` 使用 `i64` 类型，JSON Schema 中标记为 `format: "int64"`
- `data` 使用 `serde_json::Value` 表示任意 JSON 值
- `data` 字段使用 `skip_serializing_if = "Option::is_none"` 避免空值

---

## 风险、边界与改进建议

### 已知风险

1. **data 字段类型安全**：`data` 是任意 JSON 值，缺乏类型安全，客户端需要自行验证

2. **错误代码冲突**：使用 `-32000` 到 `-32099` 范围内的自定义错误代码时，可能与服务器框架的错误代码冲突

### 边界情况

1. **空 message**：虽然 `message` 是必填字段，但空字符串 `""` 是合法的
2. **零错误代码**：`code: 0` 不是标准 JSON-RPC 错误代码，但技术上可行
3. **超大 code 值**：`i64` 范围外的值在 JSON 中可能丢失精度

### 改进建议

1. **错误代码枚举**：定义强类型的错误代码枚举，替代原始 `i64`

2. **message 验证**：添加 `message` 非空验证，确保错误描述有意义

3. **结构化 data**：为常见错误场景定义结构化的 data 类型，提高类型安全性

4. **错误链支持**：考虑支持嵌套错误，便于追踪错误根源
