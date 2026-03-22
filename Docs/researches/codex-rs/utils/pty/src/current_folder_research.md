# codex-rs/utils/pty/src 深度研究文档

## 1. 场景与职责

### 1.1 模块定位

`codex-utils-pty` 是 Codex 项目中负责**进程创建与终端管理**的核心底层库。它提供了跨平台的伪终端（PTY）和管道（Pipe）进程创建能力，是上层执行命令、交互式 REPL、MCP 子进程管理等功能的基石。

### 1.2 核心使用场景

| 场景 | 说明 |
|------|------|
| **Shell 工具执行** | `codex-core` 中执行用户命令，支持沙箱隔离 |
| **交互式 PTY 会话** | TUI/App-Server 中提供交互式终端体验（如 Python REPL） |
| **MCP 子进程管理** | `rmcp-client` 中管理 MCP 服务器的stdio传输 |
| **统一执行框架** | `unified_exec` 模块中管理进程生命周期 |
| **Windows 沙箱** | `windows-sandbox-rs` 中使用 ConPTY 创建隔离进程 |

### 1.3 设计目标

1. **统一接口**：PTY 和 Pipe 两种后端提供一致的 `SpawnedProcess`/`ProcessHandle` API
2. **跨平台支持**：Unix (Linux/macOS) 使用 `portable-pty` + 原生 PTY，Windows 使用 ConPTY
3. **进程组管理**：确保子进程及其后代能够被可靠终止
4. **资源安全**：通过 RAII 模式确保 PTY 句柄、任务句柄正确释放
5. **流式 I/O**：支持异步 stdin 写入和 stdout/stderr 流式读取

---

## 2. 功能点目的

### 2.1 公共 API 概览

```rust
// 核心导出 (lib.rs)
pub use pipe::spawn_process as spawn_pipe_process;           // 管道模式创建进程
pub use pipe::spawn_process_no_stdin as spawn_pipe_process_no_stdin;  // 无stdin的管道进程
pub use pty::spawn_process as spawn_pty_process;             // PTY模式创建进程
pub use process::ProcessHandle;                              // 进程操作句柄
pub use process::SpawnedProcess;                             // 创建结果包装
pub use process::TerminalSize;                               // 终端尺寸配置
pub use process::combine_output_receivers;                   // 合并stdout/stderr
pub use pty::conpty_supported;                               // Windows ConPTY支持检测
```

### 2.2 功能点详细说明

#### 2.2.1 进程创建模式

| 模式 | 适用场景 | 特点 |
|------|----------|------|
| `spawn_pty_process` | 交互式命令（vim, python REPL） | 提供 TTY，支持 resize，合并输出 |
| `spawn_pipe_process` | 非交互式命令（cat, grep） | 分离 stdin/stdout/stderr，可独立读取 |
| `spawn_pipe_process_no_stdin` | 无需输入的命令（ripgrep） | stdin 立即 EOF，避免挂起等待 |

#### 2.2.2 ProcessHandle 操作能力

```rust
impl ProcessHandle {
    pub fn writer_sender(&self) -> mpsc::Sender<Vec<u8>>;  // 异步写入stdin
    pub fn resize(&self, size: TerminalSize) -> Result<()>; // 调整终端尺寸
    pub fn close_stdin(&self);                              // 关闭stdin
    pub fn request_terminate(&self);                        // 请求终止（保留读取）
    pub fn terminate(&self);                                // 强制终止+清理
    pub fn has_exited(&self) -> bool;                       // 检查是否已退出
    pub fn exit_code(&self) -> Option<i32>;                 // 获取退出码
}
```

#### 2.2.3 进程组管理 (process_group.rs)

```rust
// 核心功能
pub fn detach_from_tty() -> io::Result<()>;              // 脱离控制终端
pub fn set_parent_death_signal(parent_pid: pid_t);       // Linux: 父进程死亡信号
pub fn kill_process_group(process_group_id: u32);        // SIGKILL 整个进程组
pub fn terminate_process_group(process_group_id: u32);   // SIGTERM 整个进程组
pub fn kill_child_process_group(child: &mut Child);      // 通过 Child 对象终止
```

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 SpawnedProcess (process.rs)

```rust
#[derive(Debug)]
pub struct SpawnedProcess {
    pub session: ProcessHandle,                    // 进程控制句柄
    pub stdout_rx: mpsc::Receiver<Vec<u8>>,       // stdout 接收通道
    pub stderr_rx: mpsc::Receiver<Vec<u8>>,       // stderr 接收通道
    pub exit_rx: oneshot::Receiver<i32>,          // 退出码一次性接收
}
```

