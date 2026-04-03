# Footer Mode Indicator - Wide 测试研究文档

## 场景与职责

### 测试场景
该快照测试验证在**宽终端宽度（120列）**下，footer 显示完整内容的行为：
- 显示快捷提示 "? for shortcuts"
- 显示协作模式指示器 "Plan mode (shift+tab to cycle)"
- 显示上下文窗口信息 "100% context left"

### 测试数据
- **终端宽度**: 120列（宽屏）
- **模式**: `ComposerEmpty`（编辑器为空）
- **任务运行状态**: 未运行 (`is_task_running: false`)
- **协作模式**: 启用 (`collaboration_modes_enabled: true`)
- **协作模式指示器**: `Plan`
- **上下文窗口**: 未设置（默认显示 "100% context left"）

### 期望行为
在充足的空间下，footer 应该显示所有可用信息，包括快捷提示、模式指示器（含循环提示）和上下文信息。

---

## 功能点目的

### 核心功能
该测试验证 footer 的**完整显示模式**：

1. **完整信息展示**: 在空间充足时显示所有提示和信息
2. **模式发现**: 通过 "(shift+tab to cycle)" 提示帮助用户发现模式切换功能
3. **快捷方式发现**: 通过 "? for shortcuts" 提示帮助用户发现帮助功能
4. **上下文感知**: 显示上下文窗口剩余百分比

### 业务价值
- **功能发现**: 新用户可以通过 footer 提示了解可用功能
- **状态可见**: 用户始终知道当前协作模式和上下文使用情况
- **操作指引**: 清晰的提示帮助用户了解如何与系统交互

### 完整显示内容结构
```
[左侧内容]                          [右侧内容]
  ? for shortcuts · Plan mode (shift+tab to cycle)    100% context left
  └─ 快捷提示 ─┘   └─ 模式指示器（含循环提示）─┘         └─ 上下文信息 ─┘
```

---

## 具体技术实现

### 关键代码路径

#### 1. 测试入口
```rust
// footer.rs:1456-1461
let props = FooterProps {
    mode: FooterMode::ComposerEmpty,
    is_task_running: false,  // 任务未运行，显示完整提示
    collaboration_modes_enabled: true,
    // ...
};

snapshot_footer_with_mode_indicator(
    "footer_mode_indicator_wide",
    120,  // 宽屏
    &props,
    Some(CollaborationModeIndicator::Plan),
);
```

#### 2. 布局决策逻辑
```rust
// footer.rs:310-472
pub(crate) fn single_line_footer_layout(
    area: Rect,
    context_width: u16,
    collaboration_mode_indicator: Option<CollaborationModeIndicator>,
    show_cycle_hint: bool,      // true（任务未运行）
    show_shortcuts_hint: bool,  // true（ComposerEmpty 模式）
    show_queue_hint: bool,      // false（非 ComposerHasDraft 或任务未运行）
) -> (SummaryLeft, bool) {
    let hint_kind = SummaryHintKind::Shortcuts;
    let default_state = LeftSideState {
        hint: hint_kind,
        show_cycle_hint: true,  // 显示循环提示
    };
    let default_line = left_side_line(collaboration_mode_indicator, default_state);
    let default_width = default_line.width() as u16;
    
    // 120列足够容纳所有内容
    if default_width > 0 && can_show_left_with_context(area, default_width, context_width) {
        return (SummaryLeft::Default, true);  // 显示两侧
    }
    // ... 回退逻辑
}
```

#### 3. 空间检查
```rust
// footer.rs:518-527
pub(crate) fn can_show_left_with_context(
    area: Rect, 
    left_width: u16, 
    context_width: u16
) -> bool {
    let Some(context_x) = right_aligned_x(area, context_width) else {
        return true;
    };
    let left_extent = FOOTER_INDENT_COLS as u16 + left_width + FOOTER_CONTEXT_GAP_COLS;
    left_extent <= context_x.saturating_sub(area.x)
}

// 120列的计算：
// - 左侧缩进: 2
// - 左侧内容: "? for shortcuts · Plan mode (shift+tab to cycle)" = 48
// - 间隙: 1
// - 右侧内容: "100% context left" = 17
// - 右侧缩进: 2
// 总计: 2 + 48 + 1 + 17 + 2 = 70 < 120，空间充足
```

