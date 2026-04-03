# ThreadRealtimeClosedNotification 研究文档

## 场景与职责

`ThreadRealtimeClosedNotification` 是 App-Server Protocol v2 API 中用于通知客户端实时语音对话（Realtime Conversation）会话已终止的通知类型。该通知由服务器主动推送给客户端，标志着实时音频传输通道的关闭。

在 Codex 实时语音对话架构中，该通知用于：
- 通知客户端实时会话已结束
- 提供会话关闭的原因，帮助客户端理解终止原因
- 触发客户端清理相关资源（音频设备、WebSocket 连接等）
- 协调客户端 UI 状态转换（如从"通话中"切换到"待机"）

**注意**：此类型标记为 **EXPERIMENTAL**，属于实验性功能，API 可能会在未来版本中变更。

## 功能点目的

### 核心功能
1. **会话终止通知**：明确告知客户端实时对话会话已结束
2. **原因说明**：提供可选的关闭原因，支持错误诊断和用户体验优化
3. **资源清理信号**：作为客户端释放音频资源和重置状态的信号
4. **状态同步**：确保客户端和服务器的实时会话状态保持一致

### 设计考量
- **异步通知**：采用服务器推送模式（JSON-RPC notification），无需客户端轮询
- **可选原因**：`reason` 字段为可选，允许服务器在无需详细说明时省略
- **线程隔离**：通过 `threadId` 明确标识受影响的线程，支持多线程并发场景

## 具体技术实现

### Rust 结构定义

```rust
/// EXPERIMENTAL - emitted when thread realtime transport closes.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadRealtimeClosedNotification {
    pub thread_id: String,
    pub reason: Option<String>,
}
```

### TypeScript 类型定义

```typescript
interface ThreadRealtimeClosedNotification {
  threadId: string;        // 线程唯一标识符
  reason: string | null;   // 关闭原因（可选）
}
```

### 字段说明

| 字段名 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| `threadId` | `string` | 是 | 实时会话所属的线程 ID |
| `reason` | `string \| null` | 否 | 会话关闭的原因描述 |

### 关闭原因值

根据测试代码和实现，可能的 `reason` 值包括：

| 原因值 | 触发场景 |
|--------|----------|
| `"error"` | 发生错误导致会话终止（如上游服务错误） |
| `"requested"` | 客户端主动请求停止实时会话 |
| `"transport_closed"` | WebSocket 传输层关闭 |
| `null` | 未提供具体原因 |

### 触发场景

#### 1. 错误导致的关闭
```rust
// realtime_conversation.rs 第189-193行
let closed = read_notification::<ThreadRealtimeClosedNotification>(
    &mut mcp,
    "thread/realtime/closed"
).await?;
assert_eq!(closed.reason.as_deref(), Some("error"));
```

#### 2. 主动停止导致的关闭
```rust
// realtime_conversation.rs 第303-310行
let closed = read_notification::<ThreadRealtimeClosedNotification>(
    &mut mcp,
    "thread/realtime/closed"
).await?;
assert!(matches!(
    closed.reason.as_deref(),
    Some("requested" | "transport_closed")
));
```

## 关键代码路径与文件引用

### 定义位置
- **文件**：`codex-rs/app-server-protocol/src/protocol/v2.rs`
- **行号**：3803-3810

### 相关通知类型
- `ThreadRealtimeStartedNotification`（3766-3774行）：实时会话开始通知
- `ThreadRealtimeErrorNotification`（3794-3801行）：实时会话错误通知
- `ThreadRealtimeItemAddedNotification`（3776-3783行）：实时会话项目添加通知
- `ThreadRealtimeOutputAudioDeltaNotification`（3785-3792行）：音频输出通知

### 使用场景
- **通知方法**：`thread/realtime/closed`
- **传输方式**：JSON-RPC 2.0 Notification（服务器 → 客户端）

### 测试文件
- **文件**：`codex-rs/app-server/tests/suite/v2/realtime_conversation.rs`
- **测试用例**：
  - `realtime_conversation_streams_v2_notifications`：验证错误导致的关闭
  - `realtime_conversation_stop_emits_closed_notification`：验证主动停止导致的关闭

