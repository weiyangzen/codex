# pty.rs 研究文档

## 场景与职责

`pty.rs` 实现了基于伪终端（Pseudo Terminal, PTY）的交互式进程创建和管理功能。这是 `codex-utils-pty` crate 的两大核心后端之一（另一个是 `pipe.rs`），专门用于需要终端仿真功能的场景。

### 核心职责

1. **PTY 进程创建**：使用 `portable-pty` 或原生 Unix API 创建 PTY 并启动进程
2. **终端尺寸管理**：支持创建时指定和运行时调整终端大小
3. **文件描述符继承**（Unix）：支持在 exec 时保留指定的文件描述符
4. **跨平台抽象**：统一 Unix 和 Windows（ConPTY）的实现

### 使用场景

- 运行交互式 shell（bash, zsh, fish）
- 启动需要终端功能的程序（vim, less, Python REPL）
- 需要处理 ANSI 转义序列的终端应用
- 需要终端尺寸调整功能的场景

## 功能点目的

### 1. 主要公共函数

| 函数 | 用途 |
|------|------|
| `conpty_supported` | 检测 Windows ConPTY 支持 |
| `spawn_process` | 标准 PTY 进程创建 |
| `spawn_process_with_inherited_fds` | 支持 FD 继承的 PTY 创建 |

### 2. 内部实现结构

```rust
// 终止器实现
struct PtyChildTerminator {
    killer: Box<dyn portable_pty::ChildKiller + Send + Sync>,
    #[cfg(unix)] process_group_id: Option<u32>,
}

// Unix 原始 PID 终止器（FD 保留模式）
#[cfg(unix)]
struct RawPidTerminator {
    process_group_id: u32,
}
```

### 3. 创建模式

| 模式 | 函数 | 适用平台 | 特点 |
|------|------|----------|------|
| 标准模式 | `spawn_process_portable` | 全平台 | 使用 `portable-pty` crate |
| FD 保留模式 | `spawn_process_preserving_fds` | Unix | 原生 `openpty` + `pre_exec` |

## 具体技术实现

### 1. 标准 PTY 创建流程

```rust
async fn spawn_process_portable(
    program: &str,
    args: &[String],
    cwd: &Path,
    env: &HashMap<String, String>,
    arg0: &Option<String>,
    size: TerminalSize,
) -> Result<SpawnedProcess>
```

**详细流程：**

```
1. 参数验证
   └── program.is_empty() ? bail!("missing program for PTY spawn")

2. 创建 PTY 系统
   └── platform_native_pty_system()
       ├── Windows: win::ConPtySystem
       └── Unix: portable_pty::native_pty_system()

3. 打开 PTY 对
   └── pty_system.openpty(size.into())
       ├── Master: 用于父进程读写
       └── Slave: 用于子进程标准输入输出

4. 构建命令
   └── CommandBuilder::new(arg0.unwrap_or(program))
       ├── cwd(cwd)
       ├── env_clear() + 自定义环境
       └── args...

5. 启动子进程
   └── pair.slave.spawn_command(command_builder)?
       └── 返回 Child 对象

6. 提取进程信息
   ├── Unix: process_group_id = child.process_id()  // PID == PGID
   └── killer = child.clone_killer()

7. 创建 I/O 任务
   ├── reader_handle: spawn_blocking - 从 master 读取
   ├── writer_handle: spawn - 向 master 写入
   └── wait_handle: spawn_blocking - 等待进程退出

8. 组装 ProcessHandle
   └── ProcessHandle::new(..., Some(PtyHandles { _slave, _master }))
```

### 2. Unix FD 保留模式

```rust
#[cfg(unix)]
async fn spawn_process_preserving_fds(
    program: &str,
    args: &[String],
    cwd: &Path,
    env: &HashMap<String, String>,
    arg0: &Option<String>,
    size: TerminalSize,
    inherited_fds: &[RawFd],
) -> Result<SpawnedProcess>
```

**与标准模式的区别：**

| 方面 | 标准模式 | FD 保留模式 |
|------|----------|-------------|
| PTY 创建 | `portable-pty` | 原生 `libc::openpty` |
| 命令构建 | `CommandBuilder` | `std::process::Command` |
| pre_exec | 无 | 完整的信号和会话设置 |
| Master 句柄 | `Resizable` | `Opaque`（原始 FD） |

**pre_exec 钩子详解：**

