# command_exec.rs 研究文档

## 场景与职责

`command_exec.rs` 是 Codex App Server v2 API 的集成测试文件，专注于测试**命令执行(Command Execution)**功能。该文件全面验证了 `command/exec` RPC 方法及其相关操作：

1. **基础命令执行** - 同步/异步执行 shell 命令
2. **进程生命周期管理** - 启动、终止、等待进程完成
3. **流式 I/O** - stdout/stderr 实时流式传输
4. **PTY/TTY 支持** - 伪终端模式执行
5. **交互式命令** - 支持 stdin 写入和终端大小调整
6. **连接隔离** - 进程 ID 在连接范围内的隔离性

## 功能点目的

### 1. 命令执行模式

| 模式 | 描述 | 使用场景 |
|-----|------|---------|
| **缓冲模式** | 等待命令完成，返回完整输出 | 简单命令，输出量小 |
| **流式模式** | 实时推送 stdout/stderr | 长时间运行命令，需要实时反馈 |
| **PTY 模式** | 分配伪终端 | 需要终端特性的命令（如交互式 shell） |

### 2. 进程管理功能

- **process_id**: 客户端提供的连接范围内唯一标识符
- **terminate**: 强制终止运行中的进程
- **write**: 向进程 stdin 写入数据
- **resize**: 调整 PTY 终端大小

### 3. 安全与限制

- **输出上限** (`output_bytes_cap`): 限制 stdout/stderr 捕获大小
- **超时控制** (`timeout_ms` / `disable_timeout`): 防止无限等待
- **沙箱策略** (`sandbox_policy`): 执行环境隔离
- **环境变量**: 支持覆盖和继承服务器环境

## 具体技术实现

### 关键数据结构

```rust
// 命令执行请求参数
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CommandExecParams {
    pub command: Vec<String>,              // 命令参数向量
    #[ts(optional = nullable)]
    pub process_id: Option<String>,        // 客户端提供的进程 ID
    #[serde(default)]
    pub tty: bool,                         // 启用 PTY 模式
    #[serde(default)]
    pub stream_stdin: bool,                // 允许 stdin 流式写入
    #[serde(default)]
    pub stream_stdout_stderr: bool,        // 流式输出
    #[ts(type = "number | null")]
    #[ts(optional = nullable)]
    pub output_bytes_cap: Option<usize>,   // 输出大小限制
    #[serde(default)]
    pub disable_output_cap: bool,          // 禁用输出限制
    #[serde(default)]
    pub disable_timeout: bool,             // 禁用超时
    #[ts(type = "number | null")]
    #[ts(optional = nullable)]
    pub timeout_ms: Option<i64>,           // 超时毫秒数
    #[ts(optional = nullable)]
    pub cwd: Option<PathBuf>,              // 工作目录
    #[ts(optional = nullable)]
    pub env: Option<HashMap<String, Option<String>>>, // 环境变量
    #[ts(optional = nullable)]
    pub size: Option<CommandExecTerminalSize>, // 初始终端大小
    #[ts(optional = nullable)]
    pub sandbox_policy: Option<SandboxPolicy>, // 沙箱策略
}

// 命令执行响应
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CommandExecResponse {
    pub exit_code: i32,                    // 进程退出码
    pub stdout: String,                    // 缓冲的 stdout（流式时为空）
    pub stderr: String,                    // 缓冲的 stderr（流式时为空）
}

// 输出增量通知
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CommandExecOutputDeltaNotification {
    pub process_id: String,
    pub stream: CommandExecOutputStream,   // Stdout | Stderr
    pub delta_base64: String,              // Base64 编码的输出块
    pub cap_reached: bool,                 // 是否达到输出上限
}

// 终端大小
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CommandExecTerminalSize {
    pub rows: u16,                         // 行数
    pub cols: u16,                         // 列数
}

// 写入参数
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CommandExecWriteParams {
    pub process_id: String,
    #[ts(optional = nullable)]
    pub delta_base64: Option<String>,      // 要写入的 base64 数据
    #[serde(default)]
    pub close_stdin: bool,                 // 是否关闭 stdin
}

// 终止参数
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CommandExecTerminateParams {
    pub process_id: String,
}

// 调整大小参数
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CommandExecResizeParams {
    pub process_id: String,
    pub size: CommandExecTerminalSize,
}
```

### 测试用例详解

