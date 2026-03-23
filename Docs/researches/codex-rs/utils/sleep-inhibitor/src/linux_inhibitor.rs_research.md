# linux_inhibitor.rs 研究文档

## 场景与职责

`linux_inhibitor.rs` 是 `codex-utils-sleep-inhibitor` crate 的 **Linux 平台实现**，负责在 Linux 系统上阻止空闲睡眠。由于 Linux 桌面环境多样化，该实现采用**子进程策略**，通过调用外部命令（`systemd-inhibit` 或 `gnome-session-inhibit`）来实现睡眠抑制。

**核心设计决策**：
1. **子进程模型**：不同于 macOS/Windows 的直接 API 调用，Linux 实现启动一个长时间运行的子进程来持有抑制锁
2. **双后端支持**：优先尝试 `systemd-inhibit`，回退到 `gnome-session-inhibit`
3. **父进程死亡信号（PDEATHSIG）**：确保父进程崩溃时子进程自动终止

## 功能点目的

### 1. 双后端支持
- **systemd-inhibit**：现代 Linux 发行版的标准方式，支持细粒度控制（idle/sleep/关机）
- **gnome-session-inhibit**：GNOME 桌面环境的传统方式，兼容性更好

### 2. 后端优先级与记忆
- **目的**：避免每次都在两个后端间反复尝试
- **实现**：`preferred_backend` 字段记住上次成功的后端

### 3. 子进程生命周期管理
- **启动**：使用 `prctl(PR_SET_PDEATHSIG, SIGTERM)` 确保孤儿进程被清理
- **监控**：通过 `try_wait()` 检测子进程是否意外退出
- **清理**：`release()` 方法发送 `SIGKILL` 并等待子进程结束

### 4. 优雅降级
- **目的**：当没有可用后端时，不阻止程序继续运行
- **实现**：记录警告日志，静默失败

## 具体技术实现

### 核心数据结构

```rust
#[derive(Debug, Default)]
pub(crate) struct LinuxSleepInhibitor {
    state: InhibitState,                    // 当前抑制状态
    preferred_backend: Option<LinuxBackend>, // 首选后端（记忆化）
    missing_backend_logged: bool,           // 避免重复日志
}

#[derive(Debug, Default)]
enum InhibitState {
    #[default]
    Inactive,
    Active {
        backend: LinuxBackend,  // 当前使用的后端
        child: Child,           // 子进程句柄
    },
}

#[derive(Debug, Clone, Copy)]
enum LinuxBackend {
    SystemdInhibit,
    GnomeSessionInhibit,
}
```

### 命令构造

#### systemd-inhibit
```rust
systemd-inhibit \
    --what=idle \           # 仅阻止空闲睡眠
    --mode=block \          # 阻塞模式（非延迟）
    --who codex \           # 应用标识
    --why "Codex is running an active turn" \
    -- sleep 2147483647     # 保持运行的命令（i32::MAX 秒）
```

#### gnome-session-inhibit
```rust
gnome-session-inhibit \
    --inhibit idle \        # 阻止空闲
    --reason "Codex is running an active turn" \
    sleep 2147483647
```

### 关键流程

#### acquire() 流程
```
1. 检查当前状态
   └── 如果已激活，检查子进程是否仍在运行
       ├── 运行中 → 直接返回
       └── 已退出 → 记录警告，继续启动新进程

2. 确定后端尝试顺序
   └── 如果有 preferred_backend，优先尝试
       └── 失败则尝试另一个

3. 尝试启动后端
   └── 对每个后端：
       ├── spawn_backend() → 启动子进程
       ├── try_wait() → 检查是否立即退出
       │   ├── 成功运行 → 保存状态，设置 preferred_backend
       │   └── 立即退出 → 记录日志，尝试下一个
       └── 所有后端失败 → 记录 "No Linux sleep inhibitor backend is available"
```

#### 子进程启动（关键安全代码）

```rust
fn spawn_backend(backend: LinuxBackend) -> Result<Child, std::io::Error> {
    // 在 spawn 前捕获父进程 PID
    let parent_pid = unsafe { libc::getpid() };
    
    // 构造命令...
    
    unsafe {
        command.pre_exec(move || {
            // 设置父进程死亡信号
            if libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM) == -1 {
                return Err(std::io::Error::last_os_error());
            }
            // 检查父进程是否已在设置前退出（竞态条件防护）
            if libc::getppid() != parent_pid {
                libc::raise(libc::SIGTERM);
            }
            Ok(())
        });
    }
    
    command.spawn()
}
```

**安全分析**：
- `PR_SET_PDEATHSIG` 确保父进程死亡时子进程收到 `SIGTERM`
- `getppid()` 检查防止 fork/exec 竞态：如果父进程在 `prctl` 前退出，子进程会立即自杀

### 错误处理策略

| 错误场景 | 处理方式 | 日志级别 |
|----------|----------|----------|
| 后端命令未找到 | 静默跳过（仅首次记录） | warn（首次） |
| 后端立即退出 | 尝试下一个后端 | warn |
| 状态查询失败 | 尝试重启后端 | warn |
| kill 失败（已退出） | 忽略 | 无 |
| wait 失败 | 记录警告 | warn |

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/utils/sleep-inhibitor/src/linux_inhibitor.rs`（240 行）

### 调用路径
```
lib.rs (SleepInhibitor::acquire/release)
  └── linux_inhibitor.rs (本文件)
       ├── spawn_backend()
       │   ├── Command::new("systemd-inhibit")
       │   └── Command::new("gnome-session-inhibit")
       └── libc::prctl() / libc::getppid()
