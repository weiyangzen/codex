# send_input.rs 研究文档

## 场景与职责

`send_input.rs` 实现了 `send_input` 工具的处理器，用于向一个已存在的子代理发送输入。这是多代理协作系统中的核心通信工具，允许父代理与子代理进行交互，传递任务指令或对话消息。

在多代理协作场景中，父代理可以通过 `send_input` 向子代理发送文本消息或结构化输入项（如提及、图片等），驱动子代理执行特定任务。该工具还支持可选的中断功能，可以在发送新输入前先中断子代理的当前操作。

## 功能点目的

1. **向子代理发送输入**：支持发送文本消息或结构化输入项（`UserInput`）
2. **可选中断**：在发送输入前可选择性地中断子代理的当前操作
3. **输入验证**：验证输入格式，确保消息和 items 不会同时提供
4. **事件通知**：通过 `CollabAgentInteractionBeginEvent` 和 `CollabAgentInteractionEndEvent` 通知交互的开始和结束
5. **返回提交 ID**：返回输入提交的 ID，用于追踪和关联响应

## 具体技术实现

### 关键数据结构

```rust
// 发送输入的参数
#[derive(Debug, Deserialize)]
struct SendInputArgs {
    id: String,                      // 目标代理的线程 ID
    message: Option<String>,         // 文本消息（与 items 互斥）
    items: Option<Vec<UserInput>>,   // 结构化输入项（与 message 互斥）
    #[serde(default)]
    interrupt: bool,                 // 是否在发送前中断
}

// 发送操作的结果
#[derive(Debug, Serialize)]
pub(crate) struct SendInputResult {
    submission_id: String,  // 输入提交的 ID
}
```

### 关键流程

1. **参数解析与验证**：
   - 解析 `SendInputArgs`
   - 验证代理 ID 格式
   - 调用 `parse_collab_input` 验证 message 和 items 的互斥性

2. **获取代理信息**：
   - 通过 `get_agent_nickname_and_role` 获取目标代理的昵称和角色

3. **可选中断**：
   - 如果 `interrupt` 为 `true`，先调用 `interrupt_agent` 中断子代理
   - 中断失败会返回错误

4. **发送开始事件**：
   - 发送 `CollabAgentInteractionBeginEvent`，包含调用 ID、双方线程 ID 和输入预览

5. **发送输入**：
   - 调用 `AgentControl::send_input` 发送输入项
   - 获取提交 ID

6. **查询状态并发送结束事件**：
   - 查询代理当前状态
   - 发送 `CollabAgentInteractionEndEvent`，包含状态信息

7. **返回结果**：
   - 返回 `SendInputResult`，包含提交 ID

### 输入解析逻辑

`parse_collab_input` 函数（定义在 `multi_agents.rs`）：

```rust
fn parse_collab_input(
    message: Option<String>,
    items: Option<Vec<UserInput>>,
) -> Result<Vec<UserInput>, FunctionCallError> {
    match (message, items) {
        // 错误：同时提供 message 和 items
        (Some(_), Some(_)) => Err(...),
        // 错误：两者都未提供
        (None, None) => Err(...),
        // 文本消息模式
        (Some(message), None) => {
            if message.trim().is_empty() {
                return Err(...);  // 空消息错误
            }
            Ok(vec![UserInput::Text { text: message, text_elements: Vec::new() }])
        }
        // 结构化输入模式
        (None, Some(items)) => {
            if items.is_empty() {
                return Err(...);  // 空 items 错误
            }
            Ok(items)
        }
    }
}
```

### 输入预览生成

`input_preview` 函数生成用于事件通知的输入预览：
- `UserInput::Text`：直接返回文本内容
- `UserInput::Image`：返回 `[image]` 占位符
- `UserInput::LocalImage`：返回 `[local_image:path]`
- `UserInput::Skill`：返回 `[skill:name](path)`
- `UserInput::Mention`：返回 `[mention:name](path)`
- 其他：返回 `[input]`

