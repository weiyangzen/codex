# Footer Mode Indicator - Narrow Overlap Hides 测试研究文档

## 场景与职责

### 测试场景
该快照测试验证在**窄终端宽度（50列）**下，当左侧内容（快捷提示 + 协作模式指示器）与右侧内容（上下文窗口信息）发生重叠时，右侧内容被正确隐藏的行为。

### 测试数据
- **终端宽度**: 50列
- **模式**: `ComposerEmpty`（编辑器为空）
- **任务运行状态**: 未运行 (`is_task_running: false`)
- **协作模式**: 启用 (`collaboration_modes_enabled: true`)
- **协作模式指示器**: `Plan`
- **上下文窗口**: 未设置（默认显示 "100% context left"）

### 期望行为
当终端宽度不足以同时显示左侧提示和右侧上下文信息时，优先保留左侧内容，隐藏右侧内容。

---

## 功能点目的

### 核心功能
该测试验证 footer 的**响应式布局回退机制**中的关键规则：

1. **空间不足时的优先级策略**: 当 `can_show_left_with_context` 返回 false 时，footer 应该只显示左侧内容
2. **模式指示器保留**: 协作模式标签 "Plan mode (shift+tab to cycle)" 必须始终可见
3. **右侧内容优雅降级**: 上下文窗口信息在狭窄空间下被隐藏而非截断

### 业务价值
- 确保在小型终端窗口中 footer 不会换行或显示混乱
- 保持核心功能提示（模式切换）始终可见
- 提供清晰的用户体验，避免信息重叠

---

## 具体技术实现

### 关键代码路径

#### 1. 测试入口
```rust
// footer.rs:1463-1468
snapshot_footer_with_mode_indicator(
    "footer_mode_indicator_narrow_overlap_hides",
    50,  // 窄宽度
    &props,
    Some(CollaborationModeIndicator::Plan),
);
```

#### 2. 布局决策逻辑
```rust
// footer.rs:310-472 single_line_footer_layout 函数
pub(crate) fn single_line_footer_layout(
    area: Rect,
    context_width: u16,
    collaboration_mode_indicator: Option<CollaborationModeIndicator>,
    show_cycle_hint: bool,
    show_shortcuts_hint: bool,
    show_queue_hint: bool,
) -> (SummaryLeft, bool) {
    // 1. 尝试默认状态（完整提示 + 模式指示器）
    let default_state = LeftSideState { hint: hint_kind, show_cycle_hint };
    if can_show_left_with_context(area, default_width, context_width) {
        return (SummaryLeft::Default, true);  // 可以显示两侧
    }
    
    // 2. 回退：尝试仅模式指示器
    let mode_only_state = LeftSideState {
        hint: SummaryHintKind::None,
        show_cycle_hint: false,
    };
    if left_fits(area, mode_only_width) {
        return (SummaryLeft::Custom(...), false);  // 只显示左侧
    }
    
    // 3. 最终回退：不显示任何内容
    (SummaryLeft::None, true)
}
```

#### 3. 空间检查函数
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
    if left_width == 0 {
        return true;
    }
    // 左侧内容 + 间隙 + 右侧内容 必须能容纳
    let left_extent = FOOTER_INDENT_COLS as u16 + left_width + FOOTER_CONTEXT_GAP_COLS;
    left_extent <= context_x.saturating_sub(area.x)
}
```

### 渲染流程

```
测试调用
    ↓
draw_footer_frame (footer.rs:1074)
    ↓
single_line_footer_layout (判断空间不足，返回 show_context=false)
    ↓
render_footer_line (仅渲染左侧内容)
    ↓
不调用 render_context_right (右侧内容被隐藏)
```

---

## 关键代码路径与文件引用

### 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/bottom_pane/footer.rs:310-472` | `single_line_footer_layout` - 核心布局决策 |
| `codex-rs/tui/src/bottom_pane/footer.rs:518-527` | `can_show_left_with_context` - 空间可用性检查 |
| `codex-rs/tui/src/bottom_pane/footer.rs:271-300` | `left_side_line` - 左侧内容构建 |
| `codex-rs/tui/src/bottom_pane/footer.rs:474-479` | `mode_indicator_line` - 模式指示器渲染 |
| `codex-rs/tui/src/bottom_pane/footer.rs:529-554` | `render_context_right` - 右侧内容渲染 |

