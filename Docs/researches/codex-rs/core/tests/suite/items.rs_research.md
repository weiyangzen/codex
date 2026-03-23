# items.rs 研究文档

## 场景与职责

`items.rs` 是 Codex Rust 核心库的集成测试套件，专注于验证 **TurnItem 生命周期事件** 的正确性。该测试文件确保 Codex 能够正确处理对话中的各种项目类型（UserMessage、AgentMessage、Plan、Reasoning、WebSearch、ImageGeneration 等），并在项目开始和完成时发出正确的事件。

### 核心职责
1. **验证 TurnItem 事件流**：确保每个项目类型在生命周期中正确发出 `ItemStarted` 和 `ItemCompleted` 事件
2. **测试 Plan 模式**：验证 `<proposed_plan>` 标签的解析和分离逻辑
3. **验证流式内容增量**：测试内容增量事件（ContentDelta）携带正确的元数据
4. **确保向后兼容性**：验证旧版事件格式（legacy events）仍然正确发出

---

## 功能点目的

### 1. 用户消息项目测试 (`user_message_item_is_emitted`)
- **目的**：验证用户输入被正确封装为 `TurnItem::UserMessage` 并发出事件
- **关键验证点**：
  - `ItemStarted` 和 `ItemCompleted` 事件携带相同的项目 ID
  - 项目内容保留原始 `UserInput` 结构
  - 旧版 `UserMessage` 事件仍然发出（向后兼容）

### 2. 助手消息项目测试 (`assistant_message_item_is_emitted`)
- **目的**：验证助手回复被正确封装为 `TurnItem::AgentMessage`
- **关键验证点**：
  - 助手消息内容正确解析为 `AgentMessageContent::Text`
  - 事件 ID 一致性

### 3. 推理项目测试 (`reasoning_item_is_emitted`)
- **目的**：验证推理内容（reasoning）被正确封装为 `TurnItem::Reasoning`
- **关键验证点**：
  - `summary_text` 和 `raw_content` 正确提取
  - 支持加密的推理内容（通过 base64 编码）

### 4. Web 搜索项目测试 (`web_search_item_is_emitted`)
- **目的**：验证 Web 搜索调用被正确封装为 `TurnItem::WebSearch`
- **关键验证点**：
  - 搜索查询和动作正确捕获
  - `WebSearchBegin` 和 `ItemCompleted` 事件正确发出

### 5. 图像生成项目测试 (`image_generation_call_event_is_emitted`)
- **目的**：验证图像生成调用被正确封装为 `TurnItem::ImageGeneration`
- **关键验证点**：
  - 生成的图像正确保存到临时目录
  - 失败场景处理（无效 base64 数据）

### 6. Plan 模式测试套件
包含多个测试用例验证 Plan 协作模式：
- **`plan_mode_emits_plan_item_from_proposed_plan_block`**：验证 `<proposed_plan>` 标签内容被提取为独立 PlanItem
- **`plan_mode_strips_plan_from_agent_messages`**：验证 Plan 内容从助手消息中剥离
- **`plan_mode_streaming_citations_are_stripped`**：验证流式内容中的引用标签被正确剥离
- **`plan_mode_streaming_proposed_plan_tag_split_across_added_and_delta_is_parsed`**：验证跨分片的标签解析
- **`plan_mode_handles_missing_plan_close_tag`**：验证未闭合标签的容错处理

### 7. 内容增量元数据测试 (`agent_message_content_delta_has_item_metadata`)
- **目的**：验证内容增量事件携带正确的线程 ID、回合 ID 和项目 ID
- **关键验证点**：
  - `AgentMessageContentDelta` 包含 `thread_id`、`turn_id`、`item_id`
  - 旧版 `AgentMessageDelta` 仍然正确发出

### 8. 推理内容增量测试 (`reasoning_content_delta_has_item_metadata`, `reasoning_raw_content_delta_respects_flag`)
- **目的**：验证推理内容的增量更新和原始内容显示标志
- **关键验证点**：
  - `ReasoningContentDelta` 携带正确的项目 ID
  - `show_raw_agent_reasoning` 配置控制原始内容显示

---

## 具体技术实现

### 关键数据结构

```rust
// TurnItem 枚举定义（来自 codex_protocol::items）
pub enum TurnItem {
    UserMessage(UserMessageItem),
    AgentMessage(AgentMessageItem),
    Plan(PlanItem),
    Reasoning(ReasoningItem),
    WebSearch(WebSearchItem),
    ImageGeneration(ImageGenerationItem),
    ContextCompaction(ContextCompactionItem),
}

// ItemStartedEvent 和 ItemCompletedEvent
pub struct ItemStartedEvent {
    pub thread_id: ThreadId,
    pub turn_id: String,
    pub item: TurnItem,
}

pub struct ItemCompletedEvent {
    pub thread_id: ThreadId,
    pub turn_id: String,
    pub item: TurnItem,
}
```

