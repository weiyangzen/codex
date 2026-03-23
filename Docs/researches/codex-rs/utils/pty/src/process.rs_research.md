# process.rs 研究文档

## 场景与职责

`process.rs` 是 `codex-utils-pty` crate 的核心共享模块，定义了 PTY 和 Pipe 两种进程创建模式共同使用的类型和 trait。它是连接底层平台特定实现和上层公共 API 的桥梁。

### 核心职责

1. **进程句柄抽象**：`ProcessHandle` 提供统一的进程操作接口（写入、终止、调整大小、状态查询）
2. **进程生命周期管理**：协调 reader/writer/wait 任务的创建和中止
3. **PTY 句柄管理**：`PtyHandles` 和 `PtyMasterHandle` 确保 PTY 资源正确保留
4. **输出合并**：`combine_output_receivers` 将 stdout/stderr 合并为单一广播流

### 设计哲学

- **统一接口**：无论底层是 PTY 还是 Pipe，调用者使用相同的 `ProcessHandle`
- **资源安全**：通过 `Drop` 实现确保进程终止和任务清理
- **跨平台兼容**：使用条件编译处理 Unix/Windows 差异

## 功能点目的

### 1. 核心类型

| 类型 | 用途 |
|------|------|
| `ProcessHandle` | 进程操作的主要接口，包含所有控制通道 |
| `SpawnedProcess` | 进程创建后的完整返回值 |
| `TerminalSize` | 终端尺寸配置（行/列） |
| `PtyHandles` | PTY 主从句柄的包装（防止提前释放） |
| `PtyMasterHandle` | PTY 主设备的抽象（支持调整大小） |

### 2. 核心 Trait

```rust
pub(crate) trait ChildTerminator: Send + Sync {
    fn kill(&mut self) -> io::Result<()>;
}
```

- 由 `pipe.rs` 和 `pty.rs` 分别实现
- 提供跨平台的进程终止抽象

### 3. 辅助 Trait（Unix）

```rust
#[cfg(unix)]
pub(crate) trait PtyHandleKeepAlive: Send {}
```

- 用于 `PtyMasterHandle::Opaque` 变体
- 确保原始 FD 对应的句柄保持存活

## 具体技术实现

### 1. ProcessHandle 结构

```rust
pub struct ProcessHandle {
    writer_tx: StdMutex<Option<mpsc::Sender<Vec<u8>>>>,     // stdin 写入通道
    killer: StdMutex<Option<Box<dyn ChildTerminator>>>,     // 终止器
    reader_handle: StdMutex<Option<JoinHandle<()>>>,        // 读取任务句柄
    reader_abort_handles: StdMutex<Vec<AbortHandle>>,       // 读取任务中止句柄
    writer_handle: StdMutex<Option<JoinHandle<()>>>,        // 写入任务句柄
    wait_handle: StdMutex<Option<JoinHandle<()>>>,          // 等待任务句柄
    exit_status: Arc<AtomicBool>,                           // 退出状态标志
    exit_code: Arc<StdMutex<Option<i32>>>,                  // 退出码
    _pty_handles: StdMutex<Option<PtyHandles>>,             // PTY 句柄（防止释放）
}
```

**设计要点：**
- 所有 `JoinHandle` 使用 `StdMutex` 包装（非异步互斥锁）
- `Option` 包装支持 `take()` 语义，防止重复中止
- `Arc` 共享状态用于跨任务通信

### 2. 进程状态管理

```rust
impl ProcessHandle {
    /// 检查进程是否已退出
    pub fn has_exited(&self) -> bool {
        self.exit_status.load(std::sync::atomic::Ordering::SeqCst)
    }

    /// 获取退出码（如果已知）
    pub fn exit_code(&self) -> Option<i32> {
        self.exit_code.lock().ok().and_then(|guard| *guard)
    }
}
```

**状态转换：**
```
创建 → 运行 → [exit_status = true, exit_code = Some(N)] → 终止
```

### 3. 进程终止策略

**两种终止模式：**

```rust
/// 温和终止：kill 进程但保留 reader 以 drain 输出
pub fn request_terminate(&self) {
    if let Ok(mut killer_opt) = self.killer.lock() {
        if let Some(mut killer) = killer_opt.take() {
            let _ = killer.kill();  // 尝试终止进程
        }
    }
}

/// 强制终止：kill 进程并中止所有任务
pub fn terminate(&self) {
    self.request_terminate();
    
    // 中止所有 reader 任务
    if let Ok(mut h) = self.reader_handle.lock() {
        if let Some(handle) = h.take() { handle.abort(); }
    }
    if let Ok(mut handles) = self.reader_abort_handles.lock() {
        for handle in handles.drain(..) { handle.abort(); }
    }
    // ... writer 和 wait 任务同理
}
```

**使用场景：**
- `request_terminate`：需要收集进程退出前的最后输出
- `terminate`：立即清理资源，不关心剩余输出

### 4. PTY 调整大小

