# custom_terminal.rs 研究文档

## 场景与职责

`custom_terminal.rs` 是 Codex TUI 应用服务器的自定义终端实现模块，基于 `ratatui::Terminal` 进行定制，提供针对 Codex TUI 特定需求的终端渲染功能。该模块是 TUI 渲染系统的核心组件，负责管理终端缓冲区、处理绘制命令、支持内联模式（inline mode）和备用屏幕模式。

与标准 `ratatui::Terminal` 相比，该实现增加了以下特性：
- **内联模式支持**：在非备用屏幕模式下运行，保留终端滚动历史
- **OSC 序列处理**：正确处理 OSC 8 超链接等转义序列的显示宽度
- **可见历史行跟踪**：记录在内联模式下渲染的历史行数
- **增强的清除功能**：提供多种屏幕清除选项

## 功能点目的

### 1. 自定义 Frame 结构
- 提供渲染帧的上下文，包含光标位置、视口区域和缓冲区引用
- 支持 `render_widget_ref` 方法，兼容 `ratatui` 的 widget 系统
- 允许设置光标位置，控制渲染后的光标状态

### 2. 自定义 Terminal 结构
- 包装后端（Backend）和双缓冲区系统
- 支持内联模式（`no_alt_screen` 配置）
- 跟踪可见历史行数，用于内联模式的滚动管理
- 记录最后已知的光标位置，用于视口调整

### 3. 缓冲区差异计算 `diff_buffers`
- 比较前后缓冲区的差异，生成最小化的绘制命令
- 优化宽字符（如中文）的处理
- 使用 `ClearToEnd` 命令优化行尾清除

### 4. 绘制命令执行 `draw`
- 执行差异计算生成的绘制命令
- 管理光标移动和颜色状态
- 处理修饰符（粗体、斜体等）的差异更新

### 5. 显示宽度计算 `display_width`
- 正确处理 OSC 序列（如 OSC 8 超链接）
- 这些序列不占用显示列，但标准 `UnicodeWidthStr::width()` 会错误计数

### 6. 终端清除功能
- `clear`：清除视口并强制完整重绘
- `clear_scrollback`：清除滚动历史
- `clear_visible_screen`：清除整个可见屏幕
- `clear_scrollback_and_visible_screen_ansi`：使用 ANSI 序列硬重置

## 具体技术实现

### Frame 结构

```rust
#[derive(Debug, Hash)]
pub struct Frame<'a> {
    /// 绘制后光标应放置的位置
    pub(crate) cursor_position: Option<Position>,
    /// 视口区域
    pub(crate) viewport_area: Rect,
    /// 当前帧使用的缓冲区
    pub(crate) buffer: &'a mut Buffer,
}

impl Frame<'_> {
    pub const fn area(&self) -> Rect {
        self.viewport_area
    }
    
    pub fn render_widget_ref<W: WidgetRef>(&mut self, widget: W, area: Rect) {
        widget.render_ref(area, self.buffer);
    }
    
    pub fn set_cursor_position<P: Into<Position>>(&mut self, position: P) {
        self.cursor_position = Some(position.into());
    }
    
    pub fn buffer_mut(&mut self) -> &mut Buffer {
        self.buffer
    }
}
```

### Terminal 结构

```rust
#[derive(Debug, Default, Clone, Eq, PartialEq, Hash)]
pub struct Terminal<B>
where
    B: Backend + Write,
{
    backend: B,
    buffers: [Buffer; 2],  // 双缓冲区
    current: usize,        // 当前缓冲区索引
    hidden_cursor: bool,
    viewport_area: Rect,
    last_known_screen_size: Size,
    last_known_cursor_pos: Position,
    visible_history_rows: u16,  // 内联模式下的可见历史行数
}
```

### 显示宽度计算（OSC 序列处理）

```rust
fn display_width(s: &str) -> usize {
    // 快速路径：无转义序列
    if !s.contains('\x1B') {
        return s.width();
    }

    // 去除 OSC 序列：ESC ] ... BEL
    let mut visible = String::with_capacity(s.len());
    let mut chars = s.chars();
    while let Some(ch) = chars.next() {
        if ch == '\x1B' && chars.clone().next() == Some(']') {
            chars.next(); // 跳过 ']'
            for c in chars.by_ref() {
                if c == '\x07' {  // BEL 字符
                    break;
                }
            }
            continue;
        }
        visible.push(ch);
    }
    visible.width()
}
```

### 缓冲区差异计算

