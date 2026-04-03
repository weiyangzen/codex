# ThreadRealtimeErrorNotification.json 研究文档

## 场景与职责

`ThreadRealtimeErrorNotification` 是 Codex App-Server Protocol v2 中的实验性服务器推送通知，用于在实时对话（Realtime Conversation）过程中发生错误时通知客户端。

**核心场景：**
1. **WebSocket 错误** - 与后端实时服务通信时发生协议或网络错误
2. **音频处理错误** - 音频编解码、采样率不匹配等问题
3. **会话状态错误** - 后端会话异常、超时或无效状态转换
4. **认证/授权错误** - 实时服务认证失败或权限不足

**典型使用流程：**
```
// 错误发生流程
Server (检测到实时对话错误) 
  -> ThreadRealtimeErrorNotification { threadId, message } 
  -> Client

// 后续可能流程
Server -> ThreadRealtimeClosedNotification { reason: "error" } -> Client
```

**实验性状态：**
- 标记为 `EXPERIMENTAL`
- 需要启用 `realtime_conversation` 功能标志

## 功能点目的

### 1. 通知结构设计

```json
{
  "threadId": "thread-uuid-string",
  "message": "Upstream connection failed"
}
```

**设计意图：**
- **精确关联**：`threadId` 明确标识发生错误的线程
- **人类可读**：`message` 提供可理解的错误描述
- **错误恢复提示**：客户端可基于错误类型决定重试或终止

### 2. 与 ThreadRealtimeClosedNotification 的区别

| 特性 | ThreadRealtimeErrorNotification | ThreadRealtimeClosedNotification |
|------|--------------------------------|----------------------------------|
| 触发时机 | 发生错误但连接可能仍存活 | 连接已关闭或即将关闭 |
| 严重程度 | 可恢复或不可恢复 | 会话已终止 |
| 后续操作 | 可能继续或关闭 | 必须清理资源 |
| 消息内容 | 详细错误描述 | 关闭原因摘要 |

**典型序列：**
```
ErrorNotification (报告问题)
    |
    v
[可能的重试/恢复尝试]
    |
    v
ClosedNotification (最终关闭)
```

### 3. 错误分类（隐含）

虽然 `message` 是字符串，但典型错误包括：
- **网络错误**：`"upstream connection failed"`, `"websocket timeout"`
- **协议错误**：`"invalid session state"`, `"unsupported audio format"`
- **服务错误**：`"rate limit exceeded"`, `"server overloaded"`

## 具体技术实现

### 1. Rust 源码定义

**文件路径：** `codex-rs/app-server-protocol/src/protocol/v2.rs:3794-3801`

```rust
/// EXPERIMENTAL - emitted when thread realtime encounters an error.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadRealtimeErrorNotification {
    pub thread_id: String,
    pub message: String,
}
```

**关键属性：**
- `pub message: String` - 错误消息（非可选，必须提供）
- 相比 `ClosedNotification`，错误通知的消息是必填字段

### 2. 服务器通知注册

**文件路径：** `codex-rs/app-server-protocol/src/protocol/common.rs:927-928`

```rust
server_notification_definitions! {
    // ...
    #[experimental("thread/realtime/error")]
    ThreadRealtimeError => "thread/realtime/error" (v2::ThreadRealtimeErrorNotification),
    // ...
}
```

**Wire 格式：**
```json
{
  "method": "thread/realtime/error",
  "params": {
    "threadId": "thread-uuid",
    "message": "upstream boom"
  }
}
```

### 3. 服务器端发送逻辑

**文件路径：** `codex-rs/app-server/src/bespoke_event_handling.rs`

实时对话事件处理模块在以下场景发送错误通知：
1. WebSocket 连接异常
2. 后端返回错误事件
3. 音频处理失败
4. 会话状态验证失败

```rust
// 从测试用例中看到的典型错误场景
// realtime_conversation.rs:183-187
let realtime_error =
    read_notification::<ThreadRealtimeErrorNotification>(&mut mcp, "thread/realtime/error")
        .await?;
assert_eq!(realtime_error.thread_id, output_audio.thread_id);
assert_eq!(realtime_error.message, "upstream boom");
```

### 4. TypeScript 类型定义

**文件路径：** `codex-rs/app-server-protocol/schema/typescript/v2/ThreadRealtimeErrorNotification.ts`

```typescript
/**
 * EXPERIMENTAL - emitted when thread realtime encounters an error.
 */
export type ThreadRealtimeErrorNotification = { 
  threadId: string, 
  message: string, 
};
```

## 关键代码路径与文件引用

### 协议定义
| 文件 | 位置 | 说明 |
|------|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 3794-3801 | Rust 结构体定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 927-928 | 通知注册 |

### 服务器实现
| 文件 | 位置 | 说明 |
|------|------|------|
| `codex-rs/app-server/src/bespoke_event_handling.rs` | - | 实时事件处理 |

### 生成的 Schema/类型
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/schema/json/v2/ThreadRealtimeErrorNotification.json` | JSON Schema（本文件） |
| `codex-rs/app-server-protocol/schema/typescript/v2/ThreadRealtimeErrorNotification.ts` | TypeScript 类型 |
| `codex-rs/app-server-protocol/schema/json/ServerNotification.json` | 合并的通知 Schema |

### 测试
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/realtime_conversation.rs` | 集成测试（183-187 行） |

