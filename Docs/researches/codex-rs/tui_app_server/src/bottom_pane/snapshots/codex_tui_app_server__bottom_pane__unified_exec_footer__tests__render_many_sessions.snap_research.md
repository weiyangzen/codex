# UnifiedExecFooter 多会话渲染快照分析

## 场景与职责

本快照展示了 `UnifiedExecFooter` 组件在存在大量（123个）后台统一执行会话时的渲染输出。该组件是 Codex TUI 底部状态栏的一部分，用于向用户展示当前正在运行的后台终端进程数量，并提供相关的快捷操作提示。

**典型使用场景：**
- 用户通过 `/agent` 命令或其他方式启动了多个并行的代码执行任务
- 这些任务在后台的 sandbox 环境中持续运行
- TUI 需要以非侵入方式告知用户有后台活动正在进行
- 用户可以通过 `/ps` 查看所有会话，或通过 `/stop` 关闭它们

**组件职责：**
1. 跟踪活跃的统一执行进程（unified-exec processes）
2. 生成格式化的摘要文本，包含进程数量和操作提示
3. 在底部栏渲染状态信息，支持宽度自适应截断
4. 与 `StatusIndicatorWidget` 协同，可在状态行内联显示

## 功能点目的

### 1. 后台进程计数展示
- **目的**：让用户了解当前有多少个终端会话在后台运行
- **实现**：`summary_text()` 方法根据 `processes` 向量长度生成计数
- **复数处理**：智能处理单复数形式（"1 terminal" vs "N terminals"）

### 2. 快捷操作提示
- **`/ps to view`**：提示用户可以使用 `/ps` 命令查看所有后台会话的详细列表
- **`/stop to close`**：提示用户可以使用 `/stop` 命令关闭后台会话
- **分隔符使用**：使用 `·`（中间点）作为视觉分隔符，保持简洁美观

### 3. 宽度自适应截断
- **目的**：在窄终端中优雅地处理文本溢出
- **实现**：使用 `take_prefix_by_width` 工具函数按显示宽度截断
- **本快照表现**：宽度为50时，文本被截断为 `"  123 background terminals running · /ps to view ·"`，`/stop to close` 部分被隐藏

### 4. 视觉样式
- **缩进**：渲染时添加2个空格缩进（`"  {summary}"`），与底部栏其他内容对齐
- **颜色**：使用 `.dim()` 应用暗淡样式，降低视觉优先级，避免干扰主内容

## 具体技术实现

### 核心数据结构
```rust
pub(crate) struct UnifiedExecFooter {
    processes: Vec<String>,  // 存储进程标识符列表
}
```

### 摘要文本生成逻辑
```rust
pub(crate) fn summary_text(&self) -> Option<String> {
    if self.processes.is_empty() {
        return None;  // 无进程时不显示任何内容
    }

    let count = self.processes.len();
    let plural = if count == 1 { "" } else { "s" };  // 单复数处理
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
    let message = format!("  {summary}");  // 添加缩进
    let (truncated, _, _) = take_prefix_by_width(&message, width as usize);  // 宽度截断
    vec![Line::from(truncated.dim())]  // 应用暗淡样式
}
```

### 宽度截断工具函数
```rust
// 位于 live_wrap.rs
pub fn take_prefix_by_width(text: &str, max_cols: usize) -> (String, &str, usize) {
    // 基于 Unicode 字符宽度计算，正确处理中英文混排
    // 返回：(前缀字符串, 剩余后缀, 前缀宽度)
}
```

## 关键代码路径与文件引用

### 主要实现文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/bottom_pane/unified_exec_footer.rs` | `UnifiedExecFooter` 组件完整实现 |
| `codex-rs/tui_app_server/src/bottom_pane/mod.rs` | `BottomPane` 集成，管理 `unified_exec_footer` 字段 |
| `codex-rs/tui_app_server/src/bottom_pane/footer.rs` | 底部栏其他组件，与 `UnifiedExecFooter` 协同 |
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

