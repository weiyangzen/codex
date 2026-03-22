# codex-rs/utils/pty 深度研究文档

## 1. 场景与职责

### 1.1 定位与目标

`codex-utils-pty` 是 Codex 项目中负责**进程创建与管理的底层基础设施 crate**，核心职责是提供跨平台的伪终端（PTY）和普通管道（pipe）进程创建能力。它是连接上层业务逻辑（如 shell 命令执行、交互式 REPL）与操作系统底层进程 API 的关键桥梁。

### 1.2 使用场景

| 场景 | 说明 |
|------|------|
| **交互式命令执行** | 通过 PTY 启动 bash/zsh/python REPL，支持实时输入输出和终端尺寸调整 |
| **非交互式命令执行** | 通过 pipe 启动普通进程，分离 stdout/stderr，适合脚本执行 |
| **长时运行进程管理** | 提供进程生命周期控制（启动、终止、等待退出） |
| **沙箱环境执行** | 支持文件描述符继承、进程组隔离等底层原语，配合 sandbox 机制 |

### 1.3 在架构中的位置

```
┌─────────────────────────────────────────────────────────────┐
│  app-server (JSON-RPC API)                                  │
│  ├── command_exec.rs ── spawn_pty_process/spawn_pipe_process│
│  └── 提供 command/exec, command/exec/write 等接口           │
├─────────────────────────────────────────────────────────────┤
│  core crate (业务逻辑)                                       │
│  ├── exec.rs ── 命令执行与沙箱集成                           │
│  ├── spawn.rs ── 基础进程创建                                │
│  ├── shell_snapshot.rs ── shell 环境捕获                     │
│  └── unified_exec/ ── 统一执行引擎                           │
│      ├── process_manager.rs ── 进程生命周期管理              │
│      └── process.rs ── 进程抽象封装                          │
├─────────────────────────────────────────────────────────────┤
│  codex-utils-pty (本 crate)                                  │
│  ├── pty.rs ── PTY 进程创建 (Unix/Windows)                   │
│  ├── pipe.rs ── Pipe 进程创建                                │
│  ├── process.rs ── 进程句柄与输出合并                        │
│  ├── process_group.rs ── 进程组管理                          │
│  └── win/ ── Windows ConPTY 实现                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 核心功能矩阵

| 功能 | 目的 | 关键 API |
|------|------|----------|
| **PTY 进程创建** | 提供伪终端环境，支持交互式程序（如 Python REPL、vim） | `spawn_pty_process()` |
| **Pipe 进程创建** | 标准管道通信，适合非交互式脚本执行 | `spawn_pipe_process()`, `spawn_pipe_process_no_stdin()` |
| **进程控制** | 向进程发送输入、调整终端大小、强制终止 | `ProcessHandle::writer_sender()`, `resize()`, `terminate()` |
| **输出收集** | 合并 stdout/stderr 为统一输出流 | `combine_output_receivers()` |
| **进程组管理** | 确保子进程及其后代能被完整清理 | `process_group::kill_process_group()` |
| **文件描述符继承** | 支持沙箱等场景下保留特定 FD | `spawn_process_with_inherited_fds()` |

### 2.2 平台适配策略

| 平台 | PTY 实现 | 说明 |
|------|----------|------|
| Unix (Linux/macOS) | `openpty()` + `portable-pty` | 原生 PTY 支持，通过 `libc::openpty` 创建 |
| Windows | ConPTY (Pseudo Console) | 通过 `CreatePseudoConsole` API，需 Windows 10 1809+ |
| Windows (旧版) | 不支持 | `conpty_supported()` 返回 false |

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 TerminalSize

```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct TerminalSize {
    pub rows: u16,
    pub cols: u16,
}

