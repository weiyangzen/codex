# process_group.rs 研究文档

## 场景与职责

`process_group.rs` 是 `codex-utils-pty` crate 的 Unix 特定模块，专注于进程组管理和进程生命周期控制。该模块是确保子进程可靠清理的关键组件，防止孤儿进程和僵尸进程的产生。

### 核心职责

1. **进程组创建**：将子进程放入独立的进程组，便于批量管理
2. **会话管理**：脱离控制终端，创建新会话（session）
3. **进程终止**：提供进程组级别的终止功能（SIGTERM/SIGKILL）
4. **父进程死亡处理**：Linux 特有机制，确保父进程退出时子进程收到信号

### 使用场景

- 执行可能产生子进程的 shell 命令（如 `sh -c 'sleep 100 &'`）
- 需要确保进程树完全清理的交互式会话
- 防止子进程继承父进程的控制终端

## 功能点目的

### 1. 公共函数列表

| 函数 | 平台 | 用途 |
|------|------|------|
| `set_parent_death_signal` | Linux | 父进程退出时子进程自动收到 SIGTERM |
| `detach_from_tty` | Unix | 脱离控制终端，创建新会话 |
| `set_process_group` | Unix | 将进程放入新进程组 |
| `kill_process_group_by_pid` | Unix | 通过 PID 查找并终止整个进程组 |
| `terminate_process_group` | Unix | 向进程组发送 SIGTERM |
| `kill_process_group` | Unix | 向进程组发送 SIGKILL |
| `kill_child_process_group` | Unix | 终止 tokio Child 的进程组 |

### 2. 平台适配

所有函数都有 Unix 和 非 Unix 两个版本：

```rust
#[cfg(unix)]
pub fn detach_from_tty() -> io::Result<()> { /* 实际实现 */ }

#[cfg(not(unix))]
pub fn detach_from_tty() -> io::Result<()> { Ok(()) }  // 空操作
```

## 具体技术实现

### 1. 父进程死亡信号（Linux 特有）

```rust
#[cfg(target_os = "linux")]
pub fn set_parent_death_signal(parent_pid: libc::pid_t) -> io::Result<()> {
    // 1. 设置死亡信号为 SIGTERM
    if unsafe { libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM) } == -1 {
        return Err(io::Error::last_os_error());
    }
    
    // 2. 竞态保护：检查父进程是否已变更
    if unsafe { libc::getppid() } != parent_pid {
        unsafe { libc::raise(libc::SIGTERM); }
    }
    
    Ok(())
}
```

**竞态条件处理：**

```
时间线：
  父进程          子进程（pre_exec）
    │                    │
    ├────── fork ───────►│
    │                    │
    ├────── exec ───────►│
    │                    ├── prctl(PR_SET_PDEATHSIG, SIGTERM)
    │                    │
   退出 ◄────────────────┤
    │                    ├── getppid() != parent_pid
    │                    ├── raise(SIGTERM)  ← 自我终止
    │                    │
```

**关键问题：** 如果父进程在 `fork` 和 `exec` 之间退出，子进程可能被 init 进程收养，`getppid()` 会改变。

### 2. 脱离控制终端

```rust
#[cfg(unix)]
pub fn detach_from_tty() -> io::Result<()> {
    let result = unsafe { libc::setsid() };
    if result == -1 {
        let err = io::Error::last_os_error();
        if err.raw_os_error() == Some(libc::EPERM) {
            // 已经是进程组 leader，无法 setsid
            return set_process_group();
        }
        return Err(err);
    }
    Ok(())
}
```

**系统调用说明：**
- `setsid()`：创建新会话，进程成为会话 leader 和进程组 leader
- 失败原因 `EPERM`：调用者已经是进程组 leader

**回退策略：**
```rust
pub fn set_process_group() -> io::Result<()> {
    let result = unsafe { libc::setpgid(0, 0) };
    // 0,0 表示将调用者放入以自身 PID 为 ID 的新进程组
    ...
}
```

### 3. 进程组终止

#### 通过 PID 查找终止

