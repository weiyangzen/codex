# TestBackend (VT100Backend) 研究文档

## 场景与职责

`test_backend.rs` 提供了基于 VT100 模拟的测试后端，用于 Codex TUI 的测试场景。该模块位于 `codex-rs/tui_app_server/src/test_backend.rs`，主要解决以下问题：

1. **避免 stdout 污染**：标准 CrosstermBackend 在某些操作中会写入 stdout，即使使用自定义 writer
2. **终端状态模拟**：通过 vt100 解析器模拟真实终端的行为
3. **测试隔离**：确保测试不会受到或影响实际终端状态

## 功能点目的

### 1. VT100 模拟

使用 `vt100` crate 创建一个内存中的 VT100 终端模拟器：
- 解析 ANSI 转义序列
- 维护屏幕状态（光标位置、字符属性等）
- 支持终端大小查询

### 2. 避免 stdout 写入

关键设计目标：避免调用任何可能写入 stdout 的 crossterm 方法：
- 不直接调用获取终端大小的 crossterm 方法
- 不直接调用获取光标位置的 crossterm 方法
- 所有状态查询都通过 vt100 解析器完成

### 3. Backend trait 实现

为 ratatui 提供完整的 `Backend` trait 实现：
- 绘制操作（`draw`）
- 光标控制（`hide_cursor`, `show_cursor`, `get_cursor_position`, `set_cursor_position`）
- 清屏操作（`clear`, `clear_region`）
- 终端信息（`size`, `window_size`）
- 滚动操作（`scroll_region_up`, `scroll_region_down`）

## 具体技术实现

### 核心结构

```rust
pub struct VT100Backend {
    crossterm_backend: CrosstermBackend<vt100::Parser>,
}

impl VT100Backend {
    pub fn new(width: u16, height: u16) -> Self {
        crossterm::style::force_color_output(true);
        Self {
            crossterm_backend: CrosstermBackend::new(vt100::Parser::new(height, width, 0)),
        }
    }

    pub fn vt100(&self) -> &vt100::Parser {
        self.crossterm_backend.writer()
    }
}
```

### Write trait 实现

```rust
impl Write for VT100Backend {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        self.crossterm_backend.writer_mut().write(buf)
    }

    fn flush(&mut self) -> io::Result<()> {
        self.crossterm_backend.writer_mut().flush()
    }
}
```

### Display trait 实现

```rust
impl fmt::Display for VT100Backend {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.crossterm_backend.writer().screen().contents())
    }
}
```

### Backend trait 实现

```rust
impl Backend for VT100Backend {
    fn draw<'a, I>(&mut self, content: I) -> io::Result<()>
    where
        I: Iterator<Item = (u16, u16, &'a Cell)>,
    {
        self.crossterm_backend.draw(content)
    }

    fn get_cursor_position(&mut self) -> io::Result<Position> {
        Ok(self.vt100().screen().cursor_position().into())
    }

    fn size(&self) -> io::Result<Size> {
        let (rows, cols) = self.vt100().screen().size();
        Ok(Size::new(cols, rows))
    }

    fn window_size(&mut self) -> io::Result<WindowSize> {
        Ok(WindowSize {
            columns_rows: self.vt100().screen().size().into(),
            pixels: Size { width: 640, height: 480 }, // 任意值
        })
    }

    // ... 其他方法委托给 crossterm_backend
}
```

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/tui_app_server/src/test_backend.rs` (125 行)

### 依赖模块
| 模块 | 用途 |
|------|------|
| `ratatui::backend::Backend` | 后端 trait |
| `ratatui::backend::CrosstermBackend` | 基础后端实现 |
| `vt100::Parser` | VT100 终端模拟 |

### 使用场景
- 单元测试中的终端渲染测试
- 快照测试（snapshot testing）
- 无需真实终端的 UI 测试

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|------|------|
| `ratatui` | TUI 框架和 Backend trait |
| `crossterm` | 终端控制和 CrosstermBackend |
| `vt100` | VT100 终端模拟 |

### 关键类型
- `vt100::Parser` - VT100 状态机解析器
- `vt100::Screen` - 屏幕状态
- `CrosstermBackend<vt100::Parser>` - 使用 vt100 作为 writer 的后端

## 风险、边界与改进建议

### 潜在风险

1. **vt100 兼容性**：`vt100` crate 可能不支持所有现代终端特性，某些高级渲染可能无法正确模拟。

2. **像素尺寸硬编码**：`window_size()` 返回固定的 640x480 像素尺寸，这可能影响依赖像素尺寸的计算。

3. **颜色输出强制**：构造函数调用 `force_color_output(true)`，可能影响全局状态。

### 边界情况

1. **零大小终端**：`new(width, height)` 接受任意尺寸，但 0x0 可能导致问题。

2. **光标位置转换**：`cursor_position()` 返回的位置需要转换为 ratatui 的 `Position` 类型。

3. **屏幕内容获取**：`screen().contents()` 返回的是纯文本，不包含样式信息。

### 改进建议

1. **可配置像素尺寸**：允许调用者指定 `window_size()` 返回的像素尺寸。

2. **样式信息访问**：提供获取屏幕样式信息的方法（如前景/背景色）。

3. **屏幕状态快照**：提供获取完整屏幕状态（包括样式）的方法，便于更详细的断言。

4. **滚动历史访问**：vt100 解析器维护滚动历史，可以暴露此功能用于测试滚动行为。

5. **性能优化**：对于大量测试，考虑使用对象池重用 VT100Backend 实例。

### 使用示例

```rust
// 创建 80x24 的测试后端
let backend = VT100Backend::new(80, 24);
let mut terminal = Terminal::new(backend)?;

// 渲染 UI
terminal.draw(|f| {
    // 渲染逻辑...
})?;

// 验证输出
let output = terminal.backend().to_string();
assert!(output.contains("Expected text"));

// 或使用 vt100 解析器进行更详细的验证
let screen = terminal.backend().vt100().screen();
assert_eq!(screen.cursor_position(), (0, 5));
```

### 与其他测试工具的比较

| 特性 | VT100Backend | TestBackend (ratatui 内置) |
|------|--------------|---------------------------|
| ANSI 序列解析 | 是 | 否 |
| 光标位置跟踪 | 是 | 是 |
| 样式跟踪 | 部分 | 是 |
| 性能 | 中等 | 高 |
| 复杂度 | 中等 | 低 |

VT100Backend 更适合需要验证 ANSI 序列行为的测试，而 ratatui 内置的 TestBackend 更适合简单的布局测试。
