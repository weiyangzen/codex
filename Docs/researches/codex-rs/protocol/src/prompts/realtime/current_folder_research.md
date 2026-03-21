# DIR Research: codex-rs/protocol/src/prompts/realtime

## 概述

`codex-rs/protocol/src/prompts/realtime` 目录包含 Codex CLI 实时语音对话（Realtime Conversation）功能的系统提示词（System Prompts）。这些 Markdown 文件作为编译时嵌入资源，通过 `include_str!` 宏嵌入到 Rust 代码中，用于指导 AI 模型在实时语音交互场景下的行为模式。

---

## 场景与职责

### 业务场景

实时语音对话功能是 Codex CLI 的核心交互模式之一，允许用户通过语音与 AI 进行实时对话。这要求 AI 模型：

1. **理解中介架构**：AI 作为后端执行器，不直接与用户对话，而是通过中介层（TUI/App Server）转发
2. **处理转录文本**：接收来自语音识别系统的转录文本（可能缺少标点或包含识别错误）
3. **保持简洁响应**：避免冗长回复，减少用户可见的延迟
4. **区分交互模式**：在实时语音模式和普通文本聊天模式之间切换行为

### 核心职责

| 文件 | 职责 |
|------|------|
| `realtime_start.md` | 实时对话开始时注入，告知模型进入实时模式，调整响应风格 |
| `realtime_end.md` | 实时对话结束时注入，告知模型恢复正常文本聊天行为 |

---

## 功能点目的

### realtime_start.md

**目的**：在实时语音对话开始时，为 AI 模型提供行为指导。

**关键指令**：
- 明确 AI 作为"后端执行器"的角色定位，响应会被中介层消费和摘要
- 告知模型接收的是转录文本（transcript），可能缺少标点或包含识别错误
- 要求响应简洁、以行动为导向（action-oriented）
- 避免在不需要后端帮助时产生冗长响应

**典型使用场景**：
- 用户通过 TUI 按下语音按钮开始对话
- 通过 `Op::RealtimeConversationStart` 操作触发
- 在 `DeveloperInstructions::realtime_start_message()` 中被包装为 `<realtime_conversation>` 标签注入

### realtime_end.md

**目的**：在实时语音对话结束时，恢复 AI 的正常行为模式。

**关键指令**：
- 告知后续用户输入将恢复为打字文本而非转录文本
- 不再假设存在识别错误或缺少标点
- 恢复正常聊天行为

**典型使用场景**：
- 用户通过 TUI 关闭语音对话
- 通过 `Op::RealtimeConversationClose` 操作触发
- 在 `DeveloperInstructions::realtime_end_message()` 中被包装为 `<realtime_conversation>` 标签注入

---

## 具体技术实现

### 1. 编译时嵌入机制

```rust
// codex-rs/protocol/src/models.rs:491-492
const REALTIME_START_INSTRUCTIONS: &str = include_str!("prompts/realtime/realtime_start.md");
const REALTIME_END_INSTRUCTIONS: &str = include_str!("prompts/realtime/realtime_end.md");
```

这些提示词在编译时通过 `include_str!` 宏嵌入到二进制中，运行时无文件 I/O 开销。

### 2. DeveloperInstructions 封装

```rust
// codex-rs/protocol/src/models.rs:566-581
impl DeveloperInstructions {
    pub fn realtime_start_message() -> Self {
        Self::realtime_start_message_with_instructions(REALTIME_START_INSTRUCTIONS.trim())
    }

    pub fn realtime_start_message_with_instructions(instructions: &str) -> Self {
        DeveloperInstructions::new(format!(
            "{REALTIME_CONVERSATION_OPEN_TAG}\n{instructions}\n{REALTIME_CONVERSATION_CLOSE_TAG}"
        ))
    }

    pub fn realtime_end_message(reason: &str) -> Self {
        DeveloperInstructions::new(format!(
            "{REALTIME_CONVERSATION_OPEN_TAG}\n{}\n\nReason: {reason}\n{REALTIME_CONVERSATION_CLOSE_TAG}",
            REALTIME_END_INSTRUCTIONS.trim()
        ))
    }
}
```

提示词被包装在 `<realtime_conversation>` XML 标签中，便于：
- 上下文追踪和调试
- 后续文本处理（如 compaction 时识别 realtime 上下文）
- 与 AGENTS.md 等其他指令区分

