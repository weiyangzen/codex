# Sleep Inhibitor 组件研究文档

## 1. 场景与职责

### 1.1 业务场景

Sleep Inhibitor（睡眠抑制器）是 Codex TUI 应用中的一个跨平台工具组件，用于在 AI 助手执行长时间运行的任务时防止计算机进入空闲睡眠状态。这在以下场景中尤为重要：

- **长时间代码生成**：当 Codex 正在生成大量代码或执行复杂的代码分析时
- **持续的工具调用**：当 AI 正在执行一系列 shell 命令、文件操作或 MCP 工具调用时
- **后台任务执行**：当用户等待 AI 完成某个耗时操作时

### 1.2 核心职责

1. **跨平台睡眠抑制**：在 macOS、Linux、Windows 三大主流桌面平台上阻止系统空闲睡眠
2. **生命周期管理**：与 "turn"（AI 助手的一次完整响应周期）的生命周期绑定
3. **资源安全释放**：确保在 turn 结束或程序异常退出时正确释放系统资源
4. **优雅降级**：在不支持的平台或缺少必要系统工具时静默失败，不影响主程序运行

### 1.3 架构定位

```
┌─────────────────────────────────────────────────────────────────┐
│                        ChatWidget (TUI)                         │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              turn_sleep_inhibitor: SleepInhibitor       │   │
│  └─────────────────────────────────────────────────────────┘   │
│                           │                                     │
│                           ▼                                     │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              SleepInhibitor (跨平台抽象层)               │   │
│  │  ┌─────────┐  ┌─────────────────┐  ┌─────────────────┐ │   │
│  │  │  macOS  │  │     Linux       │  │     Windows     │ │   │
│  │  │ IOKit   │  │ systemd-inhibit │  │ PowerCreateReq  │ │   │
│  │  │ 绑定    │  │ gnome-session   │  │ PowerSetRequest │ │   │
│  │  └─────────┘  └─────────────────┘  └─────────────────┘ │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 功能开关控制

| 配置项 | 说明 |
|--------|------|
| Feature Flag | `PreventIdleSleep` |
| 配置 Key | `prevent_idle_sleep` |
| 开发阶段 | Experimental（实验性）|
| 默认状态 | 禁用（false）|
| 支持平台 | macOS、Linux、Windows |

### 2.2 状态机设计

SleepInhibitor 内部维护两个核心状态：

```rust
pub struct SleepInhibitor {
    enabled: bool,        // 功能是否启用（由 Feature Flag 控制）
    turn_running: bool,   // 当前是否有 turn 在运行
    platform: imp::SleepInhibitor,  // 平台特定实现
}
```

状态转换逻辑：

```
                    set_turn_running(true)
                   ┌──────────────────────┐
                   │                      │
    ┌──────────┐   │   ┌──────────────┐   │   ┌──────────┐
    │  Idle    │───┘   │   Running    │───┘   │  Idle    │
    │ (释放)   │◄──────│   (抑制睡眠)  │◄──────│ (释放)   │
    └──────────┘       └──────────────┘       └──────────┘
        ▲                    │                    ▲
        │    set_turn_       │    set_turn_       │
        │    running(false)  │    running(false)  │
        │                    │                    │
        └────────────────────┴────────────────────┘
```

### 2.3 平台特定行为

| 平台 | 实现方式 | 技术细节 |
|------|----------|----------|
| macOS | IOKit Power Assertions | 使用 `IOPMAssertionCreateWithName` 创建 `PreventUserIdleSystemSleep` 类型的断言 |
| Linux | 子进程方式 | 优先尝试 `systemd-inhibit`，回退到 `gnome-session-inhibit` |
| Windows | Power Request API | 使用 `PowerCreateRequest` + `PowerSetRequest` + `PowerRequestSystemRequired` |
| 其他 | 空实现 (No-op) | 静默不执行任何操作 |

---

## 3. 具体技术实现

### 3.1 核心数据结构

#### 3.1.1 主结构体（lib.rs）

```rust
#[derive(Debug)]
pub struct SleepInhibitor {
    enabled: bool,           // 功能开关
    turn_running: bool,      // turn 运行状态
    platform: imp::SleepInhibitor,  // 平台特定实现（条件编译）
}
```

#### 3.1.2 Linux 实现（linux_inhibitor.rs）

```rust
#[derive(Debug, Default)]
pub(crate) struct LinuxSleepInhibitor {
    state: InhibitState,
    preferred_backend: Option<LinuxBackend>,  // 首选后端缓存
    missing_backend_logged: bool,             // 避免重复日志
}

