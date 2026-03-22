# TurnStartedNotification.json 研究文档

## 场景与职责

`TurnStartedNotification` 是 Codex App-Server Protocol v2 中的服务器通知类型，用于向客户端广播 Turn 启动事件。当服务器成功处理 `turn/start` 请求并开始处理新 Turn 时发送此通知。

**核心职责：**
- 通知客户端 Turn 已正式启动
- 提供 Turn 的初始状态快照
- 与 `TurnStartResponse` 形成响应-通知对
- 作为 Turn 生命周期事件的起点

## 功能点目的

### 1. 异步状态同步
由于 `turn/start` 是异步操作：
- `TurnStartResponse` 是同步 RPC 响应
- `TurnStartedNotification` 是异步通知
- 客户端通过通知确认 Turn 实际已开始处理

### 2. Turn 状态广播
通知包含完整的 `Turn` 对象：
- `thread_id`: 标识所属线程
- `turn`: 包含 id、status、items、error
- 状态通常为 `InProgress`

### 3. 多客户端同步
在支持多客户端连接的场景中：
- 通知广播给所有订阅了该线程的客户端
- 确保所有客户端看到一致的 Turn 状态

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TurnStartedNotification {
    pub thread_id: String,
    pub turn: Turn,
}

// Turn 结构定义
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct Turn {
    pub id: String,
    /// Only populated on a `thread/resume` or `thread/fork` response.
    /// For all other responses and notifications returning a Turn,
    /// the items field will be an empty list.
    pub items: Vec<ThreadItem>,
    pub status: TurnStatus,
    /// Only populated when the Turn's status is failed.
    pub error: Option<TurnError>,
}
```

### 通知注册

```rust
server_notification_definitions! {
    // ... 其他通知
    TurnStarted => "turn/started" (v2::TurnStartedNotification),
    // ... 其他通知
}
```

### 关键流程

1. **接收请求**：服务器接收 `turn/start` RPC 请求
2. **创建 Turn**：创建新的 Turn 对象，状态为 `InProgress`
3. **发送响应**：返回 `TurnStartResponse`
4. **发送通知**：广播 `turn/started` 通知给所有订阅者
5. **开始处理**：启动实际的模型调用和处理流程

### 与 TurnStartResponse 的关系

| 特性 | TurnStartResponse | TurnStartedNotification |
|------|-------------------|------------------------|
| 类型 | RPC 响应 | 服务器通知 |
| 方向 | Server → Client | Server → Client |
| 时机 | 同步返回 | 异步广播 |
| 包含数据 | Turn 对象 | Turn 对象 + thread_id |
| 接收者 | 请求发起者 | 所有订阅者 |

## 关键代码路径与文件引用

### 定义位置
- `TurnStartedNotification`: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:4671`

### 通知注册
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs:885`
  ```rust
  TurnStarted => "turn/started" (v2::TurnStartedNotification),
  ```

### 使用位置
- `/home/sansha/Github/codex/codex-rs/app-server/tests/suite/v2/turn_start.rs:435-446`
  - 测试用例中验证通知接收
  ```rust
  let notif: JSONRPCNotification = timeout(
      DEFAULT_READ_TIMEOUT,
      mcp.read_stream_until_notification_message("turn/started"),
  ).await??;
  let started: TurnStartedNotification =
      serde_json::from_value(notif.params.expect("params must be present"))?;
  assert_eq!(started.thread_id, thread.id);
  assert_eq!(started.turn.status, TurnStatus::InProgress);
  ```

### 相关类型
- `Turn`: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:3583`
- `TurnCompletedNotification`: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:4697`

## 依赖与外部交互

### 上游依赖
- `Turn`: 通知的核心数据结构
- `ThreadItem`: Turn 中包含的项目
- `TurnStatus`: Turn 状态枚举

### 下游消费
- **TUI 客户端**：更新 UI 显示 Turn 已开始
- **VSCode 扩展**：更新聊天界面状态
- **其他客户端**：同步 Turn 状态

### 协议集成
- JSON-RPC 2.0 通知格式
- 方法名: `turn/started`
- 参数: `TurnStartedNotification` 序列化后的 JSON

示例通知：
```json
{
  "jsonrpc": "2.0",
  "method": "turn/started",
  "params": {
    "threadId": "thread-123",
    "turn": {
      "id": "turn-456",
      "items": [],
      "status": "inProgress"
    }
  }
}
```

## 风险、边界与改进建议

### 已知风险

1. **通知丢失**
   - WebSocket 连接中断可能导致通知丢失
   - 客户端重连后需要通过 `thread/read` 获取最新状态

2. **时序问题**
   - `TurnStartResponse` 和 `TurnStartedNotification` 到达顺序不确定
   - 客户端需要处理两种可能的顺序

3. **重复通知**
   - 网络重连或服务器故障转移可能导致重复通知
   - 客户端需要通过 Turn ID 去重

### 边界情况

1. **快速失败**
   - 如果 Turn 立即失败，可能先收到 `turn/started` 再收到 `turn/completed`（状态为 failed）
   - 或者如果验证失败，可能只收到错误响应而没有通知

2. **并发启动**
   - 多个客户端同时尝试启动 Turn 时，只有一个会成功
   - 失败的客户端会收到错误响应，不会收到通知

3. **线程关闭**
   - 如果线程在 Turn 启动过程中被关闭，通知可能不会被发送

### 改进建议

1. **可靠性增强**
   - 考虑添加通知确认机制（ACK）
   - 为关键通知实现重试和持久化

2. **状态一致性**
   - 考虑在通知中添加序列号或版本号
   - 帮助客户端检测和处理乱序通知

3. **调试支持**
   - 添加 `timestamp` 字段记录通知生成时间
   - 添加 `server_id` 帮助排查多服务器部署问题

4. **API 简化**
   - 考虑合并 `TurnStartResponse` 和 `TurnStartedNotification` 的重复字段
   - 或者明确区分两者的职责边界

5. **批量通知**
   - 对于高频场景，考虑支持批量通知
   - 减少网络往返开销
