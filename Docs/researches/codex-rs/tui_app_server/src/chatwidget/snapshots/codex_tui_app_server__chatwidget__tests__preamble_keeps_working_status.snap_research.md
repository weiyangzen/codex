# 序言保持工作状态测试研究文档

## 场景与职责

该 snapshot 测试验证当 AI 助手输出序言（preamble）内容时，tui_app_server 的 ChatWidget 能够正确保持"Working"状态指示器的显示，确保用户知道系统仍在处理中。

**测试场景**：
1. 任务已开始运行
2. AI 输出了序言内容（Commentary 阶段的文本）
3. 序言被提交到历史记录
4. 状态指示器应该恢复并继续显示"Working"

**职责**：确保在序言内容输出后，用户仍然清楚系统处于工作状态，避免误以为任务已完成。

## 功能点目的

- **状态连续性**：在序言输出后保持工作状态指示
- **用户反馈**：持续告知用户系统正在处理
- **防止误解**：避免用户因看到内容输出而误以为任务结束
- **视觉一致性**：保持 UI 状态与实际处理状态一致

## 具体技术实现

### 测试代码位置
`codex-rs/tui_app_server/src/chatwidget/tests.rs` 第 3968-3992 行

```rust
#[tokio::test]
async fn preamble_keeps_working_status_snapshot() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    chat.thread_id = Some(ThreadId::new());

    // Regression sequence: a preamble line is committed to history before any exec/tool event.
    // After commentary completes, the status row should be restored before subsequent work.
    chat.on_task_started();
    chat.on_agent_message_delta("Preamble line\n".to_string());
    chat.on_commit_tick();
    drain_insert_history(&mut rx);
    complete_assistant_message(
        &mut chat,
        "msg-commentary-snapshot",
        "Preamble line\n",
        Some(MessagePhase::Commentary),
    );

    let height = chat.desired_height(80);
    let mut terminal = ratatui::Terminal::new(ratatui::backend::TestBackend::new(80, height))
        .expect("create terminal");
    terminal
        .draw(|f| chat.render(f.area(), f.buffer_mut()))
        .expect("draw preamble + status widget");
    assert_snapshot!("preamble_keeps_working_status", terminal.backend());
}
```

### 关键实现细节

1. **初始化 ChatWidget**：
   - 使用 `make_chatwidget_manual` 创建测试实例
   - 设置线程 ID 模拟活跃会话

2. **模拟任务开始**：
   - 调用 `on_task_started()` 标记任务开始
   - 状态指示器变为可见

3. **模拟序言输出**：
   - `on_agent_message_delta`：添加序言文本增量
   - `on_commit_tick()`：触发提交，将序言内容写入历史
   - `drain_insert_history`：清空历史记录通道

4. **完成序言消息**：
   - `complete_assistant_message`：标记序言消息完成
   - 指定 `MessagePhase::Commentary` 表明这是序言/评论阶段

5. **渲染验证**：
   - 使用 `desired_height` 获取推荐高度
   - 创建 ratatui 测试终端
   - 渲染 ChatWidget 并捕获 snapshot

### Snapshot 输出内容

```
"                                                                                "
"• Working (0s • esc to interrupt)                                               "
"                                                                                "
"                                                                                "
"› Ask Codex to do anything                                                      "
"                                                                                "
"  ? for shortcuts                                            100% context left  "
```

关键元素：
- `• Working (0s • esc to interrupt)`：工作状态指示器
- `› Ask Codex to do anything`：输入提示
- `100% context left`：上下文窗口使用百分比

## 关键代码路径与文件引用

### 主要代码文件

1. **测试文件**：`codex-rs/tui_app_server/src/chatwidget/tests.rs`
   - 测试函数：`preamble_keeps_working_status_snapshot` (第 3968 行)
   - 辅助函数：`complete_assistant_message`, `drain_insert_history`

2. **ChatWidget 实现**：`codex-rs/tui_app_server/src/chatwidget/mod.rs`
   - 方法：`on_task_started`, `on_agent_message_delta`, `on_commit_tick`
   - 状态管理：`status_indicator_visible`, `is_task_running`

3. **底部面板**：`codex-rs/tui_app_server/src/bottom_pane/mod.rs`
   - 状态指示器渲染
   - 任务运行状态管理

4. **消息阶段**：`codex-protocol/src/protocol.rs`
   - `MessagePhase::Commentary`：序言/评论阶段

### 相关协议类型

- `MessagePhase`：消息阶段枚举
  - `Commentary`：评论/序言阶段
  - `Response`：正式响应阶段
- `AgentMessageDeltaEvent`：代理消息增量事件
- `ItemCompletedEvent`：项目完成事件

## 依赖与外部交互

### 内部依赖

| 组件 | 用途 |
|------|------|
| `ChatWidget` | 主聊天组件，管理状态和渲染 |
| `BottomPane` | 渲染状态指示器和输入区域 |
| `StatusIndicator` | 工作状态指示器组件 |
| `HistoryCell` | 历史记录单元格管理 |

### 外部依赖

- `ratatui`：终端 UI 渲染库
- `insta`：snapshot 测试框架
- `tokio`：异步运行时

### 状态转换流程

```
任务开始
    ↓
状态指示器显示 "Working"
    ↓
序言内容流式输出
    ↓
序言提交到历史
    ↓
状态指示器恢复显示
    ↓
后续工作继续...
```

## 风险、边界与改进建议

### 潜在风险

1. **状态闪烁**：序言提交时状态指示器可能短暂消失再出现，造成视觉闪烁
2. **时机问题**：如果序言处理时间过长，用户可能不知道系统仍在工作
3. **状态不同步**：实际任务状态与 UI 状态可能不一致

### 边界情况

1. **空序言**：如果序言内容为空，状态指示器行为
2. **多段序言**：多个序言段落连续输出时的状态处理
3. **中断**：用户在序言输出时中断任务的状态处理
4. **错误**：序言处理过程中发生错误的状态恢复

### 改进建议

1. **平滑过渡**：添加状态指示器的淡入淡出效果，避免闪烁
2. **进度指示**：对于长序言，显示处理进度
3. **阶段标识**：在状态指示器中显示当前处理阶段（如"Analyzing..."）
4. **时间估算**：根据历史数据估算剩余处理时间
5. **取消确认**：用户尝试中断时，确认是否真的要取消

### 相关测试

- `commentary_completion_restores_status_indicator_before_exec_begin`：评论完成后恢复状态指示器
- `plan_completion_restores_status_indicator_after_streaming_plan_output`：计划完成后恢复状态指示器
- `streaming_final_answer_keeps_task_running_state`：流式输出保持任务运行状态
- `idle_commit_ticks_do_not_restore_status_without_commentary_completion`：空闲提交不恢复状态

### 性能考虑

1. **渲染频率**：避免过于频繁的重新渲染
2. **缓冲区管理**：合理管理消息增量缓冲区
3. **内存使用**：及时清理已完成的历史记录单元格

### 用户体验优化

1. **动画效果**：为状态指示器添加微妙的动画，表明系统活跃
2. **声音反馈**：可选的声音提示，在状态变化时通知用户
3. **快捷键提示**：显示中断快捷键（esc）提示，让用户知道如何取消