#[derive(Debug, Default)]
enum InhibitState {
    #[default]
    Inactive,
    Active {
        backend: LinuxBackend,
        child: Child,  // 子进程句柄
    },
}

#[derive(Debug, Clone, Copy)]
enum LinuxBackend {
    SystemdInhibit,
    GnomeSessionInhibit,
}
```

#### 3.1.3 macOS 实现（macos.rs）

```rust
#[derive(Debug, Default)]
pub(crate) struct SleepInhibitor {
    assertion: Option<MacSleepAssertion>,
}

#[derive(Debug)]
struct MacSleepAssertion {
    id: IOPMAssertionID,  // IOKit 断言 ID
}
```

#### 3.1.4 Windows 实现（windows_inhibitor.rs）

```rust
#[derive(Debug, Default)]
pub(crate) struct WindowsSleepInhibitor {
    request: Option<PowerRequest>,
}

#[derive(Debug)]
struct PowerRequest {
    handle: HANDLE,              // Windows 电源请求句柄
    request_type: POWER_REQUEST_TYPE,
}
```

### 3.2 关键流程

#### 3.2.1 初始化流程

```rust
// 在 ChatWidget 初始化时创建
let prevent_idle_sleep = config.features.enabled(Feature::PreventIdleSleep);
// ...
turn_sleep_inhibitor: SleepInhibitor::new(prevent_idle_sleep),
```

#### 3.2.2 Turn 开始流程

```rust
fn on_task_started(&mut self) {
    self.agent_turn_running = true;
    self.turn_sleep_inhibitor.set_turn_running(true);  // 获取睡眠抑制
    // ...
}
```

#### 3.2.3 Turn 结束流程

```rust
fn on_task_completed(&mut self) {
    self.agent_turn_running = false;
    self.turn_sleep_inhibitor.set_turn_running(false);  // 释放睡眠抑制
    // ...
}
```

#### 3.2.4 Linux 后端启动流程

```
acquire()
    │
    ▼
检查当前状态 ──Active?──┬─Yes──► 检查子进程状态 ──Running?──┬─Yes──► 返回（已抑制）
    │                   │                                   │
    │                   No                                  No
    │                   │                                   │
    │                   ▼                                   ▼
    │              尝试启动后端                          记录警告
    │                   │                              标记为 Inactive
    │                   ▼                                   │
    └──────────► 按优先级尝试后端 ◄──────────────────────────┘
                      │
          ┌───────────┼───────────┐
          ▼           ▼           ▼
    systemd-inhibit  │   gnome-session-inhibit
          │           │           │
          └───────────┴───────────┘
                      │
                      ▼
              子进程启动成功?
                      │
            ┌─────────┴─────────┐
            ▼                   ▼
          Yes                  No
            │                   │
            ▼                   ▼
    记录首选后端            尝试下一个后端
    标记 Active
```

### 3.3 平台特定协议/命令

#### 3.3.1 Linux - systemd-inhibit

```bash
systemd-inhibit \
    --what=idle \
    --mode=block \
    --who "codex" \
    --why "Codex is running an active turn" \
    -- sleep 2147483647  # i32::MAX 秒
```

参数说明：
- `--what=idle`: 仅抑制空闲睡眠（不影响挂起/休眠）
- `--mode=block`: 阻塞模式（而非延迟模式）
- `--who/--why`: 标识和原因说明
- `sleep 2147483647`: 保持进程存活约 68 年

#### 3.3.2 Linux - gnome-session-inhibit

```bash
gnome-session-inhibit \
    --inhibit idle \
    --reason "Codex is running an active turn" \
    sleep 2147483647
