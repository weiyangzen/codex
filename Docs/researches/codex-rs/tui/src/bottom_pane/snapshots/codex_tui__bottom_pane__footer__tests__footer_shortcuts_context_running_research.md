# Footer Shortcuts - Context Running 测试研究文档

## 场景与职责

### 测试场景
该快照测试验证当**任务正在运行**时，footer 显示上下文窗口百分比而不是快捷提示的行为。

### 测试数据
- **模式**: `ComposerEmpty`（编辑器为空）
- **任务运行状态**: **运行中** (`is_task_running: true`)
- **上下文窗口**: 72% 剩余 (`context_window_percent: Some(72)`)
- **协作模式**: 禁用 (`collaboration_modes_enabled: false`)

### 期望行为
任务运行时，footer 应该：
1. 显示快捷提示 "? for shortcuts"
2. 显示上下文窗口信息 "72% context left"
3. 隐藏 "(shift+tab to cycle)" 提示（因为任务运行中）

---

## 功能点目的

### 核心功能
该测试验证 footer 的**任务状态感知显示逻辑**：

1. **上下文信息优先**: 任务运行时显示资源使用信息
2. **快捷提示保留**: 即使在任务运行时也保留基本快捷提示
3. **动态提示调整**: 根据任务状态调整提示内容

### 业务价值
- **资源可见性**: 用户可以随时了解上下文窗口使用情况
- **操作连续性**: 即使在任务运行时也能访问快捷帮助
- **界面简洁**: 移除不必要的提示（如模式循环）减少干扰

### 状态对比
```
空闲状态: "? for shortcuts · Plan mode (shift+tab to cycle)  100% context left"
运行状态: "? for shortcuts                                             72% context left"
差异:       保留快捷提示          移除模式指示器              显示具体百分比
```

---

## 具体技术实现

### 关键代码路径

#### 1. 测试入口
```rust
// footer.rs:1387-1403
snapshot_footer(
    "footer_shortcuts_context_running",
    FooterProps {
        mode: FooterMode::ComposerEmpty,
        esc_backtrack_hint: false,
        use_shift_enter_hint: false,
        is_task_running: true,  // 任务运行中
        collaboration_modes_enabled: false,
        context_window_percent: Some(72),  // 72% 上下文剩余
        context_window_used_tokens: None,
        // ...
    },
);
```

#### 2. 上下文行生成
```rust
// footer.rs:848-860
pub(crate) fn context_window_line(
    percent: Option<i64>, 
    used_tokens: Option<i64>
) -> Line<'static> {
    if let Some(percent) = percent {
        let percent = percent.clamp(0, 100);  // 限制在 0-100 范围
        return Line::from(vec![
            Span::from(format!("{percent}% context left")).dim()
        ]);
    }

    if let Some(tokens) = used_tokens {
        let used_fmt = format_tokens_compact(tokens);
        return Line::from(vec![
            Span::from(format!("{used_fmt} used")).dim()
        ]);
    }

    // 默认值
    Line::from(vec![Span::from("100% context left").dim()])
}
```

#### 3. 布局决策
```rust
// footer.rs:1074-1097 (draw_footer_frame 中)
let show_cycle_hint = !props.is_task_running;  // false（任务运行）
let show_shortcuts_hint = match props.mode {
    FooterMode::ComposerEmpty => true,  // true
    _ => false,
};
let show_queue_hint = match props.mode {
    FooterMode::ComposerHasDraft => props.is_task_running,
    _ => false,
};

// 右侧内容
let right_line = context_window_line(
    props.context_window_percent,      // Some(72)
    props.context_window_used_tokens,  // None
);
```

#### 4. 左侧内容构建
```rust
// footer.rs:271-300
fn left_side_line(...) -> Line<'static> {
    let mut line = Line::from("");
    
    // 添加快捷提示
    match state.hint {
        SummaryHintKind::Shortcuts => {
            line.push_span(key_hint::plain(KeyCode::Char('?')));
            line.push_span(" for shortcuts".dim());
        }
        // ...
    };
    
    // 无协作模式指示器（collaboration_modes_enabled = false）
    
    line
}
```

### 渲染流程

```
测试调用
    ↓
draw_footer_frame
    ├─ show_cycle_hint = false（任务运行）
    ├─ show_shortcuts_hint = true（ComposerEmpty）
    ├─ collaboration_mode_indicator = None（未启用）
    │
    ├─ 左侧: left_side_line
    │   └─ "? for shortcuts"（仅快捷提示，无模式指示器）
    │
    ├─ 右侧: context_window_line(Some(72), None)
    │   └─ "72% context left"
    │
    └─ 渲染左右两侧
```

---

## 关键代码路径与文件引用

### 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/bottom_pane/footer.rs:848-860` | `context_window_line` - 上下文行生成 |
| `codex-rs/tui/src/bottom_pane/footer.rs:271-300` | `left_side_line` - 左侧内容构建 |
| `codex-rs/tui/src/bottom_pane/footer.rs:1074-1234` | `draw_footer_frame` - 测试渲染框架 |
| `codex-rs/tui/src/bottom_pane/footer.rs:310-472` | `single_line_footer_layout` - 布局决策 |

