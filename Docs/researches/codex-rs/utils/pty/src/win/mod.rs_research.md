# mod.rs 研究文档

## 文件信息
- **路径**: `codex-rs/utils/pty/src/win/mod.rs`
- **大小**: 6,076 bytes
- **来源**: 基于 WezTerm (MIT License) 的 vendored 代码，有本地修改

---

## 一、场景与职责

### 1.1 核心定位
`mod.rs` 是 Windows PTY 子模块的 **入口和进程管理核心**，负责：
1. 模块组织和导出
2. Windows 子进程生命周期管理 (`WinChild`)
3. 进程终止机制 (`WinChildKiller`)
4. 异步 Future 支持

### 1.2 主要职责

| 组件 | 职责 |
|------|------|
| `WinChild` | 表示已启动的子进程，实现 `Child` 和 `Future` trait |
| `WinChildKiller` | 进程终止器，实现 `ChildKiller` trait，可克隆共享 |
| 模块导出 | 导出 `ConPtySystem` 和 `conpty_supported` 供上层使用 |

### 1.3 关键 Bug 修复
文件头部明确记录了与上游 WezTerm 的重要分歧：
```rust
// Local modifications:
// - Fix Codex bug #13945 in the Windows PTY kill path. The vendored code treated
//   `TerminateProcess`'s nonzero success return as failure and `0` as success,
//   which inverts kill outcomes for both `WinChild::do_kill` and
//   `WinChildKiller::kill`.
// - This bug still exists in the original WezTerm source as of 2026-03-08, so
//   this is an intentional divergence from upstream.
```

---

## 二、功能点目的

### 2.1 WinChild - 子进程句柄
```rust
#[derive(Debug)]
pub struct WinChild {
    proc: Mutex<OwnedHandle>,  // 进程句柄，Mutex 用于线程安全
}
```

**核心功能**:
- **状态查询**: `is_complete()` / `try_wait()` 检查进程是否退出
- **同步等待**: `wait()` 阻塞直到进程退出
- **强制终止**: `do_kill()` 调用 `TerminateProcess`
- **PID 获取**: `process_id()` 返回进程 ID
- **原始句柄**: `as_raw_handle()` 返回底层 HANDLE
- **Future 支持**: 实现 `std::future::Future` 用于异步等待

### 2.2 WinChildKiller - 可克隆的终止器
```rust
#[derive(Debug)]
pub struct WinChildKiller {
    proc: OwnedHandle,  // 独立的句柄副本
}
```

**设计目的**:
- 与 `WinChild` 分离，可在不持有 `WinChild` 的情况下终止进程
- 实现 `Clone`，支持多位置共享终止能力
- 通过 `try_clone()` 创建独立的句柄引用

### 2.3 模块组织
```rust
pub mod conpty;           // PTY 系统实现
mod procthreadattr;       // 进程线程属性（内部使用）
mod psuedocon;            // 伪控制台底层实现

pub use conpty::ConPtySystem;           // 对外导出
pub use psuedocon::conpty_supported;    // 能力检测
```

---

## 三、具体技术实现

### 3.1 关键流程

#### 3.1.1 进程状态检测 (is_complete)
```rust
fn is_complete(&mut self) -> IoResult<Option<ExitStatus>> {
    let mut status: DWORD = 0;
    let proc = self.proc.lock().unwrap().try_clone().unwrap();
    let res = unsafe { GetExitCodeProcess(proc.as_raw_handle() as _, &mut status) };
    if res != 0 {
        if status == STILL_ACTIVE {
            Ok(None)  // 仍在运行
        } else {
            Ok(Some(ExitStatus::with_exit_code(status)))  // 已退出
        }
    } else {
        Ok(None)  // API 调用失败，保守返回 None
    }
}
```

流程图:
```
GetExitCodeProcess
        │
        ▼
    res == 0? ──Yes──▶ 返回 None (API 失败)
        │ No
        ▼
    status == STILL_ACTIVE?
        │
    Yes ──▶ 返回 None (仍在运行)
        │
    No ───▶ 返回 ExitStatus (已退出)
```

