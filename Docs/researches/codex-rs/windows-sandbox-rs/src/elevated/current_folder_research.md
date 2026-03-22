# Windows Sandbox Elevated 模块研究文档

## 1. 场景与职责

### 1.1 模块定位

`elevated` 目录是 Windows Sandbox 子系统的核心组件，专门处理**提升权限（Elevated）**沙箱路径。当 Windows 沙箱级别设置为 `Elevated` 时，CLI 通过此模块启动命令执行器（command runner）来运行沙箱用户下的子进程。

### 1.2 核心场景

| 场景 | 描述 |
|------|------|
| **Elevated 沙箱执行** | 当配置 `windows_sandbox_mode = "elevated"` 时，使用此路径替代传统的 Restricted Token 路径 |
| **统一执行（Unified Exec）** | 支持 TTY 和非 TTY 模式的进程执行，通过 IPC 管道与父进程通信 |
| **进程隔离** | 使用 Job Object 确保子进程在父进程退出时被终止 |
| **安全令牌管理** | 基于 Capability SID 创建受限令牌，实现细粒度的文件系统访问控制 |

### 1.3 架构关系

```
┌─────────────────────────────────────────────────────────────────┐
│                        CLI / Core Layer                         │
│  ┌─────────────────┐  ┌───────────────────────────────────────┐ │
│  │  exec_windows_  │  │   run_windows_sandbox_capture_*       │ │
│  │  sandbox()      │  │   (elevated_impl.rs / lib.rs)         │ │
│  └────────┬────────┘  └───────────────────┬───────────────────┘ │
└───────────┼───────────────────────────────┼─────────────────────┘
            │                               │
            ▼                               ▼
┌──────────────────────┐      ┌──────────────────────────────────┐
│  Elevated Path       │      │  Legacy Path                     │
│  (elevated_impl.rs)  │      │  (lib.rs windows_impl)           │
│  - Named Pipe IPC    │      │  - Direct spawn                  │
│  - Command Runner    │      │  - Restricted Token              │
└──────────┬───────────┘      └──────────────────────────────────┘
           │
           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Elevated Module (本目录)                      │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────┐  ┌───────────┐ │
│  │command_runner│  │ ipc_framed  │  │runner_pipe│  │cwd_junction│ │
│  │_win.rs      │  │ .rs         │  │ .rs      │  │ .rs       │ │
│  └─────────────┘  └─────────────┘  └──────────┘  └───────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 command_runner_win.rs

**目的**：作为独立的二进制程序（`codex-command-runner.exe`）运行，负责在沙箱用户上下文中执行实际命令。

**关键功能**：
- 通过命名管道与父进程建立 IPC 连接
- 解析 `SpawnRequest` 并创建受限令牌
- 支持 ConPTY（TTY 模式）和管道（非 TTY 模式）两种输出方式
- 流式传输 stdout/stderr 输出回父进程
- 处理 stdin 输入和进程终止信号
- 使用 Job Object 实现进程生命周期管理

### 2.2 ipc_framed.rs

**目的**：定义父进程与 command runner 之间的 IPC 协议。

**关键功能**：
- 定义长度前缀的 JSON 消息帧格式
- 支持的消息类型：SpawnRequest、SpawnReady、Output、Stdin、Exit、Error、Terminate
- Base64 编码的二进制数据传输
- 8MB 的消息大小限制（安全边界）

### 2.3 runner_pipe.rs

**目的**：父进程侧的命名管道管理。

**关键功能**：
- 生成唯一的命名管道路径
- 创建具有限制性 DACL 的管道（仅允许沙箱用户连接）
- 解析和定位 command runner 可执行文件
- 等待 runner 进程连接

### 2.4 cwd_junction.rs

**目的**：解决 ACL 辅助工具激活时的工作目录访问问题。

**关键功能**：
- 当 `read_acl_mutex` 存在时，在 `%USERPROFILE%\.codex\.sandbox\cwd` 下创建目录连接点（junction）
- 使用路径哈希生成唯一的连接点名称
- 复用已存在的连接点以优化性能

---

## 3. 具体技术实现

### 3.1 IPC 协议详解

#### 3.1.1 消息帧格式

```rust
// 长度前缀：4 字节小端序 u32
// 后跟 JSON 编码的 FramedMessage
pub struct FramedMessage {
    pub version: u8,  // 当前为 1
    #[serde(flatten)]
    pub message: Message,
}