#### 3.1.2 ProcessHandle (process.rs)

```rust
pub struct ProcessHandle {
    writer_tx: StdMutex<Option<mpsc::Sender<Vec<u8>>>>,  // stdin 发送端
    killer: StdMutex<Option<Box<dyn ChildTerminator>>>, // 终止器
    reader_handle: StdMutex<Option<JoinHandle<()>>>,    // 读取任务句柄
    reader_abort_handles: StdMutex<Vec<AbortHandle>>,   // 可中止的读取任务
    writer_handle: StdMutex<Option<JoinHandle<()>>>,    // 写入任务句柄
    wait_handle: StdMutex<Option<JoinHandle<()>>>,      // 等待退出任务
    exit_status: Arc<AtomicBool>,                       // 退出状态标志
    exit_code: Arc<StdMutex<Option<i32>>>,              // 退出码存储
    _pty_handles: StdMutex<Option<PtyHandles>>,         // PTY句柄保持存活
}
```

#### 3.1.3 TerminalSize

```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct TerminalSize {
    pub rows: u16,    // 默认 24
    pub cols: u16,    // 默认 80
}
```

### 3.2 关键流程

#### 3.2.1 PTY 进程创建流程 (pty.rs)

```
spawn_pty_process()
    ├── platform_native_pty_system()     // 获取平台PTY系统
    │   ├── Windows: ConPtySystem        // Windows ConPTY实现
    │   └── Unix: native_pty_system()    // portable-pty原生实现
    ├── pty_system.openpty(size)         // 打开PTY主从设备
    ├── slave.spawn_command(cmd)         // 在从设备上启动命令
    ├── 创建异步任务:
    │   ├── reader_handle: spawn_blocking 读取PTY输出 → stdout_tx
    │   ├── writer_handle: tokio::spawn 接收writer_rx → PTY写入
    │   └── wait_handle: spawn_blocking 等待子进程退出
    └── 组装 SpawnedProcess
```

#### 3.2.2 Pipe 进程创建流程 (pipe.rs)

```
spawn_pipe_process()
    ├── 创建 tokio::process::Command
    ├── pre_exec 设置 (Unix):
    │   ├── detach_from_tty()            // setsid() 创建新会话
    │   ├── set_parent_death_signal()    // Linux prctl(PR_SET_PDEATHSIG)
    │   └── close_inherited_fds_except() // 关闭继承的文件描述符
    ├── 配置 stdio: stdin/stdout/stderr = piped()
    ├── command.spawn()                  // 启动子进程
    ├── 创建异步任务:
    │   ├── stdout_handle: 读取stdout → stdout_tx
    │   ├── stderr_handle: 读取stderr → stderr_tx
    │   ├── writer_handle: 接收writer_rx → stdin写入
    │   └── wait_handle: 等待子进程退出
    └── 组装 SpawnedProcess
```

#### 3.2.3 进程终止流程

```
ProcessHandle::terminate()
    ├── killer.lock().take().kill()      // 发送终止信号
    ├── reader_handle.abort()            // 中止读取任务
    ├── reader_abort_handles 遍历 abort // 中止额外读取任务
    ├── writer_handle.abort()            // 中止写入任务
    └── wait_handle.abort()              // 中止等待任务
```

Unix 终止细节：
- 优先使用 `killpg(SIGKILL)` 终止整个进程组
- 备用 `ChildKiller::kill()` 终止直接子进程

Windows 终止细节：
- 使用 `TerminateProcess(handle, 1)` 终止
- 修复了 bug #13945：正确处理 Win32 非零成功返回值

### 3.3 平台特定实现

#### 3.3.1 Unix PTY 保留 FD 模式 (pty.rs)

当需要保留特定文件描述符时（如 MCP 子进程通信），使用 `spawn_process_preserving_fds`：

```rust
#[cfg(unix)]
async fn spawn_process_preserving_fds(..., inherited_fds: &[RawFd]) {
    // 1. 使用 openpty() 直接打开 PTY
    let (master, slave) = open_unix_pty(size)?;
    
    // 2. 克隆 slave 用于 stdin/stdout/stderr
    let stdin = slave.try_clone()?;
    let stdout = slave.try_clone()?;
    let stderr = slave.try_clone()?;
    
    // 3. pre_exec 中:
    //    - 重置信号处理为默认
    //    - 清空信号掩码
    //    - setsid() 创建新会话
    //    - ioctl(TIOCSCTTY) 设置控制终端
    //    - close_inherited_fds_except(inherited_fds)
}
```

#### 3.3.2 Windows ConPTY 实现 (win/)

