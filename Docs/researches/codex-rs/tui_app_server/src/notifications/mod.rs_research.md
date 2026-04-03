# mod.rs 研究文档

## 场景与职责

`mod.rs` 是 Codex TUI 应用服务器桌面通知系统的核心模块，负责：

1. **后端抽象与管理**: 提供统一的 `DesktopNotificationBackend` 枚举，封装不同的通知实现
2. **终端检测**: 自动检测当前终端类型，选择最合适的通知协议
3. **配置集成**: 与 Codex 配置系统对接，支持用户自定义通知方式
4. **降级策略**: 在 `Auto` 模式下智能选择 OSC 9 或 BEL 作为通知后端

该模块是 TUI 应用服务器与底层通知实现之间的桥梁，确保在不同终端环境下都能提供最佳的通知体验。

## 功能点目的

### 1. 统一后端接口 (`DesktopNotificationBackend`)
- 通过枚举封装多个后端实现，提供一致的调用接口
- 支持运行时后端切换

### 2. 智能终端检测 (`supports_osc9`)
- 检测环境变量判断终端类型
- 优先使用功能更丰富的 OSC 9 协议
- 对不支持的终端（如 Windows Terminal）降级到 BEL

### 3. 配置驱动 (`for_method`)
- 支持 `Auto`, `Osc9`, `Bel` 三种模式
- 用户可通过配置文件或 CLI 指定通知方式

### 4. 测试基础设施
- 提供环境变量保护机制 (`EnvVarGuard`)
- 支持串行测试避免环境变量竞争

## 具体技术实现

### 关键数据结构

```rust
#[derive(Debug)]
pub enum DesktopNotificationBackend {
    Osc9(Osc9Backend),
    Bel(BelBackend),
}
```

- `Osc9`: OSC 9 协议后端，支持富文本通知
- `Bel`: BEL 字符后端，通用但功能有限

### 核心算法

#### 1. 后端选择逻辑 (`for_method`)

```rust
pub fn for_method(method: NotificationMethod) -> Self {
    match method {
        NotificationMethod::Auto => {
            if supports_osc9() {
                Self::Osc9(Osc9Backend)
            } else {
                Self::Bel(BelBackend)
            }
        }
        NotificationMethod::Osc9 => Self::Osc9(Osc9Backend),
        NotificationMethod::Bel => Self::Bel(BelBackend),
    }
}
```

#### 2. 终端检测逻辑 (`supports_osc9`)

检测优先级：
1. **排除 Windows Terminal**: `WT_SESSION` 存在 → 返回 `false`
2. **TERM_PROGRAM 检测**: WezTerm, Ghostty → 返回 `true`
3. **iTerm2 检测**: `ITERM_SESSION_ID` 存在 → 返回 `true`
4. **TERM 检测**: `xterm-kitty`, `wezterm`, `wezterm-mux` → 返回 `true`
5. **默认**: 无匹配 → 返回 `false` (降级到 BEL)

```rust
fn supports_osc9() -> bool {
    if env::var_os("WT_SESSION").is_some() {
        return false;
    }
    if matches!(
        env::var("TERM_PROGRAM").ok().as_deref(),
        Some("WezTerm" | "ghostty")
    ) {
        return true;
    }
    if env::var_os("ITERM_SESSION_ID").is_some() {
        return true;
    }
    matches!(
        env::var("TERM").ok().as_deref(),
        Some("xterm-kitty" | "wezterm" | "wezterm-mux")
    )
}
```

### 协议对比

| 特性 | OSC 9 | BEL |
|------|-------|-----|
| 消息内容 | 支持自定义文本 | 仅信号，无内容 |
| 终端支持 | iTerm2, WezTerm, Ghostty, Kitty | 几乎所有终端 |
| Windows Terminal | 不支持 | 支持（有限） |
| 实现复杂度 | 中等 | 简单 |

### 测试基础设施

#### EnvVarGuard 模式

```rust
struct EnvVarGuard {
    key: &'static str,
    original: Option<OsString>,
}

impl EnvVarGuard {
    fn set(key: &'static str, value: &str) -> Self { ... }
    fn remove(key: &'static str) -> Self { ... }
}

impl Drop for EnvVarGuard {
    fn drop(&mut self) {
        // 恢复原始值
    }
}
```

- 使用 RAII 模式确保环境变量在测试后恢复
- 使用 `unsafe` 块修改环境变量（测试场景下安全）
- `serial_test::serial` 确保测试串行执行

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/tui_app_server/src/notifications/mod.rs` (156 行)

### 子模块
- `codex-rs/tui_app_server/src/notifications/bel.rs`: BEL 后端实现
- `codex-rs/tui_app_server/src/notifications/osc9.rs`: OSC 9 后端实现

### 调用关系

**被调用方**:
- `codex-rs/tui_app_server/src/tui.rs`
  - `Tui::new()`: 初始化时调用 `detect_backend(NotificationMethod::default())`
  - `Tui::set_notification_method()`: 动态切换通知方式
  - `Tui::notify()`: 通过 `notification_backend.notify()` 发送通知

**配置来源**:
- `codex-rs/core/src/config/types.rs`
  - `NotificationMethod` 枚举: `Auto`, `Osc9`, `Bel`
  - `Tui` 配置结构体: `notification_method` 字段

**通知触发**:
- `codex-rs/tui_app_server/src/chatwidget.rs`
  - `Notification` 枚举定义各类通知事件
  - `ChatWidget::notify()`: 创建通知
  - `ChatWidget::maybe_post_pending_notification()`: 通过 TUI 发送

### 依赖 crate
- `codex_core::config::types::NotificationMethod`: 配置类型
- `std::env`: 环境变量读取
- `serial_test`: 测试串行化

## 依赖与外部交互

### 配置系统集成

```
config.toml
    ↓