```rust
pub fn resize(&self, size: TerminalSize) -> anyhow::Result<()> {
    let handles = self._pty_handles.lock()
        .map_err(|_| anyhow!("failed to lock PTY handles"))?;
    let handles = handles.as_ref()
        .ok_or_else(|| anyhow!("process is not attached to a PTY"))?;
    
    match &handles._master {
        PtyMasterHandle::Resizable(master) => master.resize(size.into()),
        #[cfg(unix)]
        PtyMasterHandle::Opaque { raw_fd, .. } => resize_raw_pty(*raw_fd, size),
    }
}
```

**两种调整大小路径：**

| 路径 | 适用场景 | 实现 |
|------|----------|------|
| `Resizable` | 标准 `portable-pty` | `MasterPty::resize()` |
| `Opaque` | Unix FD 保留模式 | `ioctl(TIOCSWINSZ)` |

### 5. Unix 原始 PTY 调整大小

```rust
#[cfg(unix)]
fn resize_raw_pty(raw_fd: RawFd, size: TerminalSize) -> anyhow::Result<()> {
    let mut winsize = libc::winsize {
        ws_row: size.rows,
        ws_col: size.cols,
        ws_xpixel: 0,
        ws_ypixel: 0,
    };
    let result = unsafe { libc::ioctl(raw_fd, libc::TIOCSWINSZ, &mut winsize) };
    if result == -1 {
        return Err(std::io::Error::last_os_error().into());
    }
    Ok(())
}
```

### 6. 输出合并器

```rust
pub fn combine_output_receivers(
    mut stdout_rx: mpsc::Receiver<Vec<u8>>,
    mut stderr_rx: mpsc::Receiver<Vec<u8>>,
) -> broadcast::Receiver<Vec<u8>> {
    let (combined_tx, combined_rx) = broadcast::channel(256);
    tokio::spawn(async move {
        let mut stdout_open = true;
        let mut stderr_open = true;
        
        loop {
            tokio::select! {
                stdout = stdout_rx.recv(), if stdout_open => match stdout {
                    Some(chunk) => { let _ = combined_tx.send(chunk); }
                    None => { stdout_open = false; }
                },
                stderr = stderr_rx.recv(), if stderr_open => match stderr {
                    Some(chunk) => { let _ = combined_tx.send(chunk); }
                    None => { stderr_open = false; }
                },
                else => break,
            }
        }
    });
    combined_rx
}
```

**设计特点：**
- 使用 `tokio::select!` 并发处理两个通道
- `broadcast::channel` 支持多订阅者
- 256 容量缓冲，避免慢消费者阻塞

### 7. Drop 实现

```rust
impl Drop for ProcessHandle {
    fn drop(&mut self) {
        self.terminate();
    }
}
```

**确保：**
- 进程被终止（如果仍在运行）
- 所有异步任务被中止
- 资源被清理

## 关键代码路径与文件引用

### 1. 文件依赖图

```
process.rs
  ├── 外部依赖
  │   ├── portable_pty::{MasterPty, PtySize, SlavePty}
  │   ├── tokio::sync::{broadcast, mpsc, oneshot}
  │   ├── tokio::task::{AbortHandle, JoinHandle}
  │   └── anyhow::anyhow
  │
  ├── 被 pipe.rs 使用
  │   ├── ChildTerminator (trait)
  │   ├── ProcessHandle::new()
  │   └── combine_output_receivers()
  │
  ├── 被 pty.rs 使用
  │   ├── ChildTerminator (trait)
  │   ├── ProcessHandle::new()
  │   ├── PtyHandles, PtyMasterHandle
  │   └── TerminalSize
  │
  └── 被 lib.rs re-export
      ├── ProcessHandle, SpawnedProcess, TerminalSize
      └── combine_output_receivers
```

### 2. 关键代码位置

| 功能 | 行号 | 代码 |
|------|------|------|
| ChildTerminator trait | 19-21 | trait 定义 |
| TerminalSize | 23-44 | struct + Default + From<PtySize> |
| PtyMasterHandle | 52-59 | enum 定义 |
| PtyHandles | 61-70 | struct + Debug |
| ProcessHandle | 72-206 | 完整实现 |
| resize_raw_pty | 208-221 | Unix 原始 PTY 调整大小 |
| combine_output_receivers | 223-256 | 输出合并 |
| SpawnedProcess | 258-265 | struct 定义 |

### 3. 调用链

**创建 ProcessHandle：**
```
pipe.rs / pty.rs
  └── ProcessHandle::new(
        writer_tx,           // stdin 写入通道
        killer,              // ChildTerminator 实现
        reader_handle,       // 读取任务 JoinHandle
        reader_abort_handles,// 可中止的 reader 句柄
        writer_handle,       // 写入任务 JoinHandle
        wait_handle,         // 等待任务 JoinHandle
        exit_status,         // 退出状态 Arc<AtomicBool>
        exit_code,           // 退出码 Arc<StdMutex<Option<i32>>>
        pty_handles,         // Option<PtyHandles>
      )
```

