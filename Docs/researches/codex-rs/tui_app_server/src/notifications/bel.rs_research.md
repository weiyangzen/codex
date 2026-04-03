# bel.rs 研究文档

## 场景与职责

`bel.rs` 实现了基于 BEL (Bell) 字符的桌面通知后端。这是 Codex TUI 应用服务器中桌面通知系统的降级方案 (fallback)，当终端不支持 OSC 9 通知协议时使用。

BEL 字符 (`\x07`, ASCII 7) 是终端控制序列中最基础的信号之一，历史上用于触发终端的蜂鸣声或视觉通知。在现代终端中，BEL 通常被映射为系统通知或标签页高亮。

## 功能点目的

1. **提供最小兼容性的桌面通知**: 当终端不支持 OSC 9 时，使用 BEL 字符作为通用通知机制
2. **跨平台支持**: 通过 `crossterm` crate 实现跨平台 ANSI 序列输出
3. **与 TUI 集成**: 作为 `DesktopNotificationBackend` 枚举的一个变体，统一通知接口

## 具体技术实现

### 关键数据结构

```rust
#[derive(Debug, Default)]
pub struct BelBackend;

#[derive(Debug, Clone)]
pub struct PostNotification;
```

- `BelBackend`: 空结构体，实现通知后端接口
- `PostNotification`: 实现 `crossterm::Command` trait 的命令结构体

### 核心流程

1. **通知触发** (`BelBackend::notify`):
   ```rust
   pub fn notify(&mut self, _message: &str) -> io::Result<()> {
       execute!(stdout(), PostNotification)
   }
   ```
   - 注意：`message` 参数被忽略，因为 BEL 字符本身不支持携带消息内容
   - 使用 `ratatui::crossterm::execute!` 宏执行命令

2. **ANSI 序列生成** (`PostNotification::write_ansi`):
   ```rust
   fn write_ansi(&self, f: &mut impl fmt::Write) -> fmt::Result {
       write!(f, "\x07")
   }
   ```
   - 输出单个 BEL 字符 (`\x07`)

3. **Windows 平台处理**:
   - `execute_winapi`: 返回错误，强制使用 ANSI 模式
   - `is_ansi_code_supported`: 返回 `true`，表示支持 ANSI 序列

### 协议说明

- **BEL 字符**: ASCII 7 (`\x07`)
- **效果**: 触发终端的默认通知行为（蜂鸣声、视觉闪烁、系统通知等，取决于终端配置）
- **限制**: 无法携带自定义消息内容

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/tui_app_server/src/notifications/bel.rs` (37 行)

### 调用关系

**被调用方**:
- `codex-rs/tui_app_server/src/notifications/mod.rs`
  - `DesktopNotificationBackend::Bel` 变体包含 `BelBackend`
  - `detect_backend()` 在 `Auto` 模式下且不支持 OSC 9 时选择 BEL

**调用方**:
- `codex-rs/tui_app_server/src/tui.rs`
  - `Tui::notify()` 方法通过 `notification_backend.notify()` 间接调用

### 依赖 crate
- `crossterm`: 提供 `Command` trait 和终端控制抽象
- `ratatui`: 提供 `ratatui::crossterm::execute!` 宏

## 依赖与外部交互

### 环境依赖
- 需要终端支持 BEL 字符处理
- 几乎所有现代终端都支持 BEL

### 与通知系统的集成
```
chatwidget.rs (Notification enum)
    ↓
Tui::notify() (tui.rs)
    ↓
DesktopNotificationBackend::notify() (mod.rs)
    ↓
BelBackend::notify() (bel.rs) [当使用 Bel 后端时]
    ↓
PostNotification → stdout (BEL 字符)
```

### 配置关联
- 由 `NotificationMethod::Bel` 或 `NotificationMethod::Auto` (降级时) 触发
- 配置定义在 `codex-rs/core/src/config/types.rs`

## 风险、边界与改进建议

### 已知限制

1. **消息内容丢失**: BEL 字符无法携带通知消息，用户只能收到"有通知"的信号，不知道具体内容
2. **终端行为不一致**: 不同终端对 BEL 的处理差异很大：
   - iTerm2: 可能显示为 Dock 图标弹跳或通知中心消息
   - VS Code 集成终端: 可能显示为标签页高亮
   - 某些终端: 可能只播放蜂鸣声或完全忽略
3. **Windows Terminal 不支持**: 代码中明确排除了 `WT_SESSION` 环境变量存在时使用 OSC 9，但 BEL 在 Windows Terminal 中的效果也有限

### 边界情况

1. **stdout 重定向**: 如果 stdout 被重定向到非 TTY，`execute!` 可能失败
2. **终端缓冲区**: BEL 字符会被终端缓冲区接收，即使当前不在可视区域
3. **重复通知**: 短时间内大量 BEL 字符可能导致终端行为异常（如持续蜂鸣）

### 改进建议

1. **日志记录**: 当前实现忽略了 `message` 参数，建议至少记录到日志：
   ```rust
   pub fn notify(&mut self, message: &str) -> io::Result<()> {
       tracing::debug!("BEL notification triggered: {}", message);
       execute!(stdout(), PostNotification)
   }
   ```

2. **考虑替代方案**: 对于 BEL 后端，可以考虑同时输出消息到 stderr：
   ```rust
   eprintln!("[Notification] {}", message);
   execute!(stdout(), PostNotification)
   ```

3. **终端能力检测**: 可以添加更精细的终端能力检测，在 BEL 效果不佳的终端中提供警告

4. **与 TUI 的进一步集成**: 考虑在 TUI 内部实现视觉通知（如状态栏闪烁）作为 BEL 的补充

### 测试覆盖

当前测试位于 `mod.rs` 的 `tests` 模块中：
- `selects_bel_method`: 验证 `NotificationMethod::Bel` 正确选择 BEL 后端
- `auto_prefers_bel_without_hints`: 验证在无任何环境变量时降级到 BEL

建议添加：
- 实际 BEL 字符输出测试（需要捕获 stdout）
- 不同终端环境下的行为验证
