# realtime_end.md 深度研究文档

## 文件信息
- **路径**: `codex-rs/protocol/src/prompts/realtime/realtime_end.md`
- **大小**: 223 bytes
- **类型**: Markdown 提示词模板

---

## 一、场景与职责

### 1.1 核心场景
`realtime_end.md` 是 **Realtime Conversation（实时对话）** 功能的结束提示词模板。当用户结束语音交互、切换回文本输入模式时，系统会将此提示词注入到模型上下文中，告知模型实时对话已结束，应恢复正常文本处理模式。

### 1.2 业务场景
- **模式切换**: 用户从语音输入切换回键盘文本输入
- **对话结束**: 用户主动关闭实时对话会话
- **超时/中断**: 实时对话因网络或其他原因中断

### 1.3 职责边界
- 明确告知模型"实时对话已结束"
- 指导模型恢复正常文本处理行为
- 提醒模型不再假设输入是转录文本（可能有识别错误）
- 恢复正常的标点符号和语法期望

---

## 二、功能点目的

### 2.1 功能目标

| 功能点 | 目的 |
|--------|------|
| 状态通知 | 明确告知模型实时对话已结束 |
| 行为恢复 | 指示模型恢复正常聊天行为 |
| 输入假设 | 明确后续输入不再是转录文本，不应假设有识别错误 |
| 标点恢复 | 恢复正常标点符号和语法处理期望 |

### 2.2 提示词内容解析

```markdown
Realtime conversation ended.

Subsequent user input will return to typed text rather than transcript-style text. 
Do not assume recognition errors or missing punctuation once realtime has ended. 
Resume normal chat behavior.
```

内容分解：
1. **"Realtime conversation ended."** - 明确的状态声明
2. **"Subsequent user input will return to typed text..."** - 告知输入类型变化
3. **"Do not assume recognition errors or missing punctuation..."** - 解除转录文本的特殊处理
4. **"Resume normal chat behavior."** - 行为恢复指令

### 2.3 与 realtime_start.md 的对比

| 维度 | realtime_start.md | realtime_end.md |
|------|-------------------|-----------------|
| 触发时机 | 实时对话开始时 | 实时对话结束时 |
| 核心信息 | 你是后端执行器，通过中介层通信 | 实时对话结束，恢复正常模式 |
| 输入处理 | 转录文本可能有误 | 用户输入是正常文本 |
| 输出风格 | 简洁、行动导向 | 恢复正常对话风格 |
| 长度 | 796 bytes（详细） | 223 bytes（简洁） |

---

## 三、具体技术实现

### 3.1 代码集成路径

#### 3.1.1 提示词加载
```rust
// codex-rs/protocol/src/models.rs:492
const REALTIME_END_INSTRUCTIONS: &str = include_str!("prompts/realtime/realtime_end.md");
```

#### 3.1.2 封装为 DeveloperInstructions
```rust
// codex-rs/protocol/src/models.rs:576-581
impl DeveloperInstructions {
    pub fn realtime_end_message(reason: &str) -> Self {
        DeveloperInstructions::new(format!(
            "{REALTIME_CONVERSATION_OPEN_TAG}\n{}\n\nReason: {reason}\n{REALTIME_CONVERSATION_CLOSE_TAG}",
            REALTIME_END_INSTRUCTIONS.trim()
        ))
    }
}
```

与 `realtime_start_message` 不同，`realtime_end_message` 接受一个 `reason` 参数，用于记录结束原因。

### 3.2 触发时机与流程

#### 3.2.1 状态转换触发
```rust
// codex-rs/core/src/context_manager/updates.rs:69-96
pub(crate) fn build_realtime_update_item(
    previous: Option<&TurnContextItem>,
    previous_turn_settings: Option<&PreviousTurnSettings>,
    next: &TurnContext,
) -> Option<DeveloperInstructions> {
    match (
        previous.and_then(|item| item.realtime_active),
        next.realtime_active,
    ) {
        // 从 true -> false: 发送结束消息
        (Some(true), false) => Some(DeveloperInstructions::realtime_end_message("inactive")),
        // 其他情况...
        (Some(true), true) | (Some(false), false) => None,
        (None, false) => previous_turn_settings
            .and_then(|settings| settings.realtime_active)
            .filter(|realtime_active| *realtime_active)
            .map(|_| DeveloperInstructions::realtime_end_message("inactive")),
    }
}
```

