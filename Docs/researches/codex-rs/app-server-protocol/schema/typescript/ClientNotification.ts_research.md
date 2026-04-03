# ClientNotification.ts 研究文档

## 场景与职责

`ClientNotification.ts` 定义了客户端向服务端发送的通知类型。与请求-响应模式不同，通知是单向的，不需要服务端返回响应。这是 JSON-RPC 协议中通知机制的体现，用于客户端向服务端报告状态变化或事件。

**核心职责：**
- 定义客户端可以发送的通知类型
- 支持初始化完成通知
- 为未来扩展预留通知机制

## 功能点目的

1. **初始化完成通知**
   - 客户端完成初始化后通知服务端
   - 服务端可以在此后开始发送通知和请求

2. **轻量级状态报告**
   - 无需响应的单向通信
   - 减少不必要的网络往返

3. **协议扩展性**
   - 为未来新增客户端通知预留结构
   - 保持与 JSON-RPC 通知规范的兼容

## 具体技术实现

### 类型定义

```typescript
export type ClientNotification = { "method": "initialized" };
```

### 当前支持的通知

| 方法 | 说明 |
|------|------|
| `"initialized"` | 客户端初始化完成通知 |

### 生成信息

- **生成工具**: [ts-rs](https://github.com/Aleph-Alpha/ts-rs)
- **源文件**: `codex-rs/app-server-protocol/src/protocol/common.rs`
- **Rust 类型**: `ClientNotification`
- **序列化**: 使用 method 字段作为标签

### Rust 源类型定义

```rust
client_notification_definitions! {
    Initialized,
}
```

展开后的宏定义：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, JsonSchema, TS, Display)]
#[serde(tag = "method", content = "params", rename_all = "camelCase")]
#[strum(serialize_all = "camelCase")]
pub enum ClientNotification {
    Initialized,
}
```

## 关键代码路径与文件引用

### 使用场景

1. **初始化流程**
   - 客户端发送 `initialize` 请求
   - 服务端返回 `InitializeResponse`
   - 客户端发送 `initialized` 通知

2. **JSON-RPC 消息处理**
   - 与 `JSONRPCNotification` 类型相互转换
   - 文件: `jsonrpc_lite.rs`

### 相关类型

- **`ServerNotification`**: 服务端向客户端发送的通知（更丰富）
- **`JSONRPCNotification`**: JSON-RPC 通知消息封装
- **`ClientRequest`**: 客户端请求（需要响应）

### 消息流示例

```
Client                                    Server
  |                                         |
  | --- ClientRequest::Initialize --------> |
  |                                         |
  | <---------- InitializeResponse -------- |
  |                                         |
  | --- ClientNotification::Initialized --> |
  |                                         |
  | <--- ServerNotification (各种通知) ----- |
```

## 依赖与外部交互

### 上游依赖

- 无直接依赖（基础枚举类型）

### 下游使用者

| 使用者 | 路径 | 用途 |
|--------|------|------|
| JSON-RPC 处理 | `jsonrpc_lite.rs` | 消息序列化/反序列化 |
| 连接管理 | - | 初始化流程控制 |

### 序列化格式示例

```json
// initialized 通知
{
  "method": "initialized"
}
```

## 风险、边界与改进建议

### 风险点

1. **通知丢失**
   - 通知不保证送达（无响应确认）
   - 网络问题可能导致服务端未收到 `initialized`

2. **扩展限制**
   - 当前只有一个通知类型
   - 未来扩展需要保持向后兼容

3. **时序问题**
   - 客户端必须在收到 `InitializeResponse` 后才能发送 `initialized`
   - 服务端需要处理乱序消息

### 边界情况

1. **重复通知**
   - 客户端多次发送 `initialized` 的处理
   - 应该是幂等的

2. **提前通知**
   - 在收到 `InitializeResponse` 前发送 `initialized`
   - 服务端应该拒绝或忽略

3. **连接断开**
   - 发送 `initialized` 后连接断开
   - 重连后是否需要重新初始化

### 改进建议

1. **添加更多通知类型**
   - 客户端状态变化通知
   - 用户活动通知（如用户开始输入）
   - 客户端错误报告

2. **通知确认机制**
   - 考虑为重要通知添加确认机制
   - 或者使用请求-响应模式替代

3. **参数扩展**
   - `Initialized` 通知可以携带额外信息
   - 如客户端实际支持的功能列表

4. **与 ServerNotification 对齐**
   - `ServerNotification` 非常丰富（40+ 种通知）
   - `ClientNotification` 目前过于简单
   - 考虑增加更多客户端通知类型

5. **文档完善**
   - 明确通知的使用时机和顺序
   - 提供状态机图说明初始化流程
