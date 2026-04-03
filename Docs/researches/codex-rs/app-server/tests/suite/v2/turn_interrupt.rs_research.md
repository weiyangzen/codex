# turn_interrupt.rs 研究文档

## 场景与职责

`turn_interrupt.rs` 是 Codex App Server V2 API 的集成测试文件，专注于测试 **Turn Interrupt（回合中断）** 功能。该功能允许客户端在对话回合进行中强制中止执行，用于响应用户的取消操作或超时处理。

### 核心测试场景

1. **中止运行中回合**：验证可以中断正在执行 shell 命令的回合
2. **解决待处理审批**：验证中断操作会自动处理（拒绝）待执行的命令审批请求

### 平台限制

```rust
#![cfg(unix)]
```

该测试文件仅在 Unix 平台（Linux/macOS）上运行，因为涉及 shell 命令执行和进程信号处理。

---

## 功能点目的

### Turn Interrupt 功能

Turn Interrupt 是 Codex 交互控制的核心机制：

- **用户取消**：当用户点击"停止"按钮时，中断当前正在执行的 AI 回合
- **超时处理**：当回合执行时间超过限制时，自动中断
- **资源清理**：中断后正确清理正在执行的 shell 进程和待处理请求

### 关键业务规则

1. 中断请求需要提供 `thread_id` 和 `turn_id` 进行精确定位
2. 中断后回合状态变为 `TurnStatus::Interrupted`
3. 中断会自动拒绝所有待处理的命令审批请求
4. 中断会发送 `turn/completed` 通知，状态为 `Interrupted`
5. 待处理请求的解决通知 `serverRequest/resolved` 会在中断后发送

---

## 具体技术实现

### 数据结构

#### TurnInterruptParams
```rust
pub struct TurnInterruptParams {
    pub thread_id: String,
    pub turn_id: String,
}
```

#### TurnInterruptResponse
```rust
pub struct TurnInterruptResponse {
    // 空响应，成功即表示中断已发起
}
```

#### TurnCompletedNotification
```rust
pub struct TurnCompletedNotification {
    pub thread_id: String,
    pub turn: Turn,
}

pub struct Turn {
    pub id: String,
    pub status: TurnStatus,
    // ...
}
```

#### TurnStatus
```rust
pub enum TurnStatus {
    InProgress,
    Interrupted,
    Completed,
    // ...
}
```

### 测试用例 1: 中止运行中回合

```rust
async fn turn_interrupt_aborts_running_turn() -> Result<()>
```

**测试流程**:
```
1. 创建临时目录结构 (codex_home, working_directory)
2. 创建 Mock Server，配置返回长耗时 shell 命令
   └── create_shell_command_sse_response(sleep 10s)
3. 启动 MCP 进程并初始化
4. 创建线程 (thread/start)
5. 启动回合 (turn/start)，触发 shell 命令
6. 等待 1 秒，确保命令已开始执行
7. 发送 turn/interrupt 请求
8. 验证中断响应成功
9. 验证收到 turn/completed 通知
10. 验证 turn.status == TurnStatus::Interrupted
```

**关键验证点**:
- 中断响应成功返回（空响应体）
- `turn/completed` 通知正确发送
- 回合状态正确设置为 `Interrupted`

### 测试用例 2: 解决待处理审批请求

```rust
async fn turn_interrupt_resolves_pending_command_approval_request() -> Result<()>
```

**测试流程**:
```
1. 创建临时目录和 Mock Server
2. 配置 approval_policy = "untrusted"（需要审批）
3. 创建线程
4. 启动回合，触发需要审批的 shell 命令
5. 等待收到 CommandExecutionRequestApproval 请求
6. 验证审批请求参数（item_id, thread_id, turn_id）
7. 发送 turn/interrupt 请求
8. 验证中断响应成功
9. 验证收到 serverRequest/resolved 通知
10. 验证 resolved 通知包含正确的 request_id 和 thread_id
11. 验证收到 turn/completed 通知，状态为 Interrupted
```

**关键验证点**:
- 中断前正确收到审批请求
- 中断后自动发送 `serverRequest/resolved` 通知
- 解决通知包含正确的 `request_id` 关联
- 回合最终状态为 `Interrupted`

---

## 关键代码路径与文件引用

### 测试文件
- **位置**: `codex-rs/app-server/tests/suite/v2/turn_interrupt.rs`
- **行数**: 266 行
- **平台限制**: `#[cfg(unix)]`

### 协议定义
- **位置**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
- **相关结构**:
  - `TurnInterruptParams` (行 3962-3965)
  - `TurnInterruptResponse` (行 3967-3970)
  - `TurnCompletedNotification` (行 3940-3943)
  - `TurnStatus` (行 3920-3938)