#### 3.2.2 结束原因（Reason）
代码中目前使用的结束原因：
- `"inactive"` - 默认/通用结束原因

潜在的结束场景（从代码分析）：
- 用户主动关闭: `Op::RealtimeConversationClose`
- 传输层关闭: `RealtimeConversationEnd::TransportClosed`
- 错误导致: `RealtimeConversationEnd::Error`
- 请求结束: `RealtimeConversationEnd::Requested`

#### 3.2.3 完整调用链
```
用户结束 Realtime Conversation
    ↓
Session::submit(Op::RealtimeConversationClose)
    ↓
realtime_conversation::handle_close() / end_realtime_conversation()
    ↓
发送 RealtimeConversationClosed 事件
    ↓
ContextManager 更新 TurnContext (realtime_active: true -> false)
    ↓
build_realtime_update_item() 检测到状态变化
    ↓
DeveloperInstructions::realtime_end_message("inactive")
    ↓
提示词被注入到模型消息历史
```

### 3.3 数据结构关联

#### 3.3.1 RealtimeConversationEnd 枚举
```rust
// codex-rs/core/src/realtime_conversation.rs:59-64
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum RealtimeConversationEnd {
    Requested,       // 用户请求结束
    TransportClosed, // 传输层关闭
    Error,           // 错误导致
}
```

#### 3.3.2 事件通知
```rust
// codex-rs/core/src/realtime_conversation.rs:590
send_realtime_conversation_closed(&sess_clone, sub_id, end).await;
```

### 3.4 XML 标签包装

与 `realtime_start.md` 相同，使用相同的 XML 标签包裹：
```rust
pub const REALTIME_CONVERSATION_OPEN_TAG: &str = "<realtime_conversation>";
pub const REALTIME_CONVERSATION_CLOSE_TAG: &str = "</realtime_conversation>";
```

生成的消息格式：
```xml
<realtime_conversation>
Realtime conversation ended.

Subsequent user input will return to typed text rather than transcript-style text. Do not assume recognition errors or missing punctuation once realtime has ended. Resume normal chat behavior.

Reason: inactive
</realtime_conversation>
```

---

## 四、关键代码路径与文件引用

### 4.1 核心文件

| 文件路径 | 作用 |
|---------|------|
| `codex-rs/protocol/src/prompts/realtime/realtime_end.md` | 提示词模板源文件 |
| `codex-rs/protocol/src/models.rs` | DeveloperInstructions::realtime_end_message 实现 |
| `codex-rs/protocol/src/protocol.rs` | XML 标签常量定义 |
| `codex-rs/core/src/context_manager/updates.rs` | 实时对话状态更新逻辑 |
| `codex-rs/core/src/realtime_conversation.rs` | 实时对话核心管理器，结束事件处理 |

### 4.2 关键代码行

```rust
// models.rs:492 - 提示词加载
const REALTIME_END_INSTRUCTIONS: &str = include_str!("prompts/realtime/realtime_end.md");

// models.rs:576-581 - 封装方法
pub fn realtime_end_message(reason: &str) -> Self {
    DeveloperInstructions::new(format!(
        "{REALTIME_CONVERSATION_OPEN_TAG}\n{}\n\nReason: {reason}\n{REALTIME_CONVERSATION_CLOSE_TAG}",
        REALTIME_END_INSTRUCTIONS.trim()
    ))
}

// updates.rs:78 - 触发点
(Some(true), false) => Some(DeveloperInstructions::realtime_end_message("inactive")),

// updates.rs:91-94 - 边界情况处理
(None, false) => previous_turn_settings
    .and_then(|settings| settings.realtime_active)
    .filter(|realtime_active| *realtime_active)
    .map(|_| DeveloperInstructions::realtime_end_message("inactive")),
```

### 4.3 结束事件处理

```rust
// realtime_conversation.rs:388-405
async fn stop_conversation_state(
    mut state: ConversationState,
    fanout_task_stop: RealtimeFanoutTaskStop,
) {
    state.realtime_active.store(false, Ordering::Relaxed);
    state.input_task.abort();
    let _ = state.input_task.await;

    if let Some(fanout_task) = state.fanout_task.take() {
        match fanout_task_stop {
            RealtimeFanoutTaskStop::Abort => {
                fanout_task.abort();
                let _ = fanout_task.await;
            }
            RealtimeFanoutTaskStop::Detach => {}
        }
    }
}
```

