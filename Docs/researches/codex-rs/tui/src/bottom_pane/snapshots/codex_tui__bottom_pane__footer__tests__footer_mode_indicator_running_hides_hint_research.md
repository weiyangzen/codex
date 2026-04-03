# Footer Mode Indicator - Running Hides Hint 测试研究文档

## 场景与职责

### 测试场景
该快照测试验证当**任务正在运行**时，footer 的模式指示器行为：
- 隐藏 "(shift+tab to cycle)" 提示
- 保留 "? for shortcuts" 提示
- 显示上下文窗口信息

### 测试数据
- **终端宽度**: 120列（宽屏）
- **模式**: `ComposerEmpty`（编辑器为空）
- **任务运行状态**: **运行中** (`is_task_running: true`)
- **协作模式**: 启用 (`collaboration_modes_enabled: true`)
- **协作模式指示器**: `Plan`
- **上下文窗口**: 未设置（默认显示 "100% context left"）

### 期望行为
任务运行时，用户不需要切换协作模式，因此隐藏模式循环提示，但保留其他提示和上下文信息。

---

## 功能点目的

### 核心功能
该测试验证 footer 的**上下文感知提示系统**：

1. **任务状态感知**: 根据 `is_task_running` 动态调整显示内容
2. **提示优先级管理**: 在任务运行时简化提示，减少干扰
3. **上下文信息保留**: 即使简化提示，仍保留上下文窗口信息

### 业务价值
- **减少视觉干扰**: 任务运行时用户关注输出，不需要模式切换提示
- **保持必要信息**: 上下文窗口信息始终可见，帮助用户了解资源使用
- **一致性体验**: 不同状态下 footer 的行为可预测

### 状态转换规则
```
任务未运行: "? for shortcuts · Plan mode (shift+tab to cycle)  100% context left"
                ↓ is_task_running = true
任务运行中: "? for shortcuts · Plan mode                      100% context left"
                (shift+tab to cycle) 被隐藏
```

---

## 具体技术实现

### 关键代码路径

#### 1. 测试入口
```rust
// footer.rs:1485-1490
let props = FooterProps {
    mode: FooterMode::ComposerEmpty,
    is_task_running: true,  // 关键：任务运行中
    collaboration_modes_enabled: true,
    collaboration_mode_indicator: Some(CollaborationModeIndicator::Plan),
    // ...
};

snapshot_footer_with_mode_indicator(
    "footer_mode_indicator_running_hides_hint",
    120,
    &props,
    Some(CollaborationModeIndicator::Plan),
);
```

#### 2. 提示显示决策逻辑
```rust
// footer.rs:1083 (在 draw_footer_frame 中)
let show_cycle_hint = !props.is_task_running;  // 任务运行时隐藏循环提示

// footer.rs:1084-1090
let show_shortcuts_hint = match props.mode {
    FooterMode::ComposerEmpty => true,  // 空编辑器时显示快捷提示
    FooterMode::ComposerHasDraft => false,
    _ => false,
};
```

#### 3. 左侧内容构建
```rust
// footer.rs:271-300
fn left_side_line(
    collaboration_mode_indicator: Option<CollaborationModeIndicator>,
    state: LeftSideState,
) -> Line<'static> {
    let mut line = Line::from("");
    
    // 添加快捷提示
    match state.hint {
        SummaryHintKind::Shortcuts => {
            line.push_span(key_hint::plain(KeyCode::Char('?')));
            line.push_span(" for shortcuts".dim());
        }
        // ...
    };

    // 添加模式指示器
    if let Some(indicator) = collaboration_mode_indicator {
        if !matches!(state.hint, SummaryHintKind::None) {
            line.push_span(" · ".dim());
        }
        // styled_span 根据 show_cycle_hint 决定是否添加 "(shift+tab to cycle)"
        line.push_span(indicator.styled_span(state.show_cycle_hint));
    }

    line
}
```

#### 4. 模式指示器标签生成
```rust
// footer.rs:102-115
impl CollaborationModeIndicator {
    fn label(self, show_cycle_hint: bool) -> String {
        let suffix = if show_cycle_hint {
            format!(" ({MODE_CYCLE_HINT})")  // " (shift+tab to cycle)"
        } else {
            String::new()  // 空后缀
        };
        match self {
            CollaborationModeIndicator::Plan => format!("Plan mode{suffix}"),
            // ...
        }
    }

    fn styled_span(self, show_cycle_hint: bool) -> Span<'static> {
        let label = self.label(show_cycle_hint);
        match self {
            CollaborationModeIndicator::Plan => Span::from(label).magenta(),
            CollaborationModeIndicator::PairProgramming => Span::from(label).cyan(),
            CollaborationModeIndicator::Execute => Span::from(label).dim(),
        }
    }
}
```

### 渲染流程

```
测试调用
    ↓
draw_footer_frame
    ↓
show_cycle_hint = !is_task_running = false
    ↓
left_side_line 构建内容
    ├─ "? for shortcuts" (show_shortcuts_hint=true)
    ├─ " · " 分隔符
    └─ "Plan mode" (不含 cycle hint，因为 show_cycle_hint=false)
    ↓
context_window_line 构建右侧内容
    └─ "100% context left"
    ↓
渲染左右两侧内容
```

---

## 关键代码路径与文件引用