| 测试用例 | 目的 | 关键技术点 |
|---------|------|-----------|
| `command_exec_without_streams_can_be_terminated` | 验证终止功能 | 启动长睡眠进程，终止后验证退出码 |
| `command_exec_without_process_id_keeps_buffered_compatibility` | 向后兼容 | 无 process_id 时缓冲模式工作 |
| `command_exec_env_overrides_merge_with_server_environment_and_support_unset` | 环境变量处理 | 覆盖、继承、取消设置（`null`） |
| `command_exec_rejects_disable_timeout_with_timeout_ms` | 参数互斥验证 | `disable_timeout` 和 `timeout_ms` 不能同时设置 |
| `command_exec_rejects_disable_output_cap_with_output_bytes_cap` | 参数互斥验证 | `disable_output_cap` 和 `output_bytes_cap` 不能同时设置 |
| `command_exec_rejects_negative_timeout_ms` | 输入验证 | 拒绝负超时值 |
| `command_exec_without_process_id_rejects_streaming` | 安全验证 | 流式模式需要 `process_id` |
| `command_exec_non_streaming_respects_output_cap` | 输出限制 | 缓冲模式下裁剪输出 |
| `command_exec_streaming_does_not_buffer_output` | 流式行为 | 流式模式下不缓冲，支持实时终止 |
| `command_exec_pipe_streams_output_and_accepts_write` | 交互式 I/O | stdin 写入，stdout/stderr 流式读取 |
| `command_exec_tty_implies_streaming_and_reports_pty_output` | PTY 模式 | TTY 自动启用流式，支持交互 |
| `command_exec_tty_supports_initial_size_and_resize` | 终端控制 | 初始大小设置和动态调整 |
| `command_exec_process_ids_are_connection_scoped_and_disconnect_terminates_process` | 连接隔离 | WebSocket 连接间进程隔离，断开连接自动终止 |

### 关键测试辅助函数

```rust
// 读取输出增量通知
async fn read_command_exec_delta(
    mcp: &mut McpProcess,
) -> Result<CommandExecOutputDeltaNotification> {
    let notification = mcp
        .read_stream_until_notification_message("command/exec/outputDelta")
        .await?;
    decode_delta_notification(notification)
}

// 等待特定输出内容
async fn read_command_exec_output_until_contains(
    mcp: &mut McpProcess,
    process_id: &str,
    stream: CommandExecOutputStream,
    expected: &str,
) -> Result<String>

// WebSocket 版本（用于连接隔离测试）
async fn read_command_exec_delta_ws(
    stream: &mut WsClient,
) -> Result<CommandExecOutputDeltaNotification>

// 解码通知
fn decode_delta_notification(
    notification: JSONRPCNotification,
) -> Result<CommandExecOutputDeltaNotification>

// 进程标记检测（用于验证进程存在/退出）
async fn wait_for_process_marker(marker: &str, should_exist: bool) -> Result<()>
fn process_with_marker_exists(marker: &str) -> Result<bool>
```

### 连接隔离测试详解

```rust
#[tokio::test]
async fn command_exec_process_ids_are_connection_scoped_and_disconnect_terminates_process()
-> Result<()> {
    // 1. 启动 WebSocket 服务器
    let (mut process, bind_addr) = spawn_websocket_server(codex_home.path()).await?;

    // 2. 建立两个 WebSocket 连接
    let mut ws1 = connect_websocket(bind_addr).await?;
    let mut ws2 = connect_websocket(bind_addr).await?;

    // 3. 两个连接都初始化
    send_initialize_request(&mut ws1, 1, "ws_client_one").await?;
    send_initialize_request(&mut ws2, 2, "ws_client_two").await?;

    // 4. 在 ws1 上启动进程
    send_request(&mut ws1, "command/exec", 101, Some(json!({
        "command": ["python3", "-c", "...", marker],
        "processId": "shared-process",
        "streamStdoutStderr": true,
    }))).await?;

    // 5. 验证进程已启动
    let delta = read_command_exec_delta_ws(&mut ws1).await?;
    wait_for_process_marker(&marker, true).await?;

    // 6. 在 ws2 上尝试终止（应该失败，进程不在此连接）
    send_request(&mut ws2, "command/exec/terminate", 102, ...).await?;
    let terminate_error = ...; // 验证错误："no active command/exec for process id"

    // 7. 断开 ws1
    ws1.close(None).await?;

    // 8. 验证进程已终止
    wait_for_process_marker(&marker, false).await?;
}
```

## 关键代码路径与文件引用