| 文件 | 职责 |
|------|------|
| `win/mod.rs` | WinChild/WinChildKiller 实现，进程句柄管理 |
| `win/conpty.rs` | ConPtySystem 实现，PtySystem trait |
| `win/psuedocon.rs` | PsuedoCon 封装，CreatePseudoConsole API |
| `win/procthreadattr.rs` | ProcThreadAttributeList，进程启动属性 |

关键 Windows API 调用链：
```
ConPtySystem::openpty()
    └── create_conpty_handles()
        ├── Pipe::new()                    // 创建输入/输出管道
        └── PsuedoCon::new()               // CreatePseudoConsole()
            └── CreateProcessW() with EXTENDED_STARTUPINFO_PRESENT
                └── ProcThreadAttributeList::set_pty()
```

ConPTY 支持检测：
```rust
const MIN_CONPTY_BUILD: u32 = 17_763;  // Windows 10 October 2018 Update
pub fn conpty_supported() -> bool {
    windows_build_number().is_some_and(|build| build >= MIN_CONPTY_BUILD)
}
```

### 3.4 信号与进程组管理

#### 3.4.1 Unix 进程组隔离

```rust
// pre_exec 中执行
pub fn detach_from_tty() -> io::Result<()> {
    let result = unsafe { libc::setsid() };  // 创建新会话，脱离控制TTY
    if result == -1 {
        let err = io::Error::last_os_error();
        if err.raw_os_error() == Some(libc::EPERM) {
            return set_process_group();       // 已是组长，仅设置进程组
        }
        return Err(err);
    }
    Ok(())
}
```

#### 3.4.2 Linux 父进程死亡信号

```rust
#[cfg(target_os = "linux")]
pub fn set_parent_death_signal(parent_pid: libc::pid_t) -> io::Result<()> {
    // 请求父进程死亡时接收 SIGTERM
    if unsafe { libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM) } == -1 {
        return Err(io::Error::last_os_error());
    }
    // 检查父进程是否已变化（fork/exec 竞态）
    if unsafe { libc::getppid() } != parent_pid {
        unsafe { libc::raise(libc::SIGTERM); }
    }
    Ok(())
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 源文件结构

```
codex-rs/utils/pty/src/
├── lib.rs              # 模块导出，公共API定义
├── process.rs          # ProcessHandle, SpawnedProcess, TerminalSize
├── pipe.rs             # 管道模式进程创建
├── pty.rs              # PTY模式进程创建
├── process_group.rs    # 进程组管理，信号处理
├── tests.rs            # 集成测试
└── win/                # Windows 特定实现
    ├── mod.rs          # WinChild, WinChildKiller
    ├── conpty.rs       # ConPtySystem, ConPtyMasterPty, ConPtySlavePty
    ├── psuedocon.rs    # PsuedoCon, ConPTY API 封装
    └── procthreadattr.rs  # ProcThreadAttributeList
```

### 4.2 关键代码路径

#### 4.2.1 创建 PTY 进程

```
lib.rs:31  pub use pty::spawn_process as spawn_pty_process;
    ↓
pty.rs:102 pub async fn spawn_process(...)
    ├── pty.rs:140 spawn_process_portable()  [无保留FD]
    └── pty.rs:256 spawn_process_preserving_fds()  [Unix + 保留FD]
```

#### 4.2.2 创建 Pipe 进程

```
lib.rs:13  pub use pipe::spawn_process as spawn_pipe_process;
    ↓
pipe.rs:253 pub async fn spawn_process(...)
    └── pipe.rs:98 spawn_process_with_stdin_mode()
        ├── pipe.rs:124 pre_exec 设置 (Unix)
        └── pipe.rs:154 command.spawn()
```

#### 4.2.3 进程终止

```
process.rs:176 pub fn terminate(&self)
    ├── process.rs:167 request_terminate()
    │   └── killer.lock().take().kill()
    │       ├── pipe.rs:34 PipeChildTerminator::kill()
    │       │   ├── Unix: process_group.rs:149 kill_process_group()
    │       │   └── Windows: pipe.rs:54 kill_process()
    │       └── pty.rs:56 PtyChildTerminator::kill()
    │           └── Unix: process_group.rs:149 kill_process_group()
    └── 中止各个任务句柄
```

#### 4.2.4 终端 Resize

```
process.rs:143 pub fn resize(&self, size: TerminalSize)
    ├── 有 PTY handles: PtyMasterHandle::Resizable(master)
    │   └── master.resize(size.into())  // portable-pty
    └── Unix Opaque 模式:
        └── process.rs:209 resize_raw_pty()
            └── libc::ioctl(fd, TIOCSWINSZ, &winsize)
