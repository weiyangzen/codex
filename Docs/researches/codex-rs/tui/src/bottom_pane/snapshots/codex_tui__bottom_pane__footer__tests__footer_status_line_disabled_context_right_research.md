# Footer Status Line - Disabled Context Right 测试研究文档

## 场景与职责

### 测试场景
该快照测试验证当**状态行禁用**但**协作模式启用**时，footer 显示协作模式指示器和上下文窗口信息的行为。

### 测试数据
- **终端宽度**: 120列
- **模式**: `ComposerEmpty`
- **状态行**: 禁用 (`status_line_enabled: false`)
- **状态行值**: `None`
- **协作模式**: 启用 (`collaboration_modes_enabled: true`)
- **协作模式指示器**: `Plan`
- **上下文窗口**: 50% 剩余

### 期望行为
当状态行禁用时，footer 应该：
1. 显示标准快捷提示 "? for shortcuts"
2. 显示协作模式指示器 "Plan mode (shift+tab to cycle)"
3. 右侧显示上下文窗口信息 "50% context left"

---

## 功能点目的

### 核心功能
该测试验证 footer 的**状态行与标准布局切换机制**：

1. **状态行开关**: 根据 `status_line_enabled` 选择不同的布局策略
2. **标准布局回退**: 状态行禁用时使用标准 footer 布局
3. **上下文信息保留**: 无论状态行状态如何，都显示上下文信息

### 业务价值
- **用户选择**: 允许用户通过配置禁用状态行，使用简洁布局
- **向后兼容**: 支持不使用状态行功能的旧版行为
- **灵活性**: 适应不同用户的使用习惯

### 布局对比
```
状态行启用:  [状态行内容]                                    [模式指示器]
状态行禁用:  ? for shortcuts · Plan mode (shift+tab to cycle)   50% context left
             └─ 标准 footer 布局 ─┘
```

---

## 具体技术实现

### 关键代码路径

#### 1. 测试入口
```rust
// footer.rs:1565-1585
let props = FooterProps {
    mode: FooterMode::ComposerEmpty,
    status_line_enabled: false,  // 状态行禁用
    status_line_value: None,
    collaboration_modes_enabled: true,
    context_window_percent: Some(50),
    // ...
};

snapshot_footer_with_mode_indicator(
    "footer_status_line_disabled_context_right",
    120,
    &props,
    Some(CollaborationModeIndicator::Plan),
);
```

#### 2. 布局选择逻辑
```rust
// footer.rs:1098-1210 (draw_footer_frame 中)
let status_line_active = uses_passive_footer_status_layout(props);

if status_line_active {
    // 状态行布局：左侧显示状态行，右侧显示模式指示器
    // ...
} else {
    // 标准布局：使用 single_line_footer_layout
    let (summary_left, show_context) = single_line_footer_layout(
        area,
        right_width,
        left_mode_indicator,  // Some(Plan)
        show_cycle_hint,
        show_shortcuts_hint,
        show_queue_hint,
    );
    // ...
}
```

#### 3. 状态行布局检查
```rust
// footer.rs:680-682
pub(crate) fn uses_passive_footer_status_layout(props: &FooterProps) -> bool {
    props.status_line_enabled && shows_passive_footer_line(props)
}

// footer.rs:665-673
pub(crate) fn shows_passive_footer_line(props: &FooterProps) -> bool {
    match props.mode {
        FooterMode::ComposerEmpty => true,
        FooterMode::ComposerHasDraft => !props.is_task_running,
        _ => false,
    }
}
```

#### 4. 右侧内容选择
```rust
// footer.rs:1145-1150 (状态行禁用时)
let right_line = if status_line_active {
    // 状态行布局：显示模式指示器
    // ...
} else {
    // 标准布局：显示上下文窗口信息
    Some(context_window_line(
        props.context_window_percent,      // Some(50)
        props.context_window_used_tokens,  // None
    ))
};
// 结果: "50% context left"
```

### 渲染流程

```
测试调用
    ↓
draw_footer_frame
    ├─ status_line_active = false（status_line_enabled = false）
    │
    ├─ 左侧: single_line_footer_layout
    │   ├─ show_shortcuts_hint = true
    │   ├─ collaboration_mode_indicator = Some(Plan)
    │   └─ "? for shortcuts · Plan mode (shift+tab to cycle)"
    │
    ├─ 右侧: context_window_line(Some(50), None)
    │   └─ "50% context left"
    │
    └─ 渲染左右两侧
```

---

## 关键代码路径与文件引用

### 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/bottom_pane/footer.rs:680-682` | `uses_passive_footer_status_layout` - 布局选择 |
| `codex-rs/tui/src/bottom_pane/footer.rs:665-673` | `shows_passive_footer_line` - 被动 footer 检查 |
| `codex-rs/tui/src/bottom_pane/footer.rs:310-472` | `single_line_footer_layout` - 标准布局决策 |
| `codex-rs/tui/src/bottom_pane/footer.rs:848-860` | `context_window_line` - 上下文行生成 |
| `codex-rs/tui/src/bottom_pane/footer.rs:1074-1234` | `draw_footer_frame` - 测试渲染框架 |

