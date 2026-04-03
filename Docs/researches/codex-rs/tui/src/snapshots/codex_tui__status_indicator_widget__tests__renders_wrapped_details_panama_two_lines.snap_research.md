# StatusIndicatorWidget - Details 文本换行渲染快照研究文档

## 场景与职责

本快照测试验证 `StatusIndicatorWidget` 的**详情文本换行功能**，当状态指示器需要显示额外上下文信息（如后台进程摘要）时，details 字段支持多行文本并在有限宽度内自动换行。

**测试场景：**
- 输入文本：`"A man a plan a canal panama"`（27个字符）
- 终端宽度：30列
- 前缀宽度：4列（`"  └ "`）
- 可用内容宽度：26列

**预期行为：** 文本在 26 列处换行，分成两行显示（"A man a plan a canal" + "panama"），验证换行逻辑的正确性。

---

## 功能点目的

### 1. Details 文本显示
- **目的**：提供任务执行的详细上下文信息
- **使用场景**：显示 unified-exec 后台进程摘要、命令输出预览等
- **位置**：状态头部下方，带缩进前缀显示

### 2. 智能换行
- **目的**：在有限宽度内优雅地显示长文本
- **实现**：使用 `word_wrap_lines` 配合自定义 `RtOptions`
- **缩进控制**：
  - 首行前缀：`"  └ "`（4列，dim 样式）
  - 后续行前缀：与首行前缀等宽的空格（保持对齐）

### 3. 行数限制与截断
- **默认限制**：`STATUS_DETAILS_DEFAULT_MAX_LINES = 3`
- **溢出处理**：超出限制时截断并在末尾添加省略号（`…`）
- **可配置**：通过 `update_details()` 参数自定义最大行数

### 4. 首字母大写控制
- **选项**：`StatusDetailsCapitalization::CapitalizeFirst` / `Preserve`
- **默认行为**：自动首字母大写（如输入 "a man" 显示 "A man"）

---

## 具体技术实现

### Details 数据结构

```rust
pub(crate) struct StatusIndicatorWidget {
    details: Option<String>,                 // 详细说明文本
    details_max_lines: usize,                // 最大行数限制（默认3）
    // ...
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum StatusDetailsCapitalization {
    CapitalizeFirst,    // 首字母大写
    Preserve,           // 保持原样
}
```

### 换行核心逻辑

```rust
const DETAILS_PREFIX: &str = "  └ ";

fn wrapped_details_lines(&self, width: u16) -> Vec<Line<'static>> {
    let Some(details) = self.details.as_deref() else {
        return Vec::new();
    };
    
    // 计算前缀宽度（4列）
    let prefix_width = UnicodeWidthStr::width(DETAILS_PREFIX);
    
    // 配置换行选项
    let opts = RtOptions::new(usize::from(width))
        .initial_indent(Line::from(DETAILS_PREFIX.dim()))
        .subsequent_indent(Line::from(Span::from(" ".repeat(prefix_width)).dim()))
        .break_words(true);  // 允许在单词内断行
    
    // 执行换行
    let mut out = word_wrap_lines(details.lines().map(|line| vec![line.dim()]), opts);
    
    // 行数限制与截断处理
    if out.len() > self.details_max_lines {
        out.truncate(self.details_max_lines);
        // 在最后一行添加省略号...
        let content_width = usize::from(width).saturating_sub(prefix_width).max(1);
        let max_base_len = content_width.saturating_sub(1);
        if let Some(last) = out.last_mut()
            && let Some(span) = last.spans.last_mut()
        {
            let trimmed: String = span.content.as_ref().chars().take(max_base_len).collect();
            *span = format!("{trimmed}…").dim();
        }
    }
    
    out
}
```

### 更新 Details 的方法

```rust
pub(crate) fn update_details(
    &mut self,
    details: Option<String>,
    capitalization: StatusDetailsCapitalization,
    max_lines: usize,
) {
    self.details_max_lines = max_lines.max(1);
    self.details = details
        .filter(|details| !details.is_empty())
        .map(|details| {
            let trimmed = details.trim_start();
            match capitalization {
                StatusDetailsCapitalization::CapitalizeFirst => capitalize_first(trimmed),
                StatusDetailsCapitalization::Preserve => trimmed.to_string(),
            }
        });
}
```

### 渲染流程中的 Details 处理

```rust
fn render(&self, area: Rect, buf: &mut Buffer) {
    // ... 头部渲染 ...
    
    let mut lines = Vec::new();
    lines.push(truncate_line_with_ellipsis_if_overflow(...));  // 主状态行
    
    if area.height > 1 {
        // 如果有足够空间，添加 details 行
        let details = self.wrapped_details_lines(area.width);
        let max_details = usize::from(area.height.saturating_sub(1));
        lines.extend(details.into_iter().take(max_details));
    }
    
    Paragraph::new(Text::from(lines)).render_ref(area, buf);
}
```