### 测试基础设施

测试使用 `core_test_support` 提供的工具：

1. **Mock Server 设置**：
```rust
let server = start_mock_server().await;
let TestCodex { codex, .. } = test_codex().build(&server).await?;
```

2. **SSE 事件模拟**：
```rust
let first_response = sse(vec![
    ev_response_created("resp-1"),
    ev_assistant_message("msg-1", "all done"),
    ev_completed("resp-1"),
]);
mount_sse_once(&server, first_response).await;
```

3. **事件等待工具**：
```rust
let started_item = wait_for_event_match(&codex, |ev| match ev {
    EventMsg::ItemStarted(ItemStartedEvent { item: TurnItem::AgentMessage(item), .. }) => Some(item.clone()),
    _ => None,
}).await;
```

### Plan 模式解析逻辑

Plan 模式通过正则表达式解析 `<proposed_plan>...</proposed_plan>` 标签：

1. **标签提取**：从助手消息中提取 Plan 内容
2. **内容分离**：Plan 内容从助手消息中剥离，仅保留非 Plan 文本
3. **引用清理**：移除 `<oai-mem-citation>...</oai-mem-citation>` 标签
4. **流式处理**：支持跨多个 delta 分片的标签解析

### 协作模式配置

```rust
let collaboration_mode = CollaborationMode {
    mode: ModeKind::Plan,
    settings: Settings {
        model: session_configured.model.clone(),
        reasoning_effort: None,
        developer_instructions: None,
    },
};
```

---

## 关键代码路径与文件引用

### 测试文件
- **当前文件**：`codex-rs/core/tests/suite/items.rs` (1126 行)

### 依赖的协议定义
- **`codex-rs/protocol/src/items.rs`**：TurnItem 及其变体定义
- **`codex-rs/protocol/src/protocol.rs`**：EventMsg、ItemStartedEvent、ItemCompletedEvent 定义

### 依赖的测试支持库
- **`codex-rs/core/tests/common/lib.rs`**：测试基础设施（`wait_for_event`、`wait_for_event_match`）
- **`codex-rs/core/tests/common/responses.rs`**：Mock SSE 响应生成（`sse`、`ev_*` 函数）
- **`codex-rs/core/tests/common/test_codex.rs`**：TestCodex 构建器

### 核心实现引用
- **`codex-rs/core/src/items/`**：TurnItem 处理逻辑（如果存在）
- **`codex-rs/core/src/codex.rs`**：Codex 主循环，事件生成

---

## 依赖与外部交互

### 外部依赖
1. **wiremock**：HTTP Mock 服务器，用于模拟 OpenAI Responses API
2. **tokio**：异步运行时（`#[tokio::test(flavor = "multi_thread", worker_threads = 2)]`）
3. **serde_json**：JSON 序列化/反序列化
4. **pretty_assertions**：测试断言美化

### 内部依赖
1. **codex_protocol**：协议类型定义（TurnItem、EventMsg 等）
2. **core_test_support**：测试支持库（Mock 服务器、事件等待工具）

### 网络依赖
- 使用 `skip_if_no_network!` 宏在沙箱环境中跳过测试
- 所有测试通过 Mock 服务器运行，不依赖真实网络

---

## 风险、边界与改进建议

### 已知风险

1. **平台限制**：
   - 文件使用 `#![cfg(not(target_os = "windows"))]` 排除 Windows 平台
   - 原因：某些测试依赖 Unix 特定的文件系统行为

2. **事件顺序依赖**：
   - 测试假设事件按特定顺序发出
   - 异步处理可能导致时序问题（使用 `wait_for_event_match` 缓解）

3. **Plan 模式解析的复杂性**：
   - 跨分片的标签解析逻辑复杂，容易出错
   - 测试用例 `plan_mode_streaming_citations_are_stripped_across_added_deltas_and_done` 验证此场景

### 边界情况

1. **未闭合的 Plan 标签**：
   - 测试 `plan_mode_handles_missing_plan_close_tag` 验证容错处理
   - 系统应优雅处理未闭合标签，提取已解析内容

2. **空内容处理**：
   - 验证空字符串、空数组的正确处理

3. **图像生成失败**：
   - 测试无效 base64 数据的处理（`image_generation_call_event_is_emitted_when_image_save_fails`）

### 改进建议

1. **增加并发测试**：
   - 当前测试主要验证顺序行为
   - 建议增加多线程并发提交测试

2. **扩展事件验证**：
   - 增加对 `HookStarted`/`HookCompleted` 事件的验证
   - 增加对 `ContextCompaction` 项目的验证

3. **性能测试**：
   - 大内容分片的处理性能
   - 高频事件流的处理稳定性

4. **错误场景覆盖**：
   - 增加对无效事件序列的容错测试
   - 增加对网络中断的恢复测试

5. **文档改进**：
   - 为复杂的 Plan 模式解析逻辑添加更多内联注释
   - 提供事件流时序图
