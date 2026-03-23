# command_runner.rs 深度研究文档

## 场景与职责

`command_runner.rs` 是 Codex Windows Sandbox 的**命令执行器入口文件**，作为 `codex-command-runner.exe` 二进制文件的入口点。该可执行文件在**提升权限（Elevated）沙箱路径**下运行，负责在沙箱用户上下文中执行命令，并通过 IPC 管道与父进程（CLI）进行通信。

### 核心职责

1. **平台适配**：提供 Windows 平台的命令执行能力，非 Windows 平台直接 panic
2. **委托执行**：将实际工作委托给 `command_runner_win.rs` 模块
3. **进程隔离**：作为独立进程运行，拥有独立的权限上下文

### 在沙箱架构中的位置

```
┌─────────────────────────────────────────────────────────────────┐
│                        Parent Process (CLI)                      │
│  - Creates named pipes                                           │
│  - Launches command_runner.exe via CreateProcessWithLogonW       │
│  - Communicates via IPC framed protocol                          │
└───────────────────────┬─────────────────────────────────────────┘
                        │ named pipes
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│                    command_runner.exe                            │
│  - Receives SpawnRequest via pipe                                │
│  - Creates restricted token from sandbox user                    │
│  - Spawns child process (ConPTY or pipes)                        │
│  - Streams I/O back to parent                                    │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Actual Child Process                          │
│  - Runs with restricted token                                    │
│  - Sandboxed file system access                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 功能点目的

### 1. 平台检测与编译时条件

```rust
#[cfg(target_os = "windows")]
fn main() -> anyhow::Result<()> {
    win::main()
}

#[cfg(not(target_os = "windows"))]
fn main() {
    panic!("codex-command-runner is Windows-only");
}
```

- **Windows 平台**：调用实际的 Windows 实现
- **非 Windows 平台**：编译通过但运行时 panic，确保不会在错误平台使用

### 2. 模块路径重定向

```rust
#[path = "../elevated/command_runner_win.rs"]
mod win;
```

使用 `#[path]` 属性将模块指向实际实现文件，保持代码组织结构清晰。

---

## 具体技术实现

### 实际实现：command_runner_win.rs

由于入口文件本身非常简单，实际功能都在 `elevated/command_runner_win.rs` 中实现：

#### 核心数据结构

```rust
/// IPC  spawned process handle bundle
struct IpcSpawnedProcess {
    log_dir: PathBuf,
    pi: PROCESS_INFORMATION,          // Windows 进程信息
    stdout_handle: HANDLE,            // 标准输出句柄
    stderr_handle: HANDLE,            // 标准错误句柄
    stdin_handle: Option<HANDLE>,     // 标准输入句柄（可选）
    hpc_handle: Option<HANDLE>,       // ConPTY 伪控制台句柄
}
```

#### 命令行参数解析

```rust
// 从环境变量解析命名管道路径
for arg in std::env::args().skip(1) {
    if let Some(rest) = arg.strip_prefix("--pipe-in=") {
        pipe_in = Some(rest.to_string());
    } else if let Some(rest) = arg.strip_prefix("--pipe-out=") {
        pipe_out = Some(rest.to_string());
    }
}
```

#### 主要执行流程

1. **连接管道**：打开父进程创建的命名管道
2. **读取 SpawnRequest**：接收包含命令、环境变量、策略等信息的请求
3. **创建受限令牌**：根据沙箱策略创建只读或工作区写入令牌
4. **创建工作目录连接点**：处理 ACL 辅助工具运行时的 CWD 问题
5. **启动子进程**：
   - TTY 模式：使用 ConPTY 创建伪终端
   - 非 TTY 模式：使用管道重定向 I/O
6. **I/O 多路复用**：
   - 输出线程：读取子进程 stdout/stderr，编码为 Output 帧发送回父进程
   - 输入线程：接收父进程的 Stdin/Terminate 帧，转发给子进程
7. **等待退出**：等待子进程结束或超时，发送 Exit 帧

#### 令牌创建逻辑

```rust
let token_res: Result<(HANDLE, *mut c_void)> = unsafe {
    match &policy {
        SandboxPolicy::ReadOnly { .. } => {
            create_readonly_token_with_caps_from(base, &cap_psids)
                .map(|h_token| (h_token, cap_psids[0]))
        }
        SandboxPolicy::WorkspaceWrite { .. } => {
            create_workspace_write_token_with_caps_from(base, &cap_psids)
                .map(|h_token| (h_token, cap_psids[0]))
        }
        // ...
    }
};
```

#### Job Object 管理

```rust
unsafe fn create_job_kill_on_close() -> Result<HANDLE> {
    let h = CreateJobObjectW(std::ptr::null_mut(), std::ptr::null());
    let mut limits: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = std::mem::zeroed();
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    SetInformationJobObject(h, JobObjectExtendedLimitInformation, ...);
    // 确保 runner 进程退出时，子进程也被终止
}
```

---

## 关键代码路径与文件引用

### 文件依赖关系