```

#### 3.3.3 Linux - 子进程生命周期管理

使用 `PR_SET_PDEATHSIG` 确保父进程退出时子进程自动终止：

```rust
unsafe {
    command.pre_exec(move || {
        // 设置父进程死亡信号为 SIGTERM
        if libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM) == -1 {
            return Err(std::io::Error::last_os_error());
        }
        // 检查父进程是否已退出（避免竞态条件）
        if libc::getppid() != parent_pid {
            libc::raise(libc::SIGTERM);
        }
        Ok(())
    });
}
```

#### 3.3.4 macOS - IOKit API

```rust
// 创建电源断言
let result = unsafe {
    iokit::IOPMAssertionCreateWithName(
        assertion_type_ref,           // kIOPMAssertionTypePreventUserIdleSystemSleep
        kIOPMAssertionLevelOn,        // 开启断言
        assertion_name_ref,           // 断言名称
        &mut id,                      // 输出断言 ID
    )
};

// 释放电源断言
let result = unsafe {
    iokit::IOPMAssertionRelease(assertion_id)
};
```

#### 3.3.5 Windows - Power Request API

```rust
// 创建电源请求
let handle = unsafe { PowerCreateRequest(&context) };

// 设置系统必需请求（防止空闲睡眠）
let request_type = PowerRequestSystemRequired;
unsafe { PowerSetRequest(handle, request_type) };

// 清除请求
unsafe { PowerClearRequest(handle, request_type) };

// 关闭句柄
unsafe { CloseHandle(handle) };
```

---

## 4. 关键代码路径与文件引用

### 4.1 组件文件结构

```
codex-rs/utils/sleep-inhibitor/
├── Cargo.toml              # 包配置，定义平台特定依赖
├── BUILD.bazel            # Bazel 构建配置
└── src/
    ├── lib.rs             # 主接口，跨平台抽象
    ├── dummy.rs           # 不支持平台的空实现
    ├── macos.rs           # macOS IOKit 实现
    ├── iokit_bindings.rs  # IOKit FFI 绑定（bindgen 生成）
    ├── linux_inhibitor.rs # Linux 子进程实现
    └── windows_inhibitor.rs # Windows Power Request 实现
```

### 4.2 核心代码路径

| 文件 | 关键函数/结构 | 职责 |
|------|--------------|------|
| `src/lib.rs:29-72` | `SleepInhibitor` 结构体 | 跨平台抽象接口 |
| `src/lib.rs:46-58` | `set_turn_running()` | 状态转换主入口 |
| `src/linux_inhibitor.rs:43-143` | `acquire()` | Linux 后端启动逻辑 |
| `src/linux_inhibitor.rs:145-168` | `release()` + `Drop` | Linux 资源释放 |
| `src/linux_inhibitor.rs:170-226` | `spawn_backend()` | Linux 子进程创建 |
| `src/macos.rs:38-58` | `acquire()` / `release()` | macOS 断言管理 |
| `src/macos.rs:66-91` | `MacSleepAssertion::create()` | IOKit 断言创建 |
| `src/windows_inhibitor.rs:31-52` | `acquire()` / `release()` | Windows 请求管理 |
| `src/windows_inhibitor.rs:60-96` | `PowerRequest::new_system_required()` | Windows API 调用 |

### 4.3 调用方代码路径

| 文件 | 关键代码 | 场景 |
|------|---------|------|
| `tui/src/chatwidget.rs:681` | `turn_sleep_inhibitor: SleepInhibitor` | 字段声明 |
| `tui/src/chatwidget.rs:1693-1696` | `on_task_started()` | Turn 开始时启用抑制 |
| `tui/src/chatwidget.rs:1759-1762` | `on_task_completed()` | Turn 完成时释放抑制 |
| `tui/src/chatwidget.rs:2060-2063` | 错误处理路径 | Turn 异常结束时释放 |
| `tui/src/chatwidget.rs:2341-2344` | `restore_thread_input_state()` | 恢复线程状态时同步 |
| `tui/src/chatwidget.rs:7879-7882` | `set_feature_enabled()` | 功能开关切换时重建 |
| `tui_app_server/src/chatwidget.rs` | 同上 | TUI App Server 并行实现 |

### 4.4 配置与 Feature 定义

| 文件 | 关键代码 | 说明 |
|------|---------|------|
| `core/src/features.rs:186` | `PreventIdleSleep` | Feature ID 定义 |
| `core/src/features.rs:842-859` | FeatureSpec | 配置元数据（key、阶段、默认值） |
| `tui/Cargo.toml:54` | 依赖声明 | `codex-utils-sleep-inhibitor = { workspace = true }` |
| `tui_app_server/Cargo.toml` | 依赖声明 | 同上 |

---

## 5. 依赖与外部交互

### 5.1 内部依赖

```
codex-utils-sleep-inhibitor
    │
    ├── 被依赖方 ─────────────────────────────────────────┐
    │                                                      │
    ▼                                                      │
