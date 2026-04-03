# Footer Collapse Plan Queue Full - Research Document

## 场景与职责

该快照展示了 TUI（Terminal User Interface）底部状态栏（footer）在**任务运行中**且处于**Plan 模式**时的完整显示状态。这是 Codex TUI 中聊天编辑器（ChatComposer）组件的 footer 自适应折叠（collapse）机制的一部分。

**场景条件：**
- 终端宽度：120 列（较宽）
- 输入框有内容（"Test"）
- 任务正在运行（`is_task_running = true`）
- 协作模式开启且处于 Plan 模式（`CollaborationModeIndicator::Plan`）
- 上下文窗口使用率：98%

## 功能点目的

该功能用于在底部状态栏显示**队列提示（queue hint）**和**协作模式指示器**，帮助用户了解：

1. **队列操作提示**：当任务运行时，用户可以按 `Tab` 键将当前输入的消息排队，等待当前任务完成后再发送
2. **当前协作模式**：显示当前处于 Plan 模式（洋红色显示）
3. **上下文窗口状态**：右侧显示剩余上下文百分比（98% context left）

**显示内容：**
```
  tab to queue message · Plan mode                                                                    98% context left
```

## 具体技术实现

### 核心数据结构

**`SummaryHintKind`**（定义在 `footer.rs` 第 257-263 行）：
```rust
enum SummaryHintKind {
    None,
    Shortcuts,
    QueueMessage,  // "tab to queue message"
    QueueShort,    // "tab to queue"（缩短版）
}
```

**`LeftSideState`**（第 265-269 行）：
```rust
struct LeftSideState {
    hint: SummaryHintKind,
    show_cycle_hint: bool,
}
```

### 布局计算逻辑

**`single_line_footer_layout`** 函数（第 308-472 行）负责计算 footer 布局：

1. **初始状态确定**：当 `show_queue_hint = true` 时，使用 `SummaryHintKind::QueueMessage`
2. **宽度检查**：检查默认行（包含完整 queue hint + mode）是否能与右侧上下文一起显示
3. **回退策略（Pass 1）**：尝试保持右侧上下文，依次尝试：
   - 完整 queue hint + mode + context
   - 无 cycle hint 的 queue hint + mode + context
   - 缩短版 queue hint + mode + context
4. **回退策略（Pass 2）**：如果 context 无法容纳，则丢弃 context，只显示左侧内容

### 渲染流程

**`left_side_line`** 函数（第 271-300 行）构建左侧行内容：
```rust
fn left_side_line(
    collaboration_mode_indicator: Option<CollaborationModeIndicator>,
    state: LeftSideState,
) -> Line<'static> {
    // 1. 添加 hint（如 "tab to queue message"）
    // 2. 添加分隔符 " · "
    // 3. 添加模式指示器（如 "Plan mode"）
}
```

**`CollaborationModeIndicator::styled_span`**（第 117-124 行）提供颜色：
- Plan 模式：洋红色（`.magenta()`）
- Pair Programming 模式：青色（`.cyan()`）
- Execute 模式：暗淡（`.dim()`）

## 关键代码路径与文件引用

### 主要文件

| 文件 | 职责 |
|------|------|
| `codex-rs/tui/src/bottom_pane/footer.rs` | Footer 渲染逻辑、布局计算、折叠策略 |
| `codex-rs/tui/src/bottom_pane/chat_composer.rs` | ChatComposer 状态管理、footer 属性构建 |

### 关键函数

| 函数 | 位置 | 职责 |
|------|------|------|
| `single_line_footer_layout` | footer.rs:308-472 | 核心布局计算，决定显示哪些内容 |
| `left_side_line` | footer.rs:271-300 | 构建左侧行内容（hint + mode） |
| `left_fits` | footer.rs:252-255 | 检查内容是否适合区域宽度 |
| `can_show_left_with_context` | footer.rs:518-527 | 检查左侧内容和右侧上下文是否能同时显示 |
| `render_context_right` | footer.rs:529-554 | 渲染右侧上下文信息 |
| `CollaborationModeIndicator::styled_span` | footer.rs:117-124 | 模式指示器样式 |
| `CollaborationModeIndicator::label` | footer.rs:102-115 | 模式标签生成（含 cycle hint） |