```rust
fn diff_buffers(a: &Buffer, b: &Buffer) -> Vec<DrawCommand> {
    // 1. 计算每行最后一个非空列
    // 2. 生成 ClearToEnd 命令优化行尾清除
    // 3. 比较缓冲区内容，生成 Put 命令
    // 4. 处理宽字符的无效化和跳过逻辑
}
```

### 绘制命令

```rust
#[derive(Debug, IsVariant)]
enum DrawCommand {
    Put { x: u16, y: u16, cell: Cell },
    ClearToEnd { x: u16, y: u16, bg: Color },
}
```

### 修饰符差异更新

```rust
struct ModifierDiff {
    pub from: Modifier,
    pub to: Modifier,
}

impl ModifierDiff {
    fn queue<W: io::Write>(self, w: &mut W) -> io::Result<()> {
        // 计算需要移除和添加的修饰符
        // 按特定顺序发送 ANSI 序列
    }
}
```

## 关键代码路径与文件引用

### 定义位置
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/custom_terminal.rs`

### 调用方

| 文件 | 使用方式 | 用途 |
|------|----------|------|
| `tui.rs` | `Terminal = CustomTerminal<CrosstermBackend<Stdout>>` | 定义终端类型别名 |
| `model_migration.rs` | `Terminal::draw` | 模型迁移提示界面 |
| `insert_history.rs` | `Terminal` | 历史插入界面 |
| `resume_picker.rs` | `Terminal` | 会话恢复选择器 |
| `chatwidget.rs` | `Terminal` | 主聊天界面 |
| `chatwidget/tests.rs` | `Terminal` | 测试中使用 |

### 测试使用
- `/home/sansha/Github/codex/codex-rs/tui_app_server/tests/suite/vt100_history.rs`
- `/home/sansha/Github/codex/codex-rs/tui_app_server/tests/suite/vt100_live_commit.rs`

### 模块声明
- 在 `lib.rs` 中声明为 `pub mod custom_terminal;`（公共模块）

### 许可证说明
文件头部包含详细的许可证声明，说明代码派生自 `ratatui::Terminal`（MIT 许可证）。

## 依赖与外部交互

### 外部依赖
- `ratatui`：提供 `Backend`、`Buffer`、`Cell`、`WidgetRef` 等类型
- `crossterm`：终端控制命令（光标移动、颜色设置等）
- `unicode_width`：Unicode 字符显示宽度计算
- `derive_more::IsVariant`：为 `DrawCommand` 生成 `is_put()` 和 `is_clear_to_end()` 方法

### 内部模块交互
- `tui.rs`：创建和管理 `CustomTerminal` 实例
- 多个 UI 模块通过 `tui.rs` 间接使用

## 风险、边界与改进建议

### 风险点

1. **OSC 序列处理局限**
   - 当前只处理 OSC 序列（ESC ] ... BEL）
   - 其他转义序列（如 CSI、DCS）可能影响显示宽度计算
   - **建议**：扩展处理其他常见转义序列

2. **宽字符处理复杂性**
   - `diff_buffers` 中的宽字符逻辑较为复杂
   - 边界情况（如跨行宽字符）可能处理不当
   - **当前保护**：有单元测试覆盖部分场景

3. **与 ratatui 版本兼容性**
   - 代码派生自特定版本的 ratatui
   - ratatui 更新可能需要同步修改
   - **建议**：记录基于的 ratatui 版本

### 边界情况

1. **空视口**
   - `clear` 等方法检查 `viewport_area.is_empty()`
   - 空视口时直接返回，避免无效操作

2. **光标位置恢复**
   - `Drop` 实现尝试恢复光标状态
   - 如果失败，打印错误到 stderr

3. **PTY 不支持 CPR**
   - 某些 PTY 不响应光标位置请求（`ESC[6n`）
   - 实现中使用默认值 `(0, 0)` 继续运行

### 改进建议

1. **错误处理**
   - `Drop` 中的错误处理使用 `eprintln!`
   - 建议：使用 `tracing` 记录，避免干扰终端状态

2. **配置选项**
   - 当前 `visible_history_rows` 硬编码行为
   - 建议：添加配置选项控制内联模式行为

3. **性能优化**
   - `display_width` 每次都分配新字符串
   - 建议：使用迭代器避免分配，或添加快速路径

4. **测试覆盖**
   - 当前有 2 个单元测试
   - 建议添加：
     - OSC 序列处理测试
     - 多行宽字符测试
     - 边界条件测试（空缓冲区、零尺寸等）

5. **文档完善**
   - 添加更多实现细节文档
   - 说明与标准 ratatui Terminal 的差异
   - 添加内联模式的使用说明

6. **功能扩展**
   - 支持更多终端特性检测
   - 添加终端能力协商
   - 支持六边形颜色（true color）检测