pub enum Message {
    SpawnRequest { payload: Box<SpawnRequest> },  // 父 -> Runner
    SpawnReady { payload: SpawnReady },           // Runner -> 父
    Output { payload: OutputPayload },            // Runner -> 父
    Stdin { payload: StdinPayload },              // 父 -> Runner
    Exit { payload: ExitPayload },                // Runner -> 父
    Error { payload: ErrorPayload },              // Runner -> 父
    Terminate { payload: EmptyPayload },          // 父 -> Runner
}
```

#### 3.1.2 SpawnRequest 结构

```rust
pub struct SpawnRequest {
    pub command: Vec<String>,              // 要执行的命令及参数
    pub cwd: PathBuf,                      // 工作目录
    pub env: HashMap<String, String>,      // 环境变量
    pub policy_json_or_preset: String,     // 沙箱策略（JSON 或预设名称）
    pub sandbox_policy_cwd: PathBuf,       // 策略计算用的 CWD
    pub codex_home: PathBuf,               // 沙箱用户的 Codex 主目录
    pub real_codex_home: PathBuf,          // 真实用户的 Codex 主目录
    pub cap_sids: Vec<String>,             // Capability SID 列表
    pub timeout_ms: Option<u64>,           // 超时时间（毫秒）
    pub tty: bool,                         // 是否使用 TTY
    pub stdin_open: bool,                  // 是否保持 stdin 打开
    pub use_private_desktop: bool,         // 是否使用私有桌面
}
```

### 3.2 令牌创建流程

```rust
// 1. 获取当前进程令牌
let base = unsafe { get_current_token_for_restriction()? };

// 2. 根据策略创建受限令牌
let (h_token, psid_to_use) = match &policy {
    SandboxPolicy::ReadOnly { .. } => {
        create_readonly_token_with_caps_from(base, &cap_psids)
    }
    SandboxPolicy::WorkspaceWrite { .. } => {
        create_workspace_write_token_with_caps_from(base, &cap_psids)
    }
    ...
};

// 3. 关闭基础令牌
unsafe { CloseHandle(base); }

// 4. 允许访问空设备（NUL）
unsafe { allow_null_device(psid_to_use); }
```

**令牌限制标志**：
- `DISABLE_MAX_PRIVILEGE`：禁用所有特权
- `LUA_TOKEN`：限制管理员令牌
- `WRITE_RESTRICTED`：写入受限

### 3.3 进程启动流程（TTY vs 非 TTY）

#### TTY 模式（ConPTY）

```rust
let (pi, conpty) = spawn_conpty_process_as_user(
    h_token,
    &req.command,
    &effective_cwd,
    &req.env,
    req.use_private_desktop,
    Some(log_dir.as_path()),
)?;
let (hpc, input_write, output_read) = conpty.into_raw();
```

使用 `CreateProcessAsUserW` + `EXTENDED_STARTUPINFO_PRESENT` + `PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE`

#### 非 TTY 模式（管道）

```rust
let pipe_handles: PipeSpawnHandles = spawn_process_with_pipes(
    h_token,
    &req.command,
    &effective_cwd,
    &req.env,
    stdin_mode,
    StderrMode::Separate,
    false,
)?;
```

使用匿名管道重定向 stdin/stdout/stderr

### 3.4 Job Object 生命周期管理

```rust
unsafe fn create_job_kill_on_close() -> Result<HANDLE> {
    let h = CreateJobObjectW(...);
    let mut limits: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = std::mem::zeroed();
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    SetInformationJobObject(h, JobObjectExtendedLimitInformation, ...);
    Ok(h)
}

