# exec.rs 研究文档

## 场景与职责

`exec.rs` 是 Codex 核心执行引擎的核心模块，负责处理所有外部命令的执行生命周期。它是 shell 工具调用、代码执行和其他需要 spawn 子进程操作的底层基础设施。

### 核心职责

1. **命令执行编排**：将高层执行请求转换为底层系统调用
2. **沙箱集成**：与平台特定的沙箱机制（macOS Seatbelt、Linux Seccomp、Windows Restricted Token）集成
3. **超时与取消**：支持基于时间和 CancellationToken 的执行终止
4. **输出管理**：捕获 stdout/stderr，实施大小限制和流式输出
5. **信号处理**：处理 Ctrl+C 和超时情况下的进程终止

### 在架构中的位置

```
┌─────────────────────────────────────────────────────────────┐
│  Tool Handlers (shell, code_mode, etc.)                     │
├─────────────────────────────────────────────────────────────┤
│  exec_policy.rs (Approval/Policy evaluation)               │
├─────────────────────────────────────────────────────────────┤
│  sandboxing/mod.rs (Sandbox transformation)                │
├─────────────────────────────────────────────────────────────┤
│  exec.rs ◄── 当前模块 (Execution orchestration)            │
├─────────────────────────────────────────────────────────────┤
│  spawn.rs (Process spawning primitives)                    │
├─────────────────────────────────────────────────────────────┤
│  Platform Sandboxes (seatbelt, landlock, windows)          │
└─────────────────────────────────────────────────────────────┘
```

## 功能点目的

### 1. 执行参数管理 (`ExecParams`)

封装执行请求的所有参数：
- `command`: 命令及参数列表
- `cwd`: 工作目录
- `env`: 环境变量映射
- `expiration`: 超时控制（Timeout/Default/Cancellation）
- `network`: 可选的网络代理配置
- `sandbox_permissions`: 沙箱权限级别
- `windows_sandbox_level/private_desktop`: Windows 特定配置

### 2. 执行过期策略 (`ExecExpiration`)

三种过期机制：

```rust
pub enum ExecExpiration {
    Timeout(Duration),           // 指定时长后超时
    DefaultTimeout,              // 使用 DEFAULT_EXEC_COMMAND_TIMEOUT_MS (10s)
    Cancellation(CancellationToken), // 通过 token 取消
}
```

### 3. 沙箱类型选择 (`SandboxType`)

```rust
pub enum SandboxType {
    None,
    MacosSeatbelt,           // macOS 沙箱
    LinuxSeccomp,           // Linux seccomp/landlock
    WindowsRestrictedToken, // Windows 受限令牌
}
```

### 4. 输出流管理

- **实时流式输出**：通过 `StdoutStream` 发送 `ExecCommandOutputDeltaEvent`
- **输出截断**：`EXEC_OUTPUT_MAX_BYTES` 限制总输出大小
- **Delta 事件限制**：`MAX_EXEC_OUTPUT_DELTAS_PER_CALL` (10,000) 防止事件风暴
- **智能聚合**：在容量不足时优先保留 stderr（2/3 容量）

### 5. 沙箱拒绝检测 (`is_likely_sandbox_denied`)

启发式检测命令是否因沙箱限制而失败：
- 检查退出码（SIGSYS = seccomp 违规）
- 扫描输出中的关键词（"operation not permitted", "sandbox", "landlock" 等）
- 排除常见非沙箱错误码（2, 126, 127）

## 具体技术实现

### 关键流程

#### 1. 主执行流程 (`process_exec_tool_call`)

```rust
pub async fn process_exec_tool_call(
    params: ExecParams,
    sandbox_policy: &SandboxPolicy,
    file_system_sandbox_policy: &FileSystemSandboxPolicy,
    network_sandbox_policy: NetworkSandboxPolicy,
    sandbox_cwd: &Path,
    codex_linux_sandbox_exe: &Option<PathBuf>,
    use_legacy_landlock: bool,
    stdout_stream: Option<StdoutStream>,
) -> Result<ExecToolCallOutput>
```