#### 4. 内容构建
```rust
// footer.rs:271-300
fn left_side_line(
    collaboration_mode_indicator: Option<CollaborationModeIndicator>,
    state: LeftSideState,
) -> Line<'static> {
    let mut line = Line::from("");
    
    // 快捷提示
    line.push_span(key_hint::plain(KeyCode::Char('?')));
    line.push_span(" for shortcuts".dim());
    
    // 分隔符
    line.push_span(" · ".dim());
    
    // 模式指示器（含循环提示）
    line.push_span(indicator.styled_span(state.show_cycle_hint));
    
    line
}
```

### 渲染流程

```
测试调用 (120列)
    ↓
single_line_footer_layout
    ├─ 计算左侧宽度: 48字符
    ├─ 计算右侧宽度: 17字符
    ├─ can_show_left_with_context(120, 48, 17) = true
    └─ 返回 (SummaryLeft::Default, true)
    ↓
render_footer_from_props (渲染左侧)
render_context_right (渲染右侧)
```

---

## 关键代码路径与文件引用

### 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/bottom_pane/footer.rs:310-472` | `single_line_footer_layout` - 布局决策 |
| `codex-rs/tui/src/bottom_pane/footer.rs:271-300` | `left_side_line` - 左侧内容构建 |
| `codex-rs/tui/src/bottom_pane/footer.rs:481-502` | `right_aligned_x` - 右侧内容对齐计算 |
| `codex-rs/tui/src/bottom_pane/footer.rs:504-516` | `max_left_width_for_right` - 最大左侧宽度计算 |
| `codex-rs/tui/src/bottom_pane/footer.rs:848-860` | `context_window_line` - 上下文行生成 |

### 相关常量
```rust
// footer.rs:98-99
const MODE_CYCLE_HINT: &str = "shift+tab to cycle";
const FOOTER_CONTEXT_GAP_COLS: u16 = 1;

// ui_consts
FOOTER_INDENT_COLS = 2;
```

### 样式定义
```rust
// footer.rs:117-124
fn styled_span(self, show_cycle_hint: bool) -> Span<'static> {
    let label = self.label(show_cycle_hint);
    match self {
        CollaborationModeIndicator::Plan => Span::from(label).magenta(),
        CollaborationModeIndicator::PairProgramming => Span::from(label).cyan(),
        CollaborationModeIndicator::Execute => Span::from(label).dim(),
    }
}
```

---

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|-----|------|
| `crate::key_hint` | 键盘快捷键提示渲染 |
| `crate::render::line_utils::prefix_lines` | 行前缀缩进处理 |
| `ratatui::text::Line` / `ratatui::text::Span` | 文本构建 |
| `ratatui::style::Stylize` | 样式应用（颜色、暗淡） |

### 数据结构
```rust
// footer.rs:257-263
enum SummaryHintKind {
    None,
    Shortcuts,       // 本测试使用
    QueueMessage,    // 队列消息提示
    QueueShort,      // 缩短的队列提示
}

// footer.rs:265-269
struct LeftSideState {
    hint: SummaryHintKind,
    show_cycle_hint: bool,  // 本测试为 true
}
```

### 与 ChatComposer 的集成
```rust
// chat_composer.rs:1074-1097 (draw_footer_frame)
let show_cycle_hint = !props.is_task_running;
let show_shortcuts_hint = match props.mode {
    FooterMode::ComposerEmpty => true,
    FooterMode::ComposerHasDraft => false,
    _ => false,
};
```

---

## 风险边界与改进建议

### 当前风险边界

#### 1. 固定宽度阈值
- **风险**: 120列是硬编码的测试宽度，实际布局逻辑基于动态计算
- **边界**: 如果内容长度变化，120列可能不足以显示所有内容
- **建议**: 测试应验证实际内容宽度与容器宽度的关系，而非固定值

