# lib.rs 研究文档

## 场景与职责

`lib.rs` 是 `codex-utils-sleep-inhibitor` crate 的**公共接口层和跨平台抽象核心**。它定义了统一的 `SleepInhibitor` API，并通过条件编译机制将调用路由到各平台的具体实现（Linux、macOS、Windows 或 Dummy）。

**设计目标**：
1. 为调用方（如 TUI 的 `ChatWidget`）提供**平台无关**的睡眠抑制接口
2. 支持**运行时启用/禁用**功能（通过 `enabled` 标志）
3. 与**Agent Turn 生命周期**集成，仅在任务执行期间阻止睡眠

## 功能点目的

### 1. 跨平台抽象层
- **目的**：隐藏平台差异，提供统一接口
- **实现**：使用 `cfg` 条件编译选择不同模块作为 `imp`

### 2. 功能开关机制
- **目的**：允许用户通过配置禁用睡眠抑制
- **实现**：`enabled` 字段控制是否实际调用平台实现

### 3. Turn 生命周期绑定
- **目的**：仅在 Agent 执行任务的"turn"期间阻止睡眠
- **实现**：`turn_running` 状态 + `set_turn_running()` 方法

### 4. 幂等性保证
- **目的**：允许重复调用而不产生副作用
- **实现**：平台实现内部检查状态，避免重复 acquire/release

## 具体技术实现

### 条件编译架构

```rust
// 模块选择
#[cfg(target_os = "linux")]
mod linux_inhibitor;
#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "windows")]
mod windows_inhibitor;
#[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
mod dummy;

// 实现别名
#[cfg(target_os = "linux")]
use linux_inhibitor as imp;
#[cfg(target_os = "macos")]
use macos as imp;
#[cfg(target_os = "windows")]
use windows_inhibitor as imp;
#[cfg(not(any(target_os = "linux", target_os = "macos", target_os = "windows")))]
use dummy as imp;
```

### 核心数据结构

```rust
#[derive(Debug)]
pub struct SleepInhibitor {
    enabled: bool,           // 功能总开关（用户配置）
    turn_running: bool,      // 当前是否有 turn 在执行
    platform: imp::SleepInhibitor,  // 平台特定实现
}
```

### 状态转换逻辑

```
                    set_turn_running(true)
                   ┌──────────────────────┐
                   │                      │
    ┌──────────┐   │   ┌──────────┐      ▼   ┌──────────┐
    │  Enabled │───┼──▶│  Turn    │─────────▶│ Platform │
    │  = false │   │   │ Running  │          │ acquire  │
    └──────────┘   │   │  = true  │          └──────────┘
                   │   └──────────┘
                   │          │
                   │          │ set_turn_running(false)
                   │          ▼
                   │   ┌──────────┐
                   └──▶│ Platform │
                       │ release  │
                       └──────────┘
```

### 关键方法实现

#### `set_turn_running` - 核心状态机

```rust
pub fn set_turn_running(&mut self, turn_running: bool) {
    self.turn_running = turn_running;
    
    // 如果功能被禁用，立即释放并返回
    if !self.enabled {
        self.release();
        return;
    }
    
    // 根据 turn 状态决定 acquire 或 release
    if turn_running {
        self.acquire();
    } else {
        self.release();
    }
}
```

**重要设计决策**：
- 当 `enabled` 从 `true` 变为 `false` 时，立即调用 `release()` 确保系统可以正常睡眠
- 状态变更时立即生效，无延迟

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/utils/sleep-inhibitor/src/lib.rs`（113 行）

### 平台实现文件
| 平台 | 文件路径 | 实现方式 |
|------|----------|----------|
| Linux | `linux_inhibitor.rs` | 子进程 (`systemd-inhibit` / `gnome-session-inhibit`) |
| macOS | `macos.rs` | IOKit 电源断言 API |
| Windows | `windows_inhibitor.rs` | `PowerCreateRequest` / `PowerSetRequest` |
| Other | `dummy.rs` | 无操作 |

### 调用方（上游依赖）

#### TUI 集成
- **文件**：`codex-rs/tui/src/chatwidget.rs`
- **字段**：`turn_sleep_inhibitor: SleepInhibitor`
- **初始化**：`SleepInhibitor::new(prevent_idle_sleep)`
- **生命周期绑定**：
  - `on_task_started()` → `set_turn_running(true)`
  - `on_task_ended()` → `set_turn_running(false)`
  - `on_task_failed()` → `set_turn_running(false)`
  - `restore_thread_input_state()` → 同步状态

#### TUI App Server 集成
- **文件**：`codex-rs/tui_app_server/src/chatwidget.rs`
- **相同模式**：与 TUI 完全一致的生命周期管理

### 配置集成
- **配置项**：`prevent_idle_sleep`（布尔值）
- **动态切换**：通过 `set_feature_enabled(Feature::PreventIdleSleep, enabled)` 支持运行时开关

## 依赖与外部交互

### 编译时依赖
| 依赖 | 条件 | 用途 |
|------|------|------|
| `tracing` | 无 | 日志记录（平台实现中使用） |
| `core-foundation` | `target_os = "macos"` | macOS CFString 处理 |
| `libc` | `target_os = "linux"` | Linux `prctl` / `getpid` |
| `windows-sys` | `target_os = "windows"` | Windows 电源管理 API |

### Cargo.toml 配置
```toml
[dependencies]
tracing = { workspace = true }

