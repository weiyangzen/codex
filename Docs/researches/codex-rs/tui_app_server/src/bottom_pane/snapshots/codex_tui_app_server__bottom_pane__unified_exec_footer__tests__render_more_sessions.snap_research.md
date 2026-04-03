# UnifiedExecFooter 单会话渲染快照分析

## 场景与职责

本快照展示了 `UnifiedExecFooter` 组件在仅存在单个后台统一执行会话时的渲染输出。这是最常见的基础场景，用于向用户展示有一个后台终端进程正在运行，并提供查看和管理该会话的操作提示。

**典型使用场景：**
- 用户通过 `/agent` 命令启动了一个代码执行任务（如 `rg "foo" src`）
- 任务在后台 sandbox 环境中持续运行，用户可以继续与 TUI 交互
- TUI 在底部栏显示一个简洁的提示，告知用户有后台活动
- 用户可以通过 `/ps` 查看会话详情，或通过 `/stop` 关闭它

**组件职责：**
1. 跟踪活跃的统一执行进程（unified-exec processes）
2. 生成格式化的摘要文本，正确处理单复数形式
3. 在底部栏渲染状态信息，支持宽度自适应截断
4. 与 `StatusIndicatorWidget` 协同，可在状态行内联显示

## 功能点目的

### 1. 单数形式智能处理
- **目的**：在只有一个会话时使用正确的英文语法（"1 background terminal running" 而非 "1 background terminals running"）
- **实现**：通过简单的条件判断 `if count == 1 { "" } else { "s" }` 动态添加复数后缀
- **用户体验**：避免语法错误带来的不专业感

### 2. 快捷操作提示
- **`/ps to view`**：提示用户可以使用 `/ps` 命令查看后台会话的详细列表
- **`/stop to close`**：提示用户可以使用 `/stop` 命令关闭后台会话
- **分隔符使用**：使用 `·`（中间点）作为视觉分隔符，保持简洁美观

### 3. 宽度自适应截断
- **目的**：在窄终端中优雅地处理文本溢出
- **实现**：使用 `take_prefix_by_width` 工具函数按显示宽度计算截断点
- **本快照表现**：宽度为50时，文本被截断为 `"  1 background terminal running · /ps to view · /s"`，`/stop` 被截断为 `/s`

### 4. 视觉样式
- **缩进**：渲染时添加2个空格缩进（`"  {summary}"`），与底部栏其他内容保持一致的视觉层级
- **颜色**：使用 `.dim()` 应用暗淡样式，降低视觉优先级，避免干扰主内容区域

## 具体技术实现

### 核心数据结构
```rust
pub(crate) struct UnifiedExecFooter {
    processes: Vec<String>,  // 存储进程标识符列表（本例中仅1个元素）
}
```

### 摘要文本生成逻辑
```rust
pub(crate) fn summary_text(&self) -> Option<String> {
    if self.processes.is_empty() {
        return None;  // 无进程时不显示任何内容
    }

    let count = self.processes.len();
    // 单复数处理：count == 1 时不加 "s"
    let plural = if count == 1 { "" } else { "s" };
    Some(format!(
        "{count} background terminal{plural} running · /ps to view · /stop to close"
    ))
}
```

### 渲染流程
```rust
fn render_lines(&self, width: u16) -> Vec<Line<'static>> {
    if width < 4 {
        return Vec::new();  // 宽度过小，不渲染
    }
    let Some(summary) = self.summary_text() else {
        return Vec::new();  // 无进程，不渲染
    };
    let message = format!("  {summary}");  // 添加2空格缩进
    // 按显示宽度截断，正确处理 Unicode 字符
    let (truncated, _, _) = take_prefix_by_width(&message, width as usize);
    vec![Line::from(truncated.dim())]  // 应用暗淡样式
}
```

### 宽度截断工具函数
```rust
// 位于 codex-rs/tui_app_server/src/live_wrap.rs
pub fn take_prefix_by_width(text: &str, max_cols: usize) -> (String, &str, usize) {
    // 基于 UnicodeWidthChar 计算每个字符的显示宽度
    // 正确处理 ASCII、CJK、Emoji 等不同宽度的字符
    // 返回：(前缀字符串, 剩余后缀, 前缀宽度)
}
```

## 关键代码路径与文件引用

### 主要实现文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/bottom_pane/unified_exec_footer.rs` | `UnifiedExecFooter` 组件完整实现，包含本测试用例 |
| `codex-rs/tui_app_server/src/bottom_pane/mod.rs` | `BottomPane` 集成，管理 `unified_exec_footer` 字段和生命周期 |
| `codex-rs/tui_app_server/src/bottom_pane/footer.rs` | 底部栏其他组件，与 `UnifiedExecFooter` 协同布局 |
| `codex-rs/tui_app_server/src/live_wrap.rs` | `take_prefix_by_width` 宽度截断工具函数 |

### 关键方法调用链
```
BottomPane::set_unified_exec_processes()
  └── UnifiedExecFooter::set_processes()
        └── sync_status_inline_message()
              └── StatusIndicatorWidget::update_inline_message()

BottomPane::render() / Renderable::render()
  └── UnifiedExecFooter::render()
        └── render_lines()
              └── summary_text()
              └── take_prefix_by_width()
```