#### 3.1.2 进程终止 (do_kill / kill)
```rust
fn do_kill(&mut self) -> IoResult<()> {
    let proc = self.proc.lock().unwrap().try_clone().unwrap();
    let res = unsafe { TerminateProcess(proc.as_raw_handle() as _, 1) };
    // Codex bug #13945: Win32 returns nonzero on success, so only `0` is an error.
    if res == 0 {
        Err(IoError::last_os_error())
    } else {
        Ok(())
    }
}
```

**关键修复**: Win32 API `TerminateProcess` 返回 **非零表示成功**，但原始 WezTerm 代码错误地将非零解释为失败。

#### 3.1.3 异步等待 (Future 实现)
```rust
impl std::future::Future for WinChild {
    type Output = anyhow::Result<ExitStatus>;

    fn poll(mut self: Pin<&mut Self>, cx: &mut Context) -> Poll<Self::Output> {
        match self.is_complete() {
            Ok(Some(status)) => Poll::Ready(Ok(status)),
            Err(err) => Poll::Ready(Err(err).context("...")),
            Ok(None) => {
                // 进程仍在运行，启动等待线程
                let proc = self.proc.lock().unwrap().try_clone()?;
                let waker = cx.waker().clone();
                std::thread::spawn(move || {
                    unsafe { WaitForSingleObject(proc.as_raw_handle() as _, INFINITE) };
                    waker.wake();  // 唤醒异步执行器
                });
                Poll::Pending
            }
        }
    }
}
```

**实现策略**:
- 非阻塞 poll：立即返回如果进程已完成
- 阻塞等待：启动专用线程调用 `WaitForSingleObject(INFINITE)`
- 唤醒机制：进程退出后通过 waker 通知异步执行器

### 3.2 数据结构

#### 3.2.1 退出状态封装
```rust
// 来自 portable-pty
pub struct ExitStatus {
    exit_code: Option<u32>,
}
```
- `None` 表示被信号终止（Unix 概念，Windows 不适用）
- `Some(code)` 表示正常退出，携带退出码

### 3.3 关键代码路径

| 操作 | 调用链 |
|------|--------|
| 检查状态 | `try_wait()` → `is_complete()` → `GetExitCodeProcess()` |
| 同步等待 | `wait()` → `WaitForSingleObject(INFINITE)` → `GetExitCodeProcess()` |
| 终止进程 | `kill()` → `do_kill()` → `TerminateProcess()` |
| 异步等待 | `Future::poll()` → `is_complete()` / 启动等待线程 |

---

## 四、关键代码路径与文件引用

### 4.1 内部依赖
```rust
use filedescriptor::OwnedHandle;           // 进程句柄封装
use portable_pty::{Child, ChildKiller, ExitStatus};  // Trait 定义
use winapi::shared::minwindef::DWORD;      // Windows 类型
use winapi::um::minwinbase::STILL_ACTIVE;  // 进程状态常量
use winapi::um::processthreadsapi::*;      // 进程 API
use winapi::um::synchapi::WaitForSingleObject;
use winapi::um::winbase::INFINITE;
```

### 4.2 调用关系图
```
win/mod.rs
    │
    ├─── uses ───▶ filedescriptor::OwnedHandle
    │
    ├─── uses ───▶ portable_pty::{Child, ChildKiller, ExitStatus}
    │
    ├─── exports ───▶ conpty::ConPtySystem
    │       │
    │       └─── uses ───▶ win/mod.rs (WinChild)
    │
    ├─── exports ───▶ psuedocon::conpty_supported
    │
    └─── used by ───▶ psuedocon.rs (WinChild)
              │
              └─── used by ───▶ conpty.rs (通过 SlavePty::spawn_command)
```

### 4.3 Windows API 调用汇总

| API 函数 | 用途 | 所在方法 |
|----------|------|----------|
| `GetExitCodeProcess` | 获取进程退出码 | `is_complete()` |
| `TerminateProcess` | 强制终止进程 | `do_kill()` / `WinChildKiller::kill()` |
| `WaitForSingleObject` | 等待进程退出 | `wait()` / `Future::poll()` |
| `GetProcessId` | 获取进程 ID | `process_id()` |

---

## 五、依赖与外部交互

### 5.1 外部 Crates
| Crate | 用途 |
|-------|------|
| `portable-pty` | `Child`, `ChildKiller`, `ExitStatus` trait |
| `filedescriptor` | `OwnedHandle` - RAII 进程句柄 |
| `anyhow` | 错误处理和上下文 |
| `winapi` | Windows API 绑定 |

