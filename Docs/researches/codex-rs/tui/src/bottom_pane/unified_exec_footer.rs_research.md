# unified_exec_footer.rs 深度研究文档

## 1. 场景与职责

`unified_exec_footer.rs` 是 Codex TUI 底部面板的一个辅助组件，负责显示**统一执行（unified-exec）后台会话**的状态摘要。统一执行是 Codex 的一个功能，允许在后台运行终端命令（如 `rg` 搜索、`python` 脚本等），这些命令在独立的终端会话中执行，不会阻塞主交互流程。

### 核心职责

1. **跟踪后台进程**：维护当前正在运行的后台终端进程列表
2. **生成状态摘要**：提供标准化的摘要文本，显示后台进程数量
3. **渲染 Footer**：在底部面板渲染一行状态提示
4. **与 Status Line 集成**：当状态指示器可见时，摘要可以内联显示在状态行中

### 在架构中的位置

```
ChatWidget
  └── BottomPane
        ├── ChatComposer
        ├── StatusIndicatorWidget (可选)
        ├── UnifiedExecFooter  <-- 本模块
        └── PendingInputPreview
```

`UnifiedExecFooter` 由 `BottomPane` 直接拥有和管理，通过 `set_unified_exec_processes` 方法接收更新。

## 2. 功能点目的

### 2.1 后台进程跟踪

| 功能 | 目的 |
|------|------|
| `set_processes` | 更新后台进程列表，返回是否有变化（用于决定是否需要重绘） |
| `is_empty` | 检查是否有后台进程在运行 |

### 2.2 摘要文本生成

| 功能 | 目的 |
|------|------|
| `summary_text` | 生成标准化的摘要文本，如 "1 background terminal running · /ps to view · /stop to close" |

摘要文本包含：
- 进程数量（自动处理单复数形式）
- 查看命令提示（`/ps`）
- 关闭命令提示（`/stop`）

### 2.3 渲染

| 功能 | 目的 |
|------|------|
| `render_lines` | 生成用于渲染的 `Line` 列表（带缩进和样式） |
| `render` | 实现 `Renderable` trait，在指定区域渲染 |
| `desired_height` | 计算渲染所需高度 |

## 3. 具体技术实现

### 3.1 核心数据结构

```rust
/// 跟踪活动 unified-exec 进程并渲染紧凑摘要
pub(crate) struct UnifiedExecFooter {
    processes: Vec<String>,  // 后台进程命令列表
}

impl UnifiedExecFooter {
    pub(crate) fn new() -> Self {
        Self { processes: Vec::new() }
    }
}
```

### 3.2 进程更新

```rust
pub(crate) fn set_processes(&mut self, processes: Vec<String>) -> bool {
    if self.processes == processes {
        return false;  // 无变化，避免不必要的重绘
    }
    self.processes = processes;
    true  // 有变化，需要重绘
}
```

**设计要点**：
- 返回 `bool` 表示是否有变化，调用方（`BottomPane`）据此决定是否请求重绘
- 使用 `Vec<String>` 而非 `Vec<&str>`，因为进程信息可能来自异步任务

### 3.3 摘要文本生成

```rust
pub(crate) fn summary_text(&self) -> Option<String> {
    if self.processes.is_empty() {
        return None;  // 无进程时不显示任何内容
    }

    let count = self.processes.len();
    let plural = if count == 1 { "" } else { "s" };
    Some(format!(
        "{count} background terminal{plural} running · /ps to view · /stop to close"
    ))
}
```

**设计要点**：
- 返回 `Option<String>`：`None` 表示无内容可显示
- 单复数自动处理：`terminal` vs `terminals`
- 提示用户使用 `/ps` 和 `/stop` 命令管理后台进程

### 3.4 渲染实现

```rust
fn render_lines(&self, width: u16) -> Vec<Line<'static>> {
    if width < 4 {
        return Vec::new();  // 宽度不足，不渲染
    }
    let Some(summary) = self.summary_text() else {
        return Vec::new();  // 无进程，不渲染
    };
    let message = format!("  {summary}");  // 添加前导缩进
    let (truncated, _, _) = take_prefix_by_width(&message, width as usize);
    vec![Line::from(truncated.dim())]  // 使用 dim 样式（灰色）
}
```

**样式约定**：
- 前导缩进：2 个空格（`FOOTER_INDENT_COLS` 的局部约定）
- 文本样式：`.dim()`（灰色/暗淡），表示这是辅助信息

### 3.5 Renderable Trait 实现

```rust
impl Renderable for UnifiedExecFooter {
    fn render(&self, area: Rect, buf: &mut Buffer) {
        if area.is_empty() {
            return;
        }
        Paragraph::new(self.render_lines(area.width)).render(area, buf);
    }

    fn desired_height(&self, width: u16) -> u16 {
        self.render_lines(width).len() as u16
    }
}
```

**设计要点**：
- 实现 `Renderable` trait，使其可以被通用渲染系统处理
- `desired_height` 根据内容动态计算（0 或 1 行）

## 4. 关键代码路径与文件引用

### 4.1 主要调用路径

```
后台进程状态更新
  └── App 事件处理
        └── BottomPane::set_unified_exec_processes
              └── UnifiedExecFooter::set_processes
                    └── 返回 true → BottomPane::sync_status_inline_message
                          └── StatusIndicatorWidget::update_inline_message

渲染
  └── BottomPane::render
        └── 检查 unified_exec_footer.is_empty()
              ├── 如果不为空 → UnifiedExecFooter::render
              └── 如果 status 存在 → 摘要已内联显示
```

