# UnifiedExecFooter 组件研究文档

## 场景与职责

`UnifiedExecFooter` 是 Codex TUI 应用服务器中用于显示统一执行（unified-exec）后台会话状态的 UI 组件，位于 `codex-rs/tui_app_server/src/bottom_pane/unified_exec_footer.rs`。该组件的核心职责包括：

1. **后台进程状态展示**：跟踪并显示当前运行的后台终端会话数量
2. **用户操作提示**：向用户展示可用的交互命令（`/ps` 查看、`/stop` 关闭）
3. **状态行集成**：与主状态行（status line）集成，在任务运行时以内联方式显示摘要
4. **独立页脚渲染**：当没有活动任务时，作为独立的页脚行渲染

该组件是 TUI 底部面板（Bottom Pane）状态显示系统的一部分，与 `StatusIndicatorWidget` 协同工作，为用户提供统一的后台执行可见性。

## 功能点目的

### 1. 后台进程跟踪
- **目的**：让用户了解当前有多少后台终端会话正在运行
- **实现**：维护一个 `Vec<String>` 存储进程标识（通常是命令字符串）
- **更新机制**：通过 `set_processes` 方法接收外部状态更新，仅在进程列表变化时返回 `true` 触发重绘

### 2. 摘要文本生成
- **目的**：生成人类可读的状态摘要，支持复数形式
- **示例输出**：
  - 单进程：`"1 background terminal running · /ps to view · /stop to close"`
  - 多进程：`"3 background terminals running · /ps to view · /stop to close"`

### 3. 渲染适配
- **目的**：适应不同的布局场景（状态行内联 vs 独立页脚）
- **关键方法**：
  - `summary_text()`：返回纯文本，供状态行使用
  - `render_lines()`：返回带样式的 `Line` 向量，供独立页脚使用
  - `take_prefix_by_width()`：处理宽度截断，确保内容适合可用空间

### 4. 宽度感知截断
- **目的**：在窄宽度终端中优雅地处理长文本
- **实现**：使用 `live_wrap::take_prefix_by_width` 进行显示宽度感知的截断

## 具体技术实现

### 数据结构

```rust
/// 跟踪活跃 unified-exec 进程并渲染紧凑摘要
pub(crate) struct UnifiedExecFooter {
    processes: Vec<String>,  // 后台进程标识列表
}

impl UnifiedExecFooter {
    pub(crate) fn new() -> Self {
        Self {
            processes: Vec::new(),
        }
    }
}
```

### 核心方法实现

#### 1. 进程列表更新

```rust
pub(crate) fn set_processes(&mut self, processes: Vec<String>) -> bool {
    if self.processes == processes {
        return false;  // 无变化，避免不必要的重绘
    }
    self.processes = processes;
    true  // 通知调用者需要重绘
}
```

**设计要点**：
- 使用相等性检查避免不必要的 UI 更新
- 返回布尔值让调用者决定是否请求重绘
- 符合 TUI 的响应式更新模式

#### 2. 摘要文本生成

```rust
pub(crate) fn summary_text(&self) -> Option<String> {
    if self.processes.is_empty() {
        return None;  // 无进程时不显示任何内容
    }

    let count = self.processes.len();
    let plural = if count == 1 { "" } else { "s" };  // 复数形式处理
    Some(format!(
        "{count} background terminal{plural} running · /ps to view · /stop to close"
    ))
}
```

**设计要点**：
- 返回 `Option<String>` 明确区分"无内容"和"空内容"
- 使用 `·`（中间点）作为分隔符，视觉上清晰
- 硬编码的命令提示（`/ps`、`/stop`）与 CLI 命令系统保持一致

#### 3. 渲染行生成

```rust
fn render_lines(&self, width: u16) -> Vec<Line<'static>> {
    if width < 4 {
        return Vec::new();  // 宽度不足时不渲染
    }
    let Some(summary) = self.summary_text() else {
        return Vec::new();  // 无进程时不渲染
    };
    let message = format!("  {summary}"");  // 添加左缩进
    let (truncated, _, _) = take_prefix_by_width(&message, width as usize);
    vec![Line::from(truncated.dim())]  // 使用暗淡样式
}
```

**设计要点**：
- 最小宽度检查（4 列）避免极端情况下的渲染问题
- 统一添加 2 空格缩进，与底部面板其他内容对齐
- 使用 `.dim()` 样式降低视觉优先级，避免干扰主要内容

