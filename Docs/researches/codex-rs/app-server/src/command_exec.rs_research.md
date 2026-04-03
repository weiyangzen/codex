# command_exec.rs 深度研究文档

## 文件基本信息
- **文件路径**: `codex-rs/app-server/src/command_exec.rs`
- **代码行数**: 1016 行（含测试）
- **主要功能**: 命令执行管理器，负责在 App Server 中执行 shell 命令，支持 PTY/TTY 交互式会话

---

## 一、场景与职责

### 1.1 核心场景
`command_exec.rs` 是 Codex App Server 的命令执行核心模块，处理以下场景：

1. **非交互式命令执行**: 一次性执行命令，收集 stdout/stderr 输出并返回
2. **交互式 TTY 会话**: 支持完整的终端仿真（PTY），允许实时输入输出
3. **流式命令执行**: 支持 stdin 流式输入和 stdout/stderr 流式输出
4. **Windows 沙箱执行**: 特殊处理 Windows 受限令牌沙箱的执行路径

### 1.2 架构职责
- **进程生命周期管理**: 创建、控制、终止进程
- **会话状态追踪**: 维护每个连接/进程 ID 的活跃会话映射
- **流控制**: 处理 stdin 写入、终端 resize、强制终止
- **超时处理**: 支持默认超时、自定义超时、取消令牌三种过期策略
- **连接清理**: 连接断开时自动终止关联进程

---

## 二、功能点目的

### 2.1 主要功能点

| 功能点 | 目的 | 对应 RPC 方法 |
|--------|------|---------------|
| `start` | 启动命令执行 | `command/exec` |
| `write` | 向进程 stdin 写入数据 | `command/exec/write` |
| `resize` | 调整 PTY 终端大小 | `command/exec/resize` |
| `terminate` | 强制终止进程 | `command/exec/terminate` |
| `connection_closed` | 连接断开清理 | 内部事件 |

### 2.2 执行模式矩阵

```
                    | 无 TTY | TTY 模式
--------------------|--------|----------
无流式              |   ✓    |    ✓
仅 stdin 流式       |   ✓    |    ✓ (TTY 隐含 stdin 流式)
仅 stdout/stderr 流式 | ✓  |    ✓
全流式              |   ✓    |    ✓
```

### 2.3 Windows 沙箱特殊处理
Windows 受限令牌沙箱（`WindowsRestrictedToken`）不支持：
- TTY/PTY 模式
- 流式 stdin/stdout/stderr
- 自定义 `output_bytes_cap`
- 运行时控制（write/resize/terminate）

此类执行走独立的 `execute_env` 路径，通过 `CommandExecSession::UnsupportedWindowsSandbox` 标记。

---

## 三、具体技术实现

### 3.1 核心数据结构

```rust
/// 命令执行管理器
pub(crate) struct CommandExecManager {
    /// 活跃会话映射：(ConnectionId, ProcessId) -> Session
    sessions: Arc<Mutex<HashMap<ConnectionProcessId, CommandExecSession>>>,
    /// 自增进程 ID 生成器
    next_generated_process_id: Arc<AtomicI64>,
}

/// 复合键：连接 ID + 进程 ID
#[derive(Clone, Debug, Eq, Hash, PartialEq)]
struct ConnectionProcessId {
    connection_id: ConnectionId,
    process_id: InternalProcessId,
}

/// 进程 ID 类型
enum InternalProcessId {
    Generated(i64),      // 服务器自动生成
    Client(String),      // 客户端指定（流式模式必需）
}

/// 会话状态
enum CommandExecSession {
    Active { control_tx: mpsc::Sender<CommandControlRequest> },
    UnsupportedWindowsSandbox,  // Windows 沙箱标记
}

/// 控制命令
enum CommandControl {
    Write { delta: Vec<u8>, close_stdin: bool },
    Resize { size: TerminalSize },
    Terminate,
}
```

### 3.2 启动流程 (`start` 方法)

```
1. 参数验证
   ├── 流式模式必须提供 client process_id
   ├── Windows 沙箱不支持流式
   └── 检查重复 process_id

2. 进程 ID 分配
   └── 客户端提供 -> InternalProcessId::Client
       未提供     -> InternalProcessId::Generated(自增)

3. 会话创建
   ├── Windows 沙箱: 直接 spawn 执行，无会话控制
   └── 普通模式:
       ├── 创建 control channel (mpsc)
       ├── 根据模式 spawn 进程:
       │   ├── TTY: spawn_pty_process()
       │   ├── 流式 stdin: spawn_pipe_process()
       │   └── 无 stdin: spawn_pipe_process_no_stdin()
       └── spawn run_command() 任务

4. 会话注册
   └── 插入 sessions HashMap
```

### 3.3 运行时控制流程 (`run_command`)