```

### 4.3 测试覆盖

| 测试函数 | 测试内容 | 位置 |
|----------|----------|------|
| `pty_python_repl_emits_output_and_exits` | PTY Python REPL 交互 | tests.rs:343 |
| `pipe_process_round_trips_stdin` | Pipe stdin 往返 | tests.rs:391 |
| `pipe_process_detaches_from_parent_session` | 进程组隔离验证 | tests.rs:444 |
| `pty_terminate_kills_background_children_in_same_process_group` | 进程组终止 | tests.rs:632 |
| `pty_spawn_can_preserve_inherited_fds` | FD 保留功能 | tests.rs:677 |
| `pipe_spawn_no_stdin_can_preserve_inherited_fds` | Pipe FD 保留 | tests.rs:904 |

---

## 5. 依赖与外部交互

### 5.1 外部依赖

| Crate | 用途 |
|-------|------|
| `portable-pty` | 跨平台 PTY 抽象（Unix） |
| `tokio` | 异步运行时，process/io-util/sync 特性 |
| `anyhow` | 错误处理 |
| `libc` | Unix 系统调用 (Unix only) |
| `winapi` | Windows API (Windows only) |
| `filedescriptor` | 文件描述符抽象 (Windows only) |
| `shared_library` | 动态库加载 (Windows only) |
| `lazy_static` | 静态初始化 (Windows only) |

### 5.2 内部调用方

| 调用方 | 使用方式 | 文件路径 |
|--------|----------|----------|
| `codex-core` | Shell 工具执行，统一执行框架 | `core/src/exec.rs`, `core/src/spawn.rs`, `core/src/unified_exec/process.rs` |
| `codex-app-server` | command/exec 实现 | `app-server/src/command_exec.rs` |
| `codex-rmcp-client` | MCP 子进程管理 | `rmcp-client/src/rmcp_client.rs` |
| `windows-sandbox-rs` | ConPTY 创建 | `windows-sandbox-rs/src/conpty/mod.rs` |

### 5.3 调用示例

#### 5.3.1 codex-core 中使用

```rust
// core/src/spawn.rs
cmd.pre_exec(move || {
    if detach_from_tty {
        codex_utils_pty::process_group::detach_from_tty()?;
    }
    #[cfg(target_os = "linux")]
    {
        codex_utils_pty::process_group::set_parent_death_signal(parent_pid)?;
    }
    Ok(())
});
```

```rust
// core/src/unified_exec/process.rs
use codex_utils_pty::{ExecCommandSession, SpawnedPty};

pub(crate) async fn from_spawned(
    spawned: SpawnedPty,
    ...
) -> Result<Self, UnifiedExecError> {
    let output_rx = codex_utils_pty::combine_output_receivers(stdout_rx, stderr_rx);
    // ...
}
```

#### 5.3.2 app-server 中使用

```rust
// app-server/src/command_exec.rs
use codex_utils_pty::{ProcessHandle, SpawnedProcess, TerminalSize};

let spawned = if tty {
    codex_utils_pty::spawn_pty_process(program, args, cwd, &env, &arg0, size).await
} else if stream_stdin {
    codex_utils_pty::spawn_pipe_process(program, args, cwd, &env, &arg0).await
} else {
    codex_utils_pty::spawn_pipe_process_no_stdin(program, args, cwd, &env, &arg0).await
};
```

#### 5.3.3 rmcp-client 中使用

```rust
// rmcp-client/src/rmcp_client.rs
use codex_utils_pty::process_group;

struct ProcessGroupGuard {
    #[cfg(unix)]
    process_group_id: u32,
}

