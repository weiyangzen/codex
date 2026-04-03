# 研究文档：unified_exec_wait_before_streamed_agent_message

## 场景与职责

此 snapshot 测试验证流式代理消息前的执行等待状态。测试场景包括：
- 任务开始（`TurnStarted`）
- 统一执行启动（`cargo test -p codex-core`）
- 终端交互（空输入）
- 流式代理消息增量（"Streaming response."）
- 任务完成（`TurnComplete`，无最终消息）
- 验证历史记录中等待事件在流式响应之前

该测试确保当 AI 响应是流式传输时，等待事件能够正确显示在流式内容之前。

## 功能点目的

流式代理消息前的等待状态是 TUI 中处理实时 AI 响应和后台操作的关键机制：
1. **流式体验**：支持 AI 响应的实时流式显示，提升用户体验
2. **后台同步**：确保后台操作状态与流式响应正确同步
3. **时序保真**：保持事件发生的真实时序，即使响应是流式的
4. **状态可见**：在 AI 开始响应前，后台等待状态仍然可见
5. **交互完整**：记录完整的用户-后台交互历史

这种设计确保了流式 AI 体验与后台操作管理的无缝集成。

## 具体技术实现

### 测试设置
```rust
let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;

// 1. 任务开始
chat.handle_codex_event(Event {
    id: "turn-1".into(),
    msg: EventMsg::TurnStarted(TurnStartedEvent {
        turn_id: "turn-1".to_string(),
        model_context_window: None,
        collaboration_mode_kind: ModeKind::Default,
    }),
});

// 2. 开始统一执行
begin_unified_exec_startup(
    &mut chat, 
    "call-wait-stream", 
    "proc-1", 
    "cargo test -p codex-core"
);

// 3. 终端交互（空输入 - 等待）
terminal_interaction(&mut chat, "call-wait-stream-stdin", "proc-1", "");

// 4. 流式代理消息增量
chat.handle_codex_event(Event {
    id: "turn-1".into(),
    msg: EventMsg::AgentMessageDelta(AgentMessageDeltaEvent {
        delta: "Streaming response.".into(),
    }),
});

// 5. 任务完成（无最终消息）
chat.handle_codex_event(Event {
    id: "turn-1".into(),
    msg: EventMsg::TurnComplete(TurnCompleteEvent {
        turn_id: "turn-1".to_string(),
        last_agent_message: None,  // 无最终消息
    }),
});
```

### 渲染输出格式
```
• Waited for background terminal · cargo test -p codex-core

• Streaming response.
```

格式解析：
- 第一组：等待事件
  - `• Waited for background terminal`：等待事件标记
  - `· cargo test -p codex-core`：等待的后台命令
- 空行：分隔不同事件
- 第二组：流式响应
  - `• Streaming response.`：AI 的流式响应内容

### 流式 vs 非流式对比
```
流式响应（本测试）：              非流式响应（前一测试）：
├─ TurnStarted                   ├─ TurnStarted
├─ begin_unified_exec_startup    ├─ begin_unified_exec_startup
├─ terminal_interaction          ├─ terminal_interaction
├─ AgentMessageDelta (流式)      ├─ complete_assistant_message (完整)
├─ TurnComplete (无最终消息)      ├─ TurnComplete (有最终消息)
│                                │
└─ 历史记录：                     └─ 历史记录：
   ├─ Waited                        ├─ Waited
   └─ Streaming response.           └─ Final response.
```

## 关键代码路径与文件引用

### 核心实现文件
1. **`codex-rs/tui/src/chatwidget/mod.rs`**（或等效文件）
   - 实现 `on_agent_message_delta` 方法
   - 处理 `AgentMessageDeltaEvent` 流式事件
   - 管理流式单元格的创建和更新

2. **`codex-rs/tui/src/history_cell/streaming_cell.rs`**（流式单元格实现）
   - 实现流式消息单元格的渲染
   - 处理增量内容的追加显示

3. **`codex-rs/tui/src/chatwidget/tests.rs`**（行 5231-5270）
   - 测试函数 `unified_exec_wait_before_streamed_agent_message_snapshot`
   - 验证流式响应前的等待状态显示

### 相关数据结构
```rust
// AgentMessageDeltaEvent - 代理消息增量事件
pub struct AgentMessageDeltaEvent {
    pub delta: String,  // 增量文本内容
}

// TurnCompleteEvent - 任务完成事件
pub struct TurnCompleteEvent {
    pub turn_id: String,
    pub last_agent_message: Option<String>, // 本测试中为 None
}

// 流式单元格（概念性）
struct StreamingCell {
    content: String,        // 累积的内容
    is_complete: bool,      // 是否完成
    source: StreamingSource,
}
```

### 流式处理流程
```
AgentMessageDeltaEvent
    ↓
创建/更新 StreamingCell
    ↓
实时渲染增量内容
    ↓
TurnComplete (last_agent_message = None)
    ↓
最终化 StreamingCell
    ↓
发送 InsertHistoryCell 事件
    ├─ Waited 单元格（来自空交互）
    └─ StreamingCell（转为普通消息单元格）
```

## 依赖与外部交互

### 内部依赖
| 模块 | 用途 |
|------|------|
| `chatwidget` | 流式事件处理和状态管理 |
| `history_cell::streaming` | 流式单元格实现 |
| `bottom_pane` | 统一执行状态管理 |

### 事件依赖
- `TurnStartedEvent`：任务开始
- `AgentMessageDeltaEvent`：流式消息增量
- `TerminalInteractionEvent`：终端交互
- `TurnCompleteEvent`：任务完成

### 流式 vs 完整消息
```rust
// 流式消息（本测试）
AgentMessageDeltaEvent { delta: "Streaming response." }
// → 实时显示，累积到 StreamingCell

// 完整消息（前一测试）
ItemCompletedEvent { item: TurnItem::AgentMessage(...) }
// → 直接创建完整的消息单元格
```

## 风险、边界与改进建议

### 潜在风险
1. **流式延迟**：流式响应的延迟可能导致等待事件显示时间过长
2. **内容截断**：流式内容过长时可能需要截断或分页
3. **状态竞争**：流式更新和后台状态更新可能产生竞争条件

### 边界情况
1. **空流式内容**：`delta` 为空字符串时的处理
2. **快速流式**：大量快速的增量事件可能导致渲染性能问题
3. **流式中断**：流式响应被中断时的状态处理
4. **混合模式**：流式和非流式消息混合的场景

### 改进建议
1. **流式指示器**：显示流式传输进行中的动画指示器
2. **缓冲控制**：允许用户暂停/恢复流式显示
3. **速率限制**：对快速流式事件进行速率限制，避免渲染过载
4. **智能换行**：流式内容的长行智能换行处理
5. **搜索支持**：流式完成后支持内容搜索
6. **复制功能**：提供快捷方式复制流式内容

### 相关测试
- `unified_exec_wait_before_streamed_agent_message_snapshot`：本测试文件
- `unified_exec_wait_after_final_agent_message_snapshot`：最终响应后等待测试
- `stream_recovery_restores_previous_status_header`：流式恢复测试
