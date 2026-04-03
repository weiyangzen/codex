# Research: App Server Collab Wait Items Render History

## 场景与职责

该 snapshot 测试验证当 App Server 中的协作代理等待（Wait）操作完成时，TUI 正确显示等待的代理列表及其完成状态。

**测试场景：**
- 主代理等待多个子代理完成
- 子代理有不同的完成状态（Completed、Running）
- 验证等待开始和完成的历史记录显示

**核心职责：**
1. 确保协作代理等待事件的正确处理
2. 验证多个代理状态的聚合显示
3. 确保等待完成后的状态摘要正确

---

## 功能点目的

### 1. 协作代理等待（CollabAgent Wait）
`CollabAgentTool::Wait` 用于主代理等待子代理完成：
- 指定要等待的代理 ID 列表
- 跟踪每个代理的完成状态
- 当所有代理完成或超时后返回

### 2. 多代理状态聚合
当等待多个代理时，需要：
- 显示等待的代理数量
- 列出每个代理的 ID
- 显示每个代理的完成状态和消息

### 3. 历史记录渲染
等待操作的历史记录显示：
- 等待开始：显示等待的代理列表
- 等待完成：显示每个代理的最终状态

---

## 具体技术实现

### 测试代码路径
**文件**: `codex-rs/tui_app_server/src/chatwidget/tests.rs`  
**函数**: `live_app_server_collab_wait_items_render_history`

```rust
#[tokio::test]
async fn live_app_server_collab_wait_items_render_history() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    let sender_thread_id =
        ThreadId::from_string("019cff70-2599-75e2-af72-b90000000001").expect("valid thread id");
    let receiver_thread_id =
        ThreadId::from_string("019cff70-2599-75e2-af72-b958ce5dc1cc").expect("valid thread id");
    let other_receiver_thread_id =
        ThreadId::from_string("019cff70-2599-75e2-af72-b96db334332d").expect("valid thread id");

    // 1. 发送等待开始通知
    chat.handle_server_notification(
        ServerNotification::ItemStarted(ItemStartedNotification {
            thread_id: "thread-1".to_string(),
            turn_id: "turn-1".to_string(),
            item: AppServerThreadItem::CollabAgentToolCall {
                id: "wait-1".to_string(),
                tool: AppServerCollabAgentTool::Wait,
                status: AppServerCollabAgentToolCallStatus::InProgress,
                sender_thread_id: sender_thread_id.to_string(),
                receiver_thread_ids: vec![
                    receiver_thread_id.to_string(),
                    other_receiver_thread_id.to_string(),
                ],
                prompt: None,
                model: None,
                reasoning_effort: None,
                agents_states: HashMap::new(),
            },
        }),
        None,
    );

    // 2. 发送等待完成通知
    chat.handle_server_notification(
        ServerNotification::ItemCompleted(ItemCompletedNotification {
            thread_id: "thread-1".to_string(),
            turn_id: "turn-1".to_string(),
            item: AppServerThreadItem::CollabAgentToolCall {
                id: "wait-1".to_string(),
                tool: AppServerCollabAgentTool::Wait,
                status: AppServerCollabAgentToolCallStatus::Completed,
                sender_thread_id: sender_thread_id.to_string(),
                receiver_thread_ids: vec![
                    receiver_thread_id.to_string(),
                    other_receiver_thread_id.to_string(),
                ],
                prompt: None,
                model: None,
                reasoning_effort: None,
                agents_states: HashMap::from([
                    (
                        receiver_thread_id.to_string(),
                        AppServerCollabAgentState {
                            status: AppServerCollabAgentStatus::Completed,
                            message: Some("Done".to_string()),
                        },
                    ),
                    (
                        other_receiver_thread_id.to_string(),
                        AppServerCollabAgentState {
                            status: AppServerCollabAgentStatus::Running,
                            message: None,
                        },
                    ),
                ]),
            },
        }),
        None,
    );

    // 3. 验证历史记录
    let combined = drain_insert_history(&mut rx)
        .into_iter()
        .map(|lines| lines_to_single_string(&lines))
        .collect::<Vec<_>>()
        .join("\n");
    assert_snapshot!("app_server_collab_wait_items_render_history", combined);
}
```

### 关键实现组件

#### 1. Wait 工具处理
在 `on_collab_agent_tool_call` 中处理 Wait 工具：

```rust
CollabAgentTool::Wait => {
    if matches!(status, CollabAgentToolCallStatus::InProgress) {
        // 等待开始
        self.on_collab_event(multi_agents::waiting_begin(
            codex_protocol::protocol::CollabWaitingBeginEvent {
                sender_thread_id,
                receiver_thread_ids: receiver_thread_ids
                    .iter()
                    .filter_map(|thread_id| {
                        app_server_collab_thread_id_to_core(thread_id)
                    })
                    .collect(),
                receiver_agents: Vec::new(),
            },
        ));
    } else {
        // 等待结束
        self.on_collab_event(multi_agents::waiting_end(
            codex_protocol::protocol::CollabWaitingEndEvent {
                sender_thread_id,
                receiver_thread_ids: receiver_thread_ids
                    .iter()
                    .filter_map(|thread_id| {
                        app_server_collab_thread_id_to_core(thread_id)
                    })
                    .collect(),
                agent_results: agents_states
                    .iter()
                    .filter_map(|(thread_id, state)| {
                        app_server_collab_thread_id_to_core(thread_id)
                            .map(|id| (id, state.clone()))
                    })
                    .collect(),
            },
        ));
    }
}
```