[target.'cfg(target_os = "macos")'.dependencies]
core-foundation = "0.9"

[target.'cfg(target_os = "linux")'.dependencies]
libc = { workspace = true }

[target.'cfg(target_os = "windows")'.dependencies]
windows-sys = { version = "0.61.2", features = [...] }
```

## 风险、边界与改进建议

### 当前风险

#### 1. 状态不一致风险
- **场景**：`turn_running` 状态与实际平台状态可能不一致
- **示例**：如果平台实现内部失败（如 macOS IOKit 返回错误），`turn_running` 仍为 `true`
- **缓解**：平台实现记录警告日志，但不向上传播错误

#### 2. 功能切换竞态
- **场景**：在 turn 执行期间切换 `enabled` 状态
- **当前行为**：立即生效，可能中断正在进行的睡眠抑制
- **代码位置**：`set_feature_enabled` 中重新创建 `SleepInhibitor`

### 边界情况

#### 1. 多次 Acquire
```rust
// 测试用例验证：多次 set_turn_running(true) 不会 panic
#[test]
fn sleep_inhibitor_multiple_true_calls_are_idempotent() {
    let mut inhibitor = SleepInhibitor::new(true);
    inhibitor.set_turn_running(true);
    inhibitor.set_turn_running(true);  // 幂等
    inhibitor.set_turn_running(true);  // 幂等
    inhibitor.set_turn_running(false);
}
```

#### 2. 禁用状态下的状态查询
```rust
#[test]
fn sleep_inhibitor_disabled_does_not_panic() {
    let mut inhibitor = SleepInhibitor::new(false);
    inhibitor.set_turn_running(true);
    assert!(inhibitor.is_turn_running());  // 返回 true，尽管功能被禁用
    // 注意：is_turn_running() 返回的是请求的状态，不是实际抑制状态
}
```

### 改进建议

#### 1. 增加实际抑制状态查询
```rust
// 建议添加
pub fn is_actually_inhibiting(&self) -> bool {
    self.enabled && self.turn_running && self.platform.is_acquired()
}
```

#### 2. 错误传播（可选）
当前设计将平台错误内部消化（记录日志），考虑提供可选的错误通知机制：
```rust
pub fn set_turn_running(&mut self, turn_running: bool) -> Result<(), InhibitError> {
    // ...
}
```

#### 3. 状态变更回调
允许调用方注册状态变更回调，用于 UI 指示器：
```rust
pub fn on_state_change<F: Fn(bool)>(&mut self, callback: F) {
    self.state_change_callback = Some(Box::new(callback));
}
```

#### 4. 文档改进
- 明确区分 `is_turn_running()`（请求状态）和实际抑制状态
- 添加平台行为差异说明（如 Linux 使用子进程，macOS/Windows 使用 API）

### 测试覆盖

当前测试位于 `lib.rs` 底部：

| 测试用例 | 覆盖场景 |
|----------|----------|
| `sleep_inhibitor_toggles_without_panicking` | 基本开关流程 |
| `sleep_inhibitor_disabled_does_not_panic` | 禁用状态下的操作 |
| `sleep_inhibitor_multiple_true_calls_are_idempotent` | 幂等性保证 |
| `sleep_inhibitor_can_toggle_multiple_times` | 多次切换 |

**建议增加**：
- 平台特定测试（需要条件编译）
- 功能动态切换测试
- 并发安全测试（`Send` / `Sync` 验证）