### 3. 上下文更新触发机制

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
        (Some(true), false) => Some(DeveloperInstructions::realtime_end_message("inactive")),
        (Some(false), true) | (None, true) => Some(
            if let Some(instructions) = next.config.experimental_realtime_start_instructions.as_deref() {
                DeveloperInstructions::realtime_start_message_with_instructions(instructions)
            } else {
                DeveloperInstructions::realtime_start_message()
            }
        ),
        // ... 其他状态转换
    }
}
```

**状态转换矩阵**：

| 前一状态 | 当前状态 | 操作 |
|---------|---------|------|
| true | false | 注入 `realtime_end_message` |
| false | true | 注入 `realtime_start_message` |
| true | true | 无操作（保持实时模式） |
| false | false | 无操作（保持普通模式） |

### 4. 协议层集成

在 `codex-rs/protocol/src/protocol.rs` 中定义了实时对话相关的协议操作：

```rust
// codex-rs/protocol/src/protocol.rs:206-229
pub enum Op {
    /// Start a realtime conversation stream.
    RealtimeConversationStart(ConversationStartParams),
    
    /// Send audio input to the running realtime conversation stream.
    RealtimeConversationAudio(ConversationAudioParams),
    
    /// Send text input to the running realtime conversation stream.
    RealtimeConversationText(ConversationTextParams),
    
    /// Close the running realtime conversation stream.
    RealtimeConversationClose,
    // ...
}
```

### 5. 核心层实时对话管理

```rust
// codex-rs/core/src/realtime_conversation.rs
pub(crate) struct RealtimeConversationManager {
    state: Mutex<Option<ConversationState>>,
}

// 处理启动、音频输入、文本输入、关闭等操作
pub(crate) async fn handle_start(...)
pub(crate) async fn handle_audio(...)
pub(crate) async fn handle_text(...)
pub(crate) async fn handle_close(...)
```

### 6. TUI 层集成

在 TUI 应用中，实时对话提示词被用于初始化 WebSocket 会话：

```rust
// codex-rs/tui/src/chatwidget/realtime.rs:15
const REALTIME_CONVERSATION_PROMPT: &str = "You are in a realtime voice conversation in the Codex TUI. Respond conversationally and concisely.";

// 在启动实时对话时使用
prompt: REALTIME_CONVERSATION_PROMPT.to_string()
```

注意：TUI 层使用的是硬编码的简短提示词，而 protocol 层的完整提示词通过 `experimental_realtime_ws_backend_prompt` 配置项可覆盖。

---

## 关键代码路径与文件引用

### 提示词定义

| 文件 | 行号 | 说明 |
|------|------|------|
| `codex-rs/protocol/src/prompts/realtime/realtime_start.md` | 1-9 | 实时对话开始提示词 |
| `codex-rs/protocol/src/prompts/realtime/realtime_end.md` | 1-3 | 实时对话结束提示词 |

### 嵌入与封装

| 文件 | 行号 | 功能 |
|------|------|------|
| `codex-rs/protocol/src/models.rs` | 491-492 | `include_str!` 嵌入提示词 |
| `codex-rs/protocol/src/models.rs` | 566-581 | `DeveloperInstructions` 方法封装 |
| `codex-rs/protocol/src/protocol.rs` | 96-97 | `REALTIME_CONVERSATION_OPEN_TAG` / `CLOSE_TAG` 定义 |

### 上下文管理

| 文件 | 行号 | 功能 |
|------|------|------|
| `codex-rs/core/src/context_manager/updates.rs` | 69-96 | `build_realtime_update_item` 状态转换逻辑 |
| `codex-rs/core/src/context_manager/updates.rs` | 98-104 | `build_initial_realtime_item` 初始状态构建 |

### 实时对话核心实现

| 文件 | 行号 | 功能 |
|------|------|------|
| `codex-rs/core/src/realtime_conversation.rs` | 1-1050 | 实时对话管理器完整实现 |
| `codex-rs/core/src/realtime_context.rs` | 51-117 | 实时启动上下文构建 |
| `codex-rs/core/src/codex.rs` | 4188-4214 | `Op` 分发处理实时对话操作 |

### TUI/App Server 集成

| 文件 | 行号 | 功能 |
|------|------|------|
| `codex-rs/tui/src/chatwidget/realtime.rs` | 11-15 | TUI 实时对话提示词 |
| `codex-rs/tui_app_server/src/chatwidget/realtime.rs` | 11 | App Server 实时对话提示词 |

### 配置项

| 文件 | 行号 | 配置项 |
|------|------|--------|
| `codex-rs/core/src/config/mod.rs` | 513 | `experimental_realtime_ws_backend_prompt` |
| `codex-rs/core/src/config/mod.rs` | 1415 | `experimental_realtime_start_instructions` |

---

## 依赖与外部交互

### 内部依赖

```
codex-rs/protocol/src/prompts/realtime/
    ├── 被依赖方 ──>
    │   ├── codex-rs/protocol/src/models.rs (DeveloperInstructions)
    │   ├── codex-rs/protocol/src/protocol.rs (标签常量定义)
    │   ├── codex-rs/core/src/context_manager/updates.rs (上下文更新)
    │   ├── codex-rs/core/src/realtime_conversation.rs (对话管理)
    │   └── codex-rs/tui*/src/chatwidget/realtime.rs (TUI集成)
    └── 依赖方 ──>
        └── (无，这是叶子节点资源目录)