impl Drop for ProcessGroupGuard {
    fn drop(&mut self) {
        if cfg!(unix) {
            self.maybe_terminate_process_group();
        }
    }
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 竞态条件风险

| 风险点 | 描述 | 缓解措施 |
|--------|------|----------|
| fork/exec 竞态 | `set_parent_death_signal` 中父进程可能在检查前死亡 | 使用 `getppid()` 双重检查 |
| 进程组 ID 失效 | 缓存的 PGID 可能因进程快速退出而失效 | PtyChildTerminator 中同时尝试直接 killer |
| Windows 退出码 | ConPTY 可能在最终字节前报告退出 | 测试中使用 drain 延迟处理 |

#### 6.1.2 资源泄漏风险

```rust
// PtyHandles 必须保持存活，否则子进程会收到 Control+C
_pty_handles: StdMutex<Option<PtyHandles>>,

// Windows 上 slave 必须保持存活
PtyHandles {
    _slave: if cfg!(windows) { Some(pair.slave) } else { None },
    _master: PtyMasterHandle::Resizable(pair.master),
}
```

#### 6.1.3 平台差异

| 差异点 | Unix | Windows |
|--------|------|---------|
| 进程组管理 | setsid() + setpgid() | Job Object（未实现） |
| 终止信号 | SIGTERM/SIGKILL | TerminateProcess |
| PTY 实现 | openpty() | CreatePseudoConsole |
| FD 保留 | 支持 | 不支持 |

### 6.2 边界情况

1. **空程序名**：`spawn_process` 会检查 `program.is_empty()` 并返回错误
2. **零尺寸终端**：`TerminalSize { rows: 0, cols: 0 }` 在 protocol 层被禁止
3. **超大输出**：`DEFAULT_OUTPUT_BYTES_CAP = 1MB` 限制，超出截断
4. **孤儿进程**：依赖 `set_parent_death_signal` (Linux) 或进程组终止

### 6.3 改进建议

#### 6.3.1 代码结构

1. **模块化拆分**：
   - `process.rs` 265 行尚可，但 `pty.rs` 481 行、`pipe.rs` 294 行接近上限
   - 建议将 Unix/Windows 特定代码进一步拆分到子模块

2. **错误处理增强**：
   - 当前使用 `anyhow::Result`，建议关键路径使用自定义错误类型
   - 便于调用方区分 "程序不存在"、"权限不足"、"PTY 创建失败" 等场景

#### 6.3.2 功能增强

1. **Windows 进程组支持**：
   ```rust
   // 当前 Windows 仅使用单进程终止
   // 可考虑使用 Windows Job Object 实现类似 Unix 进程组功能
   ```

2. **PTY 状态查询**：
   ```rust
   // 建议添加
   pub fn pty_size(&self) -> Option<TerminalSize>;
   pub fn is_pty(&self) -> bool;  // 区分 PTY 和 Pipe 模式
   ```

3. **优雅关闭超时**：
   ```rust
   // 当前 terminate() 立即强制终止
   // 可添加 graceful_shutdown(timeout) 先 SIGTERM，超时后 SIGKILL
   ```

#### 6.3.3 测试覆盖

1. **增加测试**：
   - Windows 特定测试（当前大部分测试是 `#[cfg(unix)]`）
   - 大流量输出压力测试（当前仅 `pipe_drains_stderr_without_stdout_activity` 覆盖 4MB）
   - 并发创建/终止测试

2. **测试稳定性**：
   ```rust
   // 当前测试使用 sleep 等待输出，可考虑使用同步原语
   // 如 wait_for_output_contains 模式推广
   ```

#### 6.3.4 文档

1. **内部文档**：
   - `process_group.rs` 已有详细模块文档，建议为 `pty.rs` 的两种创建模式添加类似文档
   - 说明何时使用 `spawn_process_portable` vs `spawn_process_preserving_fds`

2. **示例代码**：
   - README 中的示例较简单，可添加：
     - 交互式 REPL 完整示例
     - 进程终止最佳实践
     - Resize 使用示例

### 6.4 维护注意事项

1. **WezTerm 代码同步**：
   - `win/` 目录代码源自 WezTerm (MIT License)
   - 已修复 bug #13945（TerminateProcess 返回值处理）
   - 未来同步时需保留此修复

2. **portable-pty 升级**：
   - 当前使用 workspace 依赖
   - 升级时需验证 Unix PTY 行为一致性

3. **Rust 版本兼容性**：
   - 使用 `#[cfg(unix)]` / `#[cfg(windows)]` 条件编译
   - 注意 `libc` crate 的平台特定函数可用性

---

## 7. 总结

`codex-utils-pty` 是一个设计精良的跨平台进程管理库，通过统一的抽象层屏蔽了 Unix PTY 和 Windows ConPTY 的差异。其核心优势在于：

1. **一致的 API**：无论底层是 PTY 还是 Pipe，调用方使用相同的 `ProcessHandle`
2. **可靠的清理**：RAII 模式确保资源释放，进程组管理确保子进程终止
3. **灵活的模式**：支持交互式（PTY）、非交互式（Pipe）、无 stdin（no_stdin）多种场景
4. **FD 保留支持**：Unix 下支持保留特定文件描述符，满足 MCP 等高级用例

主要使用方包括 `codex-core`（Shell 执行）、`codex-app-server`（command/exec API）、`codex-rmcp-client`（MCP 子进程），是 Codex 项目执行能力的核心基础设施。
