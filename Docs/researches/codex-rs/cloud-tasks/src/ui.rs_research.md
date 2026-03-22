# ui.rs 研究文档

## 场景与职责

`ui.rs` 是 Codex Cloud Tasks TUI 应用的**渲染层核心模块**，负责所有用户界面的绘制。它基于 `ratatui` 库实现，包含：

- **主界面**: 任务列表、页脚状态栏
- **New Task 页面**: 多行输入编辑器
- **Diff 覆盖层**: 代码差异和对话详情展示
- **环境选择弹窗**: 搜索和选择运行环境
- **Best-of-N 弹窗**: 并行尝试次数选择
- **Apply 确认弹窗**: 应用变更前的确认和结果展示

该模块采用声明式渲染风格，所有绘制函数接收 `Frame` 和 `App` 状态，输出到终端缓冲区。

## 功能点目的

### 1. 主绘制入口 `draw()`

```rust
pub fn draw(frame: &mut Frame, app: &mut App)
```

**布局结构**:
```
┌─────────────────────────────┐
│  任务列表 / New Task 页面    │  Min(1)
├─────────────────────────────┤
│  页脚（帮助 + 状态栏）        │  Length(2)
└─────────────────────────────┘
```

**弹窗层级**（按优先级）：
1. Apply 确认弹窗 (`apply_modal`)
2. Diff 详情覆盖层 (`diff_overlay`)
3. 环境选择弹窗 (`env_modal`)
4. Best-of-N 弹窗 (`best_of_modal`)

### 2. 任务列表 `draw_list()`

**文件**: `ui.rs:176-234`

功能特点：
- 显示任务状态（READY/PENDING/APPLIED/ERROR）带颜色
- 显示环境标签和相对时间
- 显示 diff 统计（+adds/-dels • files）
- 选中项高亮（`› ` 前缀 + 粗体）
- 顶部 1 行空白间距
- 加载时显示居中 spinner

**标题栏动态内容**：
```rust
"Cloud Tasks" + suffix_span（当前环境）+ percent_span（滚动百分比）
```

### 3. New Task 页面 `draw_new_task_page()`

**文件**: `ui.rs:104-174`

布局特点：
- 动态计算 composer 高度（最小3行，最大终端高度-6）
- 底部锚定输入框（上方留白）
- 标题栏显示：
  - "New Task" 标签
  - 当前环境标签（或红色警告"Env: none"）
  - 当前尝试次数

### 4. Diff 覆盖层 `draw_diff_overlay()`

**文件**: `ui.rs:312-467`

**双视图支持**：
- **Diff 视图**: 语法高亮的统一差异格式
- **Prompt 视图**: 格式化的对话记录（User/Assistant）

**状态栏信息**（当同时有 diff 和 text 时）：
```
[Prompt]  [Diff]  (← → to switch view)  Attempt 1/3  (Tab/Shift-Tab or [ ] to cycle)
```

**滚动百分比**: 在标题栏显示当前滚动位置（如 "• 45%"）

### 5. 环境选择弹窗 `draw_env_modal()`

**文件**: `ui.rs:893-991`

功能特点：
- 搜索框实时过滤（支持 label/id/repo_hints）
- 首项固定为 "All Environments (Global)"
- 显示 PINNED 徽章
- 高亮当前选中项

### 6. Apply 确认弹窗 `draw_apply_modal()`

**文件**: `ui.rs:469-550`

**三阶段显示**：
1. **加载中**: 显示 "Loading…" spinner
2. **Preflight 中**: 显示 "Checking…" spinner
3. **结果展示**: 
   - 成功: 绿色消息
   - 部分成功: 洋红色消息 + 冲突/跳过列表
   - 失败: 红色消息 + 冲突/跳过列表

### 7. 对话样式渲染 `style_conversation_lines()`

**文件**: `ui.rs:558-652`

**解析逻辑**：
- 检测 `"User:"` / `"Assistant:"` 作为发言者标记
- 添加 gutter 前缀（`│ `）和角色标签
- 代码块检测（```）并应用青色样式
- 列表项检测（`- ` / `* `）并替换为 `•`
- Markdown 标题检测（`###`）并应用洋红色粗体

## 具体技术实现

### 布局系统

使用 `ratatui::Layout` 的约束系统：

```rust
// 主布局
let chunks = Layout::default()
    .direction(Direction::Vertical)
    .constraints([
        Constraint::Min(1),    // 内容区
        Constraint::Length(2), // 页脚
    ])
    .split(area);

// 弹窗居中
let inner = overlay_outer(area);  // 80%x80% 居中
```

### 样式系统

遵循项目 `styles.md` 规范：

```rust
// 使用 Stylize trait 的链式调用
"text".magenta().bold()
"text".dim()
"text".cyan()
url.cyan().underlined()

// 避免硬编码白色，使用默认前景色
```

### Diff 行样式 `style_diff_line()`

**文件**: `ui.rs:753-786`

| 前缀 | 样式 |
|------|------|
| `@@` | 洋红色 + 粗体（diff 头） |
| `+++` / `---` | 暗淡（文件路径） |
| `+` | 绿色（新增） |
| `-` | 红色（删除） |
| 其他 | 默认 |

### Spinner 实现

**文件**: `ui.rs:846-889`

```rust
// 600ms 闪烁周期
let blink_on = (start.elapsed().as_millis() / 600).is_multiple_of(2);
let dot = if blink_on { "• " } else { "◦ " };
```

两种变体：
- `draw_inline_spinner()`: 行内显示（页脚右侧）
- `draw_centered_spinner()`: 居中显示（加载状态）

### 圆角边框配置

