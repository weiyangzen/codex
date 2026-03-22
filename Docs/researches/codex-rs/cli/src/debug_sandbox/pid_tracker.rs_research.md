# pid_tracker.rs 研究文档

## 场景与职责

`pid_tracker.rs` 是 Codex CLI 的 macOS 专用模块，位于 `codex-rs/cli/src/debug_sandbox/` 目录下。其核心职责是**递归追踪进程的所有后代进程（descendants）**，用于配合 Seatbelt 沙箱的拒绝日志记录功能（DenialLogger）。

### 使用场景

1. **沙箱调试模式**：当用户运行 `codex sandbox macos --log-denials <command>` 时，需要追踪被沙箱化的命令及其所有子进程
2. **权限拒绝分析**：捕获并归因沙箱拒绝事件到具体的进程名称和能力（capability）
3. **进程生命周期监控**：监控从根进程开始的整个进程树，直到所有进程结束

### 架构位置

```
cli/src/debug_sandbox/
├── mod.rs           # 主模块，协调 Seatbelt/Landlock/Windows 沙箱
├── pid_tracker.rs   # 本文件：进程树追踪
└── seatbelt.rs      # 使用 PidTracker 进行拒绝日志记录
```

---

## 功能点目的

### 1. 进程树追踪（PidTracker）

- **目的**：实时追踪一个根进程及其所有 fork 出的后代进程
- **机制**：利用 macOS 的 `kqueue` 内核事件通知机制监控进程事件
- **输出**：返回所有曾经存在的进程 ID 集合（`HashSet<i32>`）

### 2. 进程事件监控

监控以下进程事件：
- `NOTE_FORK`：进程 fork 子进程
- `NOTE_EXEC`：进程执行新程序
- `NOTE_EXIT`：进程退出

### 3. 递归子进程发现

- 使用 `proc_listchildpids` 系统调用获取进程的子进程列表
- 递归监控所有后代进程

---

## 具体技术实现

### 核心数据结构

```rust
pub(crate) struct PidTracker {
    kq: libc::c_int,                    // kqueue 文件描述符
    handle: JoinHandle<HashSet<i32>>,   // 异步追踪任务句柄
}
```

### 关键技术：kqueue 事件通知

```rust
fn watch_pid(kq: libc::c_int, pid: i32) -> Result<(), WatchPidError> {
    let kev = libc::kevent {
        ident: pid as libc::uintptr_t,
        filter: libc::EVFILT_PROC,      // 监控进程事件
        flags: libc::EV_ADD | libc::EV_CLEAR,
        fflags: libc::NOTE_FORK | libc::NOTE_EXEC | libc::NOTE_EXIT,
        data: 0,
        udata: std::ptr::null_mut(),
    };
    // ...
}
```

### 停止机制（User Event）

使用 `EVFILT_USER` 创建自定义停止事件：

```rust
const STOP_IDENT: libc::uintptr_t = 1;

fn register_stop_event(kq: libc::c_int) -> bool {
    let kev = libc::kevent {
        ident: STOP_IDENT,
        filter: libc::EVFILT_USER,      // 用户自定义事件
        flags: libc::EV_ADD | libc::EV_CLEAR,
        // ...
    };
    // ...
}

fn trigger_stop_event(kq: libc::c_int) {
    // 触发 NOTE_TRIGGER 通知追踪循环退出
}
```

### 子进程发现流程

```rust
fn list_child_pids(parent: i32) -> Vec<i32> {
    // 使用 proc_listchildpids 系统调用
    // 动态扩容缓冲区直到获取完整列表
    loop {
        let mut buf: Vec<i32> = vec![0; capacity];
        let count = proc_listchildpids(
            parent as libc::c_int,
            buf.as_mut_ptr() as *mut libc::c_void,
            (buf.len() * std::mem::size_of::<i32>()) as libc::c_int,
        );
        // 处理返回值，必要时扩容
    }
}
```

### 主追踪循环逻辑

```rust
fn track_descendants(kq: libc::c_int, root_pid: i32) -> HashSet<i32> {
    // 1. 注册停止事件
    // 2. 初始化 seen/active 集合
    // 3. 添加根进程监控
    
    loop {
        // 如果 active 为空但根进程仍存活，重新添加监控
        if active.is_empty() {
            if !pid_is_alive(root_pid) { break; }
            add_pid_watch(kq, root_pid, &mut seen, &mut active);
        }
        
        // 等待 kqueue 事件
        let nev = libc::kevent(kq, ..., events.as_mut_ptr(), ...);
        
        // 处理事件
        for ev in events.iter().take(nev as usize) {
            // NOTE_FORK: 监控新子进程
            // NOTE_EXIT: 从 active 移除
            // EVFILT_USER + STOP_IDENT: 停止请求
        }
    }
}
```

---

## 关键代码路径与文件引用

### 本文件关键函数

| 函数 | 行号 | 职责 |
|------|------|------|
| `PidTracker::new` | 13-22 | 创建 kqueue，启动追踪任务 |
| `PidTracker::stop` | 24-27 | 触发停止事件，等待结果 |
| `track_descendants` | 185-275 | 主追踪循环 |
| `add_pid_watch` | 122-150 | 添加进程监控，递归处理子进程 |
| `watch_pid` | 83-108 | 使用 kevent 注册进程监控 |
| `list_child_pids` | 39-60 | 调用 proc_listchildpids 获取子进程 |
| `register_stop_event` | 153-165 | 注册用户停止事件 |
| `trigger_stop_event` | 167-182 | 触发停止通知 |