### 数据结构
```rust
// footer.rs:65-87
pub(crate) struct FooterProps {
    pub(crate) status_line_enabled: bool,  // 本测试: false
    pub(crate) status_line_value: Option<Line<'static>>,  // 本测试: None
    pub(crate) context_window_percent: Option<i64>,  // 本测试: Some(50)
    // ...
}
```

### 布局决策树
```
uses_passive_footer_status_layout?
├── true (status_line_enabled && shows_passive_footer_line)
│   ├── 左侧: status_line_value（或 active_agent_label）
│   └── 右侧: mode_indicator_line
│
└── false (本测试)
    ├── 左侧: single_line_footer_layout 结果
    └── 右侧: context_window_line
```

---

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|-----|------|
| `crate::key_hint` | 键盘快捷键提示渲染 |
| `crate::status::format_tokens_compact` | 令牌数格式化 |
| `ratatui::text::Line` | 文本行构建 |

### 与 ChatComposer 的集成
```rust
// chat_composer.rs:411-412
status_line_value: Option<Line<'static>>,
status_line_enabled: bool,
```

### 状态行来源
```rust
// 状态行内容由 /statusline 命令配置
// 可以包含：模型名称、git 分支、上下文使用等信息
// 当 status_line_enabled = false 时，使用标准 footer 布局
```

---

## 风险边界与改进建议

### 当前风险边界

#### 1. 布局切换的突兀性
- **风险**: 状态行启用/禁用时，footer 布局发生显著变化
- **边界**: 用户可能在切换配置后感到困惑
- **建议**: 添加过渡动画或更明显的视觉提示

#### 2. 上下文信息位置不一致
- **风险**: 状态行启用时上下文信息在左侧，禁用时在右侧
- **边界**: 用户需要适应不同位置
- **建议**: 考虑统一上下文信息的位置

#### 3. 模式指示器显示差异
- **风险**: 状态行启用时模式指示器在右侧，禁用时在左侧
- **边界**: 影响用户的视觉扫描习惯
- **建议**: 评估是否需要统一模式指示器位置

### 改进建议

#### 1. 布局一致性
```rust
// 建议：无论状态行状态如何，保持模式指示器位置一致
// 例如：始终在右侧显示模式指示器
```

#### 2. 配置引导
```rust
// 建议：当用户首次启用/禁用状态行时显示提示
if config_changed {
    show_notification("状态行已启用，footer 布局已调整");
}
```

#### 3. 测试覆盖增强
```rust
// 建议：测试状态行切换时的行为
#[test]
fn footer_status_line_toggle_transition() {
    // 验证从禁用切换到启用时的布局变化
}
```

### 相关测试
该测试与以下测试共同构成状态行测试矩阵：
- `footer_status_line_disabled_context_right`: **本测试** - 禁用状态行
- `footer_status_line_enabled_mode_right`: 启用状态行，有模式指示器
- `footer_status_line_enabled_no_mode_right`: 启用状态行，无模式指示器

---

## 快照内容分析

```
"  ? for shortcuts · Plan mode (shift+tab to cycle)                                                    50% context left  "
```

### 内容解析
| 部分 | 内容 | 长度 | 样式 |
|-----|------|------|------|
| 左侧缩进 | `  ` | 2 | 默认 |
| 快捷提示 | `? for shortcuts` | 15 | `?` 高亮 + 文本暗淡 |
| 分隔符 | ` · ` | 3 | 暗淡 |
| 模式指示器 | `Plan mode (shift+tab to cycle)` | 32 | 洋红色 |
| 填充空格 | ` ` x 52 | 52 | 默认 |
| 上下文信息 | `50% context left` | 16 | 暗淡 |
| 右侧缩进 | `  ` | 2 | 默认 |
| **总计** | | **120** | |

### 关键验证点
1. ✅ **状态行未显示**: 无 "Status line content"
2. ✅ **标准布局**: "? for shortcuts" 显示
3. ✅ **模式指示器**: "Plan mode (shift+tab to cycle)" 显示在左侧
4. ✅ **上下文信息**: "50% context left" 显示在右侧

### 与启用状态行对比
```
状态行启用: "                                                                                        Plan mode (shift+tab to cycle)  "
状态行禁用: "  ? for shortcuts · Plan mode (shift+tab to cycle)                                                    50% context left  "
差异:        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ 左侧内容完全不同
```

### 样式说明
```rust
Line::from(vec![
    "  ",                                              // 缩进
    "?".into(),                                        // 快捷提示键
    " for shortcuts".dim(),                             // 快捷提示文本
    " · ".dim(),                                       // 分隔符
    "Plan mode (shift+tab to cycle)".magenta(),        // 模式指示器
    // ... 填充空格 ...
    "50% context left".dim(),                          // 上下文信息
    "  ",                                              // 缩进
])
```