### 服务器请求类型
- **位置**: `codex-rs/app-server-protocol/src/protocol/common.rs`
- **相关类型**:
  - `ServerRequest::CommandExecutionRequestApproval`
  - `ServerRequestResolvedNotification`

### 测试支持库
- **位置**: `codex-rs/app-server/tests/common/mcp_process.rs`
- **方法**: `send_turn_interrupt_request` (行 575-582)
- **方法**: `interrupt_turn_and_wait_for_aborted` (行 632-678)

### 核心实现
- **位置**: `codex-rs/core/src/agent/` (Agent 控制逻辑)
- **相关**: 回合状态机、命令执行管理

---

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `tempfile::TempDir` | 创建临时测试目录 |
| `tokio::time::timeout` | 测试超时控制 |
| `tokio::time::sleep` | 等待命令启动 |

### 内部模块依赖

```
turn_interrupt.rs
├── app_test_support::McpProcess
├── app_test_support::create_mock_responses_server_sequence
├── app_test_support::create_shell_command_sse_response
├── app_test_support::to_response
├── codex_app_server_protocol::TurnInterruptParams
├── codex_app_server_protocol::TurnInterruptResponse
├── codex_app_server_protocol::TurnCompletedNotification
├── codex_app_server_protocol::TurnStatus
├── codex_app_server_protocol::ServerRequest
├── codex_app_server_protocol::ServerRequestResolvedNotification
└── tempfile::TempDir
```

### 平台适配

```rust
#[cfg(target_os = "windows")]
let shell_command = vec![
    "powershell".to_string(),
    "-Command".to_string(),
    "Start-Sleep -Seconds 10".to_string(),
];
#[cfg(not(target_os = "windows"))]
let shell_command = vec!["sleep".to_string(), "10".to_string()];
```

虽然代码包含 Windows 适配，但整个文件被 `#![cfg(unix)]` 限制，只在 Unix 运行。

---

## 风险、边界与改进建议

### 潜在风险

1. **竞态条件**
   - 测试使用 `tokio::time::sleep(Duration::from_secs(1))` 等待命令启动
   - 在慢速 CI 环境，1 秒可能不足以保证命令已开始
   - **缓解**: 使用 `wait_for_command_execution_item_started` 等事件驱动等待

2. **平台限制**
   - 测试仅在 Unix 运行，Windows 行为未覆盖
   - Windows 的进程中断机制与 Unix 不同
   - **缓解**: 考虑为 Windows 添加特定测试或文档说明

3. **超时设置**
   - `DEFAULT_READ_TIMEOUT = 10 秒` 可能不足以覆盖慢速环境
   - **缓解**: 考虑使用环境变量配置超时

### 边界情况

1. **快速完成的命令**: 测试未覆盖命令在收到中断前已完成的情况
2. **嵌套命令**: 测试未覆盖子进程/嵌套 shell 的中断
3. **网络延迟**: 测试未模拟高延迟网络下的中断行为
4. **多回合并发**: 测试未覆盖同时中断多个回合的场景

### 改进建议

1. **增强可靠性**
   ```rust
   // 建议：使用事件等待替代固定睡眠
   let _ = wait_for_command_execution_item_started(&mut mcp).await?;
   // 替代：tokio::time::sleep(Duration::from_secs(1)).await;
   ```

2. **增加边界测试**
   ```rust
   // 建议添加：中断已完成的回合
   async fn turn_interrupt_completed_turn_returns_error() -> Result<()>
   
   // 建议添加：中断不存在的回合
   async fn turn_interrupt_nonexistent_turn_returns_error() -> Result<()>
   
   // 建议添加：并发中断同一回合
   async fn concurrent_interrupt_is_idempotent() -> Result<()>
   ```

3. **增加性能测试**
   ```rust
   // 建议添加：中断响应时间测试
   async fn turn_interrupt_response_time_under_threshold() -> Result<()>
   ```

4. **Windows 支持**
   - 移除 `#![cfg(unix)]` 限制
   - 添加 Windows 特定的进程中断测试
   - 或使用条件编译分别实现

### 相关测试文件

- `turn_steer.rs`: 测试回合引导功能
- `turn_start.rs`: 测试回合启动功能
- `thread_unsubscribe.rs`: 包含回合中断相关测试（取消订阅时中断）

### 辅助函数复用

`interrupt_turn_and_wait_for_aborted` 在 `mcp_process.rs` 中定义，被多个测试文件复用：
- `turn_steer.rs`
- `turn_start_zsh_fork.rs`
- `thread_unsubscribe.rs`

该辅助函数封装了中断请求发送和终端通知等待的完整流程，确保测试清理的一致性。
