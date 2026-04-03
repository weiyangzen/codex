# Research: App Server Collab Spawn Completed Renders Requested Model and Effort

## 场景与职责

该 snapshot 测试验证当 App Server 中的协作代理（Collab Agent）生成完成时，TUI 正确显示代理的 ID、模型和推理级别信息。

**测试场景：**
- 主代理生成（Spawn）了一个子代理
- 子代理使用指定的模型（gpt-5）和推理级别（high）
- 生成完成后，历史记录显示代理 ID 和配置信息

**核心职责：**
1. 确保协作代理生成事件的正确处理
2. 验证代理 ID、模型和推理级别的正确显示
3. 确保 App Server 协议与 TUI 的集成正确

---

## 功能点目的

### 1. 多代理协作（Multi-Agent Collaboration）
Codex 支持多代理协作模式，其中：
- 主代理可以生成（Spawn）子代理
- 每个子代理可以配置不同的模型和推理级别
- 子代理独立执行任务，主代理等待结果

### 2. 代理生成工具（SpawnAgent Tool）
`CollabAgentTool::SpawnAgent` 用于创建新代理：
- 指定提示词（Prompt）
- 选择模型（如 gpt-5）
- 设置推理级别（如 High）

### 3. 生成完成显示
当代理生成完成时，显示：
- 代理 ID（UUID 格式）
- 使用的模型
- 推理级别（effort）
- 提示词摘要

---

## 具体技术实现

### 测试代码路径
**文件**: `codex-rs/tui_app_server/src/chatwidget/tests.rs`  
**函数**: `live_app_server_collab_spawn_completed_renders_requested_model_and_effort`

```rust
#[tokio::test]
async fn live_app_server_collab_spawn_completed_renders_requested_model_and_effort() {
    let (mut chat, mut rx, _op_rx) = make_chatwidget_manual(None).await;
    let sender_thread_id =
        ThreadId::from_string("019cff70-2599-75e2-af72-b90000000002").expect("valid thread id");
    let spawned_thread_id =
        ThreadId::from_string("019cff70-2599-75e2-af72-b91781b41a8e").expect("valid thread id");

    // 1. 发送 ItemStarted 通知（生成开始）
    chat.handle_server_notification(
        ServerNotification::ItemStarted(ItemStartedNotification {
            thread_id: "thread-1".to_string(),
            turn_id: "turn-1".to_string(),
            item: AppServerThreadItem::CollabAgentToolCall {
                id: "spawn-1".to_string(),
                tool: AppServerCollabAgentTool::SpawnAgent,
                status: AppServerCollabAgentToolCallStatus::InProgress,
                sender_thread_id: sender_thread_id.to_string(),
                receiver_thread_ids: Vec::new(),
                prompt: Some("Explore the repo".to_string()),
                model: Some("gpt-5".to_string()),
                reasoning_effort: Some(ReasoningEffortConfig::High),
                agents_states: HashMap::new(),
            },
        }),
        None,
    );

    // 2. 发送 ItemCompleted 通知（生成完成）
    chat.handle_server_notification(
        ServerNotification::ItemCompleted(ItemCompletedNotification {
            thread_id: "thread-1".to_string(),
            turn_id: "turn-1".to_string(),
            item: AppServerThreadItem::CollabAgentToolCall {
                id: "spawn-1".to_string(),
                tool: AppServerCollabAgentTool::SpawnAgent,
                status: AppServerCollabAgentToolCallStatus::Completed,
                sender_thread_id: sender_thread_id.to_string(),
                receiver_thread_ids: vec![spawned_thread_id.to_string()],
                prompt: Some("Explore the repo".to_string()),
                model: Some("gpt-5".to_string()),
                reasoning_effort: Some(ReasoningEffortConfig::High),
                agents_states: HashMap::from([(
                    spawned_thread_id.to_string(),
                    AppServerCollabAgentState {
                        status: AppServerCollabAgentStatus::PendingInit,
                        message: None,
                    },
                )]),
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
    assert_snapshot!(
        "app_server_collab_spawn_completed_renders_requested_model_and_effort",
        combined
    );
}
```

### 关键实现组件

#### 1. App Server 协议类型
```rust
// CollabAgentTool 枚举
enum CollabAgentTool {
    SpawnAgent,
    SendInput,
    ResumeAgent,
    Wait,
    CloseAgent,
}

// CollabAgentToolCallStatus 枚举
enum CollabAgentToolCallStatus {
    InProgress,
    Completed,
    Failed,
}

// ThreadItem::CollabAgentToolCall 结构
struct CollabAgentToolCall {
    id: String,
    tool: CollabAgentTool,
    status: CollabAgentToolCallStatus,
    sender_thread_id: String,
    receiver_thread_ids: Vec<String>,
    prompt: Option<String>,
    model: Option<String>,
    reasoning_effort: Option<ReasoningEffortConfig>,
    agents_states: HashMap<String, AppServerCollabAgentState>,
}
```