### 测试用例源码
```rust
#[test]
fn render_more_sessions() {
    let mut footer = UnifiedExecFooter::new();
    // 设置单个进程：模拟 "rg "foo" src" 命令
    footer.set_processes(vec!["rg \"foo\" src".to_string()]);
    let width = 50;
    let height = footer.desired_height(width);
    let mut buf = Buffer::empty(Rect::new(0, 0, width, height));
    footer.render(Rect::new(0, 0, width, height), &mut buf);
    assert_snapshot!("render_more_sessions", format!("{buf:?}"));
}
```

### 快照输出解析
```
Buffer {
    area: Rect { x: 0, y: 0, width: 50, height: 1 },
    content: [
        "  1 background terminal running · /ps to view · /s",  // 被截断的文本
    ],
    styles: [
        x: 0, y: 0, fg: Reset, bg: Reset, underline: Reset, modifier: DIM,  // 暗淡样式
    ]
}
```

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|-----|------|
| `ratatui` | 终端 UI 渲染框架，提供 `Buffer`, `Rect`, `Line`, `Paragraph`, `Stylize` trait |
| `unicode_width` | Unicode 字符宽度计算（通过 `live_wrap.rs` 间接使用） |
| `insta` | 快照测试框架，用于验证渲染输出 |
| `pretty_assertions` | 测试断言美化 |

### 与 BottomPane 的集成
```rust
// BottomPane 结构体中的 unified_exec_footer 字段
pub(crate) struct BottomPane {
    // ...
    /// Unified exec session summary source.
    ///
    /// When a status row exists, this summary is mirrored inline in that row;
    /// when no status row exists, it renders as its own footer row.
    unified_exec_footer: UnifiedExecFooter,
    // ...
}

// 更新进程列表的公共接口
pub(crate) fn set_unified_exec_processes(&mut self, processes: Vec<String>) {
    if self.unified_exec_footer.set_processes(processes) {
        self.sync_status_inline_message();  // 同步到状态指示器
        self.request_redraw();  // 请求重绘
    }
}

// 将摘要文本同步到状态指示器的内联消息
fn sync_status_inline_message(&mut self) {
    if let Some(status) = self.status.as_mut() {
        status.update_inline_message(self.unified_exec_footer.summary_text());
    }
}
```

### 与 StatusIndicatorWidget 的交互
- 当 `StatusIndicatorWidget` 活跃时（任务运行中），`UnifiedExecFooter` 的摘要文本会作为内联消息显示在状态行中
- 当无状态指示器时，`UnifiedExecFooter` 会渲染为独立的底部栏行
- 这种设计避免了在状态行已存在时重复显示信息

## 风险、边界与改进建议

### 当前边界情况

1. **宽度截断导致命令提示不完整**
   - **现象**：如本快照所示，宽度为50时，`/stop to close` 被截断为 `/s`
   - **影响**：用户可能无法识别被截断的命令提示
   - **缓解**：保持最小宽度要求，或在极窄宽度下优先保留关键命令提示

2. **单复数处理过于简单**
   - **现状**：仅通过添加 "s" 后缀处理复数
   - **风险**：国际化时无法适应其他语言的复杂复数规则（如俄语、阿拉伯语）
   - **建议**：使用 `icu` 或 `fluent` 等国际化框架

3. **进程标识符仅用于计数**
   - 当前实现中 `processes: Vec<String>` 存储进程标识符，但仅使用其长度
   - 潜在的内存开销，如果进程标识符很长或数量很多

### 潜在风险

| 风险 | 描述 | 可能性 | 影响 |
|-----|------|--------|------|
| 信息截断误导 | `/stop` 被截断为 `/s`，用户可能误解为其他命令 | 中 | 中 |
| 样式不一致 | `.dim()` 样式需要与底部栏其他组件保持同步 | 低 | 低 |
| 复数规则错误 | 当前实现仅适用于英文，国际化时会出错 | 中 | 低 |

### 改进建议

1. **响应式摘要文本**
   ```rust
   // 根据可用宽度生成不同详细程度的摘要
   fn summary_text_for_width(&self, width: usize) -> Option<String> {
       let count = self.processes.len();
       match width {
           0..=25 => None,  // 太窄，不显示
           26..=40 => Some(format!("{count} bg")),  // 极简模式
           41..=55 => Some(format!("{count} running · /ps · /stop")),  // 紧凑模式
           _ => self.summary_text(),  // 完整模式
       }
   }
   ```

2. **优先级截断策略**
   - 当前实现从左侧开始截断，保留左侧内容
   - 建议优先保留命令提示（`/ps`, `/stop`），截断中间的描述文本
   - 例如：`"1 terminal · /ps · /stop"` 而非 `"1 background terminal running · /ps to view · /s"`

3. **国际化支持**
   ```rust
   // 使用 ICU MessageFormat 处理复数
   let message = fluent::Message::new("background-terminals-running")
       .arg("count", count);
   ```

4. **内存优化**
   - 如果仅需计数，可将 `Vec<String>` 改为仅存储数量
   - 或延迟存储，仅在需要详情时才保留进程标识符

5. **交互增强**
   - 在支持鼠标的终端中，使 `/ps` 和 `/stop` 文本可点击
   - 添加键盘快捷键提示，如 `Alt+P` 快速查看，`Alt+S` 快速停止

6. **测试覆盖扩展**
   - 添加边界宽度测试（如刚好能显示完整文本的宽度）
   - 添加空进程列表测试（验证 `is_empty()` 和 `summary_text()` 返回 `None`）
   - 添加极大进程数量测试（验证性能和大数显示）