### 测试用例
```rust
#[test]
fn render_many_sessions() {
    let mut footer = UnifiedExecFooter::new();
    footer.set_processes((0..123).map(|idx| format!("cmd {idx}")).collect());  // 123个进程
    let width = 50;
    let height = footer.desired_height(width);
    let mut buf = Buffer::empty(Rect::new(0, 0, width, height));
    footer.render(Rect::new(0, 0, width, height), &mut buf);
    assert_snapshot!("render_many_sessions", format!("{buf:?}"));
}
```

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|-----|------|
| `ratatui` | 终端 UI 渲染框架，提供 `Buffer`, `Rect`, `Line`, `Paragraph`, `Stylize` |
| `unicode_width` | Unicode 字符宽度计算（通过 `live_wrap.rs` 间接使用） |
| `insta` | 快照测试框架 |
| `pretty_assertions` | 测试断言美化 |

### 与 BottomPane 的集成
```rust
// BottomPane 结构体
pub(crate) struct BottomPane {
    // ...
    unified_exec_footer: UnifiedExecFooter,  // 内联状态摘要源
    // ...
}

// 更新进程列表
pub(crate) fn set_unified_exec_processes(&mut self, processes: Vec<String>) {
    if self.unified_exec_footer.set_processes(processes) {
        self.sync_status_inline_message();
        self.request_redraw();
    }
}

// 同步到状态指示器
fn sync_status_inline_message(&mut self) {
    if let Some(status) = self.status.as_mut() {
        status.update_inline_message(self.unified_exec_footer.summary_text());
    }
}
```

### 与 StatusIndicatorWidget 的交互
- 当 `StatusIndicatorWidget` 活跃时，`UnifiedExecFooter` 的摘要文本会作为内联消息显示在状态行中
- 当无状态指示器时，`UnifiedExecFooter` 会渲染为独立的底部栏行

## 风险、边界与改进建议

### 当前边界情况

1. **宽度截断导致信息丢失**
   - **现象**：如本快照所示，宽度为50时，`/stop to close` 提示被截断
   - **影响**：用户可能不知道可以如何关闭后台会话
   - **缓解**：保持最小宽度要求，或在极窄宽度下提供替代提示

2. **复数处理仅支持英文**
   - **现状**：简单添加 "s" 后缀
   - **风险**：国际化时可能不适用其他语言的复数规则

3. **进程列表无去重机制**
   - `set_processes` 直接替换整个列表，依赖上游保证数据一致性

### 潜在风险

| 风险 | 描述 | 可能性 |
|-----|------|--------|
| 信息过载 | 大量后台进程时，摘要文本过长，频繁截断 | 中 |
| 样式不一致 | `.dim()` 样式与底部栏其他组件的样式需保持一致 | 低 |
| 性能问题 | 进程数量极多时（如数千个），字符串格式化开销 | 低 |

### 改进建议

1. **响应式摘要文本**
   ```rust
   // 建议：根据可用宽度生成不同详细程度的摘要
   fn summary_text_for_width(&self, width: usize) -> Option<String> {
       let count = self.processes.len();
       if width < 30 {
           Some(format!("{count} bg terms"))  // 极简模式
       } else if width < 50 {
           Some(format!("{count} running · /ps"))  // 中等模式
       } else {
           self.summary_text()  // 完整模式
       }
   }
   ```

2. **添加进程数量阈值提示**
   - 当进程数量超过某个阈值（如50）时，显示 "50+" 而非精确数字
   - 减少视觉噪音，同时传达"大量活动"的信息

3. **国际化支持**
   - 使用 ICU 复数规则或 `fluent` 等国际化框架处理复数形式
   - 支持多语言的命令提示（`/ps`, `/stop`）

4. **交互增强**
   - 考虑在支持鼠标的终端中，使摘要文本可点击，直接触发 `/ps` 或 `/stop`
   - 添加悬停提示（tooltip）显示完整进程列表预览

5. **性能优化**
   - 如果进程数量可能非常大，考虑使用 `iter::count()` 而非存储完整向量
   - 延迟格式化，仅在需要渲染时才生成字符串