impl Default for TerminalSize {
    fn default() -> Self {
        Self { rows: 24, cols: 80 }
    }
}
```

- 用于指定 PTY 的终端尺寸（字符行列数）
- 支持通过 `ProcessHandle::resize()` 动态调整

#### 3.1.2 ProcessHandle

```rust
pub struct ProcessHandle {
    writer_tx: StdMutex<Option<mpsc::Sender<Vec<u8>>>>,  // stdin 写入通道
    killer: StdMutex<Option<Box<dyn ChildTerminator>>>, // 进程终止器
    reader_handle: StdMutex<Option<JoinHandle<()>>>,    // stdout 读取任务
    reader_abort_handles: StdMutex<Vec<AbortHandle>>,   // 可中止的读取任务
    writer_handle: StdMutex<Option<JoinHandle<()>>>,    // stdin 写入任务
    wait_handle: StdMutex<Option<JoinHandle<()>>>,      // 进程等待任务
    exit_status: Arc<AtomicBool>,                       // 是否已退出
    exit_code: Arc<StdMutex<Option<i32>>>,             // 退出码
    _pty_handles: StdMutex<Option<PtyHandles>>,        // PTY 句柄保持
}
```

- 核心进程控制句柄，封装了与进程的所有交互通道
- 使用 `StdMutex` 保护内部状态，支持跨线程安全访问
- `Drop` 实现确保进程被正确终止

#### 3.1.3 SpawnedProcess

```rust
pub struct SpawnedProcess {
    pub session: ProcessHandle,                    // 进程控制句柄
    pub stdout_rx: mpsc::Receiver<Vec<u8>>,       // stdout 接收通道
    pub stderr_rx: mpsc::Receiver<Vec<u8>>,       // stderr 接收通道
    pub exit_rx: oneshot::Receiver<i32>,          // 退出码一次性接收
}
```

- 进程创建函数的返回值，包含所有与进程交互的端点
- stdout/stderr 分离设计，支持独立处理或合并

### 3.2 关键流程

#### 3.2.1 PTY 进程创建流程 (Unix)

```
spawn_pty_process()
    ↓
spawn_process_with_inherited_fds()
    ↓
[有 inherited_fds] ? spawn_process_preserving_fds() : spawn_process_portable()
    ↓
open_unix_pty(size) → libc::openpty() → (master_fd, slave_fd)
    ↓
设置 CLOEXEC 标志
    ↓
StdCommand::new(program)
    .stdin(Stdio::from(slave.try_clone()?))
    .stdout(Stdio::from(slave.try_clone()?))
    .stderr(Stdio::from(slave.try_clone()?))
    .pre_exec(|| {
        // 重置信号处理
        for signo in [SIGCHLD, SIGHUP, SIGINT, SIGQUIT, SIGTERM, SIGALRM] {
            libc::signal(signo, SIG_DFL);
        }
        // 清空信号掩码
        libc::sigprocmask(SIG_SETMASK, &empty_set, null_mut());
        // 创建新会话
        libc::setsid();
        // 设置控制终端
        libc::ioctl(0, TIOCSCTTY, 0);
        // 关闭非保留 FD
        close_inherited_fds_except(&inherited_fds);
    })
    ↓
command.spawn() → 启动子进程
    ↓
创建异步任务：
    - reader_handle: spawn_blocking 读取 master_fd → stdout_tx
    - writer_handle: tokio::spawn 从 writer_rx 写入 master_fd
    - wait_handle: spawn_blocking 等待子进程退出
    ↓
返回 SpawnedProcess { session, stdout_rx, stderr_rx, exit_rx }
```

#### 3.2.2 Pipe 进程创建流程

```
spawn_pipe_process()
    ↓
spawn_process_with_stdin_mode(program, args, cwd, env, arg0, PipeStdinMode::Piped, &[])
    ↓
Command::new(program)
    .pre_exec(|| {
        detach_from_tty()?;  // setsid 或 setpgid
        #[cfg(linux)] set_parent_death_signal(parent_pid)?;
        close_inherited_fds_except(&inherited_fds);
    })
    .stdin(Stdio::piped())
    .stdout(Stdio::piped())
    .stderr(Stdio::piped())
    ↓
command.spawn()
    ↓
创建异步任务：
    - writer_handle: 从 writer_rx 写入 stdin
    - stdout_handle: read_output_stream(stdout, stdout_tx)
    - stderr_handle: read_output_stream(stderr, stderr_tx)
    - reader_handle: 等待 stdout/stderr 任务完成
    - wait_handle: 等待子进程退出
    ↓
返回 SpawnedProcess
```

#### 3.2.3 进程终止流程

```
ProcessHandle::terminate()
    ↓
request_terminate() → killer.kill() → 发送 SIGKILL (Unix) / TerminateProcess (Windows)
    ↓
reader_handle.abort() → 中止 stdout 读取任务
    ↓
reader_abort_handles 中所有 handle.abort()
    ↓
writer_handle.abort() → 中止 stdin 写入任务
    ↓
