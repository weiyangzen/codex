# bel.rs 研究文档

## 场景与职责

`bel.rs` 实现了基于 BEL (Bell) 字符的桌面通知后端。BEL 是 ASCII 控制字符 (\x07)，在终端环境中用于触发系统通知或声音提示。该模块是 Codex TUI 通知系统的降级方案，当终端不支持 OSC 9 协议时使用。

**核心职责**：
- 提供最简单的终端通知机制
- 作为 OSC 9 的降级备选方案
- 通过 ANSI 转义序列发送 BEL 字符

## 功能点目的

### 1. BelBackend 结构体
- **目的**：实现桌面通知后端的 BEL 版本
- **设计**：零成本抽象，使用单元结构体 (`struct BelBackend`)
- **特点**：
  - `#[derive(Debug, Default)]` 提供调试和默认构造能力
  - 不保存任何状态，纯函数式行为

### 2. PostNotification 命令
- **目的**：实现 crossterm 的 `Command` trait，封装 BEL 字符的发送
- **ANSI 序列**：`\x07` (单个 BEL 字符)
- **Windows 兼容性**：
  - `execute_winapi()` 返回错误，强制使用 ANSI 模式
  - `is_ansi_code_supported()` 返回 true，声明 ANSI 支持

## 具体技术实现

### 关键流程

```
notify(message) -> execute!(stdout(), PostNotification)
                      -> PostNotification::write_ansi(f) -> write!(f, "\x07")
```

### 数据结构

```rust
// 后端结构体 - 无状态设计
#[derive(Debug, Default)]
pub struct BelBackend;

// 命令结构体 - 实现 crossterm Command trait
#[derive(Debug, Clone)]
pub struct PostNotification;
```

### 协议/命令实现

| 方法 | 实现 | 说明 |
|------|------|------|
| `write_ansi` | `write!(f, "\x07")` | 写入单个 BEL 字符 |
| `execute_winapi` | 返回错误 | 强制使用 ANSI 模式 |
| `is_ansi_code_supported` | 返回 `true` | 声明支持 ANSI |

### 代码路径

```
codex-rs/tui/src/notifications/bel.rs
├── BelBackend::notify()  [行12-14]
│   └── 调用 execute!() 宏发送 PostNotification
│
└── PostNotification (impl Command)
    ├── write_ansi()      [行22-24]  写入 \x07
    ├── execute_winapi()  [行27-30]  Windows API 降级处理
    └── is_ansi_code_supported() [行34-36]  声明 ANSI 支持
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|------|------|
| `crossterm::Command` | 实现终端命令 trait |
| `ratatui::crossterm::execute` | 执行终端命令的宏 |
| `std::fmt` | ANSI 写入的格式化 trait |
| `std::io` | I/O 结果类型 |
| `std::io::stdout` | 标准输出流 |

### 调用关系

**被调用方**：
- `codex-rs/tui/src/notifications/mod.rs` 中的 `DesktopNotificationBackend::Bel` 变体
- 通过 `detect_backend()` 或 `for_method(NotificationMethod::Bel)` 创建

**调用路径**：
```
chatwidget.rs:notify() 
  -> Tui::notify() 
    -> DesktopNotificationBackend::notify() 
      -> BelBackend::notify()
```

## 风险、边界与改进建议

### 风险

1. **功能限制**：BEL 字符只能触发简单的声音/通知，无法携带消息内容
   - 与 OSC 9 不同，BEL 不传递 `message` 参数内容
   - 用户收到通知后无法从通知中获知具体事件

2. **终端兼容性**：
   - 现代终端对 BEL 的支持不一致
   - 某些终端可能完全忽略 BEL 字符
   - 远程 SSH 会话中 BEL 行为可能异常

3. **用户体验**：
   - 频繁触发可能导致用户困扰（声音干扰）
   - 无视觉反馈，用户可能不知道通知来源

### 边界条件

| 场景 | 行为 |
|------|------|
| Windows 环境 | 强制使用 ANSI 模式，WinAPI 路径返回错误 |
| 消息长度 | 忽略输入消息内容，仅发送 BEL |
| 多次调用 | 每次调用都发送 BEL，无去重机制 |
| 终端未聚焦 | 依赖终端/系统的通知处理 |

### 改进建议

1. **文档增强**：
   - 添加更多关于 BEL 与 OSC 9 差异的文档注释
   - 说明何时会选择 BEL 后端（`supports_osc9()` 返回 false 时）

2. **功能扩展（有限）**：
   - 考虑添加 BEL 发送频率限制，避免声音轰炸
   - 可考虑结合其他视觉提示（如闪烁任务栏图标）

3. **测试覆盖**：
   - 当前模块无单元测试
   - 建议添加简单的 ANSI 输出验证测试
   - 测试 Windows 平台的 ANSI 强制路径

4. **与 tui_app_server 同步**：
   - `codex-rs/tui_app_server/src/notifications/bel.rs` 与当前文件内容完全一致
   - 考虑共享代码或添加同步检查机制，避免维护两份相同代码

### 相关配置

- `NotificationMethod::Bel` - 强制使用 BEL 后端
- `NotificationMethod::Auto` - 自动检测，OSC 9 不支持时降级到 BEL
- `tui.notification_method` - config.toml 中的配置项