### 数据结构
```rust
// footer.rs:65-87
pub(crate) struct FooterProps {
    pub(crate) mode: FooterMode,
    pub(crate) is_task_running: bool,
    pub(crate) context_window_percent: Option<i64>,  // 本测试: Some(72)
    pub(crate) context_window_used_tokens: Option<i64>,  // 本测试: None
    pub(crate) collaboration_modes_enabled: bool,  // 本测试: false
    // ...
}
```

### 相关常量
```rust
// 百分比限制在 0-100 范围
let percent = percent.clamp(0, 100);
```

---

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|-----|------|
| `crate::status::format_tokens_compact` | 令牌数格式化（当使用 used_tokens 时） |
| `crate::key_hint` | 键盘快捷键提示渲染 |
| `ratatui::text::Span` | 文本跨度构建 |

### 与 ChatComposer 的集成
```rust
// chat_composer.rs:391-395
context_window_percent: Option<i64>,
context_window_used_tokens: Option<i64>,

// 这些值从 ChatWidget 传递下来，反映当前会话的上下文使用情况
```

### 与 ChatWidget 的关系
```rust
// ChatWidget 负责：
// 1. 跟踪任务运行状态
// 2. 计算上下文窗口使用情况
// 3. 将这些信息传递给 ChatComposer/Footer
```

---

## 风险边界与改进建议

### 当前风险边界

#### 1. 百分比精度
- **风险**: 百分比被限制在 0-100 范围，但原始值可能超出
- **边界**: 如果计算错误导致负值或超过100，显示会被截断
- **建议**: 添加调试日志记录原始值

#### 2. 上下文信息冲突
- **风险**: 在极窄宽度下，"72% context left" 可能与左侧内容重叠
- **边界**: 当前测试使用默认宽度（80列），未测试窄屏情况
- **建议**: 添加窄屏测试用例

#### 3. 令牌数 vs 百分比的优先级
- **当前行为**: 百分比优先于令牌数
- **风险**: 如果两者都提供，令牌数被忽略
- **建议**: 明确文档说明优先级，或考虑同时显示

### 改进建议

#### 1. 上下文信息格式化增强
```rust
// 建议：更智能的格式化
pub(crate) fn context_window_line(percent: Option<i64>, used: Option<i64>) -> Line<'static> {
    match (percent, used) {
        (Some(p), Some(u)) => {
            // 同时显示百分比和令牌数
            format!("{p}% left ({u} tokens used)")
        }
        (Some(p), None) => format!("{p}% context left"),
        (None, Some(u)) => format!("{} used", format_tokens_compact(u)),
        (None, None) => "100% context left".to_string(),
    }
}
```

#### 2. 低上下文警告
```rust
// 建议：当上下文不足时改变颜色
if percent < 20 {
    Span::from(format!("{percent}% context left")).red()  // 警告色
} else {
    Span::from(format!("{percent}% context left")).dim()
}
```

#### 3. 测试覆盖增强
```rust
// 建议添加的测试用例
#[test]
fn footer_shortcuts_context_running_narrow() {
    // 窄屏下任务运行的显示
}

#[test]
fn footer_shortcuts_context_running_zero_percent() {
    // 0% 上下文时的显示
}

#[test]
fn footer_shortcuts_context_running_with_tokens() {
    // 同时提供百分比和令牌数
}
```

### 相关测试
该测试与以下测试共同构成上下文信息测试矩阵：
- `footer_shortcuts_context_running`: **本测试** - 百分比显示
- `footer_context_tokens_used`: 令牌数显示
- `footer_shortcuts_default`: 默认（无上下文信息）

---

## 快照内容分析

```
"  ? for shortcuts                                             72% context left  "
```

### 内容解析
| 部分 | 内容 | 长度 | 样式 |
|-----|------|------|------|
| 左侧缩进 | `  ` | 2 | 默认 |
| 快捷提示键 | `?` | 1 | 高亮 |
| 快捷提示文本 | ` for shortcuts` | 14 | 暗淡 |
| 填充空格 | ` ` x 45 | 45 | 默认 |
| 上下文信息 | `72% context left` | 16 | 暗淡 |
| 右侧缩进 | `  ` | 2 | 默认 |
| **总计** | | **80** | |

### 关键验证点
1. ✅ **快捷提示存在**: "? for shortcuts"
2. ✅ **上下文百分比**: "72%"（具体值，非默认值）
3. ✅ **无模式指示器**: 协作模式未启用，不显示
4. ✅ **暗淡样式**: 上下文信息使用 `.dim()`

### 与默认状态对比
```
默认:     "  ? for shortcuts                                                            "
运行72%:  "  ? for shortcuts                                             72% context left  "
差异:                                                          ^^^^^^^^^^^^^^^^^^ 新增
```

### 样式说明
```rust
Line::from(vec![
    "  ",                                    // 缩进
    "?".into(),                              // 快捷提示键
    " for shortcuts".dim(),                   // 快捷提示文本
    // ... 填充空格 ...
    "72% context left".dim(),                 // 上下文信息
    "  ",                                    // 缩进
])
```