### 4.2 相关文件

| 文件 | 关系 | 说明 |
|------|------|------|
| `codex-rs/tui/src/bottom_pane/mod.rs` | 调用方 | 拥有 UnifiedExecFooter 实例，调用 set_processes 和 render |
| `codex-rs/tui/src/live_wrap.rs` | 依赖 | 提供 `take_prefix_by_width` 用于截断文本 |
| `codex-rs/tui/src/render/renderable.rs` | 依赖 | 定义 `Renderable` trait |

### 4.3 关键行号引用

- **数据结构定义**：行 17-19
- **构造函数**：行 22-26
- **进程更新**：行 28-34
- **空检查**：行 36-38
- **摘要文本**：行 45-55
- **渲染行生成**：行 57-67
- **Renderable 实现**：行 70-82
- **测试**：行 84-117

## 5. 依赖与外部交互

### 5.1 外部 crate

| Crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染（`Buffer`, `Rect`, `Line`, `Paragraph`, `Stylize`） |

### 5.2 内部模块

| 模块 | 用途 |
|------|------|
| `crate::live_wrap::take_prefix_by_width` | 按显示宽度截断字符串 |
| `crate::render::renderable::Renderable` | 渲染抽象接口 |

### 5.3 与 BottomPane 的交互

```rust
// BottomPane 中的使用
pub(crate) fn set_unified_exec_processes(&mut self, processes: Vec<String>) {
    if self.unified_exec_footer.set_processes(processes) {
        self.sync_status_inline_message();  // 同步到状态行
        self.request_redraw();
    }
}

fn sync_status_inline_message(&mut self) {
    if let Some(status) = self.status.as_mut() {
        status.update_inline_message(self.unified_exec_footer.summary_text());
    }
}
```

**双模式显示**：
1. **独立 Footer 模式**：当没有状态指示器时，`UnifiedExecFooter` 自己渲染一行
2. **内联模式**：当状态指示器可见时，摘要显示在状态行中，Footer 不渲染

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 宽度不足处理

**风险**：当可用宽度小于 4 时，`render_lines` 返回空向量，用户看不到后台进程提示。

**当前行为**：静默不显示

**建议**：考虑在极窄宽度下显示简化版本（如仅显示数量）。

#### 6.1.2 进程列表过长

**风险**：如果后台进程很多，`summary_text` 只显示数量，但用户可能想知道具体是哪些进程。

**当前行为**：仅显示 "N background terminals running"

**建议**：考虑在 `/ps` 命令的输出中提供详细信息（这已经实现，但 Footer 本身不显示进程名）。

### 6.2 边界情况

| 场景 | 行为 | 测试覆盖 |
|------|------|----------|
| 空进程列表 | `is_empty()` 返回 true，`summary_text()` 返回 None | 是 |
| 单进程 | 使用单数形式 "terminal" | 是（`render_more_sessions`） |
| 多进程 | 使用复数形式 "terminals" | 是（`render_many_sessions`） |
| 宽度 < 4 | 返回空行列表 | 否（隐式处理） |
| 宽度不足以显示完整文本 | `take_prefix_by_width` 截断 | 是 |

### 6.3 测试覆盖

当前测试包含：

1. **`desired_height_empty`**：验证空进程列表时高度为 0
2. **`render_more_sessions`**：验证单进程渲染（使用 insta snapshot）
3. **`render_many_sessions`**：验证多进程（123 个）渲染（使用 insta snapshot）

**测试特点**：
- 使用 `insta` 进行快照测试，验证渲染输出
- 使用 `Buffer::empty` 创建测试缓冲区
- 验证 `desired_height` 和实际渲染行为一致

### 6.4 改进建议

#### 6.4.1 进程信息显示

当前只显示进程数量，可以考虑：
- 在悬停或特定快捷键下显示进程列表
- 显示最近启动的进程名称（如 "rg 'foo' src and 2 more"）

#### 6.4.2 状态区分

当前不区分进程状态，可以扩展为：
- 运行中（running）
- 已完成（completed）
- 出错（failed）

#### 6.4.3 交互增强

可以考虑添加直接交互：
- 点击摘要打开 `/ps` 视图
- 快捷键快速访问 `/stop`

#### 6.4.4 国际化

当前文本硬编码为英文，如果需要多语言支持，需要将文本提取到资源文件中。

### 6.5 代码风格一致性

根据项目 `AGENTS.md` 中的 TUI 风格约定：

- ✅ 使用 `Stylize` trait：`.dim()`
- ✅ 使用简单转换：`Line::from(truncated.dim())`
- ✅ 避免硬编码白色：使用默认前景色或 dim
- ✅ 紧凑性：`render_lines` 保持简洁

### 6.6 与 tui_app_server 的同步

根据 `AGENTS.md` 中的约定：

> When a change lands in `codex-rs/tui` and `codex-rs/tui_app_server` has a parallel implementation of the same behavior, reflect the change in `codex-rs/tui_app_server` too unless there is a documented reason not to.

需要检查 `tui_app_server` 是否有对应的 `UnifiedExecFooter` 实现，确保行为一致。