```
src/bin/command_runner.rs
    └── src/elevated/command_runner_win.rs (实际实现)
        ├── src/elevated/cwd_junction.rs (CWD 连接点处理)
        ├── src/elevated/read_acl_mutex.rs (ACL 互斥锁)
        └── src/elevated/ipc_framed.rs (IPC 协议)
            └── src/lib.rs (公共 API)
                ├── src/token.rs (令牌操作)
                ├── src/acl.rs (ACL 管理)
                ├── src/process.rs (进程创建)
                ├── src/conpty/ (ConPTY 支持)
                └── src/policy.rs (策略解析)
```

### IPC 协议帧类型

定义在 `src/elevated/ipc_framed.rs`：

| 消息类型 | 方向 | 用途 |
|---------|------|------|
| `SpawnRequest` | Parent → Runner | 启动命令请求 |
| `SpawnReady` | Runner → Parent | 进程启动确认 |
| `Output` | Runner → Parent | stdout/stderr 输出 |
| `Stdin` | Parent → Runner | 标准输入数据 |
| `Terminate` | Parent → Runner | 终止进程请求 |
| `Exit` | Runner → Parent | 进程退出状态 |
| `Error` | Runner → Parent | 错误报告 |

### 关键 Windows API 使用

| API | 用途 |
|-----|------|
| `CreateFileW` | 打开命名管道 |
| `CreateJobObjectW` / `SetInformationJobObject` | 创建 Job Object 实现进程生命周期管理 |
| `AssignProcessToJobObject` | 将子进程加入 Job |
| `WaitForSingleObject` | 等待进程退出 |
| `TerminateProcess` | 超时终止进程 |
| `ClosePseudoConsole` | 清理 ConPTY 资源 |

---

## 依赖与外部交互

### 编译依赖

```toml
[[bin]]
name = "codex-command-runner"
path = "src/bin/command_runner.rs"
```

### 运行时依赖

1. **父进程**：通过命名管道提供 IPC 通道
2. **Windows 内核**：
   - 命名管道 (`\\.\pipe\*`)
   - Job Objects
   - Access Tokens
   - ConPTY (Windows 10+)
3. **沙箱用户**：进程在该用户上下文中运行

### 环境变量

- `USERPROFILE`：用于创建 CWD 连接点
- `CODEX_HOME`：日志记录路径

### 输入/输出

**输入**：
- 命令行：`--pipe-in=<name> --pipe-out=<name>`
- 管道：Framed SpawnRequest 消息

**输出**：
- 管道：Framed Output/Exit/Error 消息
- 日志文件：`%CODEX_HOME%/.sandbox/notes.log`
- 进程退出码：子进程退出码

---

## 风险、边界与改进建议

### 已知风险

1. **权限提升风险**
   - Runner 以沙箱用户身份运行，但负责创建受限令牌
   - 如果令牌创建逻辑有漏洞，可能导致权限逃逸

2. **IPC 安全风险**
   - 命名管道使用 SDDL 限制只有沙箱用户可以连接
   - 但管道名称是随机生成的，存在被猜测的理论风险

3. **资源泄漏风险**
   - 使用大量 Windows 句柄（进程、线程、管道、Job Object）
   - 代码中有 `unsafe` 块处理句柄关闭，需要仔细审查

4. **超时处理**
   - 超时后发送 `TerminateProcess`，但子进程可能忽略终止信号
   - Job Object 的 `KILL_ON_JOB_CLOSE` 提供最后保障

### 边界条件

| 场景 | 处理方式 |
|------|----------|
| 管道连接失败 | 返回错误，清理资源 |
| SpawnRequest 解析失败 | 发送 Error 帧，退出 |
| 令牌创建失败 | 发送 Error 帧，退出 |
| 子进程启动失败 | 发送 Error 帧，退出 |
| 超时 | 终止进程，exit_code = 192 (128+64) |
| 父进程断开 | 读取 EOF，清理并退出 |

### 改进建议

1. **增强 IPC 安全性**
   - 考虑使用更安全的 IPC 机制（如 ALPC）替代命名管道
   - 添加消息认证码（MAC）防止 IPC 篡改

2. **资源管理优化**
   - 使用 RAII 包装 Windows 句柄，减少 `unsafe` 代码
   - 考虑使用 `scopeguard` 或自定义 Drop 实现

3. **错误处理增强**
   - 添加更详细的错误码分类
   - 在 Error 帧中包含更多上下文信息

4. **性能优化**
   - 考虑使用异步 I/O 替代多线程
   - 优化大输出数据的传输（当前使用 Base64 编码）

5. **可观测性**
   - 添加结构化日志（JSON 格式）
   - 导出性能指标（启动时间、I/O 吞吐量等）

### 测试建议

1. **单元测试**：IPC 帧编解码（已在 `ipc_framed.rs` 中实现）
2. **集成测试**：完整命令执行流程
3. **压力测试**：大量并发命令执行
4. **安全测试**：权限边界验证、IPC 安全测试