### 5.2 Win32 API 常量
```rust
const STILL_ACTIVE: DWORD = 259;  // 进程仍在运行
const INFINITE: DWORD = 0xFFFFFFFF;  // 无限等待
```

### 5.3 安全考虑
- `unsafe` 块封装所有 Win32 API 调用
- `OwnedHandle` 确保句柄在 drop 时正确关闭
- `try_clone()` 创建独立句柄引用，避免 use-after-free

---

## 六、风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 Bug #13945 - 已修复
```rust
// 修复前 (错误):
if res != 0 { Err(...) } else { Ok(()) }

// 修复后 (正确):
if res == 0 { Err(...) } else { Ok(()) }
```
- **影响**: 终止进程操作的结果判断被反转
- **状态**: 已在 Codex 中修复，但上游 WezTerm 截至 2026-03-08 仍存在

#### 6.1.2 锁竞争
```rust
pub struct WinChild {
    proc: Mutex<OwnedHandle>,  // 每次操作都需获取锁
}
```
- **风险**: 高频状态查询可能导致锁竞争
- **缓解**: 实际场景中进程操作频率较低，影响有限

#### 6.1.3 Future 实现的线程开销
```rust
std::thread::spawn(move || {
    unsafe { WaitForSingleObject(proc.as_raw_handle() as _, INFINITE) };
    waker.wake();
});
```
- **风险**: 每个未完成进程的 poll 都会创建新线程
- **边界**: 如果大量进程同时运行且频繁 poll，可能耗尽线程资源
- **建议**: 考虑使用线程池或 I/O Completion Port 优化

#### 6.1.4 unwrap() 使用
```rust
let proc = self.proc.lock().unwrap().try_clone().unwrap();
```
- **风险**: 锁中毒时 panic
- **位置**: 第62行、第76行、第94行、第130行、第166行

### 6.2 边界条件

#### 6.2.1 进程已退出后的操作
- `try_wait()` / `wait()`: 正常返回退出状态
- `kill()`: 可能返回错误（进程已不存在）
- `process_id()`: 可能返回已回收的 PID

#### 6.2.2 句柄有效性
- `OwnedHandle` 的 RAII 确保 drop 时关闭
- `try_clone()` 创建新的 OS 句柄引用
- 原始句柄通过 `as_raw_handle()` 暴露，调用者需谨慎

### 6.3 改进建议

#### 6.3.1 异步实现优化
```rust
// 当前: 每个 poll 创建新线程
// 建议: 使用 I/O Completion Port 或线程池

// 可能的改进方案:
use windows_sys::Win32::System::IO::CreateIoCompletionPort;
use windows_sys::Win32::System::Threading::RegisterWaitForSingleObject;
```

#### 6.3.2 错误处理增强
```rust
// 当前: 大量使用 unwrap()
// 建议: 使用 ? 运算符和自定义错误类型

pub enum WinChildError {
    LockPoisoned,
    HandleCloneFailed(std::io::Error),
    // ...
}
```

#### 6.3.3 测试覆盖
建议增加以下测试：
- 进程终止结果验证（回归测试 bug #13945）
- 并发 kill 操作测试
- Future 超时和取消测试
- 进程句柄耗尽边界测试

#### 6.3.4 文档完善
- 添加 `WinChildKiller` 的使用示例
- 说明 `Clone` 行为的语义（独立句柄引用）
- 记录 Future 实现的线程创建行为

### 6.4 与上游同步策略
- 当前与 WezTerm 存在有意分歧（bug 修复）
- 建议建立定期同步机制，评估上游修复
- 考虑向上游提交 bug #13945 的修复

---

## 七、相关文件索引

| 文件 | 关系 | 说明 |
|------|------|------|
| `win/conpty.rs` | 子模块 | 使用 `WinChild` 作为 `spawn_command` 返回值 |
| `win/psuedocon.rs` | 子模块 | 创建 `WinChild` 实例 |
| `win/procthreadattr.rs` | 子模块 | 被 `psuedocon.rs` 使用 |
| `process.rs` | 调用方 | 通过 `ChildTerminator` trait 使用 kill 功能 |
| `tests.rs` | 测试 | 集成测试验证进程生命周期 |
| `Cargo.toml` | 配置 | 依赖声明 |