### 主要文件
| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/bottom_pane/footer.rs:102-125` | `CollaborationModeIndicator` 实现 |
| `codex-rs/tui/src/bottom_pane/footer.rs:271-300` | `left_side_line` - 左侧内容构建 |
| `codex-rs/tui/src/bottom_pane/footer.rs:1074-1234` | `draw_footer_frame` - 测试渲染框架 |
| `codex-rs/tui/src/bottom_pane/footer.rs:848-860` | `context_window_line` - 上下文行生成 |

### 相关常量
```rust
// footer.rs:98
const MODE_CYCLE_HINT: &str = "shift+tab to cycle";
```

### 数据结构
```rust
// footer.rs:65-87
pub(crate) struct FooterProps {
    pub(crate) mode: FooterMode,
    pub(crate) is_task_running: bool,  // 控制 cycle hint 显示
    pub(crate) collaboration_modes_enabled: bool,
    pub(crate) context_window_percent: Option<i64>,
    pub(crate) context_window_used_tokens: Option<i64>,
    // ...
}
```

---

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|-----|------|
| `crate::key_hint` | 键盘快捷键提示渲染 |
| `crate::status::format_tokens_compact` | 令牌数格式化 |
| `ratatui::style::Stylize` | 文本样式（颜色、暗淡等） |

### 颜色方案
```rust
// footer.rs:117-124
match self {
    CollaborationModeIndicator::Plan => Span::from(label).magenta(),
    CollaborationModeIndicator::PairProgramming => Span::from(label).cyan(),
    CollaborationModeIndicator::Execute => Span::from(label).dim(),
}
```

### 与 ChatComposer 的集成
```rust
// chat_composer.rs:383-384
footer_mode: FooterMode,
is_task_running: bool,  // 从 ChatWidget 传递下来

// chat_composer.rs:604-608
pub fn set_collaboration_mode_indicator(
    &mut self,
    indicator: Option<CollaborationModeIndicator>,
) {
    self.collaboration_mode_indicator = indicator;
}
```

---

## 风险边界与改进建议

### 当前风险边界

#### 1. 硬编码的提示隐藏逻辑
- **风险**: `show_cycle_hint = !is_task_running` 是硬编码的，缺乏灵活性
- **边界**: 如果未来需要更细粒度的控制（如某些任务类型显示提示），需要重构
- **建议**: 考虑将提示显示策略提取为配置或策略模式

#### 2. 快捷提示与任务状态的耦合
- **当前行为**: 任务运行时仍显示 "? for shortcuts"
- **问题**: 任务运行时用户可能不需要快捷提示
- **建议**: 评估是否应在任务运行时隐藏所有非关键提示

#### 3. 上下文窗口信息的优先级
- **当前行为**: 上下文信息始终显示
- **风险**: 在极窄宽度下，上下文信息可能与左侧内容冲突
- **建议**: 添加上下文信息在极端情况下的回退策略

### 改进建议

#### 1. 提示优先级系统
```rust
// 建议：引入提示优先级枚举
enum HintPriority {
    Critical,    // 始终显示（如错误提示）
    High,        // 正常显示（如模式指示器）
    Medium,      // 空间允许时显示（如快捷提示）
    Low,         // 空闲时显示（如 cycle hint）
}

fn should_show_hint(priority: HintPriority, is_task_running: bool, available_width: u16) -> bool {
    match priority {
        HintPriority::Critical => true,
        HintPriority::High => true,
        HintPriority::Medium => !is_task_running,
        HintPriority::Low => !is_task_running && available_width > THRESHOLD,
    }
}
```

#### 2. 任务状态细分
```rust
// 建议：区分不同类型的任务状态
enum TaskState {
    Idle,
    Running { show_hints: bool },  // 某些任务可能允许提示
    RunningCritical,               // 关键任务，隐藏所有提示
}
```

#### 3. 测试覆盖增强
```rust
// 建议添加的测试用例
#[test]
fn footer_mode_indicator_running_with_context_percent() {
    // 任务运行时显示上下文百分比
}

#[test]
fn footer_mode_indicator_running_with_tokens_used() {
    // 任务运行时显示已用令牌数
}

#[test]
fn footer_mode_indicator_running_narrow_width() {
    // 任务运行且宽度不足时的行为
}
```

### 相关测试
该测试与以下测试共同构成任务状态测试矩阵：
- `footer_mode_indicator_wide`: 空闲状态宽屏显示
- `footer_mode_indicator_narrow_overlap_hides`: 空闲状态窄屏显示
- `footer_shortcuts_context_running`: 快捷提示在任务运行时的显示

---

## 快照内容分析

```
"  ? for shortcuts · Plan mode                                                                        100% context left  "
```

### 内容解析
- `  `: 2列左侧缩进
- `? for shortcuts`: 快捷提示（15字符）
- ` · `: 分隔符（3字符，暗淡样式）
- `Plan mode`: 模式指示器（9字符，洋红色）
- `                                                                        `: 72列空格
- `100% context left`: 上下文信息（17字符，暗淡样式）
- `  `: 2列右侧缩进

### 关键验证点
1. ✅ **包含快捷提示**: "? for shortcuts" 存在
2. ✅ **模式指示器无 cycle hint**: "Plan mode" 后面没有 "(shift+tab to cycle)"
3. ✅ **包含上下文信息**: "100% context left" 存在
4. ✅ **正确分隔**: " · " 分隔符存在

### 与空闲状态对比
```
空闲状态: "? for shortcuts · Plan mode (shift+tab to cycle)                   100% context left"
运行状态: "? for shortcuts · Plan mode                                        100% context left"
差异:                        ^^^^^^^^^^^^^^^^^^^^^^^ 被移除
```