// 进程启动后
AssignProcessToJobObject(job, pi.hProcess);
```

当 command runner 进程退出时，Job Object 会自动终止所有关联的子进程。

### 3.5 CWD Junction 实现

```rust
pub fn create_cwd_junction(requested_cwd: &Path, log_dir: Option<&Path>) -> Option<PathBuf> {
    // 1. 获取 USERPROFILE 环境变量
    let userprofile = std::env::var("USERPROFILE").ok()?;
    
    // 2. 计算 junction 根目录：%USERPROFILE%\.codex\.sandbox\cwd
    let junction_root = PathBuf::from(userprofile).join(".codex").join(".sandbox").join("cwd");
    
    // 3. 基于路径哈希生成唯一名称
    let junction_path = junction_root.join(junction_name_for_path(requested_cwd));
    
    // 4. 使用 cmd /c mklink /J 创建目录连接点
    std::process::Command::new("cmd")
        .raw_arg("/c")
        .raw_arg("mklink")
        .raw_arg("/J")
        .raw_arg(&link_quoted)
        .raw_arg(&target_quoted)
        .output()
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 核心文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `elevated/command_runner_win.rs` | 554 | Command Runner 主逻辑，进程启动和 IPC 处理 |
| `elevated/ipc_framed.rs` | 183 | IPC 协议定义和帧编解码 |
| `elevated/runner_pipe.rs` | 111 | 父进程侧命名管道管理 |
| `elevated/cwd_junction.rs` | 142 | 工作目录连接点管理 |

### 4.2 调用链

#### 4.2.1 Elevated 路径启动流程

```
codex-rs/core/src/exec.rs:exec_windows_sandbox()
    └── codex_windows_sandbox::run_windows_sandbox_capture_elevated()
        └── elevated_impl.rs:run_windows_sandbox_capture()
            ├── 创建命名管道（pipe_name, create_named_pipe）
            ├── 启动 command runner 进程（CreateProcessWithLogonW）
            ├── 等待管道连接（connect_pipe）
            ├── 发送 SpawnRequest（write_frame）
            ├── 接收 SpawnReady（read_spawn_ready）
            └── 循环接收 Output/Exit/Error 消息
```

#### 4.2.2 Command Runner 执行流程

```
codex-command-runner.exe (command_runner.rs)
    └── command_runner_win.rs:main()
        ├── 解析 --pipe-in/--pipe-out 参数
        ├── 打开命名管道（open_pipe）
        ├── 读取 SpawnRequest（read_spawn_request）
        ├── spawn_ipc_process()
        │   ├── 解析策略（parse_policy）
        │   ├── 创建 Capability SID（convert_string_sid_to_sid）
        │   ├── 创建受限令牌（create_*_token_with_caps_from）
        │   ├── 处理 CWD Junction（effective_cwd）
        │   └── 启动子进程（spawn_conpty_process_as_user 或 spawn_process_with_pipes）
        ├── 创建 Job Object（create_job_kill_on_close）
        ├── 发送 SpawnReady
        ├── 启动输出读取线程（spawn_output_reader）
        ├── 启动输入处理线程（spawn_input_loop）
        ├── 等待进程结束（WaitForSingleObject）
        └── 发送 Exit 消息
```

### 4.3 关键数据结构

```rust
// command_runner_win.rs:79-86
struct IpcSpawnedProcess {
    log_dir: PathBuf,
    pi: PROCESS_INFORMATION,
    stdout_handle: HANDLE,
    stderr_handle: HANDLE,
    stdin_handle: Option<HANDLE>,
    hpc_handle: Option<HANDLE>,  // ConPTY handle
}

// ipc_framed.rs:24
const MAX_FRAME_LEN: usize = 8 * 1024 * 1024;  // 8MB 消息限制

// runner_pipe.rs:33-35
pub const PIPE_ACCESS_INBOUND: u32 = 0x0000_0001;
pub const PIPE_ACCESS_OUTBOUND: u32 = 0x0000_0002;
```

---

## 5. 依赖与外部交互

### 5.1 模块依赖图

```
elevated/
├── command_runner_win.rs
│   ├── 依赖: ipc_framed (协议定义)
│   ├── 依赖: cwd_junction (CWD 处理)
│   ├── 依赖: ../read_acl_mutex (ACL 检测)
│   └── 依赖: crate::process (spawn_process_with_pipes)
│   └── 依赖: crate::conpty (spawn_conpty_process_as_user)
│   └── 依赖: crate::token (受限令牌创建)
│   └── 依赖: crate::cap (Capability SID)
│   └── 依赖: crate::policy (策略解析)
│
├── ipc_framed.rs
│   └── 依赖: base64, serde, serde_json
│
├── runner_pipe.rs
│   ├── 依赖: crate::helper_materialization (解析 runner 路径)
│   ├── 依赖: crate::winutil (SID 解析)
│   └── 依赖: windows-sys (命名管道 API)
│
└── cwd_junction.rs
    └── 依赖: std::process::Command (mklink)
```

### 5.2 外部系统交互

| 组件 | 交互方式 | 目的 |
|------|----------|------|
| **Windows 命名管道** | `CreateNamedPipeW` / `CreateFileW` | 父子进程 IPC |
| **Windows 安全 API** | `ConvertStringSecurityDescriptorToSecurityDescriptorW` | 管道 DACL 配置 |
| **Windows 令牌 API** | `CreateRestrictedToken` / `CreateProcessAsUserW` | 受限令牌创建和进程启动 |
| **ConPTY API** | `CreatePseudoConsole` / `ClosePseudoConsole` | TTY 模拟 |
| **Job Object API** | `CreateJobObjectW` / `AssignProcessToJobObject` | 进程生命周期管理 |
| **cmd.exe** | `mklink /J` | 创建目录连接点 |

### 5.3 与其他模块的接口

```rust
// lib.rs 导出的关键接口
pub use elevated_impl::run_windows_sandbox_capture as run_windows_sandbox_capture_elevated;
pub use windows_impl::run_windows_sandbox_capture;

// 被 core/src/exec.rs 使用
#[cfg(target_os = "windows")]
async fn exec_windows_sandbox(...) {
    use codex_windows_sandbox::run_windows_sandbox_capture;
    use codex_windows_sandbox::run_windows_sandbox_capture_elevated;
    // ...
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 安全风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| **命名管道 DACL 过于宽松** | 管道创建时仅限制特定 SID，但配置不当可能导致未授权访问 | 使用 `D:(A;;GA;;;{sandbox_sid})` 严格限制访问 |
| **Capability SID 泄露** | SID 字符串在 IPC 中传输，可能被截获 | 使用命名管道（内核对象），非网络传输 |
| **Job Object 绕过** | 子进程可能通过特定方式脱离 Job Object | 使用 `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` 标志 |
| **Junction 攻击** | 目录连接点可能被用于目录遍历攻击 | Junction 仅在 ACL 辅助工具激活时创建，且路径经过哈希处理 |

#### 6.1.2 稳定性风险

| 风险 | 描述 | 发生场景 |
|------|------|----------|
| **管道连接超时** | Runner 进程未能及时连接管道 | 系统负载高或杀毒软件拦截 |
| **消息帧过大** | 输出数据超过 8MB 限制 | 命令产生大量输出 |
| **ConPTY 兼容性问题** | 某些程序在 ConPTY 下行为异常 | 旧版控制台程序 |
| **mklink 失败** | 无法创建目录连接点 | 权限不足或路径过长 |

### 6.2 边界条件

```rust
// 1. 消息大小限制
const MAX_FRAME_LEN: usize = 8 * 1024 * 1024;

// 2. 管道缓冲区大小
CreateNamedPipeW(..., 65536, 65536, ...);  // 输入/输出缓冲区 64KB

// 3. 超时处理
let timeout = req.timeout_ms.map(|ms| ms as u32).unwrap_or(INFINITE);
let wait_res = unsafe { WaitForSingleObject(pi.hProcess, timeout) };
let timed_out = wait_res == WAIT_TIMEOUT;  // 0x0000_0102

// 4. 退出码处理
let exit_code = if timed_out { 128 + 64 } else { raw_exit as i32 };
```

### 6.3 改进建议

#### 6.3.1 短期改进

1. **增强错误上下文**
   - 当前错误信息较为简略，建议增加更多上下文（如当前执行的命令、工作目录等）
   - 参考 `process.rs` 中的详细错误格式化方式

2. **优化管道缓冲区**
   - 当前固定 64KB 缓冲区，可根据系统内存动态调整
   - 高吞吐量场景下可考虑更大的缓冲区

3. **改进 Junction 缓存策略**
   - 当前基于路径哈希，可考虑基于 inode/文件标识符的缓存
   - 添加 Junction 定期清理机制，避免累积

#### 6.3.2 中期改进

1. **支持更多策略类型**
   - 当前仅支持 `ReadOnly` 和 `WorkspaceWrite`
   - `DangerFullAccess` 和 `ExternalSandbox` 被显式拒绝，可考虑支持

2. **异步 I/O 优化**
   - 当前使用阻塞 I/O 和线程，可考虑使用 Windows Overlapped I/O
   - 减少线程创建开销，提高并发性能

3. **增强日志记录**
   - 关键路径（令牌创建、进程启动）的日志可进一步细化
   - 添加结构化日志支持，便于遥测分析

#### 6.3.3 长期改进

1. **协议版本演进**
   - 当前为版本 1，预留版本升级空间
   - 考虑支持压缩、加密等扩展

2. **跨平台抽象**
   - 当前 IPC 协议 Windows 特定，可考虑抽象为跨平台接口
   - 便于未来 Linux/macOS 类似功能的实现

3. **安全加固**
   - 考虑使用 `PROC_THREAD_ATTRIBUTE_MITIGATION_POLICY` 启用更多缓解策略
   - 评估使用 AppContainer 进一步隔离的可行性

### 6.4 测试建议

| 测试类型 | 覆盖点 |
|----------|--------|
| **单元测试** | `ipc_framed` 的编解码、`cwd_junction` 的路径哈希 |
| **集成测试** | 完整 Elevated 路径执行、超时处理、大输出处理 |
| **安全测试** | DACL 验证、令牌权限验证、Job Object 行为 |
| **兼容性测试** | 不同 Windows 版本、不同终端类型（CMD/PowerShell/WSL） |

---

## 附录：关键代码引用

### A.1 入口点

```rust
// codex-rs/windows-sandbox-rs/src/bin/command_runner.rs
#[path = "../elevated/command_runner_win.rs"]
mod win;

#[cfg(target_os = "windows")]
fn main() -> anyhow::Result<()> {
    win::main()
}
```

### A.2 IPC 帧读写

```rust
// ipc_framed.rs:125-153
pub fn write_frame<W: Write>(mut writer: W, msg: &FramedMessage) -> Result<()> {
    let payload = serde_json::to_vec(msg)?;
    if payload.len() > MAX_FRAME_LEN { ... }
    let len = payload.len() as u32;
    writer.write_all(&len.to_le_bytes())?;
    writer.write_all(&payload)?;
    writer.flush()?;
    Ok(())
}

pub fn read_frame<R: Read>(mut reader: R) -> Result<Option<FramedMessage>> {
    let mut len_buf = [0u8; 4];
    match reader.read_exact(&mut len_buf) { ... }
    let len = u32::from_le_bytes(len_buf) as usize;
    if len > MAX_FRAME_LEN { ... }
    let mut payload = vec![0u8; len];
    reader.read_exact(&mut payload)?;
    let msg: FramedMessage = serde_json::from_slice(&payload)?;
    Ok(Some(msg))
}
```

### A.3 管道创建

```rust
// runner_pipe.rs:51-95
pub fn create_named_pipe(name: &str, access: u32, sandbox_username: &str) -> io::Result<HANDLE> {
    let sandbox_sid = resolve_sid(sandbox_username)?;
    let sandbox_sid = string_from_sid_bytes(&sandbox_sid)?;
    let sddl = to_wide(format!("D:(A;;GA;;;{sandbox_sid})"));
    // ... 创建 SECURITY_ATTRIBUTES 和命名管道
}
```

---

*文档生成时间：2026-03-22*
*基于代码版本：codex-rs/windows-sandbox-rs/src/elevated/*