### 测试文件
- `/codex-rs/app-server/tests/suite/v2/command_exec.rs` - 本测试文件
- `/codex-rs/app-server/tests/suite/v2/connection_handling_websocket.rs` - WebSocket 连接工具

### 协议定义
- `/codex-rs/app-server-protocol/src/protocol/v2.rs`:
  - `CommandExecParams` (行 2286-2360)
  - `CommandExecResponse` (行 2362-2377)
  - `CommandExecWriteParams` (行 2379-2394)
  - `CommandExecTerminateParams` (行 2402-2410)
  - `CommandExecResizeParams` (行 2418-2428)
  - `CommandExecOutputStream` (行 2436-2445)
  - `CommandExecTerminalSize` (行 2269-2278)

### 测试支持
- `/codex-rs/app-server/tests/common/mcp_process.rs`:
  - `send_command_exec_request` (行 539-546)
  - `send_command_exec_write_request` (行 548-555)
  - `send_command_exec_resize_request` (行 557-564)
  - `send_command_exec_terminate_request` (行 566-573)

### WebSocket 工具
- `/codex-rs/app-server/tests/suite/v2/connection_handling_websocket.rs`:
  - `spawn_websocket_server`
  - `connect_websocket`
  - `send_request`, `read_jsonrpc_message`

## 依赖与外部交互

### 外部依赖
1. **Mock Responses 服务器** - 提供基础 OpenAI API 模拟
2. **Codex App Server** - 被测服务
3. **系统 shell** - `/bin/sh` 或 `cmd.exe`
4. **Python 3** - 用于长时间运行进程测试

### 协议依赖
- **JSON-RPC 2.0** - 请求/响应
- **WebSocket** - 连接隔离测试
- **Server-Sent Events** - 流式输出通知

### 关键系统调用
```rust
// 进程管理
std::process::Command::new("ps").args(["-axo", "command"])

// 用于验证进程存在/退出
ps -axo command | grep marker
```

## 风险、边界与改进建议

### 已知风险

1. **平台依赖**
   - 测试使用 `/bin/sh` 和 `python3`，在 Windows 上可能失败
   - `process_with_marker_exists` 使用 `ps` 命令
   - 建议：使用 `cfg!` 条件编译处理平台差异

2. **时序敏感**
   - `wait_for_process_marker` 使用轮询（50ms 间隔）
   - 在慢速系统可能超时
   - 建议：增加重试次数或自适应超时

3. **资源泄漏**
   - 测试启动的进程如果未正确终止可能泄漏
   - `kill_on_drop` 是尽力而为，不保证清理
   - 建议：添加测试后清理验证

### 边界情况

1. **大输出处理**
   - 测试 `output_bytes_cap=5` 的小限制
   - 未测试大输出（MB/GB 级别）的性能

2. **并发执行**
   - 未测试同一连接上多个并发命令
   - 未测试大量快速启动/终止的压力场景

3. **错误处理**
   - 未测试命令不存在的情况
   - 未测试权限拒绝的情况
   - 未测试沙箱违规的情况

### 改进建议

1. **平台兼容性**
   ```rust
   let shell = if cfg!(windows) { "cmd.exe" } else { "/bin/sh" };
   let args = if cfg!(windows) { vec!["/c", ...] } else { vec!["-lc", ...] };
   ```

2. **测试覆盖增强**
   ```rust
   // 建议添加：命令不存在
   #[tokio::test]
   async fn command_exec_returns_error_for_missing_command() { ... }

   // 建议添加：并发执行
   #[tokio::test]
   async fn command_exec_supports_multiple_concurrent_processes() { ... }

   // 建议添加：超大输出
   #[tokio::test]
   async fn command_exec_handles_large_output() { ... }
   ```

3. **性能测试**
   - 添加吞吐量基准测试
   - 测试大量小命令的延迟
   - 测试长时间运行的稳定性

4. **安全测试**
   - 验证沙箱策略强制执行
   - 测试危险命令的隔离
   - 验证进程无法逃逸

### 架构考虑

1. **连接隔离实现**
   - 进程 ID 仅在连接范围内有效
   - 断开连接自动清理进程
   - 防止跨连接进程操作

2. **流式 vs 缓冲权衡**
   - 流式模式：实时反馈，无输出上限
   - 缓冲模式：简单，有内存限制保护
   - 混合模式：流式 + 输出上限

3. **PTY 复杂性**
   - 自动启用流式
   - 需要终端大小管理
   - 与纯管道模式行为不同
