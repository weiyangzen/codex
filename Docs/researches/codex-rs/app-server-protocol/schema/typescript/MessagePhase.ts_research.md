# MessagePhase.ts Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`MessagePhase` 用于分类助手消息的阶段状态，区分消息是中间过程的评论性内容（commentary）还是最终答案（final_answer）。

**使用场景：**
- AI 模型生成多阶段响应时，需要区分中间思考过程和最终输出
- TUI 界面需要根据消息阶段进行不同的渲染（例如评论阶段可能显示为灰色/斜体）
- 流式响应中，客户端需要知道何时收到的是最终答案

**职责：**
- 提供标准化的消息阶段分类
- 帮助客户端正确处理不同类型的消息内容
- 支持向后兼容（处理 `None` 作为未知阶段的情况）

## 2. 功能点目的 (Purpose of This Type)

该类型的主要目的是：

1. **改善用户体验**：让用户清楚区分 AI 的思考过程和最终答案
2. **支持流式渲染**：允许客户端在收到最终答案前显示中间内容
3. **向后兼容**：处理不同模型提供商可能不一致的阶段标记

**阶段定义：**
- `commentary`：中间过程的评论性内容，如思考过程、进度叙述等
- `final_answer`：当前轮次的最终答案文本

## 3. 具体技术实现 (Technical Implementation Details)

**Rust 定义**（位于 `codex-rs/protocol/src/models.rs` 第 277-291 行）：

```rust
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "snake_case")]
/// Classifies an assistant message as interim commentary or final answer text.
///
/// Providers do not emit this consistently, so callers must treat `None` as
/// "phase unknown" and keep compatibility behavior for legacy models.
pub enum MessagePhase {
    /// Mid-turn assistant text (for example preamble/progress narration).
    ///
    /// Additional tool calls or assistant output may follow before turn
    /// completion.
    Commentary,
    /// The assistant's terminal answer text for the current turn.
    FinalAnswer,
}
```

**TypeScript 生成定义：**

```typescript
/**
 * Classifies an assistant message as interim commentary or final answer text.
 *
 * Providers do not emit this consistently, so callers must treat `None` as
 * "phase unknown" and keep compatibility behavior for legacy models.
 */
export type MessagePhase = "commentary" | "final_answer";
```

**关键实现细节：**
- 在 `ResponseItem::Message` 中作为可选字段使用（第 309-311 行）
- 使用 `skip_serializing_if = "Option::is_none"` 避免序列化空值
- 文档明确警告提供商可能不一致地发送此字段

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

**Rust 源文件：**
- `/home/sansha/Github/codex/codex-rs/protocol/src/models.rs`（第 277-291 行）：主要定义
- `/home/sansha/Github/codex/codex-rs/protocol/src/models.rs`（第 293-312 行）：在 `ResponseItem::Message` 中使用

**TypeScript 生成文件：**
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/MessagePhase.ts`

**使用位置：**
- `ResponseItem::Message` 结构体的 `phase` 字段
- 与 `AgentMessageEvent` 和 `AgentMessageDeltaEvent` 相关

## 5. 依赖与外部交互 (Dependencies and External Interactions)

**依赖 crate：**
- `serde`：序列化/反序列化
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成

**序列化格式：**
- JSON 中使用 snake_case：`"commentary"`, `"final_answer"`

**与模型提供商的交互：**
- 不同模型提供商对此字段的支持程度不同
- 客户端必须处理 `None` 的情况，保持向后兼容

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

**潜在风险：**
1. **不一致性**：不同模型提供商对此字段的支持不一致，可能导致客户端行为不一致
2. **误解**：用户可能将 `commentary` 内容误解为最终答案
3. **遗留模型**：旧模型可能完全不支持此字段

**边界情况：**
1. `None` 值：必须作为"阶段未知"处理
2. 多阶段响应：一轮对话中可能有多个 `commentary` 消息后跟一个 `final_answer`

**改进建议：**
1. **标准化推动**：推动模型提供商更一致地支持此字段
2. **客户端降级策略**：明确定义当阶段未知时的默认行为
3. **添加更多阶段**：考虑添加更多细粒度阶段，如 `planning`、`executing`、`summarizing`
4. **UI 提示**：TUI 应该明确区分不同阶段的视觉表现
5. **配置选项**：允许用户配置是否显示 `commentary` 内容