## 关键代码路径与文件引用

### 当前文件
- `/home/sansha/Github/codex/codex-rs/core/src/tools/handlers/multi_agents/send_input.rs` - 本文件

### 依赖文件
- `/home/sansha/Github/codex/codex-rs/core/src/tools/handlers/multi_agents.rs` - 父模块，提供输入解析和预览函数
- `/home/sansha/Github/codex/codex-rs/core/src/tools/registry.rs` - 工具注册表
- `/home/sansha/Github/codex/codex-rs/core/src/agent/control.rs` - `AgentControl`，提供 `send_input` 和 `interrupt_agent`
- `/home/sansha/Github/codex/codex-rs/protocol/src/protocol.rs` - 协议事件定义
- `/home/sansha/Github/codex/codex-rs/protocol/src/user_input.rs` - `UserInput` 类型定义

### 调用链
```
ToolRegistry::dispatch_any()
  -> SendInputHandler::handle()
    -> parse_collab_input()  // 解析和验证输入
    -> AgentControl::interrupt_agent()  // 可选中断
    -> Session::send_event()  // 发送开始事件
    -> AgentControl::send_input()  // 发送输入
    -> AgentControl::get_status()  // 查询状态
    -> Session::send_event()  // 发送结束事件
```

## 依赖与外部交互

### 服务依赖
- `session.services.agent_control`：用于发送输入和中断代理
- `session.send_event`：发送事件通知

### 输入类型
`UserInput` 枚举支持多种输入类型：
- `Text`：纯文本消息
- `Image`：图片（URL）
- `LocalImage`：本地图片路径
- `Skill`：技能引用
- `Mention`：提及（如应用、文件等）

### 事件类型
- `CollabAgentInteractionBeginEvent`：交互开始，包含输入预览
- `CollabAgentInteractionEndEvent`：交互结束，包含代理状态

### 中断机制
中断通过 `AgentControl::interrupt_agent` 实现，发送 `Op::Interrupt` 操作到子代理，使其停止当前执行。

## 风险、边界与改进建议

### 边界情况

1. **空输入**：空消息或空 items 列表会被拒绝
2. **互斥参数**：同时提供 `message` 和 `items` 会导致错误
3. **代理不存在**：如果目标代理不存在，`send_input` 会返回错误
4. **中断失败**：如果中断操作失败，整个 `send_input` 操作会失败

### 风险点

1. **竞态条件**：在发送输入前代理状态可能发生变化（如刚好完成执行）
2. **输入顺序**：如果多个父代理同时向同一子代理发送输入，顺序可能不确定
3. **中断副作用**：强制中断可能导致子代理丢失未保存的状态
4. **输入大小限制**：大输入项可能导致内存或传输问题

### 改进建议

1. **输入队列**：为子代理实现输入队列，确保输入按顺序处理
2. **输入确认**：添加输入确认机制，确保子代理已接收并处理输入
3. **批量发送**：支持一次发送多个输入项，减少往返开销
4. **输入优先级**：添加优先级机制，允许紧急输入插队处理
5. **输入超时**：为输入处理添加超时，避免无限期等待
6. **输入重试**：在发送失败时支持自动重试
7. **输入历史**：提供查询子代理输入历史的功能

### 测试覆盖

测试文件：`/home/sansha/Github/codex/codex-rs/core/src/tools/handlers/multi_agents_tests.rs`

相关测试：
- `send_input_rejects_empty_message`：验证空消息被拒绝
- `send_input_rejects_when_message_and_items_are_both_set`：验证互斥参数检查
- `send_input_rejects_invalid_id`：验证无效 ID 被拒绝
- `send_input_reports_missing_agent`：验证缺失代理的报告
- `send_input_interrupts_before_prompt`：验证中断功能
- `send_input_accepts_structured_items`：验证结构化输入项