wait_handle.abort() → 中止进程等待任务
```

### 3.3 Windows ConPTY 实现

Windows 平台使用从 WezTerm 项目适配的 ConPTY 实现：

#### 3.3.1 关键文件

| 文件 | 来源 | 功能 |
|------|------|------|
| `win/mod.rs` | WezTerm (MIT) | `WinChild` 结构体，实现 `Child` trait |
| `win/conpty.rs` | WezTerm (MIT) | `ConPtySystem` 实现 `PtySystem` trait |
| `win/psuedocon.rs` | WezTerm (MIT) | `PsuedoCon` 封装 Windows `CreatePseudoConsole` API |
| `win/procthreadattr.rs` | WezTerm (MIT) | 进程线程属性列表管理 |

#### 3.3.2 ConPTY 创建流程

```
ConPtySystem::openpty(size)
    ↓
create_conpty_handles(size)
    ↓
Pipe::new() → stdin/stdout 管道
    ↓
PsuedoCon::new(COORD { X: cols, Y: rows }, stdin.read, stdout.write)
    ↓
CONPTY.CreatePseudoConsole(size, input, output, PSEUDOCONSOLE_RESIZE_QUIRK, &mut hpc)
    ↓
返回 PtyPair { master: ConPtyMasterPty, slave: ConPtySlavePty }
```

#### 3.3.3 已知 Bug 修复

**Bug #13945**: `TerminateProcess` 返回值判断错误

```rust
// 修复前（错误）：
if res != 0 { Err(...) } else { Ok(()) }

// 修复后（正确）：
if res == 0 { Err(...) } else { Ok(()) }
// Win32 API: 非零表示成功，0 表示失败
```

### 3.4 进程组管理

#### 3.4.1 Unix 进程组控制

```rust
// 脱离控制终端（创建新会话）
pub fn detach_from_tty() -> io::Result<()> {
    let result = unsafe { libc::setsid() };
    if result == -1 {
        let err = io::Error::last_os_error();
        if err.raw_os_error() == Some(libc::EPERM) {
            return set_process_group();  // 已是组长，退而求其次
        }
        return Err(err);
    }
    Ok(())
}

// 设置进程组
pub fn set_process_group() -> io::Result<()> {
    let result = unsafe { libc::setpgid(0, 0) };
    // ...
}

// 杀死整个进程组
pub fn kill_process_group(process_group_id: u32) -> io::Result<()> {
    let pgid = process_group_id as libc::pid_t;
    let result = unsafe { libc::killpg(pgid, libc::SIGKILL) };
    // ...
}
```

#### 3.4.2 Linux 特有：父进程死亡信号

```rust
pub fn set_parent_death_signal(parent_pid: libc::pid_t) -> io::Result<()> {
    // 设置父进程死亡时接收 SIGTERM
    if unsafe { libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM) } == -1 {
        return Err(io::Error::last_os_error());
    }
    // 检查父进程是否已在 fork/exec 间退出
    if unsafe { libc::getppid() } != parent_pid {
        unsafe { libc::raise(libc::SIGTERM); }
    }
    Ok(())
}
```

---

## 4. 关键代码路径与文件引用

### 4.1 文件结构

```
codex-rs/utils/pty/
├── Cargo.toml              # 依赖：anyhow, portable-pty, tokio, libc/winapi
├── README.md               # API 文档与使用示例
├── BUILD.bazel             # Bazel 构建配置
└── src/
    ├── lib.rs              # 模块导出与公共 API
    ├── pty.rs              # PTY 进程创建（481 行）
    ├── pipe.rs             # Pipe 进程创建（294 行）
    ├── process.rs          # ProcessHandle 与输出合并（265 行）
    ├── process_group.rs    # 进程组管理（184 行）
    ├── tests.rs            # 单元测试（946 行）
    └── win/                # Windows 特定实现
        ├── mod.rs          # WinChild 实现（178 行）
        ├── conpty.rs       # ConPtySystem（190 行）
        ├── psuedocon.rs    # PseudoConsole API 封装（369 行）
        └── procthreadattr.rs # 进程线程属性（91 行）
