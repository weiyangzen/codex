# 研究文档：session_info_availability_nux_tooltip_snapshot

## 场景与职责

该快照测试验证会话信息单元格（`SessionInfoCell`）在显示模型可用性提示（NUX tooltip）时的渲染行为。当用户使用的模型刚刚变得可用时（例如从等待列表中激活），系统会显示一个友好的提示信息。

**核心职责**：
- 渲染会话头部信息（模型、目录、版本等）
- 在适当的时候显示工具提示（tooltips）
- 处理首次会话和非首次会话的不同显示逻辑
- 提供新用户体验（NUX）引导

## 功能点目的

**从快照内容分析**：
```
╭─────────────────────────────────────╮
│ >_ OpenAI Codex (v0.0.0)            │
│                                     │
│ model:     gpt-5   /model to change │
│ directory: /tmp/project             │
╰─────────────────────────────────────╯

  Tip: Model just became available
```

**功能特性**：
1. **会话头部卡片**：带边框的信息卡片，包含：
   - 标题：`>_ OpenAI Codex (vX.X.X)`
   - 模型信息：`model: gpt-5 /model to change`
   - 工作目录：`directory: /tmp/project`
2. **工具提示**：`Tip: Model just became available`
3. **视觉层次**：使用边框、缩进和颜色区分不同信息层级

## 具体技术实现

### 数据结构

**SessionInfoCell**（`codex-rs/tui/src/history_cell.rs` 第 1105-1119 行）：
```rust
#[derive(Debug)]
pub struct SessionInfoCell(CompositeHistoryCell);

impl HistoryCell for SessionInfoCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        self.0.display_lines(width)
    }
    // ...
}
```

**SessionHeaderHistoryCell**（第 1221-1234 行）：
```rust
pub(crate) struct SessionHeaderHistoryCell {
    version: &'static str,
    model: String,
    model_style: Style,
    reasoning_effort: Option<ReasoningEffortConfig>,
    show_fast_status: bool,
    directory: PathBuf,
}
```

### 创建流程

**`new_session_info` 函数**（第 1127-1204 行）：
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
    // 1. 创建头部单元格
    let header = SessionHeaderHistoryCell::new(
        model.clone(),
        reasoning_effort,
        show_fast_status,
        config.cwd.clone(),
        CODEX_CLI_VERSION,
    );
    let mut parts: Vec<Box<dyn HistoryCell>> = vec![Box::new(header)];

    // 2. 根据是否是首次事件决定显示内容
    if is_first_event {
        // 显示帮助信息（命令列表）
        parts.push(Box::new(PlainHistoryCell { lines: help_lines }));
    } else {
        // 显示工具提示（如果启用）
        if config.show_toollets {
            if let Some(tooltips) = tooltip_override
                .or_else(|| tooltips::get_tooltip(auth_plan, is_fast_tier))
                .map(|tip| TooltipHistoryCell::new(tip, &config.cwd))
            {
                parts.push(Box::new(tooltips));
            }
        }
        // 如果请求的模型与实际使用的不同，显示变更提示
        if requested_model != model {
            // ...
        }
    }

    SessionInfoCell(CompositeHistoryCell { parts })
}
```

### 头部渲染

**`SessionHeaderHistoryCell::display_lines`**（第 1305-1367 行）：
```rust
fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
    let Some(inner_width) = card_inner_width(width, SESSION_HEADER_MAX_INNER_WIDTH) else {
        return Vec::new();
    };

    // 构建标题行
    let title_spans: Vec<Span<'static>> = vec![
        Span::from(">_ ").dim(),
        Span::from("OpenAI Codex").bold(),
        Span::from(" ").dim(),
        Span::from(format!("(v{})", self.version)).dim(),
    ];

    // 构建模型行
    let model_spans: Vec<Span<'static>> = {
        let mut spans = vec![
            Span::from(format!("{model_label} ")).dim(),
            Span::styled(self.model.clone(), self.model_style),
        ];
        if let Some(reasoning) = reasoning_label {
            spans.push(Span::from(" "));
            spans.push(Span::from(reasoning));
        }
        if self.show_fast_status {
            spans.push("   ".into());
            spans.push(Span::styled("fast", self.model_style.magenta()));
        }
        spans.push("   ".dim());
        spans.push(CHANGE_MODEL_HINT_COMMAND.cyan());
        spans.push(CHANGE_MODEL_HINT_EXPLANATION.dim());
        spans
    };

    // 构建目录行
    let dir_spans = vec![
        Span::from(dir_prefix).dim(),
        Span::from(dir),
    ];

    // 使用边框包装
    with_border(lines)
}
```

### 工具提示渲染

**`TooltipHistoryCell`**（第 1070-1102 行）：
```rust
#[derive(Debug)]
struct TooltipHistoryCell {
    tip: String,
    cwd: PathBuf,
}

impl HistoryCell for TooltipHistoryCell {
    fn display_lines(&self, width: u16) -> Vec<Line<'static>> {
        let indent = "  ";
        let wrap_width = usize::from(width.max(1))
            .saturating_sub(indent_width)
            .max(1);
        
        // 使用 Markdown 渲染
        append_markdown(
            &format!("**Tip:** {}", self.tip),
            Some(wrap_width),
            Some(self.cwd.as_path()),
            &mut lines,
        );