```

### 依赖文件
| 文件 | 关系 |
|------|------|
| `lib.rs` | 公共接口，条件编译选择本模块 |
| `Cargo.toml` | 声明 `libc` 依赖（Linux 特定） |

## 依赖与外部交互

### 编译时依赖
```toml
[target.'cfg(target_os = "linux")'.dependencies]
libc = { workspace = true }
```

### 运行时外部依赖
| 依赖 | 用途 | 可选性 |
|------|------|--------|
| `systemd-inhibit` | 首选睡眠抑制后端 | 是（可回退） |
| `gnome-session-inhibit` | 回退后端 | 是 |
| `sleep` | 保持子进程运行 | 否（POSIX 标准） |

### 系统调用
| 调用 | 用途 |
|------|------|
| `getpid()` | 获取父进程 PID |
| `prctl(PR_SET_PDEATHSIG)` | 设置父进程死亡信号 |
| `getppid()` | 检查父进程是否已变更 |
| `raise(SIGTERM)` | 自我终止 |

## 风险、边界与改进建议

### 当前风险

#### 1. 后端可用性依赖
- **风险**：最小化/容器化 Linux 环境可能没有 `systemd-inhibit` 或 `gnome-session-inhibit`
- **影响**：睡眠抑制功能 silently 不可用
- **缓解**：调用方应提供配置选项让用户知晓此限制

#### 2. 子进程资源泄漏
- **风险**：如果 `release()` 未被调用（如 panic），子进程可能成为孤儿
- **缓解**：
  - 实现了 `Drop` trait 调用 `release()`
  - PDEATHSIG 作为最后防线

#### 3. 长时间运行的子进程
- **风险**：`sleep 2147483647`（约 68 年）理论上可能因系统时间调整而提前唤醒
- **实际影响**：极低，系统时间向前调整不会唤醒 sleep

#### 4. 命令注入风险
- **分析**：命令参数都是硬编码常量，无用户输入
- **安全状态**：安全

### 边界情况

#### 1. 后端进程被外部杀死
```rust
// acquire() 中的检测逻辑
if let InhibitState::Active { backend, child } = &mut self.state {
    match child.try_wait() {
        Ok(None) => return,  // 仍在运行
        Ok(Some(status)) => {
            warn!("backend exited unexpectedly; attempting fallback");
            // 继续尝试重新启动
        }
        // ...
    }
}
```

#### 2. 快速切换
多次快速调用 `acquire/release` 可能导致子进程频繁创建/销毁：
- 已缓解：`acquire()` 检查现有活跃状态
- 潜在优化：增加防抖延迟

#### 3. 日志洪水控制
```rust
missing_backend_logged: bool  // 防止重复记录 "No backend available"
should_log_backend_failures   // 每次 acquire 序列只记录一次失败
```

### 改进建议

#### 1. 增加更多 Linux 后端
```rust
enum LinuxBackend {
    SystemdInhibit,
    GnomeSessionInhibit,
    Xautolock,      // X11 环境
    Caffeine,       // 第三方工具
    XdgScreenSaver, // xdg-screensaver
}
```

#### 2. 支持 Wayland 原生协议
考虑使用 `idle-inhibit` Wayland 协议（通过 `wayland-client` crate），避免子进程开销。

#### 3. 配置化后端优先级
允许用户通过配置指定首选后端：
```rust
pub(crate) fn with_preferred_backend(backend: LinuxBackend) -> Self {
    // ...
}
```

#### 4. 健康检查接口
```rust
impl LinuxSleepInhibitor {
    pub(crate) fn is_healthy(&self) -> bool {
        matches!(self.state, InhibitState::Active { .. })
    }
    
    pub(crate) fn backend_info(&self) -> Option<LinuxBackend> {
        // 返回当前/上次成功的后端
    }
}
```

#### 5. 改进子进程保活
当前使用 `sleep` 命令，可考虑使用更轻量的方式：
- 使用 Rust 编写的最小化保持程序
- 使用 `pause()` 系统调用代替 `sleep`

### 测试建议

#### 单元测试（当前）
```rust
#[test]
fn sleep_seconds_is_i32_max() {
    assert_eq!(BLOCKER_SLEEP_SECONDS, format!("{}", i32::MAX));
}
```

#### 建议增加的测试
1. **后端可用性检测**：测试在没有后端的环境中优雅降级
2. **子进程清理**：验证 `Drop` 是否正确终止子进程
3. **PDEATHSIG 验证**：模拟父进程崩溃，验证子进程是否退出
4. **后端切换**：测试首选后端失败后回退到另一后端

### 性能考虑

| 操作 | 开销 | 优化建议 |
|------|------|----------|
| spawn_backend | 高（进程创建） | 避免频繁切换 |
| try_wait | 低（非阻塞） | 当前实现合理 |
| kill + wait | 中 | 仅在 release 时发生 |
