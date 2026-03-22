# Sleep Inhibitor 模块研究文档

## 目录
- [场景与职责](#场景与职责)
- [功能点目的](#功能点目的)
- [具体技术实现](#具体技术实现)
- [关键代码路径与文件引用](#关键代码路径与文件引用)
- [依赖与外部交互](#依赖与外部交互)
- [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 业务场景

Sleep Inhibitor（睡眠抑制器）是 Codex CLI/TUI 的一个跨平台工具模块，用于在 AI Agent 执行长时间任务时防止计算机进入空闲睡眠状态。这在以下场景尤为重要：

1. **长时间代码生成任务**：当 Codex 正在生成大量代码或执行复杂操作时，用户可能离开电脑，但希望任务持续进行
2. **后台执行命令**：当 Agent 执行耗时较长的 shell 命令或工具调用时
3. **实时对话模式**：在实时语音对话期间保持系统活跃

### 模块职责

该模块的核心职责包括：

1. **跨平台睡眠抑制**：在 macOS、Linux、Windows 三大主流平台上提供统一的睡眠抑制能力
2. **生命周期管理**：与 Agent Turn（对话回合）的生命周期绑定，在任务开始时抑制睡眠，任务结束后恢复
3. **优雅降级**：在不支持的平台或配置禁用时，提供无操作的空实现
4. **资源安全**：确保在异常情况下（如进程崩溃）能够正确释放系统资源

---

## 功能点目的

### 主要功能

| 功能点 | 目的 | 触发时机 |
|--------|------|----------|
| `acquire()` | 获取睡眠抑制锁，阻止系统进入空闲睡眠 | Agent Turn 开始时 |
| `release()` | 释放睡眠抑制锁，允许系统正常睡眠 | Agent Turn 结束时 |
| `set_turn_running(bool)` | 根据 Turn 状态自动管理睡眠抑制 | Turn 状态变化时 |
| 平台检测与回退 | 自动选择最佳后端，支持优雅降级 | 初始化时 |

### 平台支持矩阵

| 平台 | 实现方式 | 技术细节 |
|------|----------|----------|
| **macOS** | IOKit Power Assertions | 使用 `IOPMAssertionCreateWithName` 创建 `PreventUserIdleSystemSleep` 类型的电源断言 |
| **Linux** | 子进程方式 | 优先使用 `systemd-inhibit`，回退到 `gnome-session-inhibit` |
| **Windows** | Power Request API | 使用 `PowerCreateRequest` + `PowerSetRequest` 配合 `PowerRequestSystemRequired` |
| **其他** | 空实现 (No-op) | 无任何副作用 |

### 配置控制

该功能通过 Feature Flag 控制：

- **Feature Key**: `prevent_idle_sleep`
- **配置位置**: `config.toml` 的 `[features]` 段或 `/experimental` 菜单
- **默认状态**: 禁用（`default_enabled: false`）
- **开发阶段**: Experimental（实验性功能）

---

## 具体技术实现

### 1. 核心架构设计

```
┌─────────────────────────────────────────────────────────────┐
│                    SleepInhibitor (lib.rs)                  │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   enabled   │  │ turn_running│  │   platform (imp)    │  │
│  │    bool     │  │    bool     │  │  SleepInhibitor     │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
   ┌────▼────┐          ┌────▼────┐          ┌────▼────┐
   │  macOS  │          │  Linux  │          │ Windows │
   │  (IOKit)│          │(systemd │          │(Power  │
   │         │          │ inhibit)│          │Request)│
   └─────────┘          └─────────┘          └─────────┘
```

### 2. 关键数据结构

#### 2.1 主结构体 (`lib.rs`)

```rust
pub struct SleepInhibitor {
    enabled: bool,           // 功能是否启用
    turn_running: bool,      // 当前是否有 Turn 在运行
    platform: imp::SleepInhibitor,  // 平台特定实现
}
```

#### 2.2 Linux 实现状态机 (`linux_inhibitor.rs`)

```rust
enum InhibitState {
    Inactive,
    Active {
        backend: LinuxBackend,
        child: Child,        // 子进程句柄
    },
}

enum LinuxBackend {
    SystemdInhibit,         // 优先尝试
    GnomeSessionInhibit,    // 回退方案
}
```

#### 2.3 macOS 实现 (`macos.rs`)

```rust
struct SleepInhibitor {
    assertion: Option<MacSleepAssertion>,
}

struct MacSleepAssertion {
    id: IOPMAssertionID,    // IOKit 断言 ID
}
```

#### 2.4 Windows 实现 (`windows_inhibitor.rs`)

```rust
struct WindowsSleepInhibitor {
    request: Option<PowerRequest>,
}

struct PowerRequest {
    handle: HANDLE,          // Windows 电源请求句柄
    request_type: POWER_REQUEST_TYPE,
}
```

### 3. 关键流程

#### 3.1 Turn 状态变更流程

```
ChatWidget.on_task_started()
    │
    ▼
SleepInhibitor.set_turn_running(true)
    │
    ├── enabled = false ──► release() [提前返回]
    │
    └── enabled = true ───► acquire()
                              │
            ┌─────────────────┼─────────────────┐
            ▼                 ▼                 ▼
        macOS::acquire()  Linux::acquire()  Windows::acquire()
```

#### 3.2 Linux 后端选择流程

```
acquire()
    │
    ▼
检查当前状态是否有效 ──► 有效 ──► 直接返回
    │
    ▼ 无效或不存在
尝试 SystemdInhibit
    │
    ├── 成功 ──► 记录为首选后端
    │
    └── 失败 ──► 尝试 GnomeSessionInhibit
                    │
                    ├── 成功 ──► 记录为首选后端
                    │
                    └── 失败 ──► 记录警告，下次尝试时跳过
```

### 4. 平台特定实现细节

#### 4.1 macOS IOKit 集成

使用 `rust-bindgen` 生成的 FFI 绑定 (`iokit_bindings.rs`)：

```rust
// 关键 FFI 函数
pub fn IOPMAssertionCreateWithName(
    AssertionType: CFStringRef,
    AssertionLevel: IOPMAssertionLevel,
    AssertionName: CFStringRef,
    AssertionID: *mut IOPMAssertionID,
) -> IOReturn;

pub fn IOPMAssertionRelease(AssertionID: IOPMAssertionID) -> IOReturn;
```

断言类型：`PreventUserIdleSystemSleep`（阻止用户空闲时的系统睡眠，但允许显示器关闭）

#### 4.2 Linux 子进程管理

关键设计决策：

1. **使用 `sleep` 命令保持子进程存活**：
   ```rust
   const BLOCKER_SLEEP_SECONDS: &str = "2147483647"; // i32::MAX
   ```

2. **PDEATHSIG 机制**：使用 `prctl(PR_SET_PDEATHSIG, SIGTERM)` 确保父进程退出时子进程自动终止

3. **父进程 PID 检查**：避免 fork/exec 竞态条件
   ```rust
   if libc::getppid() != parent_pid {
       libc::raise(libc::SIGTERM);
   }
   ```

4. **后端优先级记忆**：记录上次成功的后端，下次优先尝试

#### 4.3 Windows Power Request

使用 `REASON_CONTEXT` 结构创建电源请求：

```rust
let context = REASON_CONTEXT {
    Version: POWER_REQUEST_CONTEXT_VERSION,
    Flags: POWER_REQUEST_CONTEXT_SIMPLE_STRING,
    Reason: REASON_CONTEXT_0 {
        SimpleReasonString: wide_reason.as_mut_ptr(),
    },
};
```

请求类型：`PowerRequestSystemRequired`（防止系统进入睡眠，但允许显示器关闭）

### 5. 资源安全机制

所有平台实现都使用 Rust 的 `Drop` trait 确保资源释放：

- **macOS**: `MacSleepAssertion::Drop` 调用 `IOPMAssertionRelease`
- **Linux**: `LinuxSleepInhibitor::Drop` 调用 `release()` 杀死子进程
- **Windows**: `PowerRequest::Drop` 调用 `PowerClearRequest` 和 `CloseHandle`

---

## 关键代码路径与文件引用

### 文件结构

```
codex-rs/utils/sleep-inhibitor/src/
├── lib.rs                  # 主模块，跨平台抽象
├── dummy.rs                # 空实现（不支持的平台）
├── macos.rs                # macOS IOKit 实现
├── iokit_bindings.rs       # IOKit FFI 绑定（bindgen 生成）
├── linux_inhibitor.rs      # Linux 子进程实现
└── windows_inhibitor.rs    # Windows Power Request 实现
```

### 关键代码路径

#### 初始化路径

```
codex-rs/tui/src/chatwidget.rs:3605
    SleepInhibitor::new(prevent_idle_sleep)
        │
        ▼
codex-rs/utils/sleep-inhibitor/src/lib.rs:37-43
    pub fn new(enabled: bool) -> Self {
        Self {
            enabled,
            turn_running: false,
            platform: imp::SleepInhibitor::new(),
        }
    }
```

#### Turn 开始路径

```
codex-rs/tui/src/chatwidget.rs:1693-1696
    fn on_task_started(&mut self) {
        self.agent_turn_running = true;
        self.turn_sleep_inhibitor.set_turn_running(true);
        ...
    }
        │
        ▼
codex-rs/utils/sleep-inhibitor/src/lib.rs:46-58
    pub fn set_turn_running(&mut self, turn_running: bool) {
        self.turn_running = turn_running;
        if !self.enabled { ... }
        if turn_running { self.acquire(); } else { self.release(); }
    }
```

#### Turn 结束路径

```
codex-rs/tui/src/chatwidget.rs:1758-1763
    self.agent_turn_running = false;
    self.turn_sleep_inhibitor.set_turn_running(false);
        │
        ▼
// 同上，最终调用 platform.release()
```

#### Feature 切换路径

```
codex-rs/tui/src/chatwidget.rs:7879-7883
    if feature == Feature::PreventIdleSleep {
        self.turn_sleep_inhibitor = SleepInhibitor::new(enabled);
        self.turn_sleep_inhibitor.set_turn_running(self.agent_turn_running);
    }
```

### 测试代码路径

```
codex-rs/utils/sleep-inhibitor/src/lib.rs:74-113
    mod tests {
        // 基础功能测试
        fn sleep_inhibitor_toggles_without_panicking()
        fn sleep_inhibitor_disabled_does_not_panic()
        fn sleep_inhibitor_multiple_true_calls_are_idempotent()
        fn sleep_inhibitor_can_toggle_multiple_times()
    }

codex-rs/utils/sleep-inhibitor/src/linux_inhibitor.rs:232-240
    mod tests {
        // Linux 特定测试
        fn sleep_seconds_is_i32_max()
    }
```

---

## 依赖与外部交互

### 内部依赖

| 依赖模块 | 用途 | 路径 |
|----------|------|------|
| `tracing` | 日志记录 | 工作区共享 |

### 平台特定依赖

#### macOS

```toml
[target.'cfg(target_os = "macos")'.dependencies]
core-foundation = "0.9"  # CFString 等 Core Foundation 类型
```

#### Linux

```toml
[target.'cfg(target_os = "linux")'.dependencies]
libc = { workspace = true }  # prctl, getpid, getppid
```

依赖外部命令：
- `systemd-inhibit` (systemd 239+)
- `gnome-session-inhibit` (GNOME Session)
- `sleep` (标准 POSIX 工具)

#### Windows

```toml
[target.'cfg(target_os = "windows")'.dependencies]
windows-sys = { version = "0.61.2", features = [
    "Win32_Foundation",
    "Win32_System_Power",
    "Win32_System_SystemServices",
    "Win32_System_Threading",
] }
```

### 调用方模块

```
┌──────────────────────────────────────────────────────────────┐
│                      调用方模块                               │
├──────────────────────────────────────────────────────────────┤
│ codex-rs/tui/src/chatwidget.rs                               │
│   - turn_sleep_inhibitor: SleepInhibitor                     │
│   - on_task_started() -> set_turn_running(true)              │
│   - on_task_stopped() -> set_turn_running(false)             │
│   - finalize_turn() -> set_turn_running(false)               │
│   - on_feature_changed() -> 重新创建 SleepInhibitor          │
├──────────────────────────────────────────────────────────────┤
│ codex-rs/tui_app_server/src/chatwidget.rs                    │
│   - 与 tui 模块完全相同的实现模式                            │
└──────────────────────────────────────────────────────────────┘
```

### 配置依赖

```
codex-rs/core/src/features.rs
    ├── Feature::PreventIdleSleep 定义
    ├── FeatureSpec { key: "prevent_idle_sleep", ... }
    └── Stage::Experimental { name: "Prevent sleep while running", ... }
```

---

## 风险、边界与改进建议

### 已知风险

#### 1. Linux 后端可用性风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 命令不存在 | `systemd-inhibit` 或 `gnome-session-inhibit` 未安装 | 自动回退到另一后端，静默失败 |
| 权限不足 | 非 systemd/GNOME 会话环境 | 记录警告，不影响主程序运行 |
| 子进程泄漏 | 极端情况下子进程可能成为僵尸 | PDEATHSIG 机制 + Drop 实现 |

#### 2. 竞态条件风险

```rust
// Linux 实现中的潜在竞态
unsafe {
    command.pre_exec(move || {
        if libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM) == -1 { ... }
        if libc::getppid() != parent_pid {  // 检查父进程 PID
            libc::raise(libc::SIGTERM);     // 父进程已退出则自终止
        }
        Ok(())
    });
}
```

当前实现通过 `getppid()` 检查缓解了 fork/exec 竞态，但在极高负载下仍可能存在窗口。

#### 3. 跨平台行为差异

| 行为 | macOS | Linux | Windows |
|------|-------|-------|---------|
| 显示器保持开启 | ❌ 否 | ❌ 否 | ❌ 否 |
| 阻止系统睡眠 | ✅ 是 | ✅ 是 | ✅ 是 |
| 阻止磁盘休眠 | ❌ 否 | ❌ 否 | ❌ 否 |

所有平台统一使用"阻止空闲系统睡眠但不保持显示器开启"的策略，符合 CLI 工具的预期行为。

### 边界情况

1. **多次调用 `acquire()`**：幂等处理，不会创建重复断言
2. **多次调用 `release()`**：安全处理，不会 panic
3. **父进程崩溃**：
   - macOS/Windows：OS 自动清理资源
   - Linux：PDEATHSIG 确保子进程退出
4. **配置热切换**：重新创建 `SleepInhibitor` 实例，自动释放旧资源

### 改进建议

#### 1. 增强 Linux 后端覆盖

```rust
// 建议添加更多后端支持
enum LinuxBackend {
    SystemdInhibit,
    GnomeSessionInhibit,
    XScreenSaver,      // X11 环境
    IdleInhibit,       // Wayland 通用
}
```

#### 2. 添加运行时状态查询

```rust
// 建议添加
impl SleepInhibitor {
    pub fn is_active(&self) -> bool {
        self.enabled && self.turn_running && self.platform.is_acquired()
    }
}
```

#### 3. 改进错误报告

当前实现仅记录警告日志，建议：
- 添加指标上报（otel）
- 在 TUI 状态栏显示睡眠抑制状态
- 提供 `/status` 命令查询后端健康度

#### 4. 测试增强

```rust
// 建议添加集成测试
#[test]
fn sleep_inhibitor_lifecycle() {
    // 验证 acquire -> release 完整周期
}

#[test]
fn sleep_inhibitor_parent_death() {
    // 验证父进程退出时子进程正确清理
}
```

#### 5. 文档改进

- 添加架构图到模块文档
- 记录各平台系统要求（最低 Windows 版本、systemd 版本等）
- 添加故障排查指南

### 性能考量

| 指标 | 当前实现 | 备注 |
|------|----------|------|
| 内存占用 | ~24 bytes | 仅状态字段，无缓冲区 |
| 初始化开销 | <1ms | 仅创建结构体 |
| acquire 延迟 | 平台相关 | Linux 需要 spawn 子进程 (~10-50ms) |
| release 延迟 | 平台相关 | Linux 需要 kill + wait (~5-20ms) |

Linux 子进程方式相比 D-Bus 直接调用有更高的延迟，但实现更简单且无需异步运行时依赖。

---

## 总结

Sleep Inhibitor 模块是一个设计良好的跨平台工具，通过条件编译和平台抽象实现了统一的睡眠抑制 API。其关键优势包括：

1. **零成本抽象**：不支持的平台编译为空实现，无运行时开销
2. **资源安全**：全面的 Drop 实现确保资源释放
3. **优雅降级**：Linux 多后端策略确保最大兼容性
4. **与业务逻辑解耦**：通过 `set_turn_running` 接口与 ChatWidget 生命周期自然集成

该模块符合 Codex CLI 的设计理念：在需要时提供平台原生能力，同时保持代码的可移植性和可维护性。