[tui]
notification_method = "auto"  # 或 "osc9", "bel"
    ↓
Config::tui.notification_method
    ↓
codex_core::config::types::NotificationMethod
    ↓
DesktopNotificationBackend::for_method()
```

### 通知流程

```
chatwidget.rs: Notification 事件
    ↓
ChatWidget::notify() - 优先级检查、去重
    ↓
ChatWidget::maybe_post_pending_notification()
    ↓
Tui::notify() - 检查终端焦点状态
    ↓
DesktopNotificationBackend::notify()
    ↓
[Osc9Backend::notify() | BelBackend::notify()]
    ↓
stdout (ANSI 序列)
```

### 环境变量依赖

| 变量 | 用途 | 影响 |
|------|------|------|
| `WT_SESSION` | 检测 Windows Terminal | 禁用 OSC 9 |
| `TERM_PROGRAM` | 检测 WezTerm, Ghostty | 启用 OSC 9 |
| `ITERM_SESSION_ID` | 检测 iTerm2 | 启用 OSC 9 |
| `TERM` | 检测 Kitty, WezTerm | 启用 OSC 9 |

## 风险、边界与改进建议

### 已知限制

1. **终端检测不完整**:
   - 未检测 Alacritty (不支持 OSC 9)
   - 未检测 GNOME Terminal, Konsole 等主流 Linux 终端
   - tmux/screen 下的行为不确定

2. **Windows Terminal 排除原因**:
   - Windows Terminal 目前不支持 OSC 9
   - 但 BEL 在 Windows Terminal 中的效果也有限
   - 可能需要考虑 Windows 原生通知 API

3. **环境变量竞争**:
   - 多线程环境下读取环境变量是安全的
   - 但测试中使用 `unsafe` 修改环境变量需要串行化

### 边界情况

1. **SSH 远程连接**:
   - 本地终端支持 OSC 9，但 SSH 到远程服务器后可能检测不到
   - `TERM` 变量通常会被传递，但 `TERM_PROGRAM` 可能不会

2. **tmux 会话**:
   - tmux 可能拦截或修改 OSC 序列
   - 当前检测逻辑可能无法正确处理嵌套会话

3. **配置动态切换**:
   - `set_notification_method` 可以运行时切换
   - 但已发送的通知无法撤销

### 改进建议

1. **增强终端检测**:
   ```rust
   // 添加更多终端检测
   if env::var("ALACRITTY_SOCKET").is_ok() {
       return false;  // Alacritty 不支持 OSC 9
   }
   if env::var("KONSOLE_VERSION").is_ok() {
       return false;  // Konsole 不支持
   }
   ```

2. **支持 OSC 777**:
   - 某些终端支持 OSC 777 作为替代通知协议
   - 可以作为 OSC 9 的备选

3. **添加终端能力查询**:
   - 使用 DA1 (Primary Device Attributes) 查询终端能力
   - 而不是仅依赖环境变量

4. **改进 Windows 支持**:
   ```rust
   #[cfg(windows)]
   fn supports_toast() -> bool {
       // 检测 Windows 版本，使用原生 Toast 通知
   }
   ```

5. **配置验证**:
   - 在设置通知方法时验证当前终端是否支持
   - 如果不支持，给出警告并建议替代方案

6. **通知回退链**:
   ```rust
   pub fn notify(&mut self, message: &str) -> io::Result<()> {
       if let Err(e) = self.try_notify(message) {
           tracing::warn!("Primary notification failed: {}", e);
           self.fallback_notify(message)
       }
   }
   ```

### 测试改进

当前测试覆盖：
- ✅ 方法选择逻辑
- ✅ 自动检测（iTerm 环境）
- ✅ 降级到 BEL

建议添加：
- 各终端环境变量的边界测试
- 并发环境测试
- 实际通知输出验证（使用 mock stdout）
- 配置序列化/反序列化测试

### 相关文档

- `docs/config.md`: 配置文档提及通知设置
- `codex-rs/core/src/config/types.rs`: `NotificationMethod` 定义
- `codex-rs/tui/src/notifications/mod.rs`: TUI crate 中的平行实现（AGENTS.md 要求保持同步）

### 同步要求

根据 `AGENTS.md` 中的规定：
> When a change lands in `codex-rs/tui` and `codex-rs/tui_app_server` has a parallel implementation of the same behavior, reflect the change in `codex-rs/tui_app_server` too unless there is a documented reason not to.

当前两个 crate 的通知模块实现几乎完全相同，修改时需要同步更新：
- `codex-rs/tui/src/notifications/mod.rs`
- `codex-rs/tui_app_server/src/notifications/mod.rs`