```rust
.pre_exec(move || {
    // 1. 重置信号处理为默认
    for signo in &[SIGCHLD, SIGHUP, SIGINT, SIGQUIT, SIGTERM, SIGALRM] {
        libc::signal(*signo, libc::SIG_DFL);
    }
    
    // 2. 清空信号掩码
    let empty_set: libc::sigset_t = std::mem::zeroed();
    libc::sigprocmask(libc::SIG_SETMASK, &empty_set, std::ptr::null_mut());
    
    // 3. 创建新会话
    if libc::setsid() == -1 {
        return Err(std::io::Error::last_os_error());
    }
    
    // 4. 设置控制终端（stdin 现在是 PTY slave）
    #[allow(clippy::cast_lossless)]
    if libc::ioctl(0, libc::TIOCSCTTY as _, 0) == -1 {
        return Err(std::io::Error::last_os_error());
    }
    
    // 5. 关闭非保留 FD
    close_inherited_fds_except(&inherited_fds);
    Ok(())
})
```

### 3. Unix PTY 创建

```rust
#[cfg(unix)]
fn open_unix_pty(size: TerminalSize) -> Result<(File, File)> {
    let mut master: RawFd = -1;
    let mut slave: RawFd = -1;
    let mut size = libc::winsize { ... };
    
    // 创建 PTY 对
    let result = unsafe {
        libc::openpty(
            &mut master,
            &mut slave,
            std::ptr::null_mut(),  // name
            std::ptr::null_mut(),  // termios
            std::ptr::addr_of_mut!(size),  // winsize
        )
    };
    
    if result != 0 {
        anyhow::bail!("failed to openpty: {:?}", std::io::Error::last_os_error());
    }
    
    // 设置 CLOEXEC 标志
    set_cloexec(master)?;
    set_cloexec(slave)?;
    
    Ok(unsafe { (File::from_raw_fd(master), File::from_raw_fd(slave)) })
}
```

### 4. 文件描述符清理

```rust
#[cfg(unix)]
pub(crate) fn close_inherited_fds_except(preserved_fds: &[RawFd]) {
    if let Ok(dir) = std::fs::read_dir("/dev/fd") {
        let mut fds = Vec::new();
        for entry in dir {
            // 解析 FD 编号
            let num = entry.ok()
                .map(|e| e.file_name())
                .and_then(|n| n.into_string().ok())
                .and_then(|n| n.parse::<RawFd>().ok());
            
            if let Some(num) = num {
                // 跳过标准 FD 和保留 FD
                if num <= 2 || preserved_fds.contains(&num) {
                    continue;
                }
                
                // 跳过已设置 CLOEXEC 的 FD
                let flags = unsafe { libc::fcntl(num, libc::F_GETFD) };
                if flags == -1 || flags & libc::FD_CLOEXEC != 0 {
                    continue;
                }
                
                fds.push(num);
            }
        }
        
        // 关闭收集到的 FD
        for fd in fds {
            unsafe { libc::close(fd); }
        }
    }
}
```

**设计考虑：**
- 保留 FD 0/1/2（标准输入输出错误）
- 保留调用者指定的 FD
- 保留已设置 `CLOEXEC` 的 FD（用于错误报告管道）

### 5. 异步 I/O 架构

**读取任务（spawn_blocking）：**
```rust
let reader_handle: JoinHandle<()> = tokio::task::spawn_blocking(move || {
    let mut buf = [0u8; 8_192];
    loop {
        match reader.read(&mut buf) {
            Ok(0) => break,  // EOF
            Ok(n) => {
                let _ = stdout_tx.blocking_send(buf[..n].to_vec());
            }
            Err(ref e) if e.kind() == ErrorKind::Interrupted => continue,
            Err(ref e) if e.kind() == ErrorKind::WouldBlock => {
                std::thread::sleep(Duration::from_millis(5));
                continue;
            }
            Err(_) => break,
        }
    }
});
```

**写入任务（spawn）：**
```rust
let writer_handle: JoinHandle<()> = tokio::spawn({
    let writer = Arc::clone(&writer);
    async move {
        while let Some(bytes) = writer_rx.recv().await {
            let mut guard = writer.lock().await;
            use std::io::Write;
            let _ = guard.write_all(&bytes);
            let _ = guard.flush();
        }
    }
});
```

**关键区别：**
- 读取使用 `spawn_blocking`：因为 `portable-pty` 的 reader 是同步的
- 写入使用 `spawn`：使用 `tokio::sync::Mutex` 保护异步写入

### 6. 进程终止策略

