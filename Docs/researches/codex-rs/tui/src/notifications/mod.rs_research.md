# mod.rs 研究文档

## 场景与职责

`mod.rs` 是 Codex TUI 桌面通知系统的核心模块，负责：
1. **后端抽象**：统一 BEL 和 OSC 9 两种通知后端接口
2. **自动检测**：根据终端环境自动选择最合适的通知方式
3. **配置集成**：与 config.toml 中的通知配置对接
4. **跨平台支持**：处理不同操作系统和终端的兼容性

**模块定位**：
```
codex-rs/tui/src/notifications/
├── mod.rs      # 核心模块：后端枚举、自动检测、配置集成
├── bel.rs      # BEL 后端实现
└── osc9.rs     # OSC 9 后端实现
```

## 功能点目的

### 1. DesktopNotificationBackend 枚举
- **目的**：统一不同通知后端的接口
- **变体**：
  - `Osc9(Osc9Backend)` - 富文本通知（首选）
  - `Bel(BelBackend)` - 简单通知（降级）

### 2. 自动检测逻辑 (`supports_osc9`)
- **目的**：智能选择通知后端
- **策略**：
  - 优先检测 OSC 9 支持的终端
  - Windows Terminal 明确排除（不支持 OSC 9）
  - 无明确信号时降级到 BEL

### 3. 配置集成
- **目的**：支持用户自定义通知行为
- **对接**：`NotificationMethod` 枚举（来自 `codex_core::config::types`）
  - `Auto` - 自动检测
  - `Osc9` - 强制使用 OSC 9
  - `Bel` - 强制使用 BEL

### 4. 通知过滤集成
- **目的**：根据用户配置过滤通知类型
- **对接**：`Notifications` 配置（`Enabled(bool)` 或 `Custom(Vec<String>)`）

## 具体技术实现

### 关键流程

#### 后端创建流程
```
detect_backend(method) -> DesktopNotificationBackend::for_method(method)
  ├── NotificationMethod::Auto
  │     └── if supports_osc9() -> Osc9 else -> Bel
  ├── NotificationMethod::Osc9 -> Osc9
  └── NotificationMethod::Bel -> Bel
```

#### 通知发送流程
```
DesktopNotificationBackend::notify(message)
  ├── Osc9(backend) -> Osc9Backend::notify(message)
  │                     └── 发送 OSC 9 序列: \x1b]9;{msg}\x07
  └── Bel(backend) -> BelBackend::notify(message)
                      └── 发送 BEL 字符: \x07
```

#### 终端检测流程
```
supports_osc9()
  ├── if WT_SESSION 存在 -> false (Windows Terminal 不支持)
  ├── if TERM_PROGRAM ∈ {WezTerm, ghostty} -> true
  ├── if ITERM_SESSION_ID 存在 -> true (iTerm2)
  └── if TERM ∈ {xterm-kitty, wezterm, wezterm-mux} -> true
```

### 数据结构

```rust
// 后端枚举 - 统一接口
#[derive(Debug)]
pub enum DesktopNotificationBackend {
    Osc9(Osc9Backend),
    Bel(BelBackend),
}

// 配置枚举（来自 codex_core）
pub enum NotificationMethod {
    Auto,    // 默认
    Osc9,    // 强制 OSC 9
    Bel,     // 强制 BEL
}

// 通知开关配置（来自 codex_core）
pub enum Notifications {
    Enabled(bool),           // 全局开关
    Custom(Vec<String>),     // 按类型开关
}
```

### 核心方法

| 方法 | 签名 | 说明 |
|------|------|------|
| `for_method` | `fn(NotificationMethod) -> Self` | 根据配置创建后端 |
| `method` | `fn(&self) -> NotificationMethod` | 获取当前方法类型 |
| `notify` | `fn(&mut self, &str) -> io::Result<()>` | 发送通知 |
| `detect_backend` | `fn(NotificationMethod) -> DesktopNotificationBackend` | 便捷函数 |
| `supports_osc9` | `fn() -> bool` | 检测终端支持 |

