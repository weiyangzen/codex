# osc9.rs 研究文档

## 场景与职责

`osc9.rs` 实现了基于 OSC 9 (Operating System Command 9) 协议的桌面通知后端。OSC 9 是 iTerm2 引入的终端扩展协议，允许终端应用程序通过转义序列发送桌面通知，支持自定义消息内容。

**核心职责**：
- 提供富文本桌面通知能力
- 在支持的终端（iTerm2、WezTerm、Ghostty、kitty）中显示带消息内容的通知
- 作为 Codex TUI 的首选通知机制

**支持的终端**：
- iTerm2 (macOS)
- WezTerm (跨平台)
- Ghostty (跨平台)
- kitty (Linux/macOS)

## 功能点目的

### 1. Osc9Backend 结构体
- **目的**：实现桌面通知后端的 OSC 9 版本
- **设计**：无状态单元结构体，与 BEL 后端保持一致接口
- **特点**：
  - `#[derive(Debug, Default)]` 提供调试和默认构造能力
  - `notify()` 方法接收消息字符串并发送

### 2. PostNotification 命令
- **目的**：实现 crossterm 的 `Command` trait，封装 OSC 9 序列的发送
- **ANSI 序列格式**：`\x1b]9;{message}\x07`
  - `\x1b]` - OSC 序列起始 (ESC + ])
  - `9;` - OSC 9 命令标识符
  - `{message}` - 通知消息内容
  - `\x07` - BEL 字符终止序列

## 具体技术实现

### 关键流程

```
notify(message) -> execute!(stdout(), PostNotification(message.to_string()))
                      -> PostNotification::write_ansi(f) 
                         -> write!(f, "\x1b]9;{}\x07", self.0)
```

### 数据结构

```rust
// 后端结构体 - 无状态设计
#[derive(Debug, Default)]
pub struct Osc9Backend;

// 命令结构体 - 包含消息内容
#[derive(Debug, Clone)]
pub struct PostNotification(pub String);
```

### 协议/命令实现

| 方法 | 实现 | 说明 |
|------|------|------|
| `write_ansi` | `write!(f, "\x1b]9;{}\x07", self.0)` | 写入完整 OSC 9 序列 |
| `execute_winapi` | 返回错误 | 强制使用 ANSI 模式 |
| `is_ansi_code_supported` | 返回 `true` | 声明支持 ANSI |

### OSC 9 协议详解

```
ESC ] 9 ; <message> BEL
  │   │ │      │      │
  │   │ │      │      └── 终止字符 (0x07)
  │   │ │      └───────── 通知消息内容
  │   │ └──────────────── OSC 9 命令 ID
  │   └────────────────── OSC 序列起始 (ESC + ])
  └────────────────────── 转义字符 (0x1B)
```

### 代码路径

```
codex-rs/tui/src/notifications/osc9.rs
├── Osc9Backend::notify()  [行12-14]
│   └── 调用 execute!() 宏发送 PostNotification(message)
│
└── PostNotification (impl Command)
    ├── write_ansi()       [行22-24]  写入 \x1b]9;{msg}\x07
    ├── execute_winapi()   [行27-30]  Windows API 降级处理
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
- `codex-rs/tui/src/notifications/mod.rs` 中的 `DesktopNotificationBackend::Osc9` 变体
- 通过 `detect_backend()` 或 `for_method(NotificationMethod::Osc9)` 创建

**调用路径**：
```
chatwidget.rs:notify() 
  -> Tui::notify() 
    -> DesktopNotificationBackend::notify() 
      -> Osc9Backend::notify(message)
```

**自动检测逻辑**（`mod.rs` 中的 `supports_osc9()`）：
```rust
// 排除 Windows Terminal (WT_SESSION)
if env::var_os("WT_SESSION").is_some() { return false; }

// 支持 TERM_PROGRAM = WezTerm | ghostty
if env::var("TERM_PROGRAM") == Some("WezTerm" | "ghostty") { return true; }

// 支持 ITERM_SESSION_ID (iTerm2)
if env::var_os("ITERM_SESSION_ID").is_some() { return true; }

// 支持 TERM = xterm-kitty | wezterm | wezterm-mux
if env::var("TERM") matches Some("xterm-kitty" | "wezterm" | "wezterm-mux") { return true; }
```

## 风险、边界与改进建议

### 风险

1. **终端兼容性**：
   - Windows Terminal 明确不支持 OSC 9（通过 `WT_SESSION` 检测排除）
   - 某些终端可能部分支持或行为不一致
   - tmux/screen 等终端复用器可能拦截或修改 OSC 序列

2. **消息内容安全**：
   - 消息内容直接写入 ANSI 序列，未做转义处理
   - 如果消息包含 `\x07` (BEL) 或 `\x1b` (ESC) 等控制字符，可能破坏序列
   - 潜在的安全风险：消息注入

3. **消息长度限制**：
   - 终端对 OSC 序列长度通常有限制（常见 2048 字节）
   - 超长消息可能被截断或导致未定义行为

### 边界条件

| 场景 | 行为 |
|------|------|
| Windows Terminal | 通过 `WT_SESSION` 检测，自动降级到 BEL |
| 消息含控制字符 | 未转义，可能破坏序列 |
| 空消息 | 发送 `\x1b]9;\x07`，终端行为取决于实现 |
| 超长消息 | 可能截断或失败 |
| Unicode 消息 | 支持，但计入字节长度限制 |

### 改进建议

1. **输入验证与清理**：
   ```rust
   // 建议添加消息清理
   fn sanitize_message(msg: &str) -> String {
       msg.replace('\x07', "")
          .replace('\x1b', "")
          .replace('\x9c', "")  // ST 字符也可能终止序列
   }
   ```

2. **消息截断**：
   ```rust
   // 建议添加长度限制
   const MAX_OSC9_LENGTH: usize = 1024;
   let truncated = if message.len() > MAX_OSC9_LENGTH {
       format!("{}...", &message[..MAX_OSC9_LENGTH-3])
   } else {
       message.to_string()
   };
   ```

3. **文档增强**：
   - 添加 OSC 9 协议规范的链接
   - 说明各终端的支持情况
   - 添加关于消息长度限制的注释

4. **测试覆盖**：
   - 当前模块无单元测试
   - 建议添加：
     - ANSI 输出格式验证
     - 特殊字符处理测试
     - 消息截断测试

5. **与 tui_app_server 同步**：
   - `codex-rs/tui_app_server/src/notifications/osc9.rs` 与当前文件内容完全一致
   - 考虑共享代码或添加同步检查机制

6. **Windows Terminal 支持**：
   - 调研 Windows Terminal 是否支持其他通知机制
   - 考虑使用原生 Windows 通知 API 作为备选

### 相关配置

- `NotificationMethod::Osc9` - 强制使用 OSC 9 后端
- `NotificationMethod::Auto` - 自动检测，优先使用 OSC 9
- `tui.notification_method` - config.toml 中的配置项

### 相关环境变量

| 变量 | 作用 |
|------|------|
| `WT_SESSION` | Windows Terminal 会话标识，存在时禁用 OSC 9 |
| `TERM_PROGRAM` | 终端程序名称，用于检测 WezTerm/Ghostty |
| `ITERM_SESSION_ID` | iTerm2 会话标识 |
| `TERM` | 终端类型，用于检测 kitty/wezterm |