```rust
impl ChildTerminator for PtyChildTerminator {
    fn kill(&mut self) -> std::io::Result<()> {
        #[cfg(unix)]
        if let Some(process_group_id) = self.process_group_id {
            // 先尝试进程组 SIGKILL
            let process_group_kill_result =
                crate::process_group::kill_process_group(process_group_id);
            // 再尝试直接子进程 killer
            let child_kill_result = self.killer.kill();
            
            // 合并结果逻辑
            return match child_kill_result {
                Ok(()) => Ok(()),
                Err(err) if err.kind() == ErrorKind::NotFound => process_group_kill_result,
                Err(err) => process_group_kill_result.or(Err(err)),
            };
        }
        
        self.killer.kill()
    }
}
```

**双重终止策略原因：**
- `process_group_kill`：终止整个进程组（包括孙子进程）
- `killer.kill()`：直接终止子进程（处理 PGID 缓存过期的情况）

## 关键代码路径与文件引用

### 1. 文件依赖图

```
pty.rs
  ├── 外部依赖
  │   ├── portable_pty::{native_pty_system, CommandBuilder, MasterPty, PtySize, SlavePty}
  │   ├── tokio::sync::{mpsc, oneshot}
  │   ├── tokio::task::JoinHandle
  │   ├── anyhow::Result
  │   └── libc (Unix)
  │
  ├── 内部依赖
  │   └── process.rs
  │       ├── ChildTerminator (trait)
  │       ├── ProcessHandle, SpawnedProcess, TerminalSize
  │       └── PtyHandles, PtyMasterHandle
  │
  ├── 被 lib.rs 使用
  │   ├── re-export: spawn_process → spawn_pty_process
  │   ├── re-export: conpty_supported
  │   └── re-export: RawConPty (Windows)
  │
  └── 被 pipe.rs 使用
      └── close_inherited_fds_except() (Unix)
```

### 2. 关键代码位置

| 功能 | 行号 | 代码 |
|------|------|------|
| conpty_supported | 38-48 | 平台检测 |
| PtyChildTerminator | 50-75 | 终止器实现 |
| RawPidTerminator | 77-87 | Unix 原始终止器 |
| platform_native_pty_system | 89-99 | 平台 PTY 系统选择 |
| spawn_process | 101-111 | 公共 API |
| spawn_process_with_inherited_fds | 113-138 | FD 保留入口 |
| spawn_process_portable | 140-253 | 标准模式实现 |
| spawn_process_preserving_fds | 255-406 | FD 保留模式实现 |
| open_unix_pty | 408-437 | Unix PTY 创建 |
| set_cloexec | 439-450 | FD 标志设置 |
| close_inherited_fds_except | 452-481 | FD 清理 |

### 3. 调用链

**创建 PTY 进程（标准模式）：**
```
lib.rs:spawn_pty_process()
  └── pty.rs:spawn_process()
      └── pty.rs:spawn_process_portable()
          ├── platform_native_pty_system()
          ├── pty_system.openpty(size)
          ├── CommandBuilder::new()
          ├── pair.slave.spawn_command()
          ├── 创建 reader/writer/wait 任务
          └── ProcessHandle::new()
```

**创建 PTY 进程（FD 保留模式）：**
```
lib.rs:spawn_pty_process() [with inherited_fds]
  └── pty.rs:spawn_process_with_inherited_fds()
      └── pty.rs:spawn_process_preserving_fds()
          ├── open_unix_pty()
          ├── StdCommand::new()
          ├── pre_exec 钩子设置
          ├── command.spawn()
          ├── 创建 reader/writer/wait 任务
          └── ProcessHandle::new()
```

**终止 PTY 进程：**
```
ProcessHandle::terminate()
  └── PtyChildTerminator::kill()
      ├── Unix: process_group::kill_process_group() + killer.kill()
      └── Windows: killer.kill()
```

## 依赖与外部交互

### 1. 外部 Crate

```rust
use std::collections::HashMap;
use std::io::ErrorKind;
use std::path::Path;
use std::sync::atomic::AtomicBool;
use std::sync::Arc;
use std::sync::Mutex as StdMutex;
use std::time::Duration;

use anyhow::Result;
use portable_pty::{CommandBuilder, MasterPty, PtySize, SlavePty};
use tokio::sync::{mpsc, oneshot};
use tokio::task::JoinHandle;

#[cfg(not(windows))]
use portable_pty::native_pty_system;

#[cfg(unix)]
use std::fs::File;
use std::os::fd::{AsRawFd, FromRawFd, RawFd};
use std::os::unix::process::CommandExt;
use std::process::Command as StdCommand;
use std::process::Stdio;
```

