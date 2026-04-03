# 快照研究文档: footer_composer_has_draft_queue_hint_enabled

## 基本信息
- **快照文件**: `codex_tui__bottom_pane__footer__tests__footer_composer_has_draft_queue_hint_enabled.snap`
- **源文件**: `codex-rs/tui/src/bottom_pane/footer.rs`
- **测试函数**: `footer_snapshots`
- **表达式**: `terminal.backend()`

---

## 场景与职责

### 功能场景
此快照捕获了**编辑器有草稿且任务正在运行时的底部栏状态**。当用户正在输入消息（有草稿）且后台有任务在运行时，底部栏显示队列提示，告知用户可以按Tab键将消息加入队列。

### 业务职责
1. **队列功能提示**: 告知用户可以将当前消息加入发送队列
2. **多任务协调**: 支持在任务运行时准备下一条消息
3. **键盘快捷键提示**: 显示Tab键用于队列操作

### 触发条件
- `mode: FooterMode::ComposerHasDraft` - 编辑器有草稿
- `is_task_running: true` - 有任务正在运行

---

## 功能点目的

### 核心功能
| 功能点 | 目的 | 实现方式 |
|--------|------|----------|
| 队列提示 | 提示Tab键功能 | `SummaryHintKind::QueueMessage` |
| 上下文显示 | 显示剩余上下文 | `context_window_line()` |
| 模式判断 | 确定显示队列提示 | `footer_height()` 中的 `show_queue_hint` |

### UI内容
```
"  tab to queue message                                       100% context left  "
  └─ 2空格缩进  └─ 队列提示 ─────────────────────────────────  └─ 右侧上下文
```

### 提示类型对比
| 模式 | 提示内容 | 说明 |
|------|----------|------|
| ComposerEmpty | "? for shortcuts" | 显示快捷键提示 |
| ComposerHasDraft + 运行中 | "tab to queue message" | 显示队列提示 |
| ComposerHasDraft + 空闲 | （无提示或shortcuts） | 取决于配置 |

---

## 具体技术实现

### 队列提示逻辑
```rust
pub(crate) fn footer_height(props: &FooterProps) -> u16 {
    // ...
    let show_queue_hint = match props.mode {
        FooterMode::ComposerHasDraft => props.is_task_running,  // <-- 关键条件
        _ => false,
    };
    // ...
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
        SummaryHintKind::QueueMessage => {
            line.push_span(key_hint::plain(KeyCode::Tab));
            line.push_span(" to queue message".dim());
        }
        SummaryHintKind::QueueShort => {
            line.push_span(key_hint::plain(KeyCode::Tab));
            line.push_span(" to queue".dim());
        }
        // ...
    };
    // ...
}
```

### 测试配置
```rust
snapshot_footer(
    "footer_composer_has_draft_queue_hint_enabled",
    FooterProps {
        mode: FooterMode::ComposerHasDraft,  // <-- 有草稿
        esc_backtrack_hint: false,
        use_shift_enter_hint: false,
        is_task_running: true,  // <-- 任务运行中
        collaboration_modes_enabled: false,
        is_wsl: false,
        quit_shortcut_key: key_hint::ctrl(KeyCode::Char('c')),
        context_window_percent: None,
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
| `footer.rs` | 195-201 | `show_queue_hint` 判断逻辑 |
| `footer.rs` | 257-263 | `SummaryHintKind` 枚举定义 |
| `footer.rs` | 271-300 | `left_side_line()` 左侧提示生成 |
| `footer.rs` | 282-289 | QueueMessage/QueueShort 提示 |

### 宽度自适应逻辑
```rust
// 在 single_line_footer_layout() 中
if show_queue_hint {
    // 在队列模式下，优先保留队列提示
    let queue_states = [
        default_state,
        LeftSideState {
            hint: SummaryHintKind::QueueMessage,
            show_cycle_hint: false,
        },
        LeftSideState {
            hint: SummaryHintKind::QueueShort,  // 缩短版本
            show_cycle_hint: false,
        },
    ];
    // ...
}
```

### 测试代码位置
- **测试代码**: `footer.rs` 第 1423-1439 行

---

## 依赖与外部交互

### 依赖模块
| 模块 | 用途 |
|------|------|
| `crate::key_hint` | 快捷键提示渲染 |
| `SummaryHintKind` | 提示类型枚举 |

### 状态流转
```
用户输入文本
    ↓
mode = ComposerHasDraft
    ↓
任务开始运行
    ↓
is_task_running = true
    ↓
显示 "tab to queue message"
```

---

## 风险边界与改进建议

### 潜在风险

#### 1. 提示与Status Line冲突
- **问题**: 当 `status_line_enabled` 为 true 时，队列提示可能被覆盖
- **当前处理**: Status line优先
- **建议**: 在status line模式下也显示队列指示器

#### 2. 宽度不足时的截断
- **问题**: 窄终端宽度下，"to queue message" 可能被截断为 "to queue"
- **当前处理**: 有缩短版本作为fallback
- **建议**: 添加更短版本或图标指示

#### 3. 用户认知
- **问题**: 新用户可能不理解"queue"的含义
- **建议**: 首次使用时添加更详细的提示

### 改进建议

#### 1. 图标化提示
```rust
// 建议: 使用图标+文字
SummaryHintKind::QueueIcon => {
    line.push_span("⏳".into());  // 队列图标
    line.push_span(" tab".dim());
}
```

#### 2. 队列计数显示
```rust
// 建议: 显示队列中的消息数量
if queue_count > 0 {
    line.push_span(format!(" ({} queued)", queue_count).dim());
}
```

#### 3. 动画提示
```rust
// 建议: 使用微弱动画吸引注意力
line.push_span("tab".dim().blink());  // 闪烁效果
```

### 测试覆盖分析
- ✅ 队列提示显示测试
- ✅ Status line让步测试（`footer_status_line_yields_to_queue_hint`）
- ⚠️ 建议添加: 窄宽度下的缩短提示测试
- ⚠️ 建议添加: 队列操作交互测试