#### 4. Renderable  trait 实现

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
- 空区域快速返回，避免不必要的渲染工作
- 使用 `Paragraph` 包装行列表，利用 ratatui 的布局能力
- `desired_height` 动态计算，支持可变高度布局

### 依赖工具函数

#### `take_prefix_by_width`

来自 `codex-rs/tui_app_server/src/live_wrap.rs`：

```rust
/// 提取文本前缀，确保显示宽度不超过 max_cols
pub fn take_prefix_by_width(text: &str, max_cols: usize) -> (String, &str, usize) {
    // 基于 UnicodeWidthChar 的宽度计算
    // 返回：(前缀, 剩余后缀, 前缀宽度)
}
```

该函数确保截断发生在字符边界，且考虑字符的显示宽度（而非字节长度）。

## 关键代码路径与文件引用

### 核心实现
- **主文件**：`codex-rs/tui_app_server/src/bottom_pane/unified_exec_footer.rs`（117 行）
- **模块声明**：`codex-rs/tui_app_server/src/bottom_pane/mod.rs`（第 22、110、178、181 行）

### 调用方

**`BottomPane`**：`codex-rs/tui_app_server/src/bottom_pane/mod.rs`

```rust
pub(crate) struct BottomPane {
    // ...
    unified_exec_footer: UnifiedExecFooter,  // 第 181 行
    // ...
}

impl BottomPane {
    pub fn new(params: BottomPaneParams) -> Self {
        Self {
            // ...
            unified_exec_footer: UnifiedExecFooter::new(),  // 第 232 行
            // ...
        }
    }
    
    /// 更新 unified-exec 进程集并刷新摘要显示
    pub(crate) fn set_unified_exec_processes(&mut self, processes: Vec<String>) {
        if self.unified_exec_footer.set_processes(processes) {
            self.sync_status_inline_message();  // 同步到状态行
            self.request_redraw();
        }
    }
    
    /// 将 unified-exec 摘要文本复制到活动状态行
    fn sync_status_inline_message(&mut self) {
        if let Some(status) = self.status.as_mut() {
            status.update_inline_message(self.unified_exec_footer.summary_text());
        }
    }
}
```

### 依赖模块

1. **`live_wrap`**：`codex-rs/tui_app_server/src/live_wrap.rs`
   - 提供 `take_prefix_by_width` 函数
   - 处理 Unicode 宽字符的截断

2. **`renderable`**：`codex-rs/tui_app_server/src/render/renderable.rs`
   - 定义 `Renderable` trait
   - 提供统一的渲染接口

### 外部依赖

```rust
use ratatui::buffer::Buffer;
use ratatui::layout::Rect;
use ratatui::style::Stylize;  // 提供 .dim() 方法
use ratatui::text::Line;
use ratatui::widgets::Paragraph;
```

## 依赖与外部交互

### 与 BottomPane 的交互

```rust
// BottomPane 拥有 UnifiedExecFooter 实例
// 通过 set_unified_exec_processes 接收外部更新
// 通过 sync_status_inline_message 同步到 StatusIndicatorWidget
```

交互流程：
1. 外部系统（如 AppServer）检测后台进程变化
2. 通过事件机制通知 `BottomPane`
3. `BottomPane::set_unified_exec_processes` 更新 `UnifiedExecFooter`
4. 如果进程列表变化，`sync_status_inline_message` 更新状态行
5. `request_redraw()` 触发 UI 重绘

### 与 StatusIndicatorWidget 的交互

```rust
// UnifiedExecFooter 本身不直接依赖 StatusIndicatorWidget
// 而是通过 summary_text() 提供文本，由 BottomPane 中转
```

这种设计：
- 保持 `UnifiedExecFooter` 的单一职责
- 允许状态行决定如何显示（内联 vs 独立）
- 支持状态行不存在时的降级（独立页脚模式）

### 渲染集成

实现 `Renderable` trait，与 TUI 渲染系统集成：

```rust
pub trait Renderable {
    fn render(&self, area: Rect, buf: &mut Buffer);
    fn desired_height(&self, width: u16) -> u16;
    fn cursor_pos(&self, _area: Rect) -> Option<(u16, u16)> { None }
}
```

## 风险、边界与改进建议

### 已知风险