### 2. 平台特定代码

**Unix 特有：**
- `open_unix_pty()` - 使用 `libc::openpty`
- `set_cloexec()` - 使用 `fcntl`
- `close_inherited_fds_except()` - 遍历 `/dev/fd`
- `spawn_process_preserving_fds()` - 完整 FD 保留实现
- `RawPidTerminator` - 原始 PID 终止器

**Windows 特有：**
- `win::ConPtySystem` - Windows ConPTY 系统
- `RawConPty` - 原始 ConPTY 句柄导出

**通用代码：**
- `spawn_process_portable()` - 使用 `portable-pty`
- `PtyChildTerminator` - 包装 `portable-pty::ChildKiller`

### 3. 消费者

| 消费者 | 使用内容 |
|--------|----------|
| `lib.rs` | re-export 公共 API |
| `pipe.rs` | `close_inherited_fds_except()` |
| `command_exec.rs` | `spawn_pty_process()` |

## 风险、边界与改进建议

### 1. 潜在风险

| 风险 | 描述 | 严重程度 |
|------|------|----------|
| FD 泄漏 | `/dev/fd` 读取失败时无法清理 FD | 低 |
| 竞态条件 | `setsid` 和 `TIOCSCTTY` 之间可能有信号干扰 | 低 |
| 缓冲区阻塞 | `spawn_blocking` 读取任务可能阻塞线程池 | 中 |
| PTY 句柄泄漏 | Windows 需要保留 `_slave`，Unix 不需要 | 已处理 |
| 进程组缓存过期 | `process_group_id` 缓存可能在长时间运行后失效 | 中 |

### 2. 边界情况

```rust
// 1. 空程序名检查
if program.is_empty() {
    anyhow::bail!("missing program for PTY spawn");
}

// 2. WouldBlock 处理
Err(ref e) if e.kind() == ErrorKind::WouldBlock => {
    std::thread::sleep(Duration::from_millis(5));
    continue;
}

// 3. Windows 保留 slave 句柄
_slave: if cfg!(windows) { Some(pair.slave) } else { None }

// 4. 非 Unix 平台忽略 inherited_fds
#[cfg(not(unix))]
let _ = inherited_fds;
```

### 3. 改进建议

1. **读取任务优化**
   ```rust
   // 当前：固定 5ms 睡眠
   // 建议：使用 epoll/kqueue 异步通知
   // 或使用 tokio::io::unix::AsyncFd
   ```

2. **错误处理细化**
   ```rust
   // 当前：忽略写入错误
   let _ = guard.write_all(&bytes);
   
   // 建议：添加日志或错误传播
   ```

3. **FD 清理优化**
   ```rust
   // 当前：遍历 /dev/fd
   // 建议：使用 close_range 系统调用（Linux 5.9+）
   #[cfg(target_os = "linux")]
   unsafe { libc::close_range(3, !0u, libc::CLOSE_RANGE_CLOEXEC); }
   ```

4. **PTY 尺寸默认**
   ```rust
   // 当前：TerminalSize::default() 在 process.rs 中定义
   // 建议：在 pty.rs 中定义 PTY 特定的默认值
   ```

5. **信号处理文档**
   ```rust
   // 建议：添加更多注释说明为什么重置这些特定信号
   for signo in &[SIGCHLD, SIGHUP, SIGINT, SIGQUIT, SIGTERM, SIGALRM] {
       libc::signal(*signo, libc::SIG_DFL);
   }
   ```

### 4. 安全考虑

1. **pre_exec 安全**：`pre_exec` 中的代码必须是异步信号安全的
2. **FD 继承**：`inherited_fds` 功能需谨慎使用，避免泄漏敏感资源
3. **TTY 劫持**：`TIOCSCTTY` 可能受到 TTY 劫持攻击（虽然在此场景中风险较低）

### 5. 测试建议

| 测试场景 | 验证点 |
|----------|--------|
| Python REPL 交互 | 验证双向通信正常 |
| vim 启动 | 验证终端功能完整 |
| 尺寸调整 | 验证 `stty size` 反映变化 |
| FD 继承 | 验证保留的 FD 可用 |
| 大量输出 | 验证 8KB 缓冲区不阻塞 |
| 快速终止 | 验证无资源泄漏 |
| 权限不足 | 验证错误信息清晰 |
