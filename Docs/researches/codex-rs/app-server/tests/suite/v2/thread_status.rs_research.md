# thread_status.rs 研究文档

## 场景与职责

本测试文件位于 `codex-rs/app-server/tests/suite/v2/thread_status.rs`，是 Codex App Server v2 API 的集成测试套件的一部分。其核心职责是验证 **Thread 状态变更通知机制 (`thread/status/changed`)** 的正确性，包括：

1. **运行时状态更新**：验证线程在执行 Turn 过程中会正确发送状态变更通知
2. **通知可选退出机制**：验证客户端可以通过 `optOutNotificationMethods` 在初始化时选择不接收特定通知

该测试确保客户端能够实时感知 Thread 的生命周期状态变化（Idle → Active → Idle/SystemError/NotLoaded），并支持灵活的订阅控制。

## 功能点目的

### 1. ThreadStatus 枚举定义

Thread 状态由 `codex_app_server_protocol::protocol::v2::ThreadStatus` 定义：

```rust
pub enum ThreadStatus {
    NotLoaded,    // 线程未加载到内存
    Idle,         // 线程空闲，等待输入
    SystemError,  // 系统错误状态
    Active {      // 线程活跃中
        active_flags: Vec<ThreadActiveFlag>,
    },
}

pub enum ThreadActiveFlag {
    WaitingOnApproval,   // 等待用户审批
    WaitingOnUserInput,  // 等待用户输入
}
```

### 2. ThreadStatusChangedNotification 通知

当 Thread 状态发生变化时，服务器会发送 `thread/status/changed` 通知：

```rust
pub struct ThreadStatusChangedNotification {
    pub thread_id: String,
    pub status: ThreadStatus,
}
```

### 3. 通知退出机制

客户端在初始化时可以通过 `InitializeCapabilities` 指定要退出的通知方法：

```rust
pub struct InitializeCapabilities {
    pub experimental_api: bool,
    pub opt_out_notification_methods: Option<Vec<String>>, // 如 ["thread/status/changed"]
}
```

## 具体技术实现

### 测试 1: `thread_status_changed_emits_runtime_updates`

**目的**: 验证 Turn 执行过程中会正确发送状态变更通知

**测试流程**:
1. 创建临时 CODEX_HOME 目录和 Mock 响应服务器
2. 初始化 MCP 进程并建立连接
3. 发送 `thread/start` 请求创建新 Thread
4. 发送 `turn/start` 请求启动一个 Turn
5. **轮询状态通知**: 在超时窗口内（10秒）持续读取消息流
   - 查找 `thread/status/changed` 通知
   - 验证状态转换: `Active` → `Idle`
6. 断言必须观察到 `Active` 状态和后续的 `Idle` 状态

**关键代码逻辑**:
```rust
let mut saw_active_running = false;
let mut saw_idle_after_turn = false;
// 轮询消息直到超时或收集到所需状态
while tokio::time::Instant::now() < deadline {
    let message = timeout(remaining, mcp.read_next_message()).await;
    match message {
        JSONRPCMessage::Notification(JSONRPCNotification { method, params }) 
            if method == "thread/status/changed" => {
            let notification: ThreadStatusChangedNotification = 
                serde_json::from_value(params)?;
            match notification.status {
                ThreadStatus::Active { .. } => saw_active_running = true,
                ThreadStatus::Idle if saw_active_running => saw_idle_after_turn = true,
                _ => {}
            }
        }
        _ => {}
    }
}
```

### 测试 2: `thread_status_changed_can_be_opted_out`

**目的**: 验证客户端可以退出接收 `thread/status/changed` 通知

**测试流程**:
1. 初始化 MCP 进程时传入 `opt_out_notification_methods`
2. 创建 Thread 并启动 Turn
3. 等待 `turn/completed` 通知
4. **验证**: 在 500ms 超时内不应收到 `thread/status/changed` 通知
5. 如果收到通知则测试失败

