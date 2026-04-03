# 快照研究文档: footer_shortcuts_default

## 基本信息
- **快照文件**: `codex_tui__bottom_pane__footer__tests__footer_shortcuts_default.snap`
- **源文件**: `codex-rs/tui/src/bottom_pane/footer.rs`
- **测试函数**: `footer_snapshots`
- **表达式**: `terminal.backend()`

---

## 场景与职责

### 功能场景
此快照捕获了**底部栏默认状态**的渲染结果。当编辑器为空且处于空闲状态时，底部栏显示默认的快捷键提示和上下文信息。

### 业务职责
1. **快捷键发现**: 提示用户按"?"查看所有快捷键
2. **上下文信息**: 显示剩余上下文百分比
3. **默认状态展示**: 作为底部栏的基准显示状态

### 触发条件
- `mode: FooterMode::ComposerEmpty` - 编辑器为空
- `is_task_running: false` - 空闲状态
- `status_line_enabled: false` - 未启用status line

---

## 功能点目的

### 核心功能
| 功能点 | 目的 | 实现方式 |
|--------|------|----------|
| 快捷键提示 | 提示查看所有快捷键 | "? for shortcuts" |
| 上下文百分比 | 显示剩余上下文 | "100% context left" |
| 右对齐 | 上下文信息右对齐 | `render_context_right()` |

### UI内容
```
"  ? for shortcuts                                            100% context left  "
  └─ 2空格缩进  └─ 快捷提示 ──────────────────────────────────  └─ 上下文信息
```

### 默认状态特征
- 左侧显示快捷键提示（当 `show_shortcuts_hint: true`）
- 右侧显示上下文信息
- 使用暗淡样式（dim）

---

## 具体技术实现

### 默认提示生成
```rust
FooterMode::ComposerEmpty => {
    let state = LeftSideState {
        hint: if show_shortcuts_hint {
            SummaryHintKind::Shortcuts  // <-- "? for shortcuts"
        } else {
            SummaryHintKind::None
        },
        show_cycle_hint,
    };
    vec![left_side_line(collaboration_mode_indicator, state)]
}
```

### 左侧提示生成
```rust
fn left_side_line(
    collaboration_mode_indicator: Option<CollaborationModeIndicator>,
    state: LeftSideState,
) -> Line<'static> {
    let mut line = Line::from("");
    match state.hint {
        SummaryHintKind::Shortcuts => {
            line.push_span(key_hint::plain(KeyCode::Char('?')));
            line.push_span(" for shortcuts".dim());
        }
        // ...
    };
    // ...
}
```

### 测试配置
```rust
snapshot_footer(
    "footer_shortcuts_default",
    FooterProps {
        mode: FooterMode::ComposerEmpty,
        esc_backtrack_hint: false,
        use_shift_enter_hint: false,
        is_task_running: false,
        collaboration_modes_enabled: false,
        is_wsl: false,
        quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
        context_window_percent: None,  // 默认显示 "100% context left"
        context_window_used_tokens: None,
        status_line_value: None,
        status_line_enabled: false,
        active_agent_label: None,
    },
);
```

---

## 关键代码路径与文件引用

### 主要代码位置
| 文件 | 行号范围 | 功能 |
|------|----------|------|
| `footer.rs` | 139-140 | `FooterMode::ComposerEmpty` 定义 |
| `footer.rs` | 278-281 | `SummaryHintKind::Shortcuts` 处理 |
| `footer.rs` | 596-605 | ComposerEmpty 模式处理 |
| `footer.rs` | 848-860 | `context_window_line()` 函数 |

### 测试代码位置
- **测试代码**: `footer.rs` 第 1259-1277 行

---

## 依赖与外部交互

### 渲染流程
```
FooterProps
    ↓
footer_from_props_lines()
    ↓
ComposerEmpty 分支
    ↓
left_side_line() with SummaryHintKind::Shortcuts
    ↓
context_window_line() → "100% context left"
    ↓
render_context_right()
```

---

## 风险边界与改进建议

### 潜在风险

#### 1. 信息过载
- **问题**: 窄终端宽度下，左侧提示和右侧上下文可能重叠
- **当前处理**: 有宽度自适应逻辑
- **建议**: 测试更多宽度边界

#### 2. 快捷键提示不明显
- **问题**: "?"字符较小，用户可能注意不到
- **建议**: 考虑使用图标或颜色强调

### 改进建议

#### 1. 添加快捷键图标
```rust
line.push_span("⌨ ".cyan().into());  // 键盘图标
line.push_span(key_hint::plain(KeyCode::Char('?')));
line.push_span(" for shortcuts".dim());
```

#### 2. 添加上下文警告
```rust
// 当上下文低于阈值时改变颜色
let context_line = if percent < 20 {
    Span::from(format!("{percent}% context left")).red()
} else {
    Span::from(format!("{percent}% context left")).dim()
};
```

### 测试覆盖分析
- ✅ 默认状态渲染测试
- ✅ 运行中状态测试（`footer_shortcuts_context_running`）
- ⚠️ 建议添加: 窄宽度自适应测试