### 测试示例
```rust
let closed = read_notification::<ThreadRealtimeClosedNotification>(
    &mut mcp,
    "thread/realtime/closed"
).await?;
assert_eq!(closed.thread_id, output_audio.thread_id);
assert_eq!(closed.reason.as_deref(), Some("error"));
```

### 关联的 RPC 方法
- `thread/realtime/start`：启动实时会话
- `thread/realtime/stop`：停止实时会话（会触发此通知）
- `thread/realtime/appendAudio`：追加音频输入
- `thread/realtime/appendText`：追加文本输入

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
│ 检测到会话关闭   │ →  │ 发送 closed     │ →  │ 接收通知        │
│ (错误或停止)    │     │ notification    │     │                 │
└─────────────────┘     └─────────────────┘     └────────┬────────┘
                                                         │
                                                         ↓
                                                ┌─────────────────┐
                                                │  清理资源        │
                                                │  - 释放音频设备   │
                                                │  - 重置 UI 状态   │
                                                │  - 记录日志      │
                                                └─────────────────┘
```

### 外部系统交互
- **WebSocket 传输**：通过 WebSocket 连接推送通知
- **客户端状态机**：触发客户端实时会话状态机转换到终止状态
- **UI 更新**：驱动客户端 UI 从"实时对话中"状态退出

### 与相关通知的关系
```
ThreadRealtimeStartedNotification
         ↓
[实时会话进行中]
         ↓
    ┌────┴────┐
    ↓         ↓
ThreadRealtimeErrorNotification  ThreadRealtimeStopParams
    ↓                              ↓
ThreadRealtimeClosedNotification ←─┘
```

## 风险、边界与改进建议

### 实验性状态警告
⚠️ **此类型标记为 EXPERIMENTAL**：
- API 可能在未来的版本中发生破坏性变更
- 不建议在生产环境中依赖此功能
- 需要显式启用 feature flag 才能使用

### 已知限制
1. **Feature Flag 控制**：实时对话功能需要 `realtime_conversation` feature 启用

2. **原因值非标准化**：`reason` 字段为自由文本，不同场景可能使用不同的原因字符串，客户端不应依赖特定的原因值进行逻辑判断

3. **无自动重连**：收到此通知后，客户端需要显式调用 `thread/realtime/start` 才能重新建立实时会话

### 边界情况
- **重复通知**：理论上服务器不应发送重复的关闭通知，但客户端应做好幂等处理
- **并发场景**：多线程环境下，确保 `threadId` 正确匹配
- **网络中断**：网络异常可能导致通知丢失，客户端应有超时机制

### 处理建议

#### 客户端处理流程
```typescript
function handleRealtimeClosed(notification: ThreadRealtimeClosedNotification) {
    // 1. 验证线程 ID
    if (notification.threadId !== currentThreadId) {
        return; // 忽略不相关的通知
    }
    
    // 2. 更新状态
    setRealtimeState('closed');
    
    // 3. 释放资源
    releaseAudioResources();
    
    // 4. 更新 UI
    hideRealtimeUI();
    
    // 5. 记录日志（可选）
    if (notification.reason) {
        console.log(`Realtime session closed: ${notification.reason}`);
    }
}
```

### 改进建议
1. **标准化原因码**：将 `reason` 改为枚举类型，提供标准化的关闭原因
   ```rust
   pub enum RealtimeCloseReason {
       Error(String),
       UserRequested,
       TransportClosed,
       SessionExpired,
       // ...
   }
   ```

2. **添加错误详情**：对于错误导致的关闭，添加结构化的错误信息字段

3. **会话统计**：添加会话统计信息（持续时间、音频数据量等）

4. **优雅关闭握手**：支持双向确认机制，确保双方都知晓会话结束

5. **自动重连建议**：在通知中添加 `suggested_reconnect_delay` 字段，指导客户端重连时机

6. **稳定化**：考虑将此类型从实验状态提升为稳定 API

### 调试建议
- 监听此通知并记录完整的关闭原因
- 结合服务器日志分析异常关闭的根本原因
- 监控关闭通知的到达时间，检测网络延迟问题