**关键代码逻辑**:
```rust
let message = timeout(DEFAULT_READ_TIMEOUT, mcp.initialize_with_capabilities(
    ClientInfo { ... },
    Some(InitializeCapabilities {
        experimental_api: true,
        opt_out_notification_methods: Some(vec!["thread/status/changed".to_string()]),
    }),
)).await?;

// 验证不会收到状态通知
let status_update = timeout(
    Duration::from_millis(500),
    mcp.read_stream_until_notification_message("thread/status/changed")
).await;
match status_update {
    Err(_) => {} // 预期行为：超时表示未收到通知
    Ok(Ok(notification)) => bail!("不应收到已退出的通知"),
}
```

## 关键代码路径与文件引用

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 3022-3043)
  - `ThreadStatus` 枚举定义
  - `ThreadActiveFlag` 枚举定义
  - `ThreadStatusChangedNotification` 结构体定义

### 测试支持库
- `codex-rs/app-server/tests/common/mcp_process.rs`
  - `McpProcess` 结构体：封装 MCP 进程管理
  - `initialize_with_capabilities()`：带能力的初始化
  - `read_next_message()` / `read_stream_until_notification_message()`：消息读取

- `codex-rs/app-server/tests/common/mock_model_server.rs`
  - `create_mock_responses_server_sequence()`：创建 Mock 响应服务器
  - `create_final_assistant_message_sse_response()`：生成 SSE 响应

### 相关测试
- `codex-rs/app-server/tests/suite/v2/thread_start.rs`：Thread 创建测试
- `codex-rs/app-server/tests/suite/v2/turn_start.rs`：Turn 启动测试

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|------|------|
| `tempfile::TempDir` | 创建临时 CODEX_HOME 目录 |
| `tokio::time::timeout` | 异步超时控制 |
| `wiremock::MockServer` | Mock OpenAI Responses API |
| `serde_json` | JSON 序列化/反序列化 |

### 协议交互流程
```
Client                                    Server
  |                                         |
  |-- initialize ------------------------->| 初始化连接
  |<-- initialize response -----------------| 确认初始化
  |-- thread/start ----------------------->| 创建 Thread
  |<-- thread/start response ---------------| 返回 Thread ID
  |<-- thread/started notification --------| Thread 已启动
  |-- turn/start ------------------------->| 启动 Turn
  |<-- turn/start response -----------------| 确认 Turn 启动
  |<-- thread/status/changed (Active) -----| 状态：活跃
  |<-- thread/status/changed (Idle) -------| 状态：空闲
  |<-- turn/completed notification --------| Turn 完成
```

## 风险、边界与改进建议

### 潜在风险
1. **竞态条件**: 测试依赖消息到达的时序，在慢速机器上可能因超时失败
2. **状态通知丢失**: 如果服务器实现有 bug，可能遗漏状态变更通知
3. **多线程干扰**: 多线程测试环境下，其他测试可能干扰消息流

### 边界情况
1. **快速完成的 Turn**: 如果 Turn 完成过快，可能观察不到 Active 状态
2. **错误状态**: 测试覆盖了 SystemError 和 NotLoaded 作为 Idle 的等效状态
3. **超时处理**: 使用 10 秒默认超时，对于慢速环境可能需要调整

### 改进建议
1. **增加状态转换完整性验证**: 当前只验证 Active → Idle，可增加更多状态路径
2. **并发测试**: 测试多个 Thread 同时运行时状态通知的正确性
3. **压力测试**: 高频状态变更场景下的通知可靠性
4. **文档化状态机**: 建议补充 Thread 状态机的完整文档

### 测试覆盖度
- ✅ 正常状态流转 (Idle → Active → Idle)
- ✅ 通知退出机制
- ⚠️ 错误状态 (SystemError) 的触发路径未直接测试
- ⚠️ 并发多 Thread 场景未覆盖
