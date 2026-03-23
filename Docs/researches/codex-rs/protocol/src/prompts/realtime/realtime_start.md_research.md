# realtime_start.md 深度研究文档

## 文件信息
- **路径**: `codex-rs/protocol/src/prompts/realtime/realtime_start.md`
- **大小**: 796 bytes
- **类型**: Markdown 提示词模板

---

## 一、场景与职责

### 1.1 核心场景
`realtime_start.md` 是 **Realtime Conversation（实时对话）** 功能的启动提示词模板。当用户通过语音/实时音频与 Codex 进行交互时，系统会在对话开始时将此提示词注入到模型上下文中，指导模型如何正确处理实时语音输入。

### 1.2 业务场景
- **语音交互模式**: 用户通过麦克风进行语音输入，而非键盘输入
- **中介代理模式**: 模型作为后端执行器，不直接与用户对话，而是通过中介层（intermediary）进行通信
- **转录文本处理**: 语音转文本可能包含识别错误、缺少标点等问题，模型需要特殊处理

### 1.3 职责边界
- 明确告知模型当前处于"实时对话模式"
- 建立模型与中介层之间的通信契约
- 指导模型如何处理转录文本的不确定性
- 约束模型输出风格（简洁、行动导向）

---

## 二、功能点目的

### 2.1 功能目标

| 功能点 | 目的 |
|--------|------|
| 角色定位 | 明确模型作为"后端执行器"的角色，非直接对话 |
| 输入处理 | 告知转录文本可能有识别错误，避免过度解读 |
| 输出风格 | 要求简洁、行动导向的响应，降低用户可见延迟 |
| 条件响应 | 指导模型判断何时需要工作，避免不必要的冗长响应 |

### 2.2 提示词内容解析

```markdown
Realtime conversation started.

You are operating as a backend executor behind an intermediary. 
The user does not talk to you directly. Any response you produce will be 
consumed by the intermediary and may be summarized before the user sees it.

When invoked, you receive the latest conversation transcript and any relevant 
mode or metadata. The intermediary may invoke you even when backend help is 
not actually needed. Use the transcript to decide whether you should do work. 
If backend help is unnecessary, avoid verbose responses that add user-visible latency.

When user text is routed from realtime, treat it as a transcript. 
It may be unpunctuated or contain recognition errors.

- Keep responses concise and action-oriented. Your updates should help the 
  intermediary respond to the user.
```

### 2.3 设计意图
1. **降低延迟**: 强调中介层可能总结响应，模型应避免冗长
2. **容错处理**: 明确告知转录文本可能有误，模型不应假设识别完美
3. **智能判断**: 模型需要根据 transcript 自行判断是否需要执行工作
4. **协作模式**: 建立"模型 → 中介层 → 用户"的间接通信模式

---

## 三、具体技术实现

### 3.1 代码集成路径

#### 3.1.1 提示词加载
```rust
// codex-rs/protocol/src/models.rs:491
const REALTIME_START_INSTRUCTIONS: &str = include_str!("prompts/realtime/realtime_start.md");
```

#### 3.1.2 封装为 DeveloperInstructions
```rust
// codex-rs/protocol/src/models.rs:566-574
impl DeveloperInstructions {
    pub fn realtime_start_message() -> Self {
        Self::realtime_start_message_with_instructions(REALTIME_START_INSTRUCTIONS.trim())
    }

    pub fn realtime_start_message_with_instructions(instructions: &str) -> Self {
        DeveloperInstructions::new(format!(
            "{REALTIME_CONVERSATION_OPEN_TAG}\n{instructions}\n{REALTIME_CONVERSATION_CLOSE_TAG}"
        ))
    }
}
```

#### 3.1.3 XML 标签包装
提示词被包裹在特定的 XML 标签中：
```rust
// codex-rs/protocol/src/protocol.rs:96-97
pub const REALTIME_CONVERSATION_OPEN_TAG: &str = "<realtime_conversation>";
pub const REALTIME_CONVERSATION_CLOSE_TAG: &str = "</realtime_conversation>";
```

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
        // 从 false -> true 或 None -> true: 发送开始消息
        (Some(false), true) | (None, true) => Some(
            if let Some(instructions) = next.config.experimental_realtime_start_instructions.as_deref() {
                DeveloperInstructions::realtime_start_message_with_instructions(instructions)
            } else {
                DeveloperInstructions::realtime_start_message()
            }
        ),
        ...
    }
}
```

#### 3.2.2 完整调用链
```
用户启动 Realtime Conversation
    ↓
Session::submit(Op::RealtimeConversationStart)
    ↓
realtime_conversation::handle_start()
    ↓
build_realtime_startup_context() [可选：添加上下文]
    ↓
ContextManager 更新 TurnContext
    ↓
build_realtime_update_item() 检测到 realtime_active: false -> true
    ↓
DeveloperInstructions::realtime_start_message()
    ↓
