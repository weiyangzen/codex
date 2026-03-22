# JSONRPCResponse.json 研究文档

## 场景与职责

`JSONRPCResponse` 是 Codex App-Server 协议中用于**表示 JSON-RPC 成功响应**的结构。响应用于返回请求的处理结果。

该类型是 JSON-RPC 2.0 协议响应消息的 Codex 实现，属于双向通信流（Client ↔ Server）。

### 使用场景

1. **服务器 → 客户端响应**：返回操作结果或查询数据
2. **客户端 → 服务器响应**：返回审批决策等
3. **成功结果传递**：传递任意 JSON 格式的结果数据

---

## 功能点目的

### 核心字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `id` | RequestId | ✅ | 对应请求的标识 |
| `result` | any | ✅ | 响应结果 |

### 与错误的区别

| 特性 | JSONRPCResponse | JSONRPCError |
|------|----------------|--------------|
| 结果字段 | `result` | `error` |
| 使用场景 | 成功处理 | 处理失败 |
| 结果类型 | 任意 JSON | 结构化错误对象 |

---

## 具体技术实现

### Rust 源码定义

```rust
// codex-rs/app-server-protocol/src/jsonrpc_lite.rs
/// A successful (non-error) response to a request.
#[derive(Debug, Clone, PartialEq, Deserialize, Serialize, JsonSchema, TS)]
pub struct JSONRPCResponse {
    pub id: RequestId,
    pub result: Result,  // type Result = serde_json::Value;
}

pub type Result = serde_json::Value;
```

### 序列化示例

```json
{
  "id": 42,
  "result": {
    "threadId": "thr_123",
    "status": "created"
  }
}
```

---

## 关键代码路径与文件引用

### 协议定义

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/jsonrpc_lite.rs` | 主类型定义（行 67-72） |

### 使用位置

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/jsonrpc_lite.rs` | JSONRPCMessage 枚举中使用 |

---

## 依赖与外部交互

### 依赖类型

```rust
use serde_json::Value as JsonValue;
```

### 序列化特性

- `result` 可以是任意 JSON 值
- `id` 必须与对应请求的 `id` 匹配

---

## 风险、边界与改进建议

### 已知风险

1. **结果为空**：`result` 为 `null` 时，客户端需要正确处理

2. **ID 不匹配**：响应的 `id` 与请求不匹配可能导致请求挂起

### 边界情况

1. **空结果**：`result: null` 是合法的
2. **大结果**：大型结果可能导致传输问题

### 改进建议

1. **结果包装**：考虑统一包装结果格式：
   ```rust
   pub struct JSONRPCResponse {
       pub id: RequestId,
       pub result: ResponseResult,
   }
   
   pub enum ResponseResult {
       Success(JsonValue),
       Empty,
   }
   ```

2. **响应压缩**：对于大型结果，考虑支持压缩

3. **分页支持**：对于列表结果，考虑标准分页格式
