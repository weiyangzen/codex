# pipe.rs 研究文档

## 场景与职责

`pipe.rs` 实现了基于标准管道（stdin/stdout/stderr）的非交互式进程创建和管理功能。这是 `codex-utils-pty` crate 的两大核心后端之一（另一个是 `pty.rs`）。

### 核心职责

1. **进程创建**：使用 `tokio::process::Command` 启动子进程，配置管道化的标准输入输出
2. **异步 I/O 管理**：将子进程的同步 I/O 转换为异步通道（`mpsc`）
3. **进程终止**：支持进程组和单个进程的终止（跨平台实现）
4. **FD 继承控制**（Unix）：支持在 exec 时保留指定的文件描述符

### 使用场景

- 执行无需交互的命令行工具
- 需要分别获取 stdout 和 stderr 的场景（PTY 会合并两者）
- 不需要终端仿真功能的批处理任务

## 功能点目的

### 1. 主要公共函数

| 函数 | 用途 |
|------|------|
| `spawn_process` | 创建带可写 stdin 的管道进程 |
| `spawn_process_no_stdin` | 创建 stdin 立即关闭的管道进程 |
| `spawn_process_no_stdin_with_inherited_fds` | 支持 FD 继承的无 stdin 进程 |

### 2. 内部实现结构

```rust
// 终止器实现
struct PipeChildTerminator {
    #[cfg(windows)] pid: u32,
    #[cfg(unix)] process_group_id: u32,
}

// stdin 模式枚举
enum PipeStdinMode {
    Piped,  // 保持 stdin 开放
    Null,   // 立即关闭 stdin
}
```

### 3. 核心功能模块

| 功能 | 实现 |
|------|------|
| 输出读取 | `read_output_stream()` - 异步读取到 mpsc 通道 |
| 输入写入 | 专用 tokio 任务，通过 `mpsc::Receiver` 接收数据 |
| 进程等待 | `spawn_blocking` 任务等待子进程退出 |
| 进程终止 | `ChildTerminator` trait 实现，跨平台 kill |

## 具体技术实现

### 1. 进程创建流程

```rust
async fn spawn_process_with_stdin_mode(
    program: &str,
    args: &[String],
    cwd: &Path,
    env: &HashMap<String, String>,
    arg0: &Option<String>,
    stdin_mode: PipeStdinMode,
    inherited_fds: &[i32],
) -> Result<SpawnedProcess>
```

**详细流程：**

```
1. 参数验证
   └── program.is_empty() ? bail!("missing program")

2. 命令构建 (tokio::process::Command)
   ├── 设置程序路径
   ├── Unix: arg0 覆盖 (如果提供)
   ├── pre_exec 钩子 (Unix)
   │   ├── detach_from_tty() - 脱离控制终端
   │   ├── set_parent_death_signal() - 父进程死亡信号 (Linux)
   │   └── close_inherited_fds_except() - 关闭非保留 FD
   ├── current_dir(cwd)
   ├── env_clear() + 设置自定义环境
   ├── 参数设置
   └── stdio 配置
       ├── stdin: Piped / Null
       ├── stdout: Piped
       └── stderr: Piped

3. 进程启动
   └── command.spawn()?

4. 通道和任务创建
   ├── writer_tx/rx: mpsc(128) - stdin 写入
   ├── stdout_tx/rx: mpsc(128) - stdout 读取
   ├── stderr_tx/rx: mpsc(128) - stderr 读取
   ├── writer_handle: tokio::spawn - 写入任务
   ├── stdout_handle: tokio::spawn - stdout 读取任务
   ├── stderr_handle: tokio::spawn - stderr 读取任务
   ├── reader_handle: tokio::spawn - 合并 reader 等待
   └── wait_handle: tokio::spawn - 进程等待任务

5. ProcessHandle 组装
   └── ProcessHandle::new(...)
```

### 2. Unix pre_exec 钩子详解

```rust
#[cfg(unix)]
unsafe {
    command.pre_exec(move || {
        // 1. 脱离控制终端，创建新会话
        crate::process_group::detach_from_tty()?;
        
        // 2. Linux: 设置父进程死亡信号
        #[cfg(target_os = "linux")]
        crate::process_group::set_parent_death_signal(parent_pid)?;
        
        // 3. 关闭非保留的文件描述符
        crate::pty::close_inherited_fds_except(&inherited_fds);
        Ok(())
    });
}
```