### 调用方

**seatbelt.rs**（同目录）
```rust
// DenialLogger 使用 PidTracker 追踪沙箱子进程
pub(crate) fn on_child_spawn(&mut self, child: &Child) {
    if let Some(root_pid) = child.id() {
        self.pid_tracker = PidTracker::new(root_pid as i32);
    }
}

pub(crate) async fn finish(mut self) -> Vec<SandboxDenial> {
    let pid_set = match self.pid_tracker {
        Some(tracker) => tracker.stop().await,
        None => Default::default(),
    };
    // 使用 pid_set 过滤日志...
}
```

**debug_sandbox.rs**（父模块）
```rust
// 在 spawn 子进程后启动追踪
#[cfg(target_os = "macos")]
if let Some(denial_logger) = &mut denial_logger {
    denial_logger.on_child_spawn(&child);
}

// 在子进程结束后收集拒绝日志
#[cfg(target_os = "macos")]
if let Some(denial_logger) = denial_logger {
    let denials = denial_logger.finish().await;
    // 打印拒绝信息...
}
```

### 被调用方（系统调用）

| 系统调用 | 用途 |
|----------|------|
| `kqueue()` | 创建内核事件队列 |
| `kevent()` | 注册/等待事件 |
| `proc_listchildpids()` | 获取子进程列表（macOS 私有 API） |
| `kill(pid, 0)` | 检查进程是否存活 |
| `close()` | 关闭 kqueue 描述符 |

---

## 依赖与外部交互

### 外部依赖

```toml
# Cargo.toml (codex-cli)
[dependencies]
tokio = { workspace = true, features = ["process", "rt-multi-thread"] }
tracing = { workspace = true }
libc = { workspace = true }
```

### 模块依赖图

```
pid_tracker.rs
    ├── libc (kqueue, proc_listchildpids)
    ├── tokio::task (spawn_blocking, JoinHandle)
    ├── tokio::sync (异步等待)
    └── tracing::warn (错误日志)
    
被 seatbelt.rs 依赖
    └── DenialLogger (on_child_spawn, finish)
    
被 debug_sandbox.rs 间接使用
    └── run_command_under_seatbelt (通过 DenialLogger)
```

### 平台限制

- **仅 macOS**：依赖 `proc_listchildpids` 和 `kqueue` 的 `EVFILT_PROC`
- 编译条件：`#[cfg(target_os = "macos")]`

---

## 风险、边界与改进建议

### 已知风险

1. **竞争条件（Race Condition）**
   - 问题：在 `list_child_pids` 和 `watch_pid` 之间，子进程可能已经 fork 了更多子进程
   - 缓解：`NOTE_FORK` 事件会捕获新 fork 的子进程，但可能短暂遗漏

2. **进程 ID 复用**
   - 问题：PID 可能在被监控进程退出后被新进程复用
   - 缓解：使用 `seen` 集合去重，且监控周期通常较短

3. **系统调用失败**
   - `proc_listchildpids` 可能返回错误（如权限不足）
   - `kevent` 可能因 `ESRCH`（进程不存在）失败

4. **内存使用**
   - `list_child_pids` 使用动态扩容，极端情况下可能占用较多内存

### 边界条件

| 场景 | 处理 |
|------|------|
| root_pid <= 0 | 返回 None，不创建追踪器 |
| kqueue 创建失败 | 返回只包含 root_pid 的集合 |
| 停止事件注册失败 | 关闭 kqueue，返回只包含 root_pid 的集合 |
| 进程在监控前退出 | `watch_pid` 返回 `ProcessGone`，从 active 移除 |
| 信号中断 | 主循环捕获 `ErrorKind::Interrupted` 继续 |

### 改进建议

1. **增强错误处理**
   - 当前某些错误仅记录 warn 日志，可考虑更严格的错误传播
   - 添加 metrics 收集监控失败率

2. **性能优化**
   - `list_child_pids` 的初始容量 16 可能偏小，可根据常见场景调整
   - 考虑使用 `KERN_PROC` sysctl 作为备选方案

3. **可测试性**
   - 当前测试依赖真实进程创建，可考虑抽象系统调用接口
   - 添加更多边界条件测试（如大量子进程场景）

4. **文档完善**
   - 添加更多关于 `proc_listchildpids` 行为的注释
   - 说明与 `kqueue` 的 `NOTE_TRACK`（如果可用）的区别

5. **跨平台考虑**
   - 虽然当前仅 macOS，但可考虑定义通用接口
   - Linux 可使用 `pidfd` + `inotify` 或 `netlink` 实现类似功能

### 相关测试

```rust
// pid_tracker.rs 内置测试 (行 277-371)
#[cfg(test)]
mod tests {
    // pid_is_alive_detects_current_process - 基础功能测试
    // list_child_pids_includes_spawned_child - 子进程发现测试
    // pid_tracker_collects_spawned_children - 集成测试
    // pid_tracker_collects_bash_subshell_descendants - 复杂场景测试
}
```

测试覆盖：
- 当前进程存活检测
- 子进程列表获取
- 基础追踪功能
- Bash subshell 后代追踪