#### 2. 代理状态转换
```rust
fn app_server_collab_thread_id_to_core(
    thread_id: &str,
) -> Option<codex_protocol::ThreadId> {
    codex_protocol::ThreadId::from_string(thread_id).ok()
}

fn app_server_collab_agent_status_to_core(
    status: AppServerCollabAgentStatus,
) -> codex_protocol::protocol::CollabAgentStatus {
    match status {
        AppServerCollabAgentStatus::PendingInit => 
            codex_protocol::protocol::CollabAgentStatus::PendingInit,
        AppServerCollabAgentStatus::Running => 
            codex_protocol::protocol::CollabAgentStatus::Running,
        // ... 其他状态
    }
}
```

#### 3. 历史记录创建
```rust
// 等待开始历史记录
fn waiting_begin(event: CollabWaitingBeginEvent) -> CollabEvent {
    CollabEvent::WaitingBegin(event)
}

// 等待结束历史记录
fn waiting_end(event: CollabWaitingEndEvent) -> CollabEvent {
    CollabEvent::WaitingEnd(event)
}
```

---

## 关键代码路径与文件引用

### 核心文件

| 文件路径 | 职责 |
|---------|------|
| `codex-rs/tui_app_server/src/chatwidget.rs` | ChatWidget 主实现 |
| `codex-rs/tui_app_server/src/chatwidget/tests.rs` | 测试代码 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | App Server 协议定义 |
| `codex-rs/tui/src/multi_agents.rs` | 多代理协作事件 |
| `codex-rs/tui/src/history_cell.rs` | 历史记录单元格 |

### 关键函数

| 函数 | 位置 | 职责 |
|-----|------|------|
| `on_collab_agent_tool_call` | `chatwidget.rs:3301` | 处理协作代理工具调用 |
| `waiting_begin` | `multi_agents.rs` | 创建等待开始事件 |
| `waiting_end` | `multi_agents.rs` | 创建等待结束事件 |
| `app_server_collab_thread_id_to_core` | `chatwidget.rs` | 线程 ID 转换 |

### App Server 协议类型

| 类型 | 定义位置 | 说明 |
|-----|---------|------|
| `CollabAgentTool::Wait` | `app-server-protocol/src/protocol/v2.rs:4458` | 等待工具 |
| `CollabAgentStatus` | `app-server-protocol/src/protocol/v2.rs:4538` | 代理状态枚举 |
| `CollabAgentState` | `app-server-protocol/src/protocol/v2.rs` | 代理状态结构 |

### 代理状态

| 状态 | 说明 |
|-----|------|
| `PendingInit` | 等待初始化 |
| `Running` | 运行中 |
| `Interrupted` | 已中断 |
| `Completed` | 已完成 |
| `Errored` | 出错 |
| `Shutdown` | 已关闭 |
| `NotFound` | 未找到 |

---

## 依赖与外部交互

### 内部依赖

```
tui_app_server/src/chatwidget.rs
├── app-server-protocol/src/protocol/v2.rs
├── tui/src/multi_agents.rs
├── tui/src/history_cell.rs
└── codex-protocol/src/protocol.rs
```

### 事件转换流程

```
App Server Notification
    ↓ ItemStarted/ItemCompleted
ChatWidget::handle_server_notification
    ↓ ThreadItem::CollabAgentToolCall
ChatWidget::on_collab_agent_tool_call
    ↓ CollabAgentTool::Wait
    ↓ 状态转换
    ↓ multi_agents::waiting_begin/waiting_end
    ↓ CollabEvent
    ↓ 历史记录单元格
```

---

## 风险、边界与改进建议

### 潜在风险

1. **代理状态不一致**
   - 网络延迟可能导致状态更新不及时
   - **缓解**: 实现状态同步确认机制

2. **大量代理等待**
   - 等待大量代理可能导致 UI 性能问题
   - **缓解**: 实现虚拟列表或分页显示

3. **代理 ID 解析失败**
   - 无效的线程 ID 可能导致转换失败
   - **缓解**: 添加错误处理和日志记录

### 边界情况

| 场景 | 行为 |
|-----|------|
| 等待 0 个代理 | 立即完成 |
| 代理状态未知 | 显示为 Running |
| 等待超时 | 显示超时状态 |
| 代理提前终止 | 显示实际终止状态 |
| 重复等待通知 | 去重处理 |

### 改进建议

1. **添加等待进度显示**
   - 显示已完成/总代理数量

2. **支持代理分组**
   - 按状态分组显示代理

3. **添加等待取消功能**
   - 允许用户取消长时间等待

4. **改进状态图标**
   - 使用不同图标表示不同状态

5. **添加代理详情链接**
   - 点击代理 ID 查看详细信息

---

## Snapshot 内容分析

```
• Waiting for 2 agents
  └ 019cff70-2599-75e2-af72-b958ce5dc1cc
    019cff70-2599-75e2-af72-b96db334332d


• Finished waiting
  └ 019cff70-2599-75e2-af72-b958ce5dc1cc: Completed - Done
    019cff70-2599-75e2-af72-b96db334332d: Running
```

**观察要点：**

**等待开始：**
1. 使用 "Waiting for 2 agents" 显示等待代理数量
2. 列出所有等待的代理 ID
3. 使用树形结构缩进显示

**等待完成：**
1. 使用 "Finished waiting" 表示等待结束
2. 每个代理显示 ID + 状态 + 消息
3. 不同代理可能有不同状态（Completed vs Running）
4. 状态消息（如 "Done"）提供额外上下文

**信息层次：**
- 第一行：操作和数量/状态
- 后续行：代理详情列表