提示词被注入到模型消息历史
```

### 3.3 数据结构关联

#### 3.3.1 TurnContext 中的 realtime_active 标志
```rust
// codex-rs/core/src/codex.rs
pub(crate) struct TurnContext {
    pub realtime_active: bool,
    pub config: Arc<Config>,
    // ...
}
```

#### 3.3.2 DeveloperInstructions 结构
```rust
// codex-rs/protocol/src/models.rs:469-473
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, JsonSchema, TS)]
#[serde(rename = "developer_instructions", rename_all = "snake_case")]
pub struct DeveloperInstructions {
    text: String,
}
```

### 3.4 配置覆盖机制

用户可通过配置自定义启动提示词：
```toml
# config.toml
[experimental]
realtime_start_instructions = "自定义的实时对话启动指令"
```

代码中通过 `experimental_realtime_start_instructions` 配置项实现覆盖：
```rust
if let Some(instructions) = next.config.experimental_realtime_start_instructions.as_deref() {
    DeveloperInstructions::realtime_start_message_with_instructions(instructions)
} else {
    DeveloperInstructions::realtime_start_message()
}
```

---

## 四、关键代码路径与文件引用

### 4.1 核心文件

| 文件路径 | 作用 |
|---------|------|
| `codex-rs/protocol/src/prompts/realtime/realtime_start.md` | 提示词模板源文件 |
| `codex-rs/protocol/src/models.rs` | DeveloperInstructions 实现，提示词加载 |
| `codex-rs/protocol/src/protocol.rs` | XML 标签常量定义 |
| `codex-rs/core/src/context_manager/updates.rs` | 实时对话状态更新逻辑 |
| `codex-rs/core/src/realtime_conversation.rs` | 实时对话核心管理器 |

### 4.2 关键代码行

```rust
// models.rs:491 - 提示词加载
const REALTIME_START_INSTRUCTIONS: &str = include_str!("prompts/realtime/realtime_start.md");

// models.rs:566-574 - 封装方法
pub fn realtime_start_message() -> Self { ... }
pub fn realtime_start_message_with_instructions(instructions: &str) -> Self { ... }

// protocol.rs:96-97 - XML 标签
pub const REALTIME_CONVERSATION_OPEN_TAG: &str = "<realtime_conversation>";
pub const REALTIME_CONVERSATION_CLOSE_TAG: &str = "</realtime_conversation>";

// updates.rs:69-96 - 触发逻辑
pub(crate) fn build_realtime_update_item(...) -> Option<DeveloperInstructions> { ... }
```

### 4.3 测试覆盖

| 测试文件 | 测试内容 |
|---------|---------|
| `codex-rs/core/tests/suite/realtime_conversation.rs` | 核心实时对话功能测试 |
| `codex-rs/app-server/tests/suite/v2/realtime_conversation.rs` | App Server V2 实时对话测试 |

---

## 五、依赖与外部交互

### 5.1 内部依赖

```
realtime_start.md
    ↓ include_str!
models.rs (DeveloperInstructions)
    ↓ 调用
protocol.rs (REALTIME_CONVERSATION_OPEN_TAG/CLOSE_TAG)
    ↓ 被调用
updates.rs (build_realtime_update_item)
    ↓ 集成
realtime_conversation.rs (RealtimeConversationManager)
```

### 5.2 外部交互

| 交互方 | 交互方式 | 说明 |
|--------|---------|------|
| OpenAI Realtime API | WebSocket | 实时音频流通信 |
| 中介层 (Intermediary) | 消息转发 | 提示词中提到的中介层，负责模型输出到用户的转发 |
| 用户 | 语音输入 | 通过设备麦克风输入音频 |

### 5.3 配置依赖

```toml
# 相关配置项
[experimental]
realtime_ws_base_url = "..."           # WebSocket 服务端点
realtime_ws_backend_prompt = "..."     # 后端提示词覆盖
realtime_ws_startup_context = "..."    # 启动上下文覆盖
realtime_start_instructions = "..."    # 启动提示词覆盖

[realtime]
version = "v1" | "v2"                  # API 版本
type = "conversational" | "transcription"  # 会话模式
```

---

## 六、风险、边界与改进建议

### 6.1 潜在风险

| 风险点 | 描述 | 影响级别 |
|--------|------|---------|
| 提示词注入攻击 | 如果用户能控制 `experimental_realtime_start_instructions`，可能导致提示词注入 | 中 |
| 版本漂移 | 提示词文件与代码逻辑不同步 | 低 |
| 多语言支持 | 当前仅为英文，非英语用户可能体验不佳 | 中 |
| 中介层依赖 | 强依赖中介层行为，若中介层变更，提示词可能失效 | 低 |

### 6.2 边界条件

1. **空提示词处理**: 如果 `experimental_realtime_start_instructions` 为空字符串，将使用默认提示词
2. **并发启动**: 多次启动 Realtime Conversation 会触发 `realtime_end` + `realtime_start` 序列
3. **配置热更新**: 配置变更不会立即影响已运行的实时对话会话

### 6.3 改进建议

#### 6.3.1 短期改进
1. **添加本地化支持**: 根据用户语言设置加载对应语言的提示词
2. **配置验证**: 对 `experimental_realtime_start_instructions` 进行长度和内容校验
3. **版本标记**: 在提示词中添加版本号，便于调试和追踪

#### 6.3.2 长期改进
1. **动态提示词**: 根据用户历史行为和偏好动态调整提示词
2. **A/B 测试支持**: 支持不同提示词变体的效果对比
3. **提示词模板引擎**: 使用模板引擎支持变量替换，而非硬编码拼接

### 6.4 相关 Issue/PR 建议

- 考虑添加 `realtime_start_i18n.md` 等多语言提示词文件
- 考虑在 DeveloperInstructions 中添加元数据字段（如版本、来源）
- 考虑将提示词管理抽象为独立模块，支持运行时热更新

---

## 七、总结

`realtime_start.md` 是 Codex Realtime Conversation 功能的核心提示词组件，通过明确模型在实时语音交互场景下的角色定位、输入处理策略和输出风格要求，确保模型能够以正确的行为模式处理语音输入。该提示词通过 `DeveloperInstructions` 结构封装，并在实时对话状态从非活跃转为活跃时自动注入到模型上下文中。