codex-tui (调用方)                                  codex-core
    │                                                      │
    ├── 使用 Feature::PreventIdleSleep 查询配置 ───────────┤
    │                                                      │
    └── 创建 SleepInhibitor 实例并管理生命周期 ◄───────────┘
```

### 5.2 外部依赖

| 平台 | 依赖库/工具 | 用途 | Cargo.toml 配置 |
|------|------------|------|----------------|
| 通用 | `tracing` | 日志记录 | `[dependencies]` |
| macOS | `core-foundation` | CFString 等 Core Foundation 类型 | `[target.'cfg(target_os = "macos")'.dependencies]` |
| Linux | `libc` | `prctl`, `getpid`, `getppid` | `[target.'cfg(target_os = "linux")'.dependencies]` |
| Windows | `windows-sys` | Power Request API | `[target.'cfg(target_os = "windows")'.dependencies]` |

### 5.3 系统依赖

| 平台 | 系统工具/库 | 用途 | 回退策略 |
|------|------------|------|---------|
| Linux | `systemd-inhibit` | 首选睡眠抑制后端 | 自动回退到 gnome-session-inhibit |
| Linux | `gnome-session-inhibit` | 备用睡眠抑制后端 | 静默失败（记录警告） |
| macOS | `IOKit.framework` | 电源断言 API | 无（系统内置） |
| Windows | `kernel32.dll` | Power Request API | 无（系统内置） |

### 5.4 FFI 绑定

#### IOKit 绑定（iokit_bindings.rs）

```rust
// bindgen 生成的 FFI 绑定
pub const kIOReturnSuccess: u32 = 0;
pub type IOReturn = kern_return_t;
pub type IOPMAssertionID = u32;
pub type IOPMAssertionLevel = u32;
pub const kIOPMAssertionLevelOn: _bindgen_ty_36 = 255;