#### 2. 内容长度变化
- **风险**: 如果模式名称或提示文本变化，布局可能失效
- **示例**: 如果 "Plan mode" 改为 "Planning mode"，宽度计算需要更新
- **建议**: 添加内容长度变化的测试用例

#### 3. 国际化影响
- **风险**: 如果提示文本需要国际化翻译，长度可能显著变化
- **示例**: 德语翻译通常比英语长 20-30%
- **建议**: 考虑国际化场景下的布局回退策略

### 改进建议

#### 1. 动态宽度测试
```rust
// 建议：测试基于内容宽度的动态计算
#[test]
fn footer_mode_indicator_content_width_calculation() {
    let content_width = calculate_content_width(&props);
    let min_required_width = content_width.left + FOOTER_CONTEXT_GAP_COLS + content_width.right 
                            + 2 * FOOTER_INDENT_COLS;
    
    // 测试刚好能容纳的宽度
    snapshot_footer_with_mode_indicator("boundary", min_required_width, &props, Some(Plan));
    
    // 测试刚好不能容纳的宽度
    snapshot_footer_with_mode_indicator("boundary_minus_1", min_required_width - 1, &props, Some(Plan));
}
```

#### 2. 内容变化测试
```rust
// 建议：测试不同模式名称的长度
#[test]
fn footer_mode_indicator_different_modes() {
    for mode in [Plan, PairProgramming, Execute] {
        // 验证每种模式的显示
    }
}
```

#### 3. 渐进式回退可视化
```rust
// 建议：添加宽度变化的连续测试
#[test]
fn footer_mode_indicator_width_gradient() {
    for width in (40..=120).step_by(10) {
        // 验证每个宽度下的布局行为
    }
}
```

### 相关测试
该测试是模式指示器测试矩阵的**基准测试**：
- `footer_mode_indicator_wide`: **本测试** - 完整显示
- `footer_mode_indicator_narrow_overlap_hides`: 窄屏 - 隐藏右侧
- `footer_mode_indicator_running_hides_hint`: 任务运行 - 隐藏循环提示

---

## 快照内容分析

```
"  ? for shortcuts · Plan mode (shift+tab to cycle)                                                   100% context left  "
```

### 内容解析
| 部分 | 内容 | 长度 | 样式 |
|-----|------|------|------|
| 左侧缩进 | `  ` | 2 | 默认 |
| 快捷提示 | `? for shortcuts` | 15 | `?` 高亮 + ` for shortcuts` 暗淡 |
| 分隔符 | ` · ` | 3 | 暗淡 |
| 模式指示器 | `Plan mode (shift+tab to cycle)` | 32 | 洋红色 |
| 填充空格 | ` ` x 51 | 51 | 默认 |
| 上下文信息 | `100% context left` | 17 | 暗淡 |
| 右侧缩进 | `  ` | 2 | 默认 |
| **总计** | | **120** | |

### 样式标记分析
```rust
// 实际渲染的 Span 结构
Line::from(vec![
    "  ",                                           // 缩进
    "?".into(),                                     // 快捷提示键（高亮）
    " for shortcuts".dim(),                          // 快捷提示文本（暗淡）
    " · ".dim(),                                    // 分隔符（暗淡）
    "Plan mode (shift+tab to cycle)".magenta(),     // 模式指示器（洋红色）
    // ... 填充空格 ...
    "100% context left".dim(),                      // 上下文（暗淡）
    "  ",                                           // 缩进
])
```

### 验证清单
- ✅ 左侧缩进: 2列
- ✅ 快捷提示: 完整显示
- ✅ 分隔符: " · " 存在
- ✅ 模式指示器: 包含 "(shift+tab to cycle)"
- ✅ 模式颜色: 洋红色 (Plan)
- ✅ 上下文信息: "100% context left" 显示在右侧
- ✅ 总宽度: 120列