```rust
async fn run_command(params: RunCommandParams) {
    // 1. 设置超时/取消监听器
    let expiration = match expiration { ... };
    
    // 2. 启动 stdout/stderr 输出处理任务
    let stdout_handle = spawn_process_output(...);
    let stderr_handle = spawn_process_output(...);
    
    // 3. 主事件循环 (tokio::select!)
    loop {
        select! {
            // 控制命令处理
            control = control_rx.recv() => {
                match control {
                    Write => handle_process_write(),
                    Resize => handle_process_resize(),
                    Terminate => session.request_terminate(),
                }
            }
            // 超时处理
            _ = &mut expiration => {
                timed_out = true;
                session.request_terminate();
            }
            // 进程退出
            exit = &mut exit_rx => break exit_code,
        }
    }
    
    // 4. 等待输出 drain 超时
    // 5. 收集 stdout/stderr 结果
    // 6. 发送 CommandExecResponse
}
```

### 3.4 输出处理 (`spawn_process_output`)

```rust
fn spawn_process_output(params: SpawnProcessOutputParams) -> JoinHandle<String> {
    tokio::spawn(async move {
        let mut buffer = Vec::new();
        let mut observed_bytes = 0;
        
        loop {
            select! {
                chunk = output_rx.recv() => {
                    // 应用 output_bytes_cap 限制
                    let capped = apply_cap(chunk, output_bytes_cap);
                    
                    if stream_output {
                        // 流式：立即发送 notification
                        send_notification(delta_base64, cap_reached);
                    } else {
                        // 非流式：缓冲到内存
                        buffer.extend(capped);
                    }
                }
                _ = stdio_timeout_rx => break,  // IO_DRAIN_TIMEOUT_MS
            }
        }
        
        bytes_to_string_smart(&buffer)  // 智能编码检测
    })
}
```

### 3.5 关键常量

```rust
const EXEC_TIMEOUT_EXIT_CODE: i32 = 124;  // 超时退出码
const IO_DRAIN_TIMEOUT_MS: u64 = 500;     // 输出 drain 超时（来自 codex_core::exec）
const DEFAULT_OUTPUT_BYTES_CAP: usize = 1024 * 1024;  // 1MB 输出上限
```

---

## 四、关键代码路径与文件引用

### 4.1 内部依赖

| 模块 | 路径 | 用途 |
|------|------|------|
| `error_code` | `src/error_code.rs` | JSON-RPC 错误码定义 |
| `outgoing_message` | `src/outgoing_message.rs` | 消息发送、ConnectionId |
| `codex_utils_pty` | `utils/pty/src/` | PTY/进程 spawn |

### 4.2 外部依赖

| Crate | 模块 | 用途 |
|-------|------|------|
| `codex_core` | `exec` | 超时常量、ExecExpiration |
| `codex_core` | `sandboxing` | ExecRequest、execute_env |
| `codex_app_server_protocol` | protocol | RPC 类型定义 |

### 4.3 关键代码路径

```
启动命令:
  MessageProcessor::process_request
  └── command/exec
      └── CommandExecManager::start
          ├── spawn_pty_process (TTY)
          ├── spawn_pipe_process (流式 stdin)
          ├── spawn_pipe_process_no_stdin (无 stdin)
          └── tokio::spawn(run_command)

控制命令:
  command/exec/write    -> send_control(CommandControl::Write)
  command/exec/resize   -> send_control(CommandControl::Resize)
  command/exec/terminate -> send_control(CommandControl::Terminate)

连接断开:
  TransportEvent::ConnectionClosed
  └── MessageProcessor::connection_closed
      └── CommandExecManager::connection_closed
          └── send_control(Terminate) 到所有关联进程
```

---

## 五、依赖与外部交互

### 5.1 协议类型 (codex_app_server_protocol)

```rust
// 请求/响应类型
CommandExecResponse
CommandExecWriteParams / CommandExecWriteResponse
CommandExecResizeParams / CommandExecResizeResponse
CommandExecTerminateParams / CommandExecTerminateResponse
CommandExecTerminalSize

// 通知类型
CommandExecOutputDeltaNotification {
    process_id: String,
    stream: CommandExecOutputStream,  // Stdout | Stderr
    delta_base64: String,
    cap_reached: bool,
}
```

### 5.2 核心类型 (codex_core)

```rust
// 执行请求
pub struct ExecRequest {
    pub command: Vec<String>,
    pub cwd: PathBuf,
    pub env: HashMap<String, String>,
    pub expiration: ExecExpiration,
    pub sandbox: SandboxType,
    // ... 其他字段
}

// 过期策略
pub enum ExecExpiration {
    Timeout(Duration),
    DefaultTimeout,
    Cancellation(CancellationToken),
}
```