---

## 五、依赖与外部交互

### 5.1 内部依赖

```
realtime_end.md
    ↓ include_str!
models.rs (DeveloperInstructions::realtime_end_message)
    ↓ 调用
protocol.rs (REALTIME_CONVERSATION_OPEN_TAG/CLOSE_TAG)
    ↓ 被调用
updates.rs (build_realtime_update_item)
    ↓ 集成
realtime_conversation.rs (RealtimeConversationManager, 结束处理)
```

### 5.2 与 realtime_start.md 的关系

```
[正常流程]
realtime_start.md 注入 → 实时对话进行 → realtime_end.md 注入 → 恢复正常模式

[异常/重入流程]
realtime_start.md 注入 → 实时对话进行 → 新 start 请求 → 
    内部自动调用 end → realtime_end.md 注入 → 
    立即重新注入 realtime_start.md → 新的实时对话
```

### 5.3 外部交互

| 交互方 | 交互方式 | 说明 |
|--------|---------|------|
| 用户 | 主动关闭 | 用户点击/输入关闭实时对话 |
| 网络层 | WebSocket 关闭 | 连接断开触发 TransportClosed |
| 错误处理 | 异常捕获 | 错误发生时触发 Error 结束 |

---

## 六、风险、边界与改进建议

### 6.1 潜在风险

| 风险点 | 描述 | 影响级别 |
|--------|------|---------|
| 重复结束 | 如果状态管理不当，可能重复发送结束提示词 | 低 |
| 原因信息不足 | 当前仅使用 "inactive" 作为原因，缺乏细节 | 中 |
| 与 start 不匹配 | 如果 end 触发但 start 未触发，可能导致状态不一致 | 低 |
| 提示词过短 | 223 bytes 可能不足以让模型完全理解状态变化 | 低 |

### 6.2 边界条件

1. **重复结束**: 连续多次调用 `realtime_end_message` 会生成多条结束消息
2. **未匹配的结束**: 如果会话从未启动实时对话，但 `previous_turn_settings` 标记为活跃，会触发结束消息
3. **并发结束**: 快速切换可能导致 start/end 消息顺序问题

```rust
// 边界情况处理：previous_turn_settings 存在且 realtime_active 为 true
(None, false) => previous_turn_settings
    .and_then(|settings| settings.realtime_active)
    .filter(|realtime_active| *realtime_active)
    .map(|_| DeveloperInstructions::realtime_end_message("inactive")),
```

### 6.3 改进建议

#### 6.3.1 短期改进
1. **丰富结束原因**: 将 `RealtimeConversationEnd` 的变体映射到更具体的 reason 字符串
   ```rust
   match end {
       RealtimeConversationEnd::Requested => "user_requested",
       RealtimeConversationEnd::TransportClosed => "connection_lost",
       RealtimeConversationEnd::Error => "error_occurred",
   }
   ```

2. **去重机制**: 添加逻辑防止重复发送结束提示词

3. **日志记录**: 记录结束原因，便于问题排查

#### 6.3.2 长期改进
1. **会话恢复**: 支持实时对话中断后的恢复，而非简单结束
2. **平滑过渡**: 添加过渡提示词，帮助模型从实时模式平滑过渡到正常模式
3. **上下文保留**: 考虑保留实时对话的关键上下文到正常模式

### 6.4 与 realtime_start.md 的协同改进

1. **统一模板引擎**: 两个提示词使用相同的变量替换机制
2. **版本对齐**: 确保 start 和 end 提示词的版本一致
3. **状态机文档**: 明确定义实时对话的状态转换图

---

## 七、总结

`realtime_end.md` 是 Codex Realtime Conversation 功能的重要组成部分，虽然内容简洁（仅 223 bytes），但承担着明确的状态通知和行为恢复职责。它通过与 `realtime_start.md` 配合，构建了完整的实时对话生命周期管理：

- **Start**: 进入特殊模式（后端执行器、转录文本处理）
- **End**: 退出特殊模式（恢复正常聊天行为）

当前实现使用硬编码的 `"inactive"` 作为结束原因，建议未来根据 `RealtimeConversationEnd` 的具体变体提供更丰富的上下文信息，帮助模型更好地理解对话结束的原因和背景。