unsafe extern "C" {
    pub fn IOPMAssertionRelease(AssertionID: IOPMAssertionID) -> IOReturn;
    pub fn IOPMAssertionCreateWithName(
        AssertionType: CFStringRef,
        AssertionLevel: IOPMAssertionLevel,
        AssertionName: CFStringRef,
        AssertionID: *mut IOPMAssertionID,
    ) -> IOReturn;
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 Linux 平台风险

| 风险 | 描述 | 缓解措施 |
|------|------|---------|
| 后端不可用 | 系统未安装 systemd 或 GNOME | 自动回退，静默失败 |
| 子进程泄漏 | 父进程崩溃时子进程可能成为孤儿 | 使用 `PR_SET_PDEATHSIG` |
| 竞态条件 | fork/exec 之间父进程退出 | `pre_exec` 中检查 `getppid()` |
| 长时间运行 | sleep i32::MAX 可能不适用于所有系统 | 使用标准值 2147483647 |

#### 6.1.2 跨平台风险

| 风险 | 描述 | 影响 |
|------|------|------|
| 资源泄漏 | 断言/句柄未正确释放 | 系统无法进入睡眠直到重启 |
| 重复获取 | 多次调用 `acquire()` | 通过状态检查实现幂等 |
| 功能开关竞态 | 切换 feature 时状态不一致 | 重建 SleepInhibitor 实例 |

### 6.2 边界情况

#### 6.2.1 已处理的边界

1. **多次启用/禁用**：`set_turn_running(true)` 多次调用是幂等的
2. **禁用状态下调用**：`enabled=false` 时调用 `set_turn_running(true)` 不会获取资源
3. **后端崩溃检测**：Linux 实现会检查子进程状态，崩溃时自动重启后端
4. **Drop 安全**：所有平台实现都实现了 `Drop` trait，确保资源释放

#### 6.2.2 潜在边界问题

1. **快速切换**：turn 快速开始/结束可能导致频繁创建/销毁资源
2. **多线程**：SleepInhibitor 不是 `Send + Sync`，但 TUI 是单线程事件循环
3. **信号安全**：Linux 的 `pre_exec` 中调用 `libc` 函数在信号处理上下文中

### 6.3 改进建议

#### 6.3.1 短期改进

1. **增加指标上报**
   ```rust
   // 建议添加
   tracing::info!(backend = ?backend, "sleep_inhibitor_acquired");
   tracing::info!(duration_ms = ?elapsed, "sleep_inhibitor_released");
   ```

2. **Linux 后端健康检查**
   - 当前仅在 `acquire()` 时检查子进程状态
   - 建议添加定期健康检查或监听子进程退出信号

3. **配置热重载优化**
   - 当前切换 feature 会重建整个 SleepInhibitor
   - 可考虑实现 `set_enabled()` 方法避免重建

#### 6.3.2 中期改进

1. **支持更多 Linux 桌面环境**
   ```rust
   // 可添加的后端
   enum LinuxBackend {
       SystemdInhibit,
       GnomeSessionInhibit,
       KdeInhibit,        // KDE 支持
       XdgPortalInhibit,  // Flatpak/沙盒环境
   }
   ```

2. **休眠/挂起区分**
   - 当前仅阻止空闲睡眠
   - 可考虑区分 `idle` vs `sleep` vs `hibernate`

3. **电池感知**
   - 在电池供电时自动禁用或降低抑制级别
   - 需要与系统电源管理集成

#### 6.3.3 长期改进

1. **异步化**
   - 当前为同步阻塞 API
   - 考虑使用 `tokio::process` 和异步 FFI（如 `io_uring`）

2. **跨平台统一抽象**
   - 考虑使用 `zbus` 等跨平台 D-Bus 库统一 Linux 实现
   - 探索 `winit` 或 `tao` 等跨平台窗口库的内置电源管理

3. **测试覆盖**
   - 当前测试仅验证状态机逻辑
   - 建议添加集成测试（需要模拟系统电源状态）

### 6.4 监控与调试

建议添加的日志和指标：

```rust
// 在 acquire/release 中添加结构化日志
tracing::info!(
    target: "sleep_inhibitor",
    action = "acquire",
    platform = %std::env::consts::OS,
    backend = ?backend,  // Linux only
    success = success,
);

// 添加 OpenTelemetry span
let _span = tracing::info_span!(
    "sleep_inhibition",
    turn_id = %turn_id,
).entered();
```

---

## 7. 总结

Sleep Inhibitor 是一个设计良好的跨平台工具组件，具有以下特点：

1. **清晰的抽象**：通过条件编译实现平台特定代码隔离
2. **安全的设计**：使用 RAII 模式（Drop trait）确保资源释放
3. **优雅降级**：在不支持的平台或缺少依赖时静默失败
4. **与业务逻辑解耦**：通过 `set_turn_running()` 与 turn 生命周期绑定

主要调用方是 TUI 的 `ChatWidget`，在 turn 开始/结束时同步睡眠抑制状态。功能通过 `PreventIdleSleep` feature flag 控制，当前处于实验性阶段。