```rust
#[cfg(unix)]
pub fn kill_process_group_by_pid(pid: u32) -> io::Result<()> {
    let pid = pid as libc::pid_t;
    
    // 1. 获取进程组 ID
    let pgid = unsafe { libc::getpgid(pid) };
    if pgid == -1 {
        let err = io::Error::last_os_error();
        if err.kind() != ErrorKind::NotFound {
            return Err(err);
        }
        return Ok(());  // 进程已不存在
    }
    
    // 2. 向整个进程组发送 SIGKILL
    let result = unsafe { libc::killpg(pgid, libc::SIGKILL) };
    if result == -1 {
        let err = io::Error::last_os_error();
        if err.kind() != ErrorKind::NotFound {
            return Err(err);
        }
    }
    
    Ok(())
}
```

#### 直接通过 PGID 终止

```rust
/// SIGTERM 终止（温和）
pub fn terminate_process_group(process_group_id: u32) -> io::Result<bool> {
    let pgid = process_group_id as libc::pid_t;
    let result = unsafe { libc::killpg(pgid, libc::SIGTERM) };
    if result == -1 {
        let err = io::Error::last_os_error();
        if err.kind() == ErrorKind::NotFound {
            return Ok(false);  // 进程组已不存在
        }
        return Err(err);
    }
    Ok(true)
}

/// SIGKILL 终止（强制）
pub fn kill_process_group(process_group_id: u32) -> io::Result<()> {
    let pgid = process_group_id as libc::pid_t;
    let result = unsafe { libc::killpg(pgid, libc::SIGKILL) };
    ...
}
```

**信号选择：**
- `SIGTERM` (15)：请求终止，进程可以捕获并清理
- `SIGKILL` (9)：强制终止，无法捕获或忽略

### 4. 进程组概念图解

```
会话（Session）
├── 控制终端（Controlling Terminal）
│
└── 进程组 1（Foreground）
│   ├── 进程 A（Leader, PID=PGID）
│   └── 进程 B
│
└── 进程组 2（Background）
    ├── 进程 C（Leader, PID=PGID）
    └── 进程 D

killpg(PGID_2, SIGKILL) 会终止进程 C 和 D
```

## 关键代码路径与文件引用

### 1. 文件依赖图

```
process_group.rs
  ├── 外部依赖
  │   ├── std::io
  │   ├── tokio::process::Child
  │   └── libc (Unix)
  │
  ├── 被 pipe.rs 使用
  │   ├── detach_from_tty()        [pre_exec 钩子]
  │   ├── set_parent_death_signal() [pre_exec 钩子, Linux]
  │   └── kill_process_group()     [终止器实现]
  │
  ├── 被 pty.rs 使用
  │   └── close_inherited_fds_except() 间接使用
  │
  └── 被 lib.rs 引用
      └── pub mod process_group
```

### 2. 关键代码位置

| 功能 | 行号 | 代码 |
|------|------|------|
| set_parent_death_signal | 22-45 | Linux 父进程死亡信号 |
| detach_from_tty | 47-65 | 脱离控制终端 |
| set_process_group | 67-84 | 设置进程组 |
| kill_process_group_by_pid | 86-118 | 通过 PID 终止进程组 |
| terminate_process_group | 120-145 | SIGTERM 终止 |
| kill_process_group | 147-168 | SIGKILL 终止 |
| kill_child_process_group | 170-184 | tokio Child 包装 |

### 3. 调用链

**进程创建时（pre_exec）：**
```
pipe.rs:spawn_process_with_stdin_mode()
  └── Command::pre_exec()
      ├── process_group::detach_from_tty()
      │   ├── libc::setsid()  [成功]
      │   └── libc::setpgid(0, 0)  [setsid 失败时回退]
      ├── process_group::set_parent_death_signal(parent_pid)  [Linux]
      │   ├── libc::prctl(PR_SET_PDEATHSIG, SIGTERM)
      │   └── libc::getppid() 验证
      └── pty.rs:close_inherited_fds_except()
```

**进程终止时：**
```
ProcessHandle::terminate()
  └── PipeChildTerminator::kill() / PtyChildTerminator::kill()
      └── process_group::kill_process_group(process_group_id)
          └── libc::killpg(pgid, SIGKILL)
```

## 依赖与外部交互

### 1. 外部依赖

```rust
use std::io;
use tokio::process::Child;

#[cfg(unix)]
use libc;
```

### 2. 系统调用汇总