        prefix_lines(lines, indent.into(), indent.into())
    }
}
```

### 边框渲染

**`with_border` 函数**（第 1005-1061 行）：
```rust
fn with_border_internal(
    lines: Vec<Line<'static>>,
    forced_inner_width: Option<usize>,
) -> Vec<Line<'static>> {
    // 计算最大行宽
    let max_line_width = lines.iter().map(|line| {
        line.iter()
            .map(|span| UnicodeWidthStr::width(span.content.as_ref()))
            .sum::<usize>()
    }).max().unwrap_or(0);

    // 构建边框
    let mut out = Vec::with_capacity(lines.len() + 2);
    let border_inner_width = content_width + 2;
    out.push(vec![format!("╭{}╮", "─".repeat(border_inner_width)).dim()].into());

    for line in lines {
        // 添加左右边框和填充
        let mut spans: Vec<Span<'static>> = Vec::with_capacity(span_count + 4);
        spans.push(Span::from("│ ").dim());
        spans.extend(line.into_iter());
        if used_width < content_width {
            spans.push(Span::from(" ".repeat(content_width - used_width)).dim());
        }
        spans.push(Span::from(" │").dim());
        out.push(Line::from(spans));
    }

    out.push(vec![format!("╰{}╯", "─".repeat(border_inner_width)).dim()].into());
    out
}
```

## 关键代码路径与文件引用

### 主要文件

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui/src/history_cell.rs` | `SessionInfoCell`、`SessionHeaderHistoryCell`、`TooltipHistoryCell` 实现 |
| `codex-rs/tui/src/tooltips.rs` | 工具提示生成逻辑 |
| `codex-rs/tui/src/markdown.rs` | Markdown 渲染支持 |

### 测试代码

**位置**：`codex-rs/tui/src/history_cell.rs` 第 2751-2767 行

```rust
#[tokio::test]
async fn session_info_availability_nux_tooltip_snapshot() {
    let mut config = test_config().await;
    config.cwd = PathBuf::from("/tmp/project");
    let cell = new_session_info(
        &config,
        "gpt-5",
        session_configured_event("gpt-5"),
        false,  // 非首次事件
        Some("Model just became available".to_string()),  // 覆盖提示
        Some(PlanType::Free),
        false,
    );

    let rendered = render_transcript(&cell).join("\n");
    insta::assert_snapshot!(rendered);
}
```

### 关键常量

```rust
pub(crate) const SESSION_HEADER_MAX_INNER_WIDTH: usize = 56;
const CHANGE_MODEL_HINT_COMMAND: &str = "/model";
const CHANGE_MODEL_HINT_EXPLANATION: &str = " to change";
const DIR_LABEL: &str = "directory:";
```

## 依赖与外部交互

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `ratatui` | 终端 UI 渲染 |
| `unicode_width` | Unicode 宽度计算 |
| `codex_protocol` | 协议类型（`SessionConfiguredEvent`、`PlanType` 等） |

### 内部依赖

- `crate::tooltips::get_tooltip`：根据用户计划和层级获取合适的提示
- `crate::markdown::append_markdown`：Markdown 文本渲染
- `crate::version::CODEX_CLI_VERSION`：版本信息
- `crate::text_formatting::center_truncate_path`：路径截断显示

### 调用链

```
new_session_info(config, requested_model, event, is_first_event, tooltip_override, ...)
├── SessionHeaderHistoryCell::new(model, reasoning_effort, show_fast_status, directory, version)
│   └── SessionHeaderHistoryCell::display_lines(width)
│       └── with_border(lines)
├── TooltipHistoryCell::new(tip, cwd)  [可选]
│   └── TooltipHistoryCell::display_lines(width)
│       └── append_markdown(...)
└── CompositeHistoryCell::new(parts)
```

## 风险、边界与改进建议

### 潜在风险

1. **宽度计算**：
   - `SESSION_HEADER_MAX_INNER_WIDTH = 56` 是硬编码的
   - 在极窄终端上可能显示不完整

2. **首次事件检测**：
   - 依赖 `is_first_event` 参数，如果调用者传递错误值，显示逻辑会出错

3. **工具提示覆盖**：
   - `tooltip_override` 直接覆盖其他提示，可能导致重要信息丢失

### 边界情况

| 场景 | 当前行为 | 评估 |
|-----|---------|------|
| 宽度 < 4 | 返回空向量 | ✅ 防御性处理 |
| 首次会话 | 显示帮助命令列表 | ✅ 良好的 NUX |
| 工具提示禁用 | 不显示任何提示 | ✅ 尊重用户偏好 |
| 模型变更 | 显示 "model changed:" 提示 | ✅ 信息透明 |
| 长路径 | 使用 `center_truncate_path` 截断 | ⚠️ 可能丢失信息 |

### 改进建议

1. **响应式宽度**：
   ```rust
   fn calculate_max_inner_width(terminal_width: u16) -> usize {
       (terminal_width.saturating_sub(10) as usize).min(56)
   }
   ```

2. **提示优先级队列**：
   ```rust
   enum TooltipPriority {
       Critical,   // 模型变更
       High,       // 可用性提示
       Normal,     // 一般提示
   }
   // 允许多个提示同时显示，按优先级排序
   ```

3. **可配置的提示**：
   ```rust
   pub struct TooltipConfig {
       pub show_availability_tips: bool,
       pub show_feature_tips: bool,
       pub max_tips_per_session: usize,
   }
   ```

4. **国际化支持**：
   ```rust
   // 使用本地化字符串
   t!("session.model_changed", requested = requested_model, actual = model)
   ```

5. **改进路径显示**：
   ```rust
   // 提供悬停提示显示完整路径
   // 支持点击复制路径
   ```

6. **版本检查**：
   ```rust
   // 如果版本较旧，提示更新
   if is_outdated(version) {
       parts.push(Box::new(UpdateAvailableHistoryCell::new(...)));
   }
   ```