```rust
static ROUNDED: OnceLock<bool> = OnceLock::new();

fn rounded_enabled() -> bool {
    *ROUNDED.get_or_init(|| {
        std::env::var("CODEX_TUI_ROUNDED")
            .ok()
            .map(|v| v == "1")
            .unwrap_or(true)  // 默认启用
    })
}
```

## 关键代码路径与文件引用

### 主绘制流程

**文件**: `lib.rs:917-921`
```rust
let render_if_needed = |terminal, app, needs_redraw| -> anyhow::Result<()> {
    if *needs_redraw {
        terminal.draw(|f| ui::draw(f, app))?;
        *needs_redraw = false;
    }
    Ok(())
};
```

### 任务项渲染

**文件**: `ui.rs:788-844`
```rust
fn render_task_item(_app: &App, t: &TaskSummary) -> ListItem<'static> {
    // 构建四行内容：
    // 1. [STATUS] Title
    // 2. environment_label  •  relative_time
    // 3. +adds/-dels  •  N files
    // 4. （空行分隔）
}
```

### 页脚帮助文本

**文件**: `ui.rs:236-310`
```rust
fn draw_footer(frame: &mut Frame, area: Rect, app: &mut App) {
    // 动态构建帮助项（根据当前状态显示不同快捷键）
    // 右上角显示 loading spinner
    // 底部显示状态文本（截断至2000字符）
}
```

### 尝试状态样式

**文件**: `ui.rs:742-751`
```rust
fn attempt_status_span(status: AttemptStatus) -> Option<Span<'static>> {
    match status {
        AttemptStatus::Completed => Some("Completed".green()),
        AttemptStatus::Failed => Some("Failed".red().bold()),
        AttemptStatus::InProgress => Some("In progress".magenta()),
        AttemptStatus::Pending => Some("Pending".cyan()),
        AttemptStatus::Cancelled => Some("Cancelled".dim()),
        AttemptStatus::Unknown => None,
    }
}
```

## 依赖与外部交互

### 外部 Crate

| Crate | 用途 |
|-------|------|
| `ratatui` | TUI 渲染框架（Layout, Widgets, Styles） |
| `crossterm` | 终端控制（通过 ratatui backend） |
| `unicode-width` | 字符宽度计算（通过 scrollable_diff） |

### 内部模块依赖

```
ui.rs
├── app.rs
│   ├── App 状态
│   ├── DiffOverlay
│   ├── EnvironmentRow
│   ├── AttemptView
│   └── 各种 ModalState
├── scrollable_diff.rs
│   └── ScrollableDiff (内容换行和滚动)
├── util.rs
│   └── format_relative_time_now()
└── codex_tui
    └── render_markdown_text() (Markdown 渲染)
```

### 从 lib.rs 接收的事件驱动

```rust
// AppEvent 处理触发重绘
app::AppEvent::TasksLoaded { .. } => { needs_redraw = true; }
app::AppEvent::DetailsDiffLoaded { .. } => { needs_redraw = true; }
app::AppEvent::EnvironmentsLoaded { .. } => { needs_redraw = true; }
// ... 所有事件都可能导致 needs_redraw = true
```

## 风险、边界与改进建议

### 当前风险

1. **长状态文本溢出**
   ```rust
   if status_line.len() > 2000 {
       status_line.truncate(2000);
       status_line.push('…');
   }
   ```
   - 硬编码截断，可能截断多字节字符

2. **样式不一致风险**
   - `style_diff_line()` 和 `style_conversation_lines()` 使用不同样式逻辑
   - 新增视图类型时需要同步更新

3. **布局硬编码**
   - 弹窗尺寸使用固定百分比（80%）
   - 小终端上可能显示不佳

### 边界情况

| 场景 | 当前行为 |
|------|----------|
| 终端高度 < 10 | 布局可能重叠，但未崩溃 |
| 任务标题超长 | 自然换行或截断（依赖 ratatui） |
| 空任务列表 | 显示空白列表 + "Loading tasks…" |
| 无环境配置 | 显示 "Env: none (press ctrl-o to choose)".red() |
| 多字节字符 | unicode-width 正确处理 |

### 改进建议

1. **响应式布局**
   ```rust
   // 根据终端尺寸动态调整弹窗比例
   let modal_ratio = if area.width < 80 { 95 } else { 80 };
   ```

2. **搜索高亮**
   ```rust
   // 在 draw_env_modal 中高亮匹配文本
   fn highlight_match(text: &str, query: &str) -> Vec<Span> {
       // 分割文本，匹配部分应用高亮样式
   }
   ```

3. **Diff 语法高亮增强**
   ```rust
   // 识别更多 diff 模式
   if raw.starts_with("@@") { /* 已支持 */ }
   if raw.starts_with("index ") { /* 新增: index 行样式 */ }
   if raw.starts_with("diff --git") { /* 新增: diff 头样式 */ }
   ```

4. **可访问性改进**
   - 支持高对比度模式（环境变量开关）
   - 颜色盲友好的状态指示（不只是颜色，还有符号）

5. **性能优化**
   ```rust
   // 当前: 每次重绘都重新构建所有 ListItem
   // 优化: 缓存任务项渲染结果，仅在有变化时重建
   struct TaskItemCache { hash: u64, item: ListItem<'static> }
   ```

6. **键盘导航增强**
   - 任务列表支持 `/` 搜索
   - Diff 视图支持 `g`/`G` 跳转到行号
   - 支持书签标记和跳转

7. **国际化准备**
   - 当前硬编码英文文本
   - 建议提取到常量或资源文件
   ```rust
   const MSG_ENV_NONE: &str = "Env: none (press ctrl-o to choose)";
   ```
