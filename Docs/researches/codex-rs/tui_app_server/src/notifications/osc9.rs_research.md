# osc9.rs 研究文档

## 场景与职责

`osc9.rs` 实现了基于 OSC 9 (Operating System Command 9) 协议的桌面通知后端。OSC 9 是一种终端控制序列，允许应用程序通过终端发送桌面通知，无需直接调用系统通知 API。

这是 Codex TUI 应用服务器的首选通知机制，当终端支持时优先使用。

## 功能点目的

1. **富文本桌面通知**: 通过终端协议发送带有自定义消息内容的通知
2. **跨平台兼容性**: 通过 ANSI 转义序列工作，不依赖特定操作系统 API
3. **终端集成**: 通知由终端应用处理，与终端的现有通知系统集成

## 具体技术实现

### 关键数据结构

```rust
#[derive(Debug, Default)]
pub struct Osc9Backend;

#[derive(Debug, Clone)]
pub struct PostNotification(pub String);
```

- `Osc9Backend`: 空结构体，实现通知后端接口
- `PostNotification`: 包含通知消息字符串，实现 `crossterm::Command` trait

### 核心流程

1. **通知触发** (`Osc9Backend::notify`):
   ```rust
   pub fn notify(&mut self, message: &str) -> io::Result<()> {
       execute!(stdout(), PostNotification(message.to_string()))
   }
   ```
   - 将消息字符串包装为 `PostNotification` 命令
   - 通过 `execute!` 宏输出到 stdout

2. **ANSI 序列生成** (`PostNotification::write_ansi`):
   ```rust
   fn write_ansi(&self, f: &mut impl fmt::Write) -> fmt::Result {
       write!(f, "\x1b]9;{}\x07", self.0)
   }
   ```
   - 生成 OSC 9 序列格式：`ESC ] 9 ; <message> BEL`
   - `\x1b]` 是 OSC (Operating System Command) 序列起始
   - `9` 是 OSC 9 命令编号（通知）
   - `\x07` (BEL) 是序列终止符

3. **Windows 平台处理**:
   - `execute_winapi`: 返回错误，强制使用 ANSI 模式
   - `is_ansi_code_supported`: 返回 `true`

### 协议说明

- **OSC 9 格式**: `ESC ] 9 ; <message> BEL`
  - `ESC ]` (`\x1b]`): OSC 序列起始
  - `9`: 通知命令
  - `;`: 分隔符
  - `<message>`: 通知内容（纯文本）
  - `BEL` (`\x07`): 序列终止

- **支持的终端**:
  - iTerm2 (通过 `ITERM_SESSION_ID` 检测)
  - WezTerm (通过 `TERM_PROGRAM=WezTerm` 或 `TERM=wezterm` 检测)
  - Ghostty (通过 `TERM_PROGRAM=ghostty` 检测)
  - Kitty (通过 `TERM=xterm-kitty` 检测)

- **不支持的终端**:
  - Windows Terminal (通过 `WT_SESSION` 检测并排除)

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/tui_app_server/src/notifications/osc9.rs` (37 行)

### 调用关系

**被调用方**:
- `codex-rs/tui_app_server/src/notifications/mod.rs`
  - `DesktopNotificationBackend::Osc9` 变体包含 `Osc9Backend`
  - `detect_backend()` 在 `Auto` 模式下且支持 OSC 9 时选择此后端

**调用方**:
- `codex-rs/tui_app_server/src/tui.rs`
  - `Tui::notify()` 方法通过 `notification_backend.notify()` 间接调用

### 依赖 crate
- `crossterm`: 提供 `Command` trait
- `ratatui`: 提供 `ratatui::crossterm::execute!` 宏

## 依赖与外部交互

### 环境检测逻辑（在 mod.rs 中）

```rust
fn supports_osc9() -> bool {
    if env::var_os("WT_SESSION").is_some() {
        return false;  // Windows Terminal 不支持
    }
    if matches!(
        env::var("TERM_PROGRAM").ok().as_deref(),
        Some("WezTerm" | "ghostty")
    ) {
        return true;
    }
    if env::var_os("ITERM_SESSION_ID").is_some() {
        return true;  // iTerm2
    }
    matches!(
        env::var("TERM").ok().as_deref(),
        Some("xterm-kitty" | "wezterm" | "wezterm-mux")
    )
}
```

### 与通知系统的集成
```
chatwidget.rs (Notification enum)
    ↓
Tui::notify() (tui.rs)
    ↓
DesktopNotificationBackend::notify() (mod.rs)
    ↓
Osc9Backend::notify() (osc9.rs) [当使用 OSC9 后端时]
    ↓
PostNotification → stdout (OSC 9 序列)
```

### 配置关联
- 由 `NotificationMethod::Osc9` 或 `NotificationMethod::Auto` (自动检测支持时) 触发
- 配置定义在 `codex-rs/core/src/config/types.rs`

## 风险、边界与改进建议

### 已知限制

1. **终端支持有限**: 仅特定终端支持 OSC 9，主流终端如 Windows Terminal、GNOME Terminal、Alacritty 等不支持
2. **消息格式限制**: OSC 9 只支持纯文本，不支持 HTML、图片等富媒体
3. **无通知 ID**: 无法更新或撤销已发送的通知
4. **消息长度限制**: 过长的消息可能被终端截断

### 边界情况

1. **特殊字符转义**: 当前实现未对消息中的特殊字符进行转义，如果消息包含 `\x07` 或 `\x1b` 可能破坏序列
   ```rust
   // 潜在问题
   message = "Error: \x07"  // 会被解释为序列终止
   ```

2. **多行消息**: OSC 9 通常不支持多行消息，换行符可能被忽略或导致问题

3. **Unicode 处理**: 非 ASCII 字符的处理取决于终端的 UTF-8 支持

### 改进建议

1. **输入验证/清理**:
   ```rust
   fn sanitize_message(msg: &str) -> String {
       msg.replace('\x07', "")
          .replace('\x1b', "")
          .replace('\n', " ")
   }
   ```

2. **消息截断**: 添加长度限制防止终端缓冲区溢出
   ```rust
   const MAX_OSC9_LENGTH: usize = 1024;
   let truncated = if message.len() > MAX_OSC9_LENGTH {
       format!("{}...", &message[..MAX_OSC9_LENGTH-3])
   } else {
       message.to_string()
   };
   ```

3. **支持更多终端**: 考虑添加对以下终端的检测：
   - Alacritty (虽然原生不支持 OSC 9，但可通过配置支持)
   - tmux (需要特殊处理，可能需要包装序列)

4. **考虑 OSC 777 作为备选**: 某些终端支持 OSC 777 作为替代通知协议

5. **错误处理改进**: 当前无法知道通知是否实际显示，可以考虑：
   - 添加超时机制
   - 在 TUI 内部维护通知状态

### 测试覆盖

当前测试位于 `mod.rs` 的 `tests` 模块中：
- `selects_osc9_method`: 验证 `NotificationMethod::Osc9` 正确选择 OSC9 后端
- `auto_uses_osc9_for_iterm`: 验证在 iTerm 环境下自动选择 OSC9

建议添加：
- 序列格式验证测试
- 特殊字符处理测试
- 消息长度边界测试

### 相关文档

- iTerm2 文档: https://iterm2.com/documentation-escape-codes.html
- WezTerm 文档: https://wezfurlong.org/wezterm/escape-sequences.html
- 终端通知协议比较: https://sw.kovidgoyal.net/kitty/desktop-notifications/
