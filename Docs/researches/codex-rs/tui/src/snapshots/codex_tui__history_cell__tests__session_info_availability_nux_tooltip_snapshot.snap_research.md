# Research Document: Session Info Availability NUX Tooltip Snapshot

## 场景与职责

此快照测试验证 **SessionInfoCell** 组件在会话开始时的信息展示功能，特别是当模型可用性发生变化时显示的提示工具（Tooltip）。这是用户首次启动 Codex TUI 或模型状态变更时的关键用户体验场景。

该组件负责：
- 展示会话头部信息（版本、模型、工作目录）
- 提供快速入门指引（首次使用时）
- 显示动态提示信息（如模型可用性变更）
- 以卡片形式组织信息，保持界面整洁

## 功能点目的

**主要功能**：验证会话信息卡片在以下场景下的渲染效果：

1. **会话头部卡片**：带边框的信息卡片展示版本、模型、工作目录
2. **模型可用性提示**：当模型从不可用变为可用时显示提示 `"Tip: Model just became available"`
3. **视觉层次**：使用边框、缩进和颜色区分不同信息层级
4. **命令提示**：显示 `/model` 命令提示用户可以切换模型

**预期输出结构**：
```
╭─────────────────────────────────────╮
│ >_ OpenAI Codex (v0.0.0)            │
│                                     │
│ model:     gpt-5   /model to change │
│ directory: /tmp/project             │
╰─────────────────────────────────────╯

  Tip: Model just became available
```

## 具体技术实现

### 核心数据结构

**SessionInfoCell**（位于 `history_cell.rs`）：
```rust
#[derive(Debug)]
pub struct SessionInfoCell(CompositeHistoryCell);

pub(crate) struct CompositeHistoryCell {
    parts: Vec<Box<dyn HistoryCell>>,
}
```

**SessionHeaderHistoryCell**：
```rust
#[derive(Debug)]
pub(crate) struct SessionHeaderHistoryCell {
    version: &'static str,
    model: String,
    model_style: Style,
    reasoning_effort: Option<ReasoningEffortConfig>,
    show_fast_status: bool,
    directory: PathBuf,
}
```

**TooltipHistoryCell**：
```rust
#[derive(Debug)]
struct TooltipHistoryCell {
    tip: String,
    cwd: PathBuf,
}
```

### 关键渲染流程

1. **会话信息创建**（`new_session_info` 函数，第 1121-1204 行）：
```rust
pub(crate) fn new_session_info(
    config: &Config,
    requested_model: &str,
    event: SessionConfiguredEvent,
    is_first_event: bool,
    tooltip_override: Option<String>,
    auth_plan: Option<PlanType>,
    show_fast_status: bool,
) -> SessionInfoCell {
    // 1. 创建头部卡片
    let header = SessionHeaderHistoryCell::new(...);
    let mut parts: Vec<Box<dyn HistoryCell>> = vec![Box::new(header)];
    
    // 2. 首次事件显示帮助信息
    if is_first_event {
        parts.push(Box::new(PlainHistoryCell { lines: help_lines }));
    } else {
        // 3. 非首次事件显示提示
        if config.show_tooltips && let Some(tooltips) = tooltip_override {
            parts.push(Box::new(TooltipHistoryCell::new(tip, &config.cwd)));
        }
    }
    
    SessionInfoCell(CompositeHistoryCell { parts })
}
```

2. **头部卡片渲染**（`SessionHeaderHistoryCell::display_lines`）：
   - 使用 `with_border` 函数添加边框
   - 格式化目录路径（使用 `relativize_to_home` 将绝对路径转为 `~` 形式）
   - 显示模型名称和推理级别（reasoning effort）

3. **边框渲染**（`with_border_internal` 函数）：
```rust
fn with_border_internal(
    lines: Vec<Line<'static>>,
    forced_inner_width: Option<usize>,
) -> Vec<Line<'static>> {
    // ╭─────────────────────────────────────╮
    // │ >_ OpenAI Codex (v0.0.0)            │
    // ╰─────────────────────────────────────╯
}
```

4. **提示渲染**（`TooltipHistoryCell::display_lines`）：
   - 使用 `append_markdown` 解析 Markdown 格式
   - 应用缩进 `"  "`
   - 格式：`"**Tip:** {tip}`

### 样式应用

- 标题：`">_ ".dim()` + `"OpenAI Codex".bold()` + `"(v{version})".dim()`
- 标签：`"model:".dim()`、`"directory:".dim()`
- 模型名：可配置样式（`model_style`）
- 命令提示：`"/model".cyan()`
- 提示文本：`"Tip:".bold()` + 提示内容

## 关键代码路径与文件引用

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/history_cell.rs` | SessionInfoCell、SessionHeaderHistoryCell、TooltipHistoryCell 实现 |
| `codex-rs/tui/src/tooltips.rs` | 提示内容生成逻辑 |
| `codex-rs/tui/src/exec_command.rs` | `relativize_to_home` 路径处理 |
| `codex-rs/tui/src/markdown.rs` | `append_markdown` Markdown 渲染 |

### 测试代码位置

```rust
// history_cell.rs 第 2752-2767 行
#[tokio::test]
async fn session_info_availability_nux_tooltip_snapshot() {
    let mut config = test_config().await;
    config.cwd = PathBuf::from("/tmp/project");
    let cell = new_session_info(
        &config,
        "gpt-5",
        session_configured_event("gpt-5"),
        false,  // is_first_event = false，显示 tooltip
        Some("Model just became available".to_string()),  // tooltip_override
        Some(PlanType::Free),
        false,
    );
    let rendered = render_transcript(&cell).join("\n");
    insta::assert_snapshot!(rendered);
}
```

## 依赖与外部交互

### 内部依赖

- **ratatui**: 边框绘制、文本样式
- **unicode-width**: 宽度计算
- **dirs**: 获取用户主目录（用于路径简化）

### 外部协议依赖

- **codex-protocol**: `SessionConfiguredEvent`、`PlanType`
- **codex-core**: `Config`、`ReasoningEffortConfig`

### 配置依赖

```rust
pub struct Config {
    pub show_tooltips: bool,      // 控制是否显示提示
    pub cwd: PathBuf,             // 当前工作目录
    pub service_tier: Option<ServiceTier>,
    // ...
}
```

## 风险、边界与改进建议

### 已知风险

1. **路径长度**：超长路径可能导致卡片宽度超出屏幕
2. **版本号长度**：版本号过长可能破坏布局
3. **提示文本长度**：长提示文本可能换行不美观

### 边界情况

| 场景 | 当前行为 |
|------|---------|
| 屏幕宽度 < 40 | 卡片内容可能被截断 |
| 路径无法 relativize | 显示完整绝对路径 |
| tooltip_override 为 None | 尝试从 `tooltips::get_tooltip` 获取 |
| show_tooltips = false | 不显示任何提示 |

### 改进建议

1. **响应式布局**：
   - 根据终端宽度动态调整卡片内边距
   - 超长路径使用中间截断（`center_truncate_path`）

2. **国际化支持**：
   - 提示文本支持多语言
   - 日期时间格式本地化

3. **可访问性**：
   - 为边框卡片提供屏幕阅读器标签
   - 增加键盘导航支持

4. **功能扩展**：
   - 支持自定义提示内容（用户配置）
   - 提示信息可点击跳转相关文档
   - 增加更多上下文相关的智能提示

5. **代码优化**：
   - 将 `SESSION_HEADER_MAX_INNER_WIDTH` 改为可配置
   - 分离视图逻辑和数据模型