**终止流程：**
```
ProcessHandle::terminate()
  ├── request_terminate()
  │   └── killer.kill()  // 平台特定实现
  ├── reader_handle.abort()
  ├── reader_abort_handles 中所有 handle.abort()
  ├── writer_handle.abort()
  └── wait_handle.abort()
```

## 依赖与外部交互

### 1. 外部 Crate

```rust
use core::fmt;
use std::io;
use std::sync::atomic::AtomicBool;
use std::sync::Arc;
use std::sync::Mutex as StdMutex;

use anyhow::anyhow;
use portable_pty::{MasterPty, PtySize, SlavePty};
use tokio::sync::{broadcast, mpsc, oneshot};
use tokio::task::{AbortHandle, JoinHandle};

#[cfg(unix)]
use std::os::fd::RawFd;
```

### 2. 平台特定代码

**Unix 特有：**
- `RawFd` 类型
- `PtyMasterHandle::Opaque` 变体
- `resize_raw_pty()` 函数
- `PtyHandleKeepAlive` trait

**通用代码：**
- `PtyMasterHandle::Resizable` 变体
- 所有 `ProcessHandle` 方法

### 3. 消费者

| 消费者 | 使用内容 |
|--------|----------|
| `pipe.rs` | `ChildTerminator`, `ProcessHandle`, `SpawnedProcess`, `combine_output_receivers` |
| `pty.rs` | `ChildTerminator`, `ProcessHandle`, `PtyHandles`, `PtyMasterHandle`, `TerminalSize` |
| `lib.rs` | re-export 所有公共类型 |
| `command_exec.rs` | `ProcessHandle` 方法调用 |

## 风险、边界与改进建议

### 1. 潜在风险

| 风险 | 描述 | 影响 |
|------|------|------|
| 锁 Poisoning | `StdMutex` 在 panic 后可能 poison | 方法返回错误而非 panic |
| 竞态条件 | `has_exited()` 和 `exit_code()` 可能看到不一致状态 | 需原子性读取两者 |
| 资源泄漏 | `PtyHandles` 的 `_slave` 字段在 Unix 上为 None | 设计如此，Unix 不需要保留 slave |
| 广播滞后 | `broadcast::channel` 的 256 容量可能导致旧消费者丢失消息 | 使用 `RecvError::Lagged` 处理 |

### 2. 边界情况

```rust
// 1. 重复调用 terminate()
// 由于使用 Option::take()，重复调用是安全的

// 2. writer_sender() 在关闭后
pub fn writer_sender(&self) -> mpsc::Sender<Vec<u8>> {
    if let Ok(writer_tx) = self.writer_tx.lock() {
        if let Some(writer_tx) = writer_tx.as_ref() {
            return writer_tx.clone();
        }
    }
    // 返回一个已关闭的通道
    let (writer_tx, writer_rx) = mpsc::channel(1);
    drop(writer_rx);
    writer_tx
}

// 3. 非 PTY 进程调用 resize()
// 返回错误："process is not attached to a PTY"

// 4. 锁获取失败
// resize() 中：map_err(|_| anyhow!("failed to lock PTY handles"))
```

### 3. 改进建议

1. **状态一致性**
   ```rust
   // 当前：分别读取 exit_status 和 exit_code
   // 建议：使用单一原子状态
   enum ProcessState {
       Running,
       Exited(i32),
   }
   ```

2. **错误类型细化**
   ```rust
   // 当前：使用 anyhow
   // 建议：定义特定错误类型
   #[derive(Debug, thiserror::Error)]
   enum ProcessError {
       #[error("process is not attached to a PTY")]
       NotAPty,
       #[error("failed to lock internal state")]
       LockPoisoned,
   }
   ```

3. **优雅关闭超时**
   ```rust
   // 当前：terminate() 立即中止所有任务
   // 建议：添加超时参数
   pub fn terminate_with_timeout(&self, drain_timeout: Duration)
   ```

4. **内存使用优化**
   ```rust
   // 当前：combine_output_receivers 使用 broadcast::channel(256)
   // 建议：考虑使用 backpressure 策略
   ```

5. **PTY 句柄类型安全**
   ```rust
   // 当前：PtyMasterHandle::Opaque 使用 RawFd
   // 建议：使用类型安全的 FD 包装器
   struct OwnedFd(RawFd);
   impl Drop for OwnedFd { ... }
   ```

### 4. 测试建议

| 测试场景 | 验证点 |
|----------|--------|
| 重复终止 | 验证不会 panic 或死锁 |
| 终止后写入 | 验证 writer_sender 返回已关闭通道 |
| resize 非 PTY | 验证返回正确错误 |
| 输出合并 | 验证 stdout/stderr 交错顺序合理 |
| 大输出量 | 验证 broadcast 通道不溢出 |
| Drop 清理 | 验证进程被正确终止 |
