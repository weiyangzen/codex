# ThreadSetNameResponse.json 研究文档

## 场景与职责

`ThreadSetNameResponse` 是 Codex App Server Protocol v2 中 `thread/name/set` 方法的响应结构。这是一个极简的响应类型，仅用于确认线程名称设置操作已成功完成。

该响应的设计遵循 JSON-RPC 2.0 规范的成功响应语义，不包含额外的数据负载，因为：
- 名称设置是幂等操作
- 客户端可通过 `ThreadNameUpdatedNotification` 获取更新后的名称
- 减少不必要的网络传输

## 功能点目的

### 核心功能
- **操作确认**: 向客户端确认名称设置请求已成功处理
- **协议完整性**: 满足 JSON-RPC 请求-响应模式的完整性要求

### 设计哲学
采用空响应而非返回完整 Thread 对象的原因：
1. **性能优化**: 避免重复传输线程数据
2. **事件驱动**: 状态变更通过通知机制广播，响应仅表示操作完成
3. **简单性**: 减少客户端解析复杂度

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadSetNameResponse {}
```

### JSON Schema 定义

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "ThreadSetNameResponse",
  "type": "object"
}
```

### 响应流程

1. **操作成功**: 名称成功持久化到磁盘
2. **响应发送**: 返回空的 `ThreadSetNameResponse`
3. **通知广播**: 发送 `ThreadNameUpdatedNotification` 给所有客户端

### 典型响应示例

```json
{
  "jsonrpc": "2.0",
  "id": 42,
  "result": {}
}
```

## 关键代码路径与文件引用

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs`: ThreadSetNameResponse 结构体定义
- `codex-rs/app-server-protocol/schema/json/v2/ThreadSetNameResponse.json`: JSON Schema 定义

### 服务端实现
- `codex-rs/app-server/src/codex_message_processor.rs`:
  - `thread_set_name()` 方法发送响应 (line 2319-2321)

### 客户端处理
- `codex-rs/tui_app_server/src/app_server_session.rs`:
  - 调用线程名称设置并处理响应

### 测试用例
- `codex-rs/app-server/tests/suite/v2/thread_name_websocket.rs`:
  - 验证响应接收和通知广播

### TypeScript 类型定义
- `codex-rs/app-server-protocol/schema/typescript/v2/ThreadSetNameResponse.ts`:
  ```typescript
  export type ThreadSetNameResponse = {};
  ```

## 依赖与外部交互

### 关联通知
客户端应监听 `ThreadNameUpdatedNotification` 获取实际的状态更新：

```rust
pub struct ThreadNameUpdatedNotification {
    pub thread_id: String,
    pub thread_name: Option<String>,
}
```

### 错误响应
操作失败时返回 JSON-RPC Error 而非成功响应：
- **无效请求错误** (-32600): 空名称、无效线程 ID
- **内部错误** (-32603): 持久化失败

## 风险、边界与改进建议

### 已知限制

1. **无状态返回**: 客户端需额外请求获取更新后的完整线程状态
2. **竞态条件**: 快速连续修改时，通知顺序可能与请求顺序不一致

### 改进建议

1. **返回更新时间**: 添加 `updated_at` 时间戳帮助客户端排序
2. **返回规范化名称**: 返回服务端实际存储的名称（经过规范化处理后）
3. **批量操作**: 考虑支持批量设置多个线程名称

### 兼容性
- 空对象响应对所有 JSON-RPC 客户端兼容
- 未来可安全添加可选字段，保持向后兼容