**关键系统调用：**
- `setsid()` - 创建新会话，脱离控制终端
- `setpgid(0, 0)` - 创建新进程组（`setsid` 失败时的回退）
- `prctl(PR_SET_PDEATHSIG, SIGTERM)` - 父进程死亡时接收 SIGTERM
- `fcntl(FD_CLOEXEC)` 检查 - 保留 CLOEXEC 描述符用于错误报告

### 3. 异步 I/O 架构

**输入流（stdin）：**
```rust
let writer_handle = if let Some(stdin) = stdin {
    let writer = Arc::new(tokio::sync::Mutex::new(stdin));
    tokio::spawn(async move {
        while let Some(bytes) = writer_rx.recv().await {
            let mut guard = writer.lock().await;
            let _ = guard.write_all(&bytes).await;
            let _ = guard.flush().await;
        }
    })
}
```

**输出流（stdout/stderr）：**
```rust
async fn read_output_stream<R>(mut reader: R, output_tx: mpsc::Sender<Vec<u8>>)
where R: AsyncRead + Unpin,
{
    let mut buf = vec![0u8; 8_192];  // 8KB 缓冲区
    loop {
        match reader.read(&mut buf).await {
            Ok(0) => break,  // EOF
            Ok(n) => { let _ = output_tx.send(buf[..n].to_vec()).await; }
            Err(ref e) if e.kind() == ErrorKind::Interrupted => continue,
            Err(_) => break,
        }
    }
}
```

### 4. 进程终止实现

**Unix 实现：**
```rust
impl ChildTerminator for PipeChildTerminator {
    fn kill(&mut self) -> io::Result<()> {
        crate::process_group::kill_process_group(self.process_group_id)
        // 使用 SIGKILL 终止整个进程组
    }
}
```

**Windows 实现：**
```rust
#[cfg(windows)]
fn kill_process(pid: u32) -> io::Result<()> {
    unsafe {
        let handle = winapi::um::processthreadsapi::OpenProcess(
            winapi::um::winnt::PROCESS_TERMINATE, 0, pid,
        );
        if handle.is_null() { return Err(io::Error::last_os_error()); }
        let success = winapi::um::processthreadsapi::TerminateProcess(handle, 1);
        let err = io::Error::last_os_error();
        winapi::um::handleapi::CloseHandle(handle);
        if success == 0 { Err(err) } else { Ok(()) }
    }
}
```

## 关键代码路径与文件引用

### 1. 文件依赖图

```
pipe.rs
  ├── 外部依赖
  │   ├── anyhow::Result, anyhow::bail
  │   ├── tokio::io::*, tokio::process::Command, tokio::sync::*
  │   └── libc (Unix)
  │
  ├── 内部依赖
  │   ├── process.rs
  │   │   ├── ChildTerminator (trait)
  │   │   ├── ProcessHandle
  │   │   └── SpawnedProcess
  │   └── process_group.rs (Unix)
  │       ├── detach_from_tty()
  │       ├── set_parent_death_signal()
  │       └── kill_process_group()
  │
  └── 被 lib.rs 引用
      └── re-export 为 spawn_pipe_process, spawn_pipe_process_no_stdin
```

### 2. 关键代码位置

| 功能 | 行号 | 代码 |
|------|------|------|
| 终止器定义 | 27-51 | `PipeChildTerminator` struct + `ChildTerminator` impl |
| Windows kill | 53-73 | `kill_process()` 函数 |
| 输出读取 | 75-90 | `read_output_stream()` 函数 |
| stdin 模式 | 92-96 | `PipeStdinMode` enum |
| 核心创建逻辑 | 98-250 | `spawn_process_with_stdin_mode()` 函数 |
| 公共 API | 252-294 | `spawn_process()`, `spawn_process_no_stdin()` 等 |

### 3. 调用链

**创建管道进程：**
```
lib.rs:spawn_pipe_process()
  └── pipe.rs:spawn_process()
      └── pipe.rs:spawn_process_with_stdin_mode()
          ├── tokio::process::Command::spawn()
          ├── 创建 writer/stdout/stderr 通道
          ├── 启动 writer_handle (stdin 写入任务)
          ├── 启动 stdout_handle (stdout 读取任务)
          ├── 启动 stderr_handle (stderr 读取任务)
          ├── 启动 reader_handle (合并 reader 等待)
          ├── 启动 wait_handle (进程退出等待)
          └── process.rs:ProcessHandle::new()
```

