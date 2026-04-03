# ThreadStatusChangedNotification.json 研究文档

## 场景与职责

`ThreadStatusChangedNotification` 是 Codex App-Server Protocol v2 中定义的服务器向客户端发送的通知类型，用于实时告知客户端某个 Thread（会话线程）的状态发生变化。这是 Thread 生命周期管理中的核心通知机制，让客户端能够及时响应线程状态变化并更新 UI。

典型使用场景：
- 当 Thread 从 `idle` 变为 `active`（开始处理用户输入）
- 当 Thread 进入等待状态（如等待用户批准、等待用户输入）
- 当 Thread 发生系统错误时通知客户端
- 当 Thread 从 `notLoaded` 状态变为其他状态

## 功能点目的

该通知的主要目的是：
1. **状态同步**：确保客户端始终掌握 Thread 的最新运行状态
2. **UI 反馈**：驱动客户端显示加载状态、等待批准提示、错误提示等
3. **流程控制**：客户端根据状态变化决定下一步操作（如显示批准对话框）

### ThreadStatus 状态定义

| 状态类型 | 描述 |
|---------|------|
| `notLoaded` | Thread 尚未加载到内存 |
| `idle` | Thread 空闲，等待用户输入 |
| `systemError` | Thread 发生系统级错误 |
| `active` | Thread 正在处理中，可能带有 `activeFlags` 标志 |

### ThreadActiveFlag 标志定义

| 标志 | 描述 |
|------|------|
| `waitingOnApproval` | 正在等待用户批准某个操作 |
| `waitingOnUserInput` | 正在等待用户输入 |

## 具体技术实现

### JSON Schema 结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "properties": {
    "status": { "$ref": "#/definitions/ThreadStatus" },
    "threadId": { "type": "string" }
  },
  "required": ["status", "threadId"]
}
```

### Rust 实现

位于 `codex-rs/app-server-protocol/src/protocol/v2.rs`：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadStatusChangedNotification {
    pub thread_id: String,
    pub status: ThreadStatus,
}
```

### ThreadStatus 枚举定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(tag = "type", rename_all = "camelCase")]
#[ts(tag = "type")]
#[ts(export_to = "v2/")]
pub enum ThreadStatus {
    NotLoaded,
    Idle,
    SystemError,
    #[serde(rename_all = "camelCase")]
    #[ts(rename_all = "camelCase")]
    Active {
        active_flags: Vec<ThreadActiveFlag>,
    },
}
```

### 服务端注册

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中注册为服务器通知：

```rust
server_notification_definitions! {
    ThreadStatusChanged => "thread/status/changed" (v2::ThreadStatusChangedNotification),
    // ...
}
```

## 关键代码路径与文件引用

### 核心定义文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/schema/json/v2/ThreadStatusChangedNotification.json` | JSON Schema 定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构体定义（行 4620-4626） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 服务器通知注册（行 878） |
| `codex-rs/app-server-protocol/schema/typescript/v2/ThreadStatusChangedNotification.ts` | TypeScript 类型定义 |

### 服务端发送代码

位于 `codex-rs/app-server/src/thread_status.rs`：
- `broadcast_thread_status_update()` 函数负责广播状态变更通知
- 在 Thread 状态变化时通过 WebSocket 发送给所有订阅的客户端

### 测试文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/tests/suite/v2/thread_status.rs` | Thread 状态相关测试 |
| `codex-rs/app-server/tests/suite/v2/thread_start.rs` | Thread 启动测试（包含状态验证） |
| `codex-rs/app-server/tests/suite/v2/thread_fork.rs` | Thread Fork 测试 |

## 依赖与外部交互

### 上游依赖

1. **codex_protocol**: 核心协议类型定义
2. **schemars**: JSON Schema 生成
3. **ts-rs**: TypeScript 类型生成
4. **serde**: 序列化/反序列化

### 下游消费者

1. **tui_app_server**: TUI 应用服务器适配器消费此通知更新界面状态
2. **VSCode 扩展**: 通过 WebSocket 接收状态更新
3. **CLI 工具**: 实时显示 Thread 状态

### 相关通知类型

- `ThreadStartedNotification`: Thread 创建时发送
- `ThreadArchivedNotification`: Thread 归档时发送
- `ThreadUnarchivedNotification`: Thread 解除归档时发送
- `ThreadClosedNotification`: Thread 关闭时发送

## 风险、边界与改进建议

### 潜在风险

1. **状态竞争**：如果客户端在网络延迟期间发送多个请求，可能收到乱序的状态通知
2. **状态丢失**：WebSocket 重连期间可能丢失状态变更通知
3. **循环通知**：服务端需要确保不会无限循环发送相同的状态通知

### 边界情况

1. **并发状态变更**：多个操作同时改变 Thread 状态时，通知顺序需要保证
2. **客户端离线**：离线客户端重连后需要通过 `thread/read` 获取当前状态
3. **空 activeFlags**：`active` 状态必须包含至少一个 `activeFlags`，否则状态不明确

### 改进建议

1. **添加序列号**：为通知添加单调递增的序列号，帮助客户端检测丢失的通知
2. **状态快照**：在通知中添加完整的状态快照，而不仅是状态类型
3. **批量通知**：考虑支持批量状态变更通知，减少网络开销
4. **心跳机制**：添加定期心跳通知，帮助客户端检测连接健康状态

### 版本兼容性

- 当前为 v2 API，遵循 camelCase 命名规范
- 与 v1 API 不兼容，v1 使用不同的状态模型
- TypeScript 类型通过 `ts-rs` 自动生成，保持与 Rust 定义同步