| 函数 | 系统调用 | 用途 |
|------|----------|------|
| `set_parent_death_signal` | `prctl(PR_SET_PDEATHSIG)` | 设置父进程死亡信号 |
| | `getppid()` | 获取父进程 PID |
| | `raise(SIGTERM)` | 自我发送信号 |
| `detach_from_tty` | `setsid()` | 创建新会话 |
| `set_process_group` | `setpgid(0, 0)` | 创建新进程组 |
| `kill_process_group_by_pid` | `getpgid(pid)` | 获取进程组 ID |
| | `killpg(pgid, SIGKILL)` | 终止进程组 |
| `terminate_process_group` | `killpg(pgid, SIGTERM)` | 温和终止 |
| `kill_process_group` | `killpg(pgid, SIGKILL)` | 强制终止 |

### 3. 错误处理策略

```rust
// 1. NotFound 错误视为成功（进程已退出）
if err.kind() != ErrorKind::NotFound {
    return Err(err);
}
return Ok(());  // 或 Ok(false)

// 2. EPERM 错误有特定处理
if err.raw_os_error() == Some(libc::EPERM) {
    return set_process_group();
}
```

## 风险、边界与改进建议

### 1. 潜在风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 竞态条件 | `set_parent_death_signal` 中 `prctl` 和 `getppid` 之间有窗口 | 重新检查父进程 PID |
| 权限不足 | `killpg` 可能因权限失败 | 忽略 NotFound，其他错误传播 |
| 孤儿进程组 | 如果进程组 leader 先退出，剩余进程成为孤儿 | 使用 `setsid` 创建新会话 |
| 信号继承 | 子进程可能继承父进程的信号掩码 | `pty.rs` 中重置信号处理 |

### 2. 边界情况

```rust
// 1. 已经是进程组 leader 时 setsid 失败
// 处理：回退到 set_process_group()

// 2. 进程在 getpgid 和 killpg 之间退出
// 处理：killpg 返回 NotFound，视为成功

// 3. 父进程在 fork 后、prctl 前退出
// 处理：getppid() 检查会失败，子进程自我终止

// 4. 非 Linux Unix（macOS, *BSD）
// 处理：set_parent_death_signal 为空操作
```

### 3. 改进建议

1. **优雅终止策略**
   ```rust
   // 当前：直接使用 SIGKILL
   // 建议：先 SIGTERM，超时后 SIGKILL
   pub async fn terminate_process_group_graceful(
       process_group_id: u32,
       timeout: Duration,
   ) -> io::Result<bool>
   ```

2. **进程组存在检查**
   ```rust
   // 当前：killpg 返回错误来判断
   // 建议：添加显式检查函数
   pub fn process_group_exists(process_group_id: u32) -> bool
   ```

3. **信号选择可配置**
   ```rust
   // 建议：允许调用者选择信号
   pub fn signal_process_group(
       process_group_id: u32,
       signal: Signal,
   ) -> io::Result<()>
   ```

4. **文档增强**
   ```rust
   // 建议：添加更多实现细节注释
   /// # Safety
   /// This function uses unsafe libc calls. The caller must ensure
   /// that process_group_id is valid and the calling process has
   /// appropriate permissions.
   ```

5. **测试覆盖**
   - 进程组嵌套场景
   - 大量并发进程组创建/终止
   - 权限不足场景

### 4. 安全考虑

1. **信号广播风险**：`killpg` 会终止进程组内所有进程，包括可能不相关的进程
2. **权限检查**：确保调用者有权限向目标进程组发送信号
3. **PID 重用**：短时间内 PID 重用可能导致误杀其他进程

### 5. 与 pty.rs 的协作

在 `pty.rs:spawn_process_preserving_fds()` 中，信号处理重置与进程组管理配合：

```rust
.pre_exec(move || {
    // 重置信号处理为默认
    for signo in &[SIGCHLD, SIGHUP, SIGINT, SIGQUIT, SIGTERM, SIGALRM] {
        libc::signal(*signo, libc::SIG_DFL);
    }
    
    // 清空信号掩码
    let empty_set: libc::sigset_t = std::mem::zeroed();
    libc::sigprocmask(libc::SIG_SETMASK, &empty_set, std::ptr::null_mut());
    
    // 创建新会话
    if libc::setsid() == -1 { ... }
    
    // 设置控制终端
    if libc::ioctl(0, libc::TIOCSCTTY as _, 0) == -1 { ... }
    
    close_inherited_fds_except(&inherited_fds);
    Ok(())
})
```

这确保了：
- 子进程不继承父进程的信号处理程序
- 子进程不继承父进程的信号掩码
- 子进程有自己的会话和控制终端