流程：
1. 调用 `build_exec_request` 构建执行请求
2. 通过 `sandboxing::execute_env` 路由到统一执行路径

#### 2. 执行请求构建 (`build_exec_request`)

```rust
pub fn build_exec_request(...) -> Result<ExecRequest>
```

关键步骤：
1. 选择沙箱类型：`select_process_exec_tool_sandbox_type`
2. 构建 `CommandSpec` 封装命令参数
3. 调用 `SandboxManager::transform` 转换请求

#### 3. 核心执行逻辑 (`exec`)

平台分支：
- **Windows + WindowsRestrictedToken**: 调用 `exec_windows_sandbox`
- **其他平台**: 调用 `spawn_child_async` 后直接消费输出

#### 4. Windows 沙箱执行 (`exec_windows_sandbox`)

```rust
#[cfg(target_os = "windows")]
async fn exec_windows_sandbox(
    params: ExecParams,
    sandbox_policy: &SandboxPolicy,
) -> Result<RawExecToolCallOutput>
```

特点：
- 使用 `tokio::task::spawn_blocking` 在阻塞线程执行
- 支持 Elevated 和 Legacy 两种模式
- 失败时记录指标到 `codex.windows_sandbox.createprocessasuserw_failed`

#### 5. 输出消费 (`consume_truncated_output`)

```rust
async fn consume_truncated_output(
    mut child: Child,
    expiration: ExecExpiration,
    stdout_stream: Option<StdoutStream>,
) -> Result<RawExecToolCallOutput>
```

并发处理：
1. 启动 stdout 读取任务：`read_capped`
2. 启动 stderr 读取任务：`read_capped`
3. 等待子进程结束或超时/取消信号
4. 使用 `IO_DRAIN_TIMEOUT_MS` (2s) 限制 I/O 排空时间

#### 6. 带上限的读取 (`read_capped`)

```rust
async fn read_capped<R: AsyncRead + Unpin + Send + 'static>(
    mut reader: R,
    stream: Option<StdoutStream>,
    is_stderr: bool,
) -> io::Result<StreamOutput<Vec<u8>>>
```

功能：
- 8KB 分块读取 (`READ_CHUNK_SIZE`)
- 发送 `ExecCommandOutputDeltaEvent` 事件
- 限制保留字节数 (`EXEC_OUTPUT_MAX_BYTES`)

### 关键数据结构

#### `ExecToolCallOutput`

```rust
pub struct ExecToolCallOutput {
    pub exit_code: i32,
    pub stdout: StreamOutput<String>,
    pub stderr: StreamOutput<String>,
    pub aggregated_output: StreamOutput<String>,
    pub duration: Duration,
    pub timed_out: bool,
}
```

#### `StreamOutput<T>`

```rust
pub struct StreamOutput<T: Clone> {
    pub text: T,
    pub truncated_after_lines: Option<u32>,
}
```

### 常量定义

| 常量 | 值 | 说明 |
|------|-----|------|
| `DEFAULT_EXEC_COMMAND_TIMEOUT_MS` | 10,000 | 默认超时 10 秒 |
| `EXEC_OUTPUT_MAX_BYTES` | 与 PTY 相同 | 输出大小上限 |
| `MAX_EXEC_OUTPUT_DELTAS_PER_CALL` | 10,000 | 每调用最大 delta 事件数 |
| `IO_DRAIN_TIMEOUT_MS` | 2,000 | I/O 排空超时 |
| `READ_CHUNK_SIZE` | 8,192 | 每次读取字节数 |
| `SIGKILL_CODE` | 9 | SIGKILL 信号码 |
| `TIMEOUT_CODE` | 64 | 自定义超时信号码 |
| `EXEC_TIMEOUT_EXIT_CODE` | 124 | 超时退出码（与 timeout(1) 一致）|

## 关键代码路径与文件引用

### 入口点

```rust
// codex-rs/core/src/tools/handlers/shell.rs
// 或
// codex-rs/core/src/tools/code_mode/execute_handler.rs
↓
process_exec_tool_call()
```

### 内部调用链