**终止管道进程：**
```
ProcessHandle::terminate()
  └── PipeChildTerminator::kill()
      ├── Unix: process_group.rs:kill_process_group()
      │   └── libc::killpg(pgid, SIGKILL)
      └── Windows: kill_process()
          └── winapi::TerminateProcess()
```

## 依赖与外部交互

### 1. 标准库和外部 Crate

```rust
use std::collections::HashMap;
use std::io;
use std::io::ErrorKind;
use std::path::Path;
use std::process::Stdio;
use std::sync::atomic::AtomicBool;
use std::sync::Arc;
use std::sync::Mutex as StdMutex;

use anyhow::Result;
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWriteExt, BufReader};
use tokio::process::Command;
use tokio::sync::{mpsc, oneshot};
use tokio::task::JoinHandle;

#[cfg(target_os = "linux")]
use libc;
```

### 2. 内部模块交互

| 依赖模块 | 导入内容 | 用途 |
|----------|----------|------|
| `process.rs` | `ChildTerminator`, `ProcessHandle`, `SpawnedProcess` | 进程管理和句柄共享 |
| `process_group.rs` | `kill_process_group`, `detach_from_tty`, `set_parent_death_signal` | Unix 进程组管理 |
| `pty.rs` | `close_inherited_fds_except` | FD 清理（Unix） |

### 3. 平台特定代码

**Unix 特有：**
- `pre_exec` 钩子设置
- `process_group_id` 使用
- `libc` 依赖

**Windows 特有：**
- `pid` 直接使用
- `winapi` 调用 `OpenProcess`, `TerminateProcess`, `CloseHandle`

## 风险、边界与改进建议

### 1. 潜在风险

| 风险 | 描述 | 严重程度 |
|------|------|----------|
| 僵尸进程 | 如果 `wait_handle` 被中止，子进程可能变成僵尸 | 中 |
| 信号竞争 | `set_parent_death_signal` 和 `getppid` 检查之间存在竞态窗口 | 低 |
| FD 泄漏 | `/dev/fd` 读取失败时，`close_inherited_fds_except` 无法执行 | 低 |
| 缓冲区溢出 | `read_output_stream` 使用固定 8KB 缓冲区，大流量可能积压 | 低 |

### 2. 边界情况处理

```rust
// 1. 空程序名检查
if program.is_empty() {
    anyhow::bail!("missing program for pipe spawn");
}

// 2. PID 获取失败
let pid = child.id()
    .ok_or_else(|| io::Error::other("missing child pid"))?;

// 3. 信号中断重试
Err(ref e) if e.kind() == ErrorKind::Interrupted => continue,

// 4. 通道关闭处理
let (writer_tx, writer_rx) = mpsc::channel::<Vec<u8>>(128);
// 如果 stdin 不可用，writer_rx 被立即 drop
```

### 3. 改进建议

1. **错误处理增强**
   ```rust
   // 当前：忽略写入错误
   let _ = guard.write_all(&bytes).await;
   
   // 建议：添加日志或错误传播
   if let Err(e) = guard.write_all(&bytes).await {
       log::warn!("Failed to write to stdin: {}", e);
   }
   ```

2. **缓冲区大小可配置**
   ```rust
   // 当前硬编码 8KB
   let mut buf = vec![0u8; 8_192];
   
   // 建议：通过参数或常量配置
   const PIPE_BUFFER_SIZE: usize = 8 * 1024;
   ```

3. **优雅关闭支持**
   ```rust
   // 当前：直接 SIGKILL
   // 建议：先尝试 SIGTERM，超时后 SIGKILL
   pub fn terminate_graceful(&self, timeout: Duration) -> io::Result<()>
   ```

4. **Windows 进程组支持**
   ```rust
   // 当前 Windows 只 kill 单个进程
   // 建议：使用 Job Object 实现进程组管理
   ```

5. **内存优化**
   ```rust
   // 当前：每次读取都分配新 Vec
   let _ = output_tx.send(buf[..n].to_vec()).await;
   
   // 建议：考虑使用对象池或 bytes crate
   ```

### 4. 测试建议

| 测试场景 | 验证点 |
|----------|--------|
| 大输出量 | 验证 8KB 缓冲区不会导致死锁 |
| 快速连续写入 | 验证 128 容量通道不会溢出 |
| 进程提前退出 | 验证 reader 任务正确处理 EOF |
| 权限不足 | 验证错误信息清晰 |
| 大量并发 | 验证系统 FD 限制处理 |
