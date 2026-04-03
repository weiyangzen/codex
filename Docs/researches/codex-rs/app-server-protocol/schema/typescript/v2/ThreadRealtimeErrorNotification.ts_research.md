# ThreadRealtimeErrorNotification 研究文档

## 场景与职责

`ThreadRealtimeErrorNotification` 是 App-Server Protocol v2 API 中用于通知客户端实时语音对话（Realtime Conversation）过程中发生错误的通知类型。该通知由服务器主动推送给客户端，报告实时会话中遇到的错误情况。

在 Codex 实时语音对话架构中，该通知用于：
- 通知客户端实时会话中发生了错误
- 提供错误消息，帮助客户端理解问题原因
- 触发客户端的错误处理流程
- 协调客户端进行恢复或优雅降级

**注意**：此类型标记为 **EXPERIMENTAL**，属于实验性功能，API 可能会在未来版本中变更。

## 功能点目的

### 核心功能
1. **错误报告**：及时通知客户端实时会话中的错误情况
2. **诊断信息**：通过 `message` 字段提供人类可读的错误描述
3. **故障隔离**：通过 `threadId` 限定错误范围，支持多线程并发场景
4. **状态同步**：帮助客户端理解服务器端的错误状态

### 设计考量
- **异步通知**：采用服务器推送模式（JSON-RPC notification），确保错误及时送达
- **单一职责**：专注于错误通知，不包含恢复逻辑（恢复由客户端决定）
- **简洁设计**：仅包含必要的线程标识和错误消息，避免过度设计

## 具体技术实现

### Rust 结构定义

```rust
/// EXPERIMENTAL - emitted when realtime encounters an error.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadRealtimeErrorNotification {
    pub thread_id: String,
    pub message: String,
}
```

### TypeScript 类型定义

```typescript
interface ThreadRealtimeErrorNotification {
  threadId: string;   // 发生错误的线程 ID
  message: string;    // 错误消息描述
}
```

### 字段说明

| 字段名 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| `threadId` | `string` | 是 | 发生错误的线程唯一标识符 |
| `message` | `string` | 是 | 人类可读的错误描述信息 |

### 错误场景示例

根据测试代码，典型的错误场景包括：

#### 1. 上游服务错误
```rust
// realtime_conversation.rs 第69-72行
json!({
    "type": "error",
    "message": "upstream boom"
})
```

对应的通知验证：
```rust
// realtime_conversation.rs 第183-187行
let realtime_error = read_notification::<ThreadRealtimeErrorNotification>(
    &mut mcp,
    "thread/realtime/error"
).await?;
assert_eq!(realtime_error.thread_id, output_audio.thread_id);
assert_eq!(realtime_error.message, "upstream boom");
```

### 与关闭通知的关系

错误通知通常预示着会话即将关闭：

```
ThreadRealtimeErrorNotification
         ↓
ThreadRealtimeClosedNotification (reason: "error")
```

测试代码中的典型流程（第183-193行）：
```rust
// 1. 收到错误通知
let realtime_error = read_notification::<ThreadRealtimeErrorNotification>(
    &mut mcp,
    "thread/realtime/error"
).await?;
assert_eq!(realtime_error.message, "upstream boom");

// 2. 随后收到关闭通知
let closed = read_notification::<ThreadRealtimeClosedNotification>(
    &mut mcp,
    "thread/realtime/closed"
).await?;
assert_eq!(closed.reason.as_deref(), Some("error"));
```

## 关键代码路径与文件引用

### 定义位置
- **文件**：`codex-rs/app-server-protocol/src/protocol/v2.rs`
- **行号**：3794-3801

### 相关通知类型
- `ThreadRealtimeStartedNotification`（3766-3774行）：实时会话开始通知
- `ThreadRealtimeClosedNotification`（3803-3810行）：实时会话关闭通知
- `ThreadRealtimeItemAddedNotification`（3776-3783行）：实时会话项目添加通知
- `ThreadRealtimeOutputAudioDeltaNotification`（3785-3792行）：音频输出通知

### 使用场景
- **通知方法**：`thread/realtime/error`
- **传输方式**：JSON-RPC 2.0 Notification（服务器 → 客户端）

### 测试文件
- **文件**：`codex-rs/app-server/tests/suite/v2/realtime_conversation.rs`
- **测试用例**：`realtime_conversation_streams_v2_notifications`
- **测试行号**：183-187行

### 测试示例
```rust
let realtime_error = read_notification::<ThreadRealtimeErrorNotification>(
    &mut mcp,
    "thread/realtime/error"
).await?;
assert_eq!(realtime_error.thread_id, output_audio.thread_id);
assert_eq!(realtime_error.message, "upstream boom");
```

### 关联的 RPC 方法
- `thread/realtime/start`：启动实时会话
- `thread/realtime/stop`：停止实时会话
- `thread/realtime/appendAudio`：追加音频输入
- `thread/realtime/appendText`：追加文本输入