1. **硬编码命令提示**
   - 风险：`/ps` 和 `/stop` 命令在代码中硬编码，如果 CLI 命令变更可能导致不一致
   - 缓解：这些命令是核心交互，变更概率低；文档化依赖关系
   - 改进：考虑从配置或命令注册表动态获取

2. **宽度计算精度**
   - 风险：`take_prefix_by_width` 依赖 `unicode_width` 库，某些特殊字符的宽度可能计算不准确
   - 缓解：使用标准库，社区广泛测试
   - 边界：极窄宽度（<4）时直接跳过渲染

3. **状态同步延迟**
   - 风险：进程状态更新和 UI 显示之间存在异步延迟
   - 缓解：TUI 的 60fps 渲染循环确保延迟在可接受范围

### 边界情况

1. **空进程列表**
   - `summary_text()` 返回 `None`
   - `render_lines()` 返回空向量
   - `desired_height()` 返回 0
   - 行为：组件在 UI 中完全隐藏

2. **极长进程标识**
   - 单个进程命令可能很长（如复杂 shell 命令）
   - 当前实现只显示数量，不显示具体命令
   - 风险：低（摘要设计 intentionally 简洁）

3. **大量后台进程**
   - 测试覆盖：123 个进程的渲染测试（`render_many_sessions`）
   - 行为：只显示数量，性能与进程数无关

4. **宽度截断**
   - 当终端宽度不足以显示完整摘要时，文本被截断
   - 示例：`"3 background terminals running · /ps to view · /stop"`（截断）
   - 改进建议：考虑在极窄宽度下显示简化版本（如 `"3 terms · /ps · /stop"`）

### 改进建议

1. **可配置性**
   - 当前命令提示（`/ps`、`/stop`）是硬编码的
   - 建议：允许通过配置或参数注入自定义提示
   - 使用场景：不同部署环境可能有不同的命令前缀

2. **国际化（i18n）**
   - 当前文本是硬编码的英文
   - 建议：使用本地化框架支持多语言
   - 注意：复数形式处理（`terminal` vs `terminals`）在不同语言中规则不同

3. ** richer 信息展示**
   - 当前只显示数量
   - 可选增强：
     - 显示最近启动的进程名称
     - 显示运行时间
     - 显示进程状态（运行中、已暂停等）

4. **交互增强**
   - 当前只是静态显示
   - 可选增强：
     - 支持鼠标点击 `/ps` 或 `/stop` 直接执行
     - 悬停显示进程详情 tooltip

5. **测试覆盖**

当前测试（第 84-117 行）：
```rust
#[cfg(test)]
mod tests {
    use super::*;
    use insta::assert_snapshot;
    use pretty_assertions::assert_eq;

    #[test]
    fn desired_height_empty() { /* ... */ }
    
    #[test]
    fn render_more_sessions() { /* 使用 insta 快照测试 */ }
    
    #[test]
    fn render_many_sessions() { /* 123 个进程场景 */ }
}
```

**建议添加**：
- 边界宽度测试（恰好容纳、刚好不足）
- Unicode 字符宽度测试
- 快速连续更新测试（确保无竞态条件）

### 代码质量

1. **文档完整性**
   - 文件头文档清晰说明了组件目的
   - 每个公共方法都有文档注释
   - 建议：`render_lines` 可以添加关于缩进（2 空格）的注释

2. **错误处理**
   - 使用 `Option` 明确表达"无内容"状态
   - 宽度检查避免极端情况下的 panic
   - 建议：考虑在宽度 < 4 时记录警告日志（debug 模式）

3. **性能特征**
   - `set_processes` 使用相等性检查避免不必要更新
   - `render_lines` 每次调用重新分配字符串
   - 优化建议：考虑使用小型字符串优化（SSO）或字符串池

### 架构关系

```
┌─────────────────────────────────────────────────────────────┐
│                        BottomPane                           │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                 StatusIndicatorWidget                │   │
│  │  ┌───────────────────────────────────────────────┐  │   │
│  │  │  Inline Message (from UnifiedExecFooter)      │  │   │
│  │  └───────────────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                 UnifiedExecFooter                    │   │
│  │  (独立页脚行，当无状态行时显示)                       │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

这种双层设计确保：
- 有状态行时：摘要以内联方式显示，节省垂直空间
- 无状态行时：作为独立页脚显示，保持可见性
