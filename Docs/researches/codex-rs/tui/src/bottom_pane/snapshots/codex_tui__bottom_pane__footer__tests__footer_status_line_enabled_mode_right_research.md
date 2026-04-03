# Footer Status Line - Enabled Mode Right 测试研究文档

## 场景与职责

### 测试场景
该快照测试验证当**状态行启用**且**状态行值为空**（命令超时/无内容）时，footer 右侧显示协作模式指示器的行为。

### 测试数据
- **终端宽度**: 120列
- **模式**: `ComposerEmpty`
- **状态行**: 启用 (`status_line_enabled: true`)
- **状态行值**: `None`（命令超时或空）
- **协作模式**: 启用 (`collaboration_modes_enabled: true`)
- **协作模式指示器**: `Plan`
- **上下文窗口**: 50% 剩余

### 期望行为
状态行启用时，footer 应该：
1. 左侧显示状态行内容（本测试为空）
2. 右侧显示协作模式指示器 "Plan mode (shift+tab to cycle)"

---

## 功能点目的

### 核心功能
该测试验证状态行布局的**专用渲染路径**：

1. **状态行优先布局**: 启用状态行时使用专用布局
2. **模式指示器定位**: 状态行布局下模式指示器固定在右侧
3. **空状态处理**: 状态行值为空时的优雅降级

### 业务价值
- **配置可见性**: 状态行配置始终影响布局，即使内容为空
- **一致性**: 状态行启用时布局行为可预测
- **模式发现**: 右侧的模式指示器帮助用户了解当前模式

### 布局结构
```
状态行布局:
[左侧: 状态行内容（或空）]                              [右侧: 模式指示器]
                                                        Plan mode (shift+tab to cycle)
```

---

## 具体技术实现

### 关键代码路径

#### 1. 测试入口
```rust
// footer.rs:1551-1563
let props = FooterProps {
    mode: FooterMode::ComposerEmpty,
    status_line_enabled: true,   // 状态行启用
    status_line_value: None,     // 状态行值为空（命令超时）
    collaboration_modes_enabled: true,
    context_window_percent: Some(50),
    // ...
};

snapshot_footer_with_mode_indicator(
    "footer_status_line_enabled_mode_right",
    120,
    &props,
    Some(CollaborationModeIndicator::Plan),
);
```

#### 2. 状态行布局检查
```rust
// footer.rs:1098
let status_line_active = uses_passive_footer_status_layout(props);
// 结果: true（status_line_enabled = true && ComposerEmpty 模式）

// footer.rs:1136-1145
let right_line = if status_line_active {
    let full = mode_indicator_line(collaboration_mode_indicator, show_cycle_hint);
    let compact = mode_indicator_line(collaboration_mode_indicator, false);
    let full_width = full.as_ref().map(|line| line.width() as u16).unwrap_or(0);
    
    // 根据空间选择完整或紧凑模式指示器
    if can_show_left_with_context(area, left_width, full_width) {
        full   // "Plan mode (shift+tab to cycle)"
    } else {
        compact  // "Plan mode"
    }
} else {
    // 标准布局...
};
```

#### 3. 模式指示器行生成
```rust
// footer.rs:474-479
pub(crate) fn mode_indicator_line(
    indicator: Option<CollaborationModeIndicator>,
    show_cycle_hint: bool,
) -> Option<Line<'static>> {
    indicator.map(|indicator| {
        Line::from(vec![indicator.styled_span(show_cycle_hint)])
    })
}
```

#### 4. 左侧内容处理
```rust
// footer.rs:1099-1121
let passive_status_line = if status_line_active {
    passive_footer_status_line(props)  // 尝试获取被动 footer 状态行
} else {
    None
};

// footer.rs:638-659 (passive_footer_status_line)
pub(crate) fn passive_footer_status_line(props: &FooterProps) -> Option<Line<'static>> {
    if !shows_passive_footer_line(props) {
        return None;
    }

    let mut line = if props.status_line_enabled {
        props.status_line_value.clone()  // 本测试: None
    } else {
        None
    };
    // ...
    line  // 本测试返回 None
}
```

### 渲染流程

```
测试调用
    ↓
draw_footer_frame
    ├─ status_line_active = true
    │
    ├─ 左侧: passive_footer_status_line
    │   ├─ status_line_value = None
    │   └─ 无内容可渲染
    │
    ├─ 右侧: mode_indicator_line(Some(Plan), true)
    │   └─ "Plan mode (shift+tab to cycle)"（洋红色）
    │
    └─ 仅渲染右侧内容
```

---

## 关键代码路径与文件引用