### 测试代码

**测试函数**：`footer_collapse_snapshots`（chat_composer.rs:4749-4921）

**测试设置**：
```rust
snapshot_composer_state_with_width(
    "footer_collapse_plan_queue_full",
    120,  // 宽度 120 列
    true,
    |composer| {
        setup_collab_footer(composer, 98, Some(CollaborationModeIndicator::Plan));
        composer.set_task_running(true);
        composer.set_text_content("Test".to_string(), Vec::new(), Vec::new());
    },
);
```

## 依赖与外部交互

### 依赖模块

- **`crate::key_hint`**：键盘快捷键提示渲染
- **`crate::ui_consts::FOOTER_INDENT_COLS`**：Footer 缩进常量（2 列）
- **`ratatui`**：TUI 渲染库（`Line`, `Span`, `Rect`, `Buffer` 等）

### 外部状态输入

**`FooterProps`**（footer.rs:65-87）：
- `mode: FooterMode` - 当前 footer 模式
- `is_task_running: bool` - 任务是否运行中（决定是否显示 queue hint）
- `collaboration_modes_enabled: bool` - 协作模式是否启用
- `context_window_percent: Option<i64>` - 上下文窗口百分比

**`ChatComposer` 状态**：
- `footer_mode: FooterMode` - 当前 footer 模式
- `is_task_running: bool` - 任务运行状态
- `collaboration_mode_indicator: Option<CollaborationModeIndicator>` - 协作模式指示器
- `context_window_percent: Option<i64>` - 上下文窗口使用率

## 风险、边界与改进建议

### 边界情况

1. **终端宽度变化**：
   - 120 列宽度足够显示完整内容
   - 当宽度小于约 50 列时，会触发缩短版 hint（"tab to queue"）
   - 当宽度小于约 30 列时，可能只显示 mode 或完全隐藏左侧内容

2. **模式指示器优先级**：
   - Queue hint 优先级高于 mode cycle hint
   - 当空间不足时，优先保留 queue hint，丢弃 mode cycle hint

3. **Context 显示**：
   - 右侧 context（98% context left）在宽度不足时会被隐藏
   - 但 queue hint 会尽可能保留，因为它对用户操作更重要

### 潜在风险

1. **硬编码宽度阈值**：
   - 布局回退逻辑依赖硬编码的宽度检查
   - 如果修改了 hint 文本长度，需要同步调整测试用例的宽度参数

2. **国际化问题**：
   - hint 文本是硬编码的英文
   - 未来国际化时需要考虑文本长度变化对布局的影响

3. **颜色可访问性**：
   - Plan 模式使用洋红色，在某些终端主题下可能不够明显

### 改进建议

1. **动态宽度计算**：
   ```rust
   // 建议：基于实际文本长度计算阈值，而非硬编码
   let queue_hint_width = measure_text("tab to queue message");
   let mode_width = measure_text("Plan mode");
   ```

2. **配置化 hint 文本**：
   - 支持通过配置或本地化文件自定义 hint 文本
   - 在计算布局时动态测量文本宽度

3. **增强可访问性**：
   - 为模式指示器添加图标或前缀，不仅依赖颜色区分
   - 考虑支持高对比度模式

4. **测试覆盖**：
   - 添加更多边界宽度测试（如刚好能显示/不能显示的临界值）
   - 测试不同协作模式（Pair Programming、Execute）的显示效果

5. **文档完善**：
   - 在 `single_line_footer_layout` 函数中添加更多注释，解释回退策略的具体数值依据