---

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/status_indicator_widget.rs:199-229` | `wrapped_details_lines()` 核心实现 |
| `codex-rs/tui/src/status_indicator_widget.rs:109-126` | `update_details()` 更新方法 |
| `codex-rs/tui/src/status_indicator_widget.rs:281-286` | `render()` 中的 details 渲染逻辑 |
| `codex-rs/tui/src/wrapping.rs` | `word_wrap_lines()` 和 `RtOptions` 定义 |
| `codex-rs/tui/src/text_formatting.rs` | `capitalize_first()` 首字母大写 |

### 测试代码位置

```rust
// codex-rs/tui/src/status_indicator_widget.rs:348-370
#[test]
fn renders_wrapped_details_panama_two_lines() {
    let (tx_raw, _rx) = unbounded_channel::<AppEvent>();
    let tx = AppEventSender::new(tx_raw);
    let mut w = StatusIndicatorWidget::new(tx, crate::tui::FrameRequester::test_dummy(), false);
    w.update_details(
        Some("A man a plan a canal panama".to_string()),
        StatusDetailsCapitalization::CapitalizeFirst,
        STATUS_DETAILS_DEFAULT_MAX_LINES,
    );
    w.set_interrupt_hint_visible(false);

    // 冻结时间以保持快照稳定
    w.is_paused = true;
    w.elapsed_running = Duration::ZERO;

    // 宽度30，前缀4列，内容宽度26（比完整短语27列少1）
    let mut terminal = Terminal::new(TestBackend::new(30, 3)).expect("terminal");
    terminal
        .draw(|f| w.render(f.area(), f.buffer_mut()))
        .expect("draw");
    insta::assert_snapshot!(terminal.backend());
}
```

---

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `ratatui` | Line, Span, Text, Paragraph 等渲染类型 |
| `unicode-width` | Unicode 字符串宽度计算（`UnicodeWidthStr::width`） |
| `textwrap` | 底层文本换行算法（通过 `wrapping.rs` 封装） |

### 内部模块依赖

```
wrapped_details_lines()
├── UnicodeWidthStr::width() ← unicode-width crate
├── RtOptions::new() ← wrapping.rs
├── word_wrap_lines() ← wrapping.rs
│   └── textwrap::wrap() ← textwrap crate
└── capitalize_first() ← text_formatting.rs
```

### 样式处理

```rust
// 前缀样式
"  └ ".dim()  // 暗淡样式

// 内容样式
line.dim()    // 所有 details 文本使用暗淡样式

// 省略号样式
format!("{trimmed}…").dim()
```

---

## 风险、边界与改进建议

### 已知风险

1. **宽度计算精度**
   - 全角字符（CJK）宽度计算可能不准确
   - 依赖 `unicode-width` crate，但某些特殊字符可能处理不当

2. **行数限制截断**
   - 截断时可能切断多字节 UTF-8 字符
   - 当前实现使用 `chars().take()` 是安全的，但需持续验证

3. **性能问题**
   - 每次渲染都重新计算换行
   - 长文本频繁渲染可能影响性能

### 边界情况

| 场景 | 当前行为 | 评估 |
|-----|---------|------|
| 文本为空字符串 | 不显示 details 区域 | ✅ 正确 |
| 宽度为 0 | 返回空 Vec | ✅ 安全 |
| 单行文本很短 | 正常显示，不换行 | ✅ 正确 |
| 文本包含换行符 | 按原换行分割后再 wrap | ✅ 符合预期 |
| 文本长度 = 内容宽度 | 刚好一行，不换行 | ✅ 正确 |
| 文本长度 = 内容宽度 + 1 | 强制换行 | ✅ 正确 |
| 行数 > max_lines | 截断并添加省略号 | ✅ 正确 |

### 改进建议

1. **缓存优化**
   ```rust
   // 建议：缓存换行结果，避免重复计算
   struct StatusIndicatorWidget {
       details_cache: Option<(String, u16, Vec<Line<'static>>)>,
   }
   ```

2. **更智能的截断**
   - 当前在字符边界截断，建议在单词边界截断
   - 使用 `textwrap` 的 `WordSplitter` 功能

3. **滚动支持**
   - 当内容超过 max_lines 时，支持垂直滚动查看完整内容
   - 添加滚动指示器（如 "… (3 more lines)"）

4. **URL 识别**
   - 参考 `wrapping.rs` 的 URL 检测逻辑
   - 避免在 URL 中间换行，保持链接可点击

5. **配置扩展**
   ```rust
   pub struct DetailsConfig {
       pub max_lines: usize,
       pub break_words: bool,           // 是否允许单词内断行
       pub preserve_urls: bool,         // 是否保护 URL 不被截断
       pub truncation_indicator: String, // 自定义截断指示器
   }
   ```

6. **测试增强**
   - 添加 CJK 字符宽度测试
   - 添加 emoji 字符测试
   - 添加零宽度连接符（ZWNJ）测试