```
process_exec_tool_call
├── build_exec_request
│   ├── select_process_exec_tool_sandbox_type
│   └── SandboxManager::transform (sandboxing/mod.rs)
│
└── sandboxing::execute_env
    └── execute_exec_request
        ├── exec (平台分支)
        │   ├── exec_windows_sandbox (Windows)
        │   └── spawn_child_async + consume_truncated_output (Unix/其他)
        │
        └── finalize_exec_result
            └── is_likely_sandbox_denied
```

### 相关文件

| 文件 | 关系 |
|------|------|
| `sandboxing/mod.rs` | 沙箱转换和执行路由 |
| `spawn.rs` | 底层进程创建 |
| `seatbelt.rs` | macOS Seatbelt 沙箱 |
| `landlock.rs` | Linux Landlock/seccomp |
| `windows_sandbox.rs` | Windows 受限令牌沙箱 |
| `exec_policy.rs` | 执行策略评估 |
| `exec_env.rs` | 环境变量构建 |
| `tools/sandboxing.rs` | 工具运行时沙箱 trait |

## 依赖与外部交互

### 外部 Crate

| Crate | 用途 |
|-------|------|
| `tokio::process` | 异步进程管理 |
| `tokio::io` | 异步 I/O |
| `tokio_util::sync::CancellationToken` | 取消信号 |
| `async_channel::Sender` | 事件流发送 |
| `codex_network_proxy::NetworkProxy` | 网络代理配置 |
| `codex_utils_pty::process_group` | 进程组管理 |
| `codex_windows_sandbox` | Windows 沙箱 (Windows only) |

### 环境变量

| 变量 | 设置位置 | 用途 |
|------|----------|------|
| `CODEX_SANDBOX_NETWORK_DISABLED` | `spawn.rs` | 标记网络被禁用 |
| `CODEX_SANDBOX` | `seatbelt.rs` | 标记沙箱类型 |

### 信号处理

- **超时**: 发送 SIGTERM 到进程组，返回 exit code 124
- **Ctrl+C**: 发送 SIGKILL (code 9) 到进程组
- **Unix**: 使用 `prctl(PR_SET_PDEATHSIG)` 确保父进程死亡时子进程终止

## 风险、边界与改进建议

### 已知风险

1. **孤儿进程风险**
   - 问题：孙进程可能继承 stdout/stderr FD，导致 I/O 任务挂起
   - 缓解：`IO_DRAIN_TIMEOUT_MS` 限制等待时间
   - 改进：考虑使用 PID namespace（Linux）或 job control（更复杂）

2. **Windows 沙箱限制**
   - 仅支持 timeout 形式的 `ExecExpiration`，不支持 CancellationToken
   - 代码注释：`TODO(iceweasel-oai): run_windows_sandbox_capture should support all variants`

3. **输出截断信息丢失**
   - 当输出超过 `EXEC_OUTPUT_MAX_BYTES` 时，只是简单截断
   - 没有明确标记告诉用户输出被截断

### 边界情况

1. **空命令**: 返回 `InvalidInput` 错误
2. **管道继承**: 通过 `StdioPolicy::RedirectForShellTool` 避免 stdin 挂起
3. **大输出**: 超过 10,000 delta 事件后停止发送事件，但继续读取
4. **跨平台信号**: Windows 使用 `ExitStatus::from_raw(code as u32)` 处理负值

### 改进建议

1. **增强可观测性**
   - 添加结构化日志记录命令执行开始/结束
   - 记录沙箱类型选择和转换决策

2. **统一超时处理**
   - 为 Windows 沙箱实现 CancellationToken 支持
   - 考虑使用 `tokio::select!` 统一处理所有过期类型

3. **输出改进**
   - 在截断输出时添加明确的 `[truncated]` 标记
   - 考虑压缩/摘要大输出而不是简单截断

4. **错误分类**
   - 细化 `is_likely_sandbox_denied` 的启发式规则
   - 区分沙箱拒绝和其他权限错误

5. **测试覆盖**
   - 添加更多 Windows 沙箱测试
   - 测试极端并发情况下的资源竞争