```

### 4.2 核心代码路径

#### 4.2.1 PTY 创建入口

- **文件**: `src/pty.rs`
- **函数**: `spawn_process()` (line 102), `spawn_process_with_inherited_fds()` (line 115)
- **Unix 特有**: `spawn_process_preserving_fds()` (line 256), `open_unix_pty()` (line 409)

#### 4.2.2 Pipe 创建入口

- **文件**: `src/pipe.rs`
- **函数**: `spawn_process()` (line 253), `spawn_process_no_stdin()` (line 264)
- **内部**: `spawn_process_with_stdin_mode()` (line 98)

#### 4.2.3 进程控制

- **文件**: `src/process.rs`
- **结构**: `ProcessHandle` (line 73)
- **方法**: `writer_sender()` (line 120), `resize()` (line 143), `terminate()` (line 176)
- **函数**: `combine_output_receivers()` (line 224)

#### 4.2.4 进程组管理

- **文件**: `src/process_group.rs`
- **关键函数**: `detach_from_tty()`, `set_process_group()`, `kill_process_group()`, `set_parent_death_signal()`

### 4.3 调用方引用

| 调用方 | 文件 | 使用方式 |
|--------|------|----------|
| app-server | `command_exec.rs:266-279` | `spawn_pty_process()`, `spawn_pipe_process()`, `spawn_pipe_process_no_stdin()` |
| core/exec | `exec.rs:41-42` | `DEFAULT_OUTPUT_BYTES_CAP`, `kill_child_process_group()` |
| core/spawn | `spawn.rs:92-100` | `detach_from_tty()`, `set_parent_death_signal()` |
| core/shell_snapshot | `shell_snapshot.rs:286-288` | `detach_from_tty()` |
| core/unified_exec | `process_manager.rs:553-572` | `spawn_process_with_inherited_fds()`, `spawn_process_no_stdin_with_inherited_fds()` |
| core/unified_exec | `process.rs:21-22` | `ExecCommandSession`, `SpawnedPty` 别名 |

---

## 5. 依赖与外部交互

### 5.1 外部依赖

| Crate | 用途 | 版本 |
|-------|------|------|
| `anyhow` | 错误处理 | workspace |
| `portable-pty` | 跨平台 PTY 抽象 | workspace |
| `tokio` | 异步运行时 | workspace (features: io-util, macros, process, rt-multi-thread, sync, time) |
| `libc` | Unix 系统调用 | workspace (Unix only) |
| `winapi` | Windows API 绑定 | 0.3.9 (Windows only) |
| `filedescriptor` | 文件描述符抽象 | 0.8.3 (Windows only) |
| `shared_library` | 动态库加载 | 0.1.9 (Windows only) |
| `lazy_static` | 静态初始化 | workspace (Windows only) |
| `log` | 日志 | workspace (Windows only) |

### 5.2 与 portable-pty 的关系

```
portable-pty (外部 crate)
├── PtySystem trait ──→ 由 ConPtySystem (Windows) 或 native_pty_system (Unix) 实现
├── MasterPty trait ──→ ConPtyMasterPty / 原生实现
├── SlavePty trait ───→ ConPtySlavePty / 原生实现
└── Child trait ─────→ WinChild (Windows) / 原生实现
```

### 5.3 平台特定代码分布

| 平台 | 代码行数 | 主要文件 |
|------|----------|----------|
| Unix | ~400 行 | `pty.rs` (Unix 部分), `process_group.rs`, `pipe.rs` (Unix 部分) |
| Windows | ~800 行 | `win/*.rs`, `pty.rs` (Windows 部分), `pipe.rs` (Windows 部分) |
| 通用 | ~600 行 | `process.rs`, `lib.rs`, `tests.rs` |

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 进程泄漏风险

**风险描述**: 如果 `ProcessHandle` 被意外丢弃且 `Drop` 实现未能正确执行，可能导致僵尸进程。

**缓解措施**:
- `Drop` 实现调用 `terminate()` 强制清理
- 使用 `kill_on_drop(true)` 在 tokio 任务中
- 进程组级别的 `kill_process_group` 确保后代进程也被终止

#### 6.1.2 文件描述符泄漏

**风险描述**: `inherited_fds` 功能在 Unix 上需要遍历 `/dev/fd`，如果目录权限受限可能失败。

**代码位置**: `src/pty.rs:453-480`

```rust
pub(crate) fn close_inherited_fds_except(preserved_fds: &[RawFd]) {
    if let Ok(dir) = std::fs::read_dir("/dev/fd") {
        // ... 遍历并关闭 FD
    }
}
```

#### 6.1.3 Windows ConPTY 兼容性

**风险描述**: ConPTY 需要 Windows 10 1809 (Build 17763) 或更高版本。

**检测**: `conpty_supported()` 函数检查构建号

#### 6.1.4 信号竞争条件

**风险描述**: `set_parent_death_signal` 中检查 `getppid()` 与 `prctl` 之间可能存在竞争。

**代码**: `src/process_group.rs:27-38`

### 6.2 边界条件

| 边界 | 行为 | 测试覆盖 |
|------|------|----------|
| 空程序名 | `bail!("missing program for PTY spawn")` | 是 |
| 零行列数 | 协议层拒绝 (rows/cols > 0) | 是 (app-server) |
| 输出上限 | `DEFAULT_OUTPUT_BYTES_CAP = 1MB` | 是 |
| 进程数上限 | `MAX_UNIFIED_EXEC_PROCESSES` (core 层控制) | 是 |
| 超时处理 | `IO_DRAIN_TIMEOUT_MS = 2s` | 是 |

### 6.3 改进建议

#### 6.3.1 代码结构优化

1. **模块化拆分**: `pty.rs` 481 行已接近 AGENTS.md 建议的 500 行上限，可考虑将 Unix/Windows 实现分离到子模块
2. **错误类型细化**: 当前大量使用 `anyhow::Result`，可考虑定义专门的错误枚举以提高可诊断性
3. **文档完善**: 增加更多内部实现注释，特别是平台特定的行为差异

#### 6.3.2 功能增强

1. **PTY 状态查询**: 当前无法查询 PTY 是否处于 raw mode 或 cooked mode
2. **环境变量过滤**: 提供标准的环境变量清理功能（类似 `UNIFIED_EXEC_ENV`）
3. **执行时间统计**: 在 `ProcessHandle` 中内置启动时间记录

#### 6.3.3 测试覆盖

1. **Windows 测试**: 当前测试主要在 Unix 上运行，Windows 特定测试较少
2. **并发压力测试**: 大规模并发进程创建/销毁的稳定性测试
3. **资源泄漏检测**: 使用 `valgrind` 或类似工具检测 FD 泄漏

#### 6.3.4 依赖更新

1. **portable-pty**: 评估是否可以直接使用 `tokio-pty` 等纯 Rust 实现减少依赖
2. **winapi**: 考虑迁移到 `windows-rs` crate（微软官方维护）

### 6.4 安全考虑

1. **命令注入**: 本 crate 不负责命令解析，调用方需确保参数正确转义
2. **环境变量泄漏**: `env_clear()` 确保子进程不继承父进程环境，但调用方传入的 `env` 仍需谨慎审查
3. **FD 继承**: `inherited_fds` 功能应严格限制，避免敏感 FD 泄露给子进程

---

## 7. 附录：测试分析

### 7.1 测试覆盖

`src/tests.rs` 包含 946 行测试代码，主要测试场景：

| 测试 | 描述 |
|------|------|
| `pty_python_repl_emits_output_and_exits` | PTY 模式 Python REPL 交互测试 |
| `pipe_process_round_trips_stdin` | Pipe 模式 stdin/stdout 回环测试 |
| `pipe_process_detaches_from_parent_session` | 进程组分离验证 |
| `pipe_and_pty_share_interface` | 接口一致性验证 |
| `pipe_drains_stderr_without_stdout_activity` | stderr 独立排空测试 |
| `pipe_process_can_expose_split_stdout_and_stderr` | stdout/stderr 分离测试 |
| `pipe_terminate_aborts_detached_readers` | 终止后读取任务中止验证 |
| `pty_terminate_kills_background_children_in_same_process_group` | 进程组级终止验证 |
| `pty_spawn_can_preserve_inherited_fds` | FD 继承功能测试 |
| `pty_preserving_inherited_fds_keeps_python_repl_running` | FD 继承下 REPL 稳定性 |
| `pty_spawn_with_inherited_fds_reports_exec_failures` | exec 失败错误报告 |
| `pty_spawn_with_inherited_fds_supports_resize` | FD 继承下 resize 功能 |
| `pipe_spawn_no_stdin_can_preserve_inherited_fds` | Pipe 模式 FD 继承 |

### 7.2 测试工具函数

- `collect_output_until_exit()`: 收集输出直到进程退出或超时
- `wait_for_python_repl_ready()`: 等待 Python REPL 就绪标记
- `wait_for_marker_pid()`: 从输出中提取 PID
- `process_exists()`: 检查进程是否存在 (Unix)

---

*文档生成时间: 2026-03-22*
*基于代码版本: codex-rs/utils/pty 当前 HEAD*