### 相关常量
```rust
// footer.rs:99
const FOOTER_CONTEXT_GAP_COLS: u16 = 1;  // 左右内容间隙

// ui_consts (通过导入)
FOOTER_INDENT_COLS = 2;  // 左侧缩进
```

### 测试辅助函数
```rust
// footer.rs:1236-1246
fn snapshot_footer_with_mode_indicator(
    name: &str,
    width: u16,           // 测试指定的终端宽度
    props: &FooterProps,
    collaboration_mode_indicator: Option<CollaborationModeIndicator>,
)
```

---

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|-----|------|
| `crate::key_hint` | 键盘快捷键提示渲染 |
| `crate::render::line_utils::prefix_lines` | 行前缀处理 |
| `ratatui::layout::Rect` | 终端区域计算 |
| `ratatui::text::Line` | 文本行构建 |

### 数据结构
```rust
// footer.rs:265-269
struct LeftSideState {
    hint: SummaryHintKind,      // 提示类型（Shortcuts/QueueMessage/QueueShort/None）
    show_cycle_hint: bool,      // 是否显示循环提示
}

// footer.rs:302-306  
pub(crate) enum SummaryLeft {
    Default,        // 使用默认渲染
    Custom(Line<'static>),  // 自定义行
    None,           // 不显示左侧
}
```

### 协作模式指示器
```rust
// footer.rs:89-96
pub(crate) enum CollaborationModeIndicator {
    Plan,              // 规划模式（洋红色）
    PairProgramming,   // 结对编程模式（青色）- 当前隐藏
    Execute,           // 执行模式（暗淡）- 当前隐藏
}
```

---

## 风险边界与改进建议

### 当前风险边界

#### 1. 宽度阈值敏感性
- **风险**: 50列是一个固定的测试宽度，实际用户可能使用各种宽度
- **边界**: 当宽度在 45-55 列之间时，布局行为可能发生剧烈变化
- **建议**: 添加更多边界值测试（45, 48, 52, 55列）

#### 2. 内容截断 vs 隐藏策略
- **当前行为**: 右侧内容完全隐藏
- **替代方案**: 右侧内容截断显示（如 "100% cont..."）
- **建议**: 评估是否需要在某些场景下显示部分上下文信息

#### 3. 模式循环提示的优先级
- **当前行为**: "(shift+tab to cycle)" 随模式指示器一起保留
- **风险**: 在极窄宽度下，模式指示器本身可能被截断
- **建议**: 添加测试验证模式指示器在极窄宽度下的行为

### 改进建议

#### 1. 测试覆盖增强
```rust
// 建议添加的测试用例
#[test]
fn footer_mode_indicator_ultra_narrow() {
    // 测试 30-40 列宽度下的行为
}

#[test]
fn footer_mode_indicator_boundary_width() {
    // 测试刚好能容纳/不能容纳的边界宽度
}
```

#### 2. 动态宽度适应
考虑实现更细粒度的回退策略：
```rust
// 当前：直接隐藏右侧
// 建议：渐进式降级
1. 尝试完整显示（左侧 + 右侧）
2. 缩短队列提示（"to queue message" → "to queue"）
3. 隐藏快捷提示（"? for shortcuts"）
4. 隐藏模式循环提示（"(shift+tab to cycle)"）
5. 仅显示模式名称
6. 隐藏右侧上下文
```

#### 3. 文档改进
- 在代码中添加具体的宽度阈值注释
- 说明每种回退策略触发的具体条件

### 相关测试
该测试与以下测试共同构成模式指示器的完整测试矩阵：
- `footer_mode_indicator_wide`: 宽屏下的完整显示
- `footer_mode_indicator_running_hides_hint`: 任务运行时的提示隐藏
- `footer_status_line_enabled_mode_right`: 状态行启用时的模式显示

---

## 快照内容分析

```
"  Plan mode (shift+tab to cycle)                  "
```

### 内容解析
- `  `: 2列左侧缩进 (`FOOTER_INDENT_COLS`)
- `Plan mode (shift+tab to cycle)`: 模式指示器（32字符）
- `                  `: 16列尾部空格（填充到50列）

### 缺失内容验证
- **无右侧上下文**: "100% context left" 未显示（验证隐藏逻辑正确）
- **无快捷提示**: "? for shortcuts" 未显示（空间不足被省略）

### 颜色标记（在ratatui渲染中）
- `Plan mode`: 洋红色 (`magenta()`)
- `(shift+tab to cycle)`: 默认颜色