### 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/bottom_pane/footer.rs:638-659` | `passive_footer_status_line` - 被动 footer 状态行生成 |
| `codex-rs/tui/src/bottom_pane/footer.rs:474-479` | `mode_indicator_line` - 模式指示器行生成 |
| `codex-rs/tui/src/bottom_pane/footer.rs:680-682` | `uses_passive_footer_status_layout` - 布局选择 |
| `codex-rs/tui/src/bottom_pane/footer.rs:1136-1145` | 右侧内容选择逻辑 |

### 数据结构
```rust
// footer.rs:65-87
pub(crate) struct FooterProps {
    pub(crate) status_line_enabled: bool,  // 本测试: true
    pub(crate) status_line_value: Option<Line<'static>>,  // 本测试: None
    // ...
}
```

### 状态行布局特点
```rust
// 状态行启用时的布局特点：
// 1. 左侧: status_line_value（可能为空）
// 2. 右侧: mode_indicator_line（协作模式指示器）
// 3. 不显示: 快捷提示、上下文窗口信息
```

---

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|-----|------|
| `crate::key_hint` | 键盘快捷键渲染 |
| `ratatui::text::Line` | 文本行构建 |
| `ratatui::style::Stylize` | 样式应用 |

### 状态行来源
```rust
// 状态行内容由 /statusline 命令配置
// 支持动态内容：模型名称、git 分支、时间等
// 当命令超时或返回空时，status_line_value = None
```

### 与 ChatComposer 的集成
```rust
// chat_composer.rs:411-412
status_line_value: Option<Line<'static>>,
status_line_enabled: bool,

// chat_composer.rs 负责从配置读取状态行设置
```

---

## 风险边界与改进建议

### 当前风险边界

#### 1. 空状态行的视觉反馈
- **风险**: 状态行值为空时，footer 大部分区域为空，可能让用户困惑
- **边界**: 用户可能以为状态行功能未正常工作
- **建议**: 空状态时显示占位符或提示

#### 2. 上下文信息丢失
- **风险**: 状态行启用时不显示上下文窗口信息
- **边界**: 用户无法了解上下文使用情况
- **建议**: 考虑在状态行布局中也显示上下文信息

#### 3. 快捷提示丢失
- **风险**: 状态行启用时不显示 "? for shortcuts"
- **边界**: 新用户可能不知道如何查看快捷帮助
- **建议**: 评估是否需要保留快捷提示

### 改进建议

#### 1. 空状态占位符
```rust
// 建议：空状态时显示提示
let line = if props.status_line_enabled {
    props.status_line_value.clone().or_else(|| {
        Some(Line::from("(status line empty - run /statusline to configure)".dim()))
    })
} else {
    None
};
```

#### 2. 上下文信息整合
```rust
// 建议：在状态行布局中保留上下文信息
if status_line_active {
    // 左侧: 状态行
    // 右侧: 模式指示器 + 上下文信息
}
```

#### 3. 测试覆盖增强
```rust
// 建议：测试状态行命令超时的场景
#[test]
fn footer_status_line_command_timeout() {
    // 模拟状态行命令超时
}
```

### 相关测试
该测试与以下测试共同构成状态行启用测试矩阵：
- `footer_status_line_enabled_mode_right`: **本测试** - 状态行为空
- `footer_status_line_enabled_no_mode_right`: 启用状态行，无模式指示器
- `footer_status_line_overrides_shortcuts`: 启用状态行，有内容

---

## 快照内容分析

```
"                                                                                        Plan mode (shift+tab to cycle)  "
```

### 内容解析
| 部分 | 内容 | 长度 | 样式 |
|-----|------|------|------|
| 填充空格 | ` ` x 88 | 88 | 默认 |
| 模式指示器 | `Plan mode (shift+tab to cycle)` | 32 | 洋红色 |
| 右侧缩进 | `  ` | 2 | 默认 |
| **总计** | | **120** | |

### 关键验证点
1. ✅ **左侧为空**: 无状态行内容显示
2. ✅ **模式指示器在右侧**: "Plan mode (shift+tab to cycle)"
3. ✅ **无快捷提示**: "? for shortcuts" 未显示
4. ✅ **无上下文信息**: "50% context left" 未显示

### 与禁用状态行对比
```
状态行禁用: "  ? for shortcuts · Plan mode (shift+tab to cycle)                                                    50% context left  "
状态行启用: "                                                                                        Plan mode (shift+tab to cycle)  "
差异:        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ 左侧内容完全不同，右侧也不同
```

### 样式说明
```rust
Line::from(vec![
    // ... 88列空格 ...
    "Plan mode (shift+tab to cycle)".magenta(),  // 模式指示器
    "  ",                                          // 缩进
])
```

### 视觉分析
- 大部分区域为空（88列空格）
- 模式指示器右对齐
- 洋红色突出显示当前协作模式
- 用户可能需要配置状态行以填充左侧空白
