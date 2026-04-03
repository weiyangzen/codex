# Snapshot Research: replayed_interrupted_reconnect_footer_row

## 场景与职责

此快照测试验证在重放（replay）中断重新连接事件后，页脚行的正确渲染。当会话恢复时，系统会重放历史事件，包括重新连接事件。此测试确保在重放这些事件后，页脚不会错误地显示活动状态（如 "Working" 或 "Reconnecting"）。

测试场景：
- 创建 ChatWidget 并模拟会话恢复
- 重放初始消息序列：`TurnStarted` 后跟 `StreamError`（重新连接事件）
- 重新连接消息："Reconnecting... 2/5"
- 使用 `render_bottom_first_row` 渲染页脚第一行
- 验证页脚不包含 "Reconnecting" 或 "Working"

## 功能点目的

1. **状态正确性**：确保重放的历史事件不会错误地激活当前状态指示器
2. **用户体验**：避免在会话恢复后显示误导性的活动状态
3. **历史隔离**：区分历史事件和当前活动事件
4. **回归防护**：防止重新连接状态在重放后持续显示

## 具体技术实现

### 关键流程

1. **事件重放流程**：
   ```
   replay_initial_messages([
       TurnStarted { turn_id: "turn-1", ... },
       StreamError { message: "Reconnecting... 2/5", ... }
   ])
   ↓
   处理重放事件（标记为历史事件）
   ↓
   render_bottom_first_row(&chat, 80)
   ↓
   验证：不包含 "Reconnecting" 和 "Working"
   ```

2. **历史事件处理**：
   - 重放的事件被特殊标记，不应触发活动状态更新
   - `StreamError` 事件在重放时不应激活状态指示器
   - 页脚应显示默认的输入提示状态

### 数据结构

```rust
pub struct TurnStartedEvent {
    pub turn_id: String,
    pub model_context_window: Option<u32>,
    pub collaboration_mode_kind: ModeKind,
}

pub struct StreamErrorEvent {
    pub message: String,
    pub codex_error_info: Option<CodexErrorInfo>,
    pub additional_details: Option<String>,
}

pub enum EventMsg {
    TurnStarted(TurnStartedEvent),
    StreamError(StreamErrorEvent),
    // ...
}
```

### 测试断言

```rust
let header = render_bottom_first_row(&chat, 80);
assert!(
    !header.contains("Reconnecting") && !header.contains("Working"),
    "expected replayed interrupted reconnect to avoid active status row, got {header:?}"
);
```

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui/src/chatwidget/tests.rs` | 测试定义（tui，line ~10426） |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试定义（tui_app_server，line ~11158） |
| `codex-rs/tui/src/chatwidget.rs` | `replay_initial_messages()` 和事件处理实现 |
| `codex-rs/tui/src/bottom_pane/mod.rs` | 页脚渲染实现 |

### 关键函数

- `ChatWidget::replay_initial_messages()` - 重放初始消息序列
- `ChatWidget::handle_codex_event()` - 处理 Codex 事件
- `render_bottom_first_row()` - 测试辅助函数，渲染页脚第一行
- `BottomPane::render()` - 渲染页脚

### 相关测试

```rust
// codex-rs/tui/src/chatwidget/tests.rs
#[tokio::test]
async fn replayed_interrupted_reconnect_footer_row_snapshot() {
    let (mut chat, _rx, _op_rx) = make_chatwidget_manual(None).await;

    chat.replay_initial_messages(vec![
        EventMsg::TurnStarted(TurnStartedEvent {
            turn_id: "turn-1".to_string(),
            model_context_window: None,
            collaboration_mode_kind: ModeKind::Default,
        }),
        EventMsg::StreamError(StreamErrorEvent {
            message: "Reconnecting... 2/5".to_string(),
            codex_error_info: Some(CodexErrorInfo::Other),
            additional_details: Some("Idle timeout waiting for SSE".to_string()),
        }),
    ]);

    let header = render_bottom_first_row(&chat, 80);
    assert!(
        !header.contains("Reconnecting") && !header.contains("Working"),
        "expected replayed interrupted reconnect to avoid active status row, got {header:?}"
    );
    assert_snapshot!("replayed_interrupted_reconnect_footer_row", header);
}
```

## 依赖与外部交互

### 内部依赖

- `EventMsg`, `TurnStartedEvent`, `StreamErrorEvent` - 事件结构
- `ModeKind` - 协作模式类型
- `CodexErrorInfo` - 错误信息类型
- `render_bottom_first_row()` - 测试辅助函数

### 外部交互

- **会话恢复**：从持久化存储恢复会话时重放历史事件
- **事件系统**：区分实时事件和重放事件
- **UI 渲染**：页脚状态的正确渲染

## 风险、边界与改进建议

### 潜在风险

1. **状态泄漏**：重放事件可能意外激活当前状态
2. **事件顺序**：事件重放顺序可能影响状态恢复
3. **并发问题**：重放期间的新事件可能与重放事件冲突

### 边界情况

- 多个连续的重新连接事件
- 重放事件与实时事件的交错
- 会话恢复失败后的回退处理
- 部分事件重放（网络中断导致）

### 改进建议

1. **事件处理增强**：
   - 添加明确的历史事件标记机制
   - 实现事件重放的隔离环境
   - 添加重放完成后的状态验证

2. **测试覆盖**：
   - 添加更多重放场景的测试
   - 测试重放与实时事件的交互
   - 测试会话恢复失败的处理

3. **调试支持**：
   - 添加重放事件的日志记录
   - 提供会话恢复状态的可视化指示

---

**快照内容**：
```
› Ask Codex to do anything
```

**说明**：显示重放中断重新连接事件后的页脚行。关键点是页脚只显示默认的输入提示符 `› Ask Codex to do anything`，而不包含 "Reconnecting" 或 "Working" 状态指示。这验证了历史事件不会错误地激活当前状态指示器。