## 依赖与外部交互

### 1. 上游依赖

```
ThreadRealtimeErrorNotification
  └── 实时对话子系统
       ├── WebSocket 连接
       ├── 后端实时服务 (OpenAI Realtime API)
       ├── 音频处理管道
       └── 会话状态管理
```

### 2. 下游消费者

```
ThreadRealtimeErrorNotification
  ├── VSCode Extension
  │    └── 显示错误提示，提供重试按钮
  ├── TUI Client
  │    └── 在状态栏显示错误，记录日志
  └── 其他客户端
       └── 根据错误类型决定后续操作
```

### 3. 错误处理流程

```
┌─────────────────────────────────────────────────────────────┐
│                     Realtime Session                        │
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │   Active    │───▶│    Error    │───▶│   Closed    │     │
│  │  (正常传输)  │    │  (错误通知)  │    │  (连接关闭)  │     │
│  └─────────────┘    └─────────────┘    └─────────────┘     │
│         │                  │                  │             │
│         │                  ▼                  │             │
│         │         ThreadRealtimeError         │             │
│         │              Notification           │             │
│         │                  │                  │             │
│         │                  ▼                  │             │
│         │         ┌─────────────┐             │             │
│         │         │  Client     │             │             │
│         │         │  显示错误    │             │             │
│         │         │  决定是否重试 │             │             │
│         │         └─────────────┘             │             │
│         │                                     │             │
│         └─────────────────────────────────────┘             │
│                    (或继续运行)                              │
└─────────────────────────────────────────────────────────────┘
```

### 4. 相关协议方法

| 方法/通知 | 方向 | 说明 |
|-----------|------|------|
| `thread/realtime/start` | Client → Server | 启动实时对话 |
| `thread/realtime/started` | Server → Client | 启动成功通知 |
| `thread/realtime/appendAudio` | Client → Server | 发送音频数据 |
| `thread/realtime/appendText` | Client → Server | 发送文本数据 |
| `thread/realtime/error` | Server → Client | 错误通知（本通知） |
| `thread/realtime/closed` | Server → Client | 关闭通知 |

## 风险、边界与改进建议

### 1. 已知风险

**风险 1：错误消息的非结构化**
- **描述**：`message` 是自由字符串，非错误码或结构化数据
- **影响**：
  - 客户端难以程序化地分类错误
  - 国际化困难（消息为英文）
  - 错误处理逻辑依赖字符串匹配
- **缓解**：当前依赖文档约定，建议未来添加错误码

**风险 2：缺少错误严重级别**
- **描述**：无法区分致命错误（必须关闭）和警告（可继续）
- **影响**：客户端可能过度反应或忽视重要错误
- **缓解**：需要结合 ClosedNotification 判断最终状态

**风险 3：实验性 API 的变更风险**
- **描述**：API 可能在未来版本中添加字段或改变结构
- **影响**：客户端需要适配 breaking changes
- **缓解**：客户端应忽略未知字段

### 2. 边界情况

| 场景 | 行为 |
|------|------|
| 连续多个错误 | 每个错误发送独立通知 |
| 错误后关闭 | 通常先发送 Error，再发送 Closed |
| 空消息字符串 | 技术上可能，但应避免 |
| 不存在的 thread_id | 通知仍发送，客户端验证 |

### 3. 改进建议

**建议 1：添加错误码**
```rust
pub struct ThreadRealtimeErrorNotification {
    pub thread_id: String,
    pub code: RealtimeErrorCode, // 新增：结构化错误码
    pub message: String,
}

pub enum RealtimeErrorCode {
    WebSocketError,
    AudioFormatError,
    SessionError,
    RateLimitError,
    AuthenticationError,
    // ...
}
```

**建议 2：添加严重级别**
```rust
pub struct ThreadRealtimeErrorNotification {
    pub thread_id: String,
    pub severity: ErrorSeverity, // 新增：Fatal, Warning, Info
    pub code: RealtimeErrorCode,
    pub message: String,
}
```

**建议 3：添加恢复建议**
```rust
pub struct ThreadRealtimeErrorNotification {
    pub thread_id: String,
    pub message: String,
    pub recoverable: bool,        // 是否可恢复
    pub suggested_action: Option<RealtimeErrorAction>, // 建议操作
}

pub enum RealtimeErrorAction {
    Retry,
    Restart,
    CheckNetwork,
    ContactSupport,
}
```

**建议 4：添加错误上下文**
```rust
pub struct ThreadRealtimeErrorNotification {
    pub thread_id: String,
    pub message: String,
    pub context: Option<ErrorContext>, // 错误发生时的上下文
}

pub struct ErrorContext {
    pub operation: String,      // 正在执行的操作
    pub elapsed_ms: u64,        // 会话已持续时间
    pub bytes_transferred: u64, // 已传输字节数
}
```

### 4. 测试缺口

| 缺口 | 优先级 | 说明 |
|------|--------|------|
| 各种错误码覆盖 | 高 | 验证所有错误场景的通知 |
| 错误恢复流程 | 高 | 验证错误后重试的正确性 |
| 多错误并发 | 中 | 验证快速连续错误的处理 |
| 错误消息国际化 | 低 | 验证多语言错误消息 |
