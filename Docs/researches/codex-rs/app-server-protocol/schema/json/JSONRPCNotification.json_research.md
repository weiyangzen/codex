# JSONRPCNotification.json 研究文档

## 场景与职责

`JSONRPCNotification` 是 Codex App-Server 协议中用于**表示 JSON-RPC 通知**的结构。通知是一种不需要响应的消息，用于单向事件传递。

该类型是 JSON-RPC 2.0 协议通知消息的 Codex 实现，属于双向通信流（Client ↔ Server）。

### 使用场景

1. **服务器 → 客户端通知**：如 `turn/started`, `item/completed` 等事件
2. **客户端 → 服务器通知**：如 `initialized` 通知
3. **事件广播**：向所有连接的客户端广播状态变化

---

## 功能点目的

### 核心字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `method` | string | ✅ | 通知方法名 |
| `params` | any | ❌ | 通知参数 |

### 与请求的区别

| 特性 | JSONRPCRequest | JSONRPCNotification |
|------|---------------|---------------------|
| `id` 字段 | 必需 | 省略 |
| 响应期望 | 是 | 否 |
| 使用场景 | 需要结果的操作 | 单向事件通知 |

---

## 具体技术实现

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/jsonrpc_lite.rs
/// A notification which does not expect a response.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize, JsonSchema, TS)]
pub struct JSONRPCNotification {
    pub method: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub params: Option<serde_json::Value>,
}
```

### 序列化示例

```json
{
  "method": "thread/started",
  "params": {
    "threadId": "thr_123",
    "status": { "type": "running" }
  }
}
```

---

## 关键代码路径与文件引用

### 协议定义

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/jsonrpc_lite.rs` | 主类型定义（行 58-65） |

### 使用位置

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/jsonrpc_lite.rs` | JSONRPCMessage 枚举中使用 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ServerNotification 转换 |

---

## 依赖与外部交互

### 依赖类型

```rust
use serde_json::Value as JsonValue;
```

### 序列化特性

- `params` 可选，使用 `skip_serializing_if = "Option::is_none"`
- 不包含 `id` 字段（与请求的区别）

---

## 风险、边界与改进建议

### 已知风险

1. **无响应保证**：通知不保证送达，客户端/服务器需要处理丢失情况

2. **与请求混淆**：如果错误地包含 `id` 字段，可能被解析为请求

### 边界情况

1. **空参数**：`params` 为 `null` 或省略
2. **未知方法**：接收方可能不认识通知的方法名

### 改进建议

1. **方法名验证**：添加方法名格式验证（如必须包含命名空间前缀）

2. **通知确认**：对于重要通知，考虑添加可选的确认机制

3. **批量通知**：考虑支持批量发送多个通知