#### 2. 事件处理
在 `chatwidget.rs` 中，`on_collab_agent_tool_call` 方法处理协作代理工具调用：

```rust
fn on_collab_agent_tool_call(&mut self, item: ThreadItem) {
    let ThreadItem::CollabAgentToolCall { tool, status, model, reasoning_effort, ... } = item;
    
    match tool {
        CollabAgentTool::SpawnAgent => {
            if !matches!(status, CollabAgentToolCallStatus::InProgress) {
                // 生成完成，记录模型和推理级别
                let spawn_request = self.pending_collab_spawn_requests.remove(&id)
                    .or_else(|| {
                        model.zip(reasoning_effort).map(|(model, reasoning_effort)| {
                            multi_agents::SpawnRequestSummary {
                                model,
                                reasoning_effort,
                            }
                        })
                    });
                
                // 触发协作事件
                self.on_collab_event(multi_agents::spawn_end(...));
            }
        }
        // ... 其他工具处理
    }
}
```

#### 3. 历史记录创建
使用 `multi_agents` 模块创建协作事件历史记录：
```rust
// 生成结束事件
fn spawn_end(event: CollabAgentSpawnEndEvent) -> CollabEvent {
    CollabEvent::SpawnEnd(event)
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
| `handle_server_notification` | `chatwidget.rs:5804` | 处理服务器通知 |
| `spawn_end` | `multi_agents.rs` | 创建生成结束事件 |
| `drain_insert_history` | `tests.rs` | 测试辅助：获取历史记录 |

### App Server 协议类型

| 类型 | 定义位置 | 说明 |
|-----|---------|------|
| `CollabAgentTool` | `app-server-protocol/src/protocol/v2.rs:4455` | 协作代理工具枚举 |
| `CollabAgentToolCallStatus` | `app-server-protocol/src/protocol/v2.rs:4529` | 工具调用状态 |
| `CollabAgentState` | `app-server-protocol/src/protocol/v2.rs:4548` | 代理状态 |
| `ItemStartedNotification` | `app-server-protocol/src/protocol/v2.rs` | 项目开始通知 |
| `ItemCompletedNotification` | `app-server-protocol/src/protocol/v2.rs` | 项目完成通知 |

---

## 依赖与外部交互

### 内部依赖

```
tui_app_server/src/chatwidget.rs
├── app-server-protocol/src/protocol/v2.rs (协议定义)
├── tui/src/multi_agents.rs (协作事件)
├── tui/src/history_cell.rs (历史记录)
└── codex-protocol/src/protocol.rs (核心协议)
```

### 协议转换

App Server 协议需要转换为内部协议：
```rust
// App Server -> Core Protocol
codex_app_server_protocol::CollabAgentToolCallStatus 
    -> codex_protocol::protocol::CollabAgentSpawnEndEvent
```

### 事件流

```
App Server
    ↓ ServerNotification::ItemStarted
TUI App Server ChatWidget
    ↓ 处理 CollabAgentToolCall
    ↓ 转换为 CollabEvent
    ↓ 创建历史记录单元格
    ↓ AppEvent::InsertHistoryCell
```

---

## 风险、边界与改进建议

### 潜在风险

1. **协议版本不兼容**
   - App Server 协议变更可能导致 TUI 解析失败
   - **缓解**: 使用版本化协议，添加兼容性处理

2. **代理状态丢失**
   - 网络中断可能导致代理状态同步失败
   - **缓解**: 实现状态恢复机制

3. **大量代理并发**
   - 大量代理同时生成可能影响性能
   - **缓解**: 限制并发代理数量

### 边界情况

| 场景 | 行为 |
|-----|------|
| 生成失败 | 显示错误状态 |
| 模型不可用 | 使用默认模型 |
| 无推理级别 | 使用默认级别 |
| 代理 ID 冲突 | 使用最新状态 |
| 重复完成通知 | 去重处理 |

### 改进建议

1. **添加代理状态实时显示**
   - 显示代理的实时运行状态

2. **支持代理嵌套层级显示**
   - 显示代理之间的父子关系

3. **添加代理性能指标**
   - 显示代理执行时间、Token 消耗等

4. **改进代理识别**
   - 支持为代理设置别名，而非仅显示 UUID

5. **添加代理日志查看**
   - 支持查看子代理的详细执行日志

---

## Snapshot 内容分析

```
• Spawned 019cff70-2599-75e2-af72-b91781b41a8e (gpt-5 high)
  └ Explore the repo
```

**观察要点：**
1. 使用 "Spawned" 表示代理生成动作
2. 显示代理 ID（UUID 格式）
3. 在括号中显示模型（gpt-5）和推理级别（high）
4. 提示词作为子行显示
5. 简洁清晰，包含关键配置信息

**信息层次：**
- 第一行：动作 + 代理 ID + 配置
- 第二行：提示词摘要