```

### 外部交互

1. **OpenAI Realtime API**：通过 WebSocket 连接，发送包含 instructions 的 session.update
2. **TUI 语音模块**：捕获音频、播放音频、管理设备状态
3. **State DB**：加载历史线程元数据构建启动上下文

### 配置覆盖

用户可通过 `config.toml` 覆盖默认提示词：

```toml
[experimental]
realtime_ws_backend_prompt = "自定义实时对话后端提示词"
realtime_start_instructions = "自定义实时对话开始指令"
```

---

## 风险、边界与改进建议

### 当前风险

1. **提示词版本不一致**
   - TUI 层 (`tui/src/chatwidget/realtime.rs`) 使用硬编码简短提示词
   - Protocol 层提供完整提示词但需通过配置显式启用
   - 可能导致不同入口点的行为差异

2. **实验性功能依赖**
   - `experimental_realtime_ws_backend_prompt` 和 `experimental_realtime_start_instructions` 均为实验性配置
   - 未来 API 变更可能导致配置失效

3. **状态转换竞态条件**
   - `realtime_active` 状态在 `TurnContext` 和 `PreviousTurnSettings` 中分别维护
   - 快速连续切换可能导致状态不一致

4. **多语言支持缺失**
   - 提示词目前仅为英文
   - 非英语用户可能获得次优体验

### 边界情况

1. **Compaction 处理**
   - 远程 compaction 会重新注入 `realtime_start` 或 `realtime_end` 形状（见 `core/tests/suite/snapshots/`）
   - 确保对话历史压缩后仍能正确恢复实时状态

2. **Handoff 场景**
   - 实时对话中的 handoff 请求会将文本路由回主对话
   - 需要确保提示词状态与 handoff 状态同步

3. **V1/V2 协议差异**
   - Realtime API 有 V1 和 V2 两个版本
   - 提示词注入逻辑需兼容两种协议

### 改进建议

1. **统一提示词来源**
   ```rust
   // 建议：TUI 层也使用 protocol 层的提示词
   use codex_protocol::models::DeveloperInstructions;
   let prompt = DeveloperInstructions::realtime_start_message().into_text();
   ```

2. **国际化支持**
   - 添加 `realtime_start.zh.md`、`realtime_start.ja.md` 等多语言版本
   - 根据用户 locale 动态选择

3. **提示词模板化**
   - 使用 `format!` 支持动态插入变量（如用户名、当前时间）
   - 示例：`"Hello {username}, you are now in realtime mode at {timestamp}"`

4. **A/B 测试框架**
   - 支持多版本提示词并行测试
   - 通过配置开关控制流量分配

5. **运行时热更新**
   - 当前编译时嵌入无法热更新
   - 开发模式下可从文件系统加载便于调试

6. **文档完善**
   - 添加提示词设计原则文档
   - 记录提示词变更历史（类似 CHANGELOG）

---

## 附录：相关测试

| 测试文件 | 说明 |
|---------|------|
| `codex-rs/core/tests/suite/realtime_conversation.rs` | 实时对话集成测试 |
| `codex-rs/core/tests/suite/compact_remote.rs` | 远程 compaction 与 realtime 状态测试 |
| `codex-rs/core/src/realtime_conversation_tests.rs` | 实时对话单元测试 |
| `codex-rs/core/src/realtime_context_tests.rs` | 实时上下文构建测试 |
| `codex-rs/core/src/config/config_tests.rs` | 配置加载测试（含 experimental_realtime_ws_backend_prompt）|

---

## 变更历史

- **初始研究**: 2026-03-21 - 完成目录结构、依赖关系、技术实现分析