### 核心协议错误事件
- **文件**：`codex-rs/protocol/src/protocol.rs`
- **行号**：177-193行
- **类型**：`RealtimeEvent::Error(String)`

```rust
pub enum RealtimeEvent {
    // ... 其他变体
    Error(String),
    // ...
}
```

## 依赖与外部交互

### 依赖关系
- `serde`：序列化/反序列化
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成

### 通知流程

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   服务器内部     │     │  WebSocket 连接  │     │   客户端        │
│                 │     │                 │     │                 │
│ 检测到错误      │ →  │ 发送 error      │ →  │ 接收通知        │
│ (上游服务错误)   │     │ notification    │     │                 │
└─────────────────┘     └─────────────────┘     └────────┬────────┘
                                                         │
                                                         ↓
                                                ┌─────────────────┐
                                                │  错误处理        │
                                                │  - 显示错误提示   │
                                                │  - 记录日志      │
                                                │  - 触发恢复逻辑   │
                                                └─────────────────┘
                                                         │
                                                         ↓
                                                ┌─────────────────┐
                                                │  等待关闭通知    │
                                                │  (session closed)│
                                                └─────────────────┘
```

### 外部系统交互
- **WebSocket 传输**：通过 WebSocket 连接推送通知
- **上游服务**：错误可能源自 OpenAI Realtime API 或其他后端服务
- **客户端错误处理**：触发客户端的错误恢复或降级逻辑

### 与相关通知的关系
```
                    ┌─────────────────────────┐
                    │   Realtime Session      │
                    └───────────┬─────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        ↓                       ↓                       ↓
ThreadRealtimeStarted   ThreadRealtimeError      ThreadRealtimeClosed
                                │
                                ↓
                    ThreadRealtimeClosed
                       (reason: "error")
```

## 风险、边界与改进建议

### 实验性状态警告
⚠️ **此类型标记为 EXPERIMENTAL**：
- API 可能在未来的版本中发生破坏性变更
- 不建议在生产环境中依赖此功能
- 需要显式启用 feature flag 才能使用

### 已知限制
1. **Feature Flag 控制**：实时对话功能需要 `realtime_conversation` feature 启用

2. **错误信息非结构化**：`message` 字段为自由文本，客户端难以程序化地处理不同类型的错误

3. **无错误码**：缺少标准化的错误码，不利于客户端进行针对性的错误处理

4. **无重试建议**：通知中不包含是否建议重试的信息

### 边界情况
- **重复错误**：同一错误可能触发多次通知，客户端应做好去重处理
- **并发场景**：多线程环境下，确保 `threadId` 正确匹配
- **网络中断**：网络异常可能导致错误通知丢失

### 处理建议

#### 客户端处理流程
```typescript
function handleRealtimeError(notification: ThreadRealtimeErrorNotification) {
    // 1. 验证线程 ID
    if (notification.threadId !== currentThreadId) {
        return; // 忽略不相关的通知
    }
    
    // 2. 记录错误
    console.error(`Realtime error: ${notification.message}`);
    
    // 3. 显示用户友好的错误提示
    showErrorToast(notification.message);
    
    // 4. 更新状态
    setRealtimeState('error');
    
    // 5. 等待关闭通知进行清理
    // （关闭通知通常会在错误通知后到达）
}
```

### 改进建议

1. **添加错误码**：引入标准化的错误码，便于客户端程序化地处理错误
   ```rust
   pub struct ThreadRealtimeErrorNotification {
       pub thread_id: String,
       pub code: RealtimeErrorCode,  // 新增
       pub message: String,
   }
   
   pub enum RealtimeErrorCode {
       UpstreamError,
       AudioEncodingError,
       NetworkError,
       SessionExpired,
       RateLimitExceeded,
       // ...
   }
   ```

2. **添加可恢复性标记**：指示错误是否可恢复
   ```rust
   pub struct ThreadRealtimeErrorNotification {
       pub thread_id: String,
       pub message: String,
       pub recoverable: bool,  // 新增
       pub suggested_action: Option<RealtimeErrorAction>,  // 新增
   }
   ```

3. **添加时间戳**：帮助客户端理解错误发生的时间顺序
   ```rust
   pub timestamp: i64,  // Unix 时间戳
   ```

4. **添加错误详情**：对于复杂错误，提供结构化的详细信息
   ```rust
   pub details: Option<JsonValue>,
   ```

5. **与关闭通知合并**：考虑将错误信息合并到关闭通知中，简化协议
   ```rust
   pub struct ThreadRealtimeClosedNotification {
       pub thread_id: String,
       pub reason: CloseReason,
       pub error: Option<ThreadRealtimeErrorNotification>,  // 如果是错误关闭
   }
   ```

6. **稳定化**：考虑将此类型从实验状态提升为稳定 API

### 调试建议
- 监听此通知并记录完整的错误消息
- 结合服务器日志分析错误的根本原因
- 建立错误分类机制，统计各类错误的发生频率
- 对于频繁发生的错误，考虑添加自动重试或降级逻辑