### 5.3 PTY 工具 (codex_utils_pty)

```rust
// 公开 API
pub use pty::spawn_process as spawn_pty_process;      // TTY 模式
pub use pipe::spawn_process as spawn_pipe_process;     // 管道模式
pub use pipe::spawn_process_no_stdin;                  // 无 stdin

pub struct SpawnedProcess {
    pub session: ProcessHandle,       // 进程控制句柄
    pub stdout_rx: mpsc::Receiver<Vec<u8>>,
    pub stderr_rx: mpsc::Receiver<Vec<u8>>,
    pub exit_rx: oneshot::Receiver<i32>,
}

pub struct ProcessHandle {
    pub fn writer_sender(&self) -> mpsc::Sender<Vec<u8>>;
    pub fn resize(&self, size: TerminalSize) -> Result<()>;
    pub fn close_stdin(&self);
    pub fn request_terminate(&self);
}
```

---

## 六、风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 进程泄漏 | 极端情况下进程句柄未正确清理 | `Drop` 实现 + connection_closed 处理 |
| 内存溢出 | 非流式模式大输出缓冲 | `output_bytes_cap` 限制（默认 1MB）|
| 僵尸进程 | 进程退出但任务未结束 | `IO_DRAIN_TIMEOUT_MS` 超时 |
| 重复 ID | 客户端提供重复 process_id | 启动时 HashMap 重复检查 |
| 竞态条件 | 控制命令发送时进程已退出 | oneshot channel + 错误映射 |

### 6.2 边界条件

```rust
// 1. Windows 沙箱限制
if matches!(exec_request.sandbox, SandboxType::WindowsRestrictedToken) {
    // 不支持: tty, stream_stdin, stream_stdout_stderr, custom output_bytes_cap
}

// 2. 终端大小验证
if size.rows == 0 || size.cols == 0 {
    return Err(invalid_params("rows and cols must be greater than 0"));
}

// 3. 流式模式必需 client process_id
if process_id.is_none() && (tty || stream_stdin || stream_stdout_stderr) {
    return Err(invalid_request("tty or streaming requires client-supplied processId"));
}

// 4. 控制命令仅对 Active 会话有效
let CommandExecSession::Active { control_tx } = session else {
    return Err(invalid_request("not supported for windows sandbox"));
};
```

### 6.3 改进建议

1. **资源限制增强**
   - 添加并发进程数限制，防止资源耗尽
   - 支持 per-connection 的进程配额

2. **可观测性**
   - 添加进程生命周期指标（启动数、活跃数、退出码分布）
   - 记录命令执行时长直方图

3. **错误处理细化**
   - 区分 spawn 失败、执行失败、信号终止等不同错误码
   - 提供更详细的错误上下文（如系统错误码）

4. **安全加固**
   - 考虑命令白名单/黑名单机制
   - 敏感环境变量过滤

5. **性能优化**
   - 流式模式下考虑零拷贝传输
   - 大输出场景下的分块策略优化

---

## 七、测试覆盖

### 7.1 单元测试列表

| 测试名 | 验证场景 |
|--------|----------|
| `windows_sandbox_streaming_exec_is_rejected` | Windows 沙箱拒绝流式请求 |
| `windows_sandbox_non_streaming_exec_uses_execution_path` | Windows 沙箱非流式执行路径 |
| `cancellation_expiration_keeps_process_alive_until_terminated` | 取消令牌过期策略 |
| `windows_sandbox_process_ids_reject_write_requests` | Windows 沙箱拒绝控制命令 |
| `windows_sandbox_process_ids_reject_terminate_requests` | Windows 沙箱拒绝终止命令 |
| `dropped_control_request_is_reported_as_not_running` | 控制任务退出后的错误处理 |

### 7.2 测试技术
- 使用 `tokio::time::timeout` 验证异步行为
- 使用 `mpsc::channel` 模拟 OutgoingMessageSender
- 使用 `CancellationToken` 测试取消场景

---

## 八、相关文件引用

```
codex-rs/
├── app-server/src/
│   ├── command_exec.rs          # 本文件
│   ├── error_code.rs            # 错误码定义
│   ├── outgoing_message.rs      # 消息发送基础设施
│   ├── message_processor.rs     # RPC 请求路由
│   └── lib.rs                   # 模块声明
├── utils/pty/src/
│   ├── lib.rs                   # 公开 API
│   ├── pty.rs                   # PTY spawn 实现
│   ├── pipe.rs                  # 管道 spawn 实现
│   └── process.rs               # ProcessHandle 定义
├── core/src/
│   ├── exec.rs                  # ExecExpiration、超时常量
│   └── sandboxing/mod.rs        # ExecRequest、execute_env
└── app-server-protocol/src/
    └── protocol/                # RPC 类型定义
```