### 代码路径

```
codex-rs/tui/src/notifications/mod.rs
├── DesktopNotificationBackend 枚举定义 [行12-15]
│
├── impl DesktopNotificationBackend
│   ├── for_method()           [行18-30]  根据配置创建后端
│   ├── method()               [行32-37]  获取方法类型
│   └── notify()               [行39-44]  分发到具体后端
│
├── detect_backend()           [行47-49]  便捷函数
│
├── supports_osc9()            [行51-72]  终端检测逻辑
│   ├── WT_SESSION 检查        [行52-54]  排除 Windows Terminal
│   ├── TERM_PROGRAM 检查      [行57-62]  检测 WezTerm/Ghostty
│   ├── ITERM_SESSION_ID 检查  [行64-66]  检测 iTerm2
│   └── TERM 检查              [行68-71]  检测 kitty/wezterm
│
└── tests 模块                 [行74-156]
    ├── EnvVarGuard 辅助结构   [行81-113]  环境变量测试工具
    ├── selects_osc9_method    [行115-121] 测试强制 OSC 9
    ├── selects_bel_method     [行123-129] 测试强制 BEL
    ├── auto_prefers_bel_without_hints [行131-142] 测试无信号时降级
    └── auto_uses_osc9_for_iterm       [行144-155] 测试 iTerm2 检测
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 来源 | 用途 |
|------|------|------|
| `bel::BelBackend` | 本地 mod | BEL 后端实现 |
| `osc9::Osc9Backend` | 本地 mod | OSC 9 后端实现 |
| `NotificationMethod` | `codex_core::config::types` | 配置枚举 |
| `std::env` | 标准库 | 环境变量读取 |
| `std::io` | 标准库 | I/O 结果类型 |
| `serial_test::serial` | 测试依赖 | 串行化测试 |

### 调用关系

**被调用方**：
- `codex-rs/tui/src/tui.rs`：
  - `Tui::new()` 中初始化：`notification_backend: Some(detect_backend(NotificationMethod::default()))`
  - `Tui::set_notification_method()` 中重新配置
  - `Tui::notify()` 中调用后端发送通知

- `codex-rs/tui/src/chatwidget.rs`：
  - 通过 `Tui::notify()` 间接使用
  - `ChatWidget::notify()` 创建通知
  - `ChatWidget::maybe_post_pending_notification()` 在适当时机触发

**配置来源**：
- `codex-rs/core/src/config/types.rs`：
  - `NotificationMethod` 枚举定义（行685-692）
  - `Notifications` 枚举定义（行672-683）
  - `Tui` 配置结构体中的 `notifications` 和 `notification_method` 字段（行718-724）

- `codex-rs/core/src/config/mod.rs`：
  - `tui_notifications` 配置项（行2794-2798）
  - `tui_notification_method` 配置项（行2799+）

### 通知类型过滤

在 `chatwidget.rs` 中，`Notification` 枚举定义了可通知的事件类型：

```rust
enum Notification {
    AgentTurnComplete { response: String },      // agent-turn-complete
    ExecApprovalRequested { command: String },   // approval-requested
    EditApprovalRequested { cwd: PathBuf, changes: Vec<PathBuf> }, // approval-requested
    ElicitationRequested { server_name: String }, // approval-requested
    PlanModePrompt { title: String },            // plan-mode-prompt
    UserInputRequested { question_count: usize, summary: Option<String> }, // user-input-requested
}
```

过滤逻辑：
```rust
fn allowed_for(&self, settings: &Notifications) -> bool {
    match settings {
        Notifications::Enabled(enabled) => *enabled,
        Notifications::Custom(allowed) => allowed.iter().any(|a| a == self.type_name()),
    }
}
```

## 风险、边界与改进建议

### 风险

1. **终端检测误判**：
   - 环境变量可能被用户手动设置，导致错误检测
   - 终端复用器（tmux/screen）可能隐藏真实终端信息
   - SSH 远程会话中环境变量可能传递异常

2. **Windows Terminal 限制**：
   - 明确排除 Windows Terminal 的 OSC 9 支持
   - 但 Windows Terminal 可能在未来版本支持 OSC 9
   - 需要持续关注终端更新

3. **并发测试问题**：
   - 测试修改全局环境变量，使用 `serial_test::serial` 串行化
   - `unsafe` 代码块用于 `std::env::set_var/remove_var`
   - 测试间可能相互影响

4. **代码重复**：
   - `tui` 和 `tui_app_server` 两个 crate 有完全相同的 notifications 模块
   - 维护成本增加，容易遗漏同步更新

### 边界条件

| 场景 | 行为 |
|------|------|
| 所有检测变量未设置 | 降级到 BEL |
| WT_SESSION 设置但其他 OSC 9 信号也存在 | 优先排除，使用 BEL |
| 多个终端信号冲突 | 任一信号存在即启用 OSC 9 |
| 配置为 Osc9 但不支持 | 仍尝试 OSC 9，可能无效果 |
| 配置为 Bel | 强制使用 BEL，忽略检测 |
| notify() 失败 | `Tui::notify()` 中禁用后端，不再尝试 |

### 改进建议

1. **终端检测增强**：
   ```rust
   // 建议添加更多检测信号
   fn supports_osc9() -> bool {
       // 现有检测...
       
       // 添加 VTE 版本检测（GNOME Terminal 等）
       if let Ok(vte_version) = env::var("VTE_VERSION") {
           if vte_version.parse::<u32>().unwrap_or(0) >= 5200 {
               return true;
           }
       }
       
       // 添加 Konsole 检测
       if env::var_os("KONSOLE_VERSION").is_some() {
           return true;
       }
       
       false
   }
   ```

2. **动态检测更新**：
   - 当前检测在初始化时执行一次
   - 考虑在终端切换时重新检测（如 SSH 到不同主机）
   - 添加手动刷新接口

3. **Windows Terminal 支持**：
   - 调研 Windows Terminal 的通知替代方案
   - 考虑使用 Windows 原生通知 API
   - 关注 Windows Terminal 的 OSC 9 支持进展

4. **代码去重**：
   - 将 notifications 模块提取到共享 crate（如 `codex_utils`）
   - 或创建 `codex_notifications` 子 crate
   - 确保 tui 和 tui_app_server 使用同一份代码

5. **测试改进**：
   - 添加更多终端模拟测试
   - 测试环境变量冲突场景
   - 添加集成测试验证实际通知效果

6. **配置扩展**：
   ```toml
   # 建议添加更细粒度的配置
   [tui]
   notifications = ["agent-turn-complete", "approval-requested"]  # 白名单模式
   notification_method = "auto"
   notification_timeout = 5000  # 通知显示时长（毫秒）
   ```

7. **错误处理增强**：
   - 当前 `notify()` 失败后在 `Tui::notify()` 中禁用后端
   - 建议添加重试机制和错误日志
   - 提供用户可感知的错误反馈

### 测试分析

当前测试覆盖：
- ✅ 强制选择 OSC 9 后端
- ✅ 强制选择 BEL 后端
- ✅ 无信号时自动降级到 BEL
- ✅ iTerm2 环境检测

建议添加：
- Windows Terminal 排除检测
- WezTerm/Ghostty 检测
- kitty 检测
- 环境变量冲突处理
- 通知发送失败处理

### 相关文件引用

| 文件 | 关系 |
|------|------|
| `codex-rs/tui/src/notifications/bel.rs` | 子模块，BEL 后端实现 |
| `codex-rs/tui/src/notifications/osc9.rs` | 子模块，OSC 9 后端实现 |
| `codex-rs/tui/src/tui.rs` | 调用方，TUI 核心 |
| `codex-rs/tui/src/chatwidget.rs` | 调用方，通知创建和过滤 |
| `codex-rs/core/src/config/types.rs` | 配置类型定义 |
| `codex-rs/core/src/config/mod.rs` | 配置加载和应用 |
| `codex-rs/tui_app_server/src/notifications/mod.rs` | 并行实现（代码重复） |
