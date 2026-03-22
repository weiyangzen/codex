# ReasoningSummary.ts Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`ReasoningSummary` 定义了推理摘要的生成模式，控制是否以及如何生成模型推理过程的摘要。

**使用场景：**
- 配置模型推理摘要的生成方式
- 在会话或单轮对话中控制推理可见性
- 调试时启用详细的推理摘要

**职责：**
- 提供标准化的推理摘要配置选项
- 支持不同的摘要详细程度
- 与 OpenAI API 兼容

## 2. 功能点目的 (Purpose of This Type)

该类型的主要目的是：

1. **可观测性**：让用户能够了解模型的推理过程
2. **调试支持**：详细的推理摘要有助于调试模型行为
3. **灵活性**：允许用户根据需要选择摘要级别

**摘要模式：**
- `auto`：自动决定是否生成摘要（默认）
- `concise`：生成简洁的推理摘要
- `detailed`：生成详细的推理摘要
- `none`：不生成推理摘要

## 3. 具体技术实现 (Technical Implementation Details)

**Rust 定义**（位于 `codex-rs/protocol/src/config_types.rs` 第 10-25 行）：

```rust
/// A summary of the reasoning performed by the model. This can be useful for
/// debugging and understanding the model's reasoning process.
/// See https://platform.openai.com/docs/guides/reasoning?api-mode=responses#reasoning-summaries
#[derive(
    Debug, Serialize, Deserialize, Default, Clone, Copy, PartialEq, Eq, Display, JsonSchema, TS,
)]
#[serde(rename_all = "lowercase")]
#[strum(serialize_all = "lowercase")]
pub enum ReasoningSummary {
    #[default]
    Auto,
    Concise,
    Detailed,
    /// Option to disable reasoning summaries.
    None,
}
```

**TypeScript 生成定义：**

```typescript
/**
 * A summary of the reasoning performed by the model. This can be useful for
 * debugging and understanding the model's reasoning process.
 * See https://platform.openai.com/docs/guides/reasoning?api-mode=responses#reasoning-summaries
 */
export type ReasoningSummary = "auto" | "concise" | "detailed" | "none";
```

**关键实现细节：**
- 默认值为 `Auto`
- 实现了 `Display` trait
- 与 OpenAI API 的推理摘要参数兼容
- 在 `ModelInfo` 中作为 `default_reasoning_summary` 字段使用

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

**Rust 源文件：**
- `/home/sansha/Github/codex/codex-rs/protocol/src/config_types.rs`（第 10-25 行）：主要定义

**TypeScript 生成文件：**
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/ReasoningSummary.ts`

**使用位置：**
- `ModelInfo.default_reasoning_summary`（openai_models.rs 第 262 行）
- `Settings` 结构体
- `Op::UserTurn` 和 `Op::OverrideTurnContext` 操作
- `CollaborationMode` 配置

**相关类型：**
- `ReasoningItemReasoningSummary`：具体的推理摘要内容
- `ReasoningEffort`：推理努力级别

## 5. 依赖与外部交互 (Dependencies and External Interactions)

**依赖 crate：**
- `serde`：序列化/反序列化
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成
- `strum`：字符串枚举处理

**序列化格式：**
- JSON 中使用 lowercase：`"auto"`, `"concise"`, `"detailed"`, `"none"`

**与 OpenAI API 的交互：**
- 直接映射到 OpenAI API 的推理摘要参数
- 参考文档：https://platform.openai.com/docs/guides/reasoning#reasoning-summaries

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

**潜在风险：**
1. **模型兼容性**：不是所有模型都支持推理摘要
2. **额外成本**：生成摘要可能产生额外的 token 成本
3. **延迟增加**：生成详细摘要可能增加响应时间

**边界情况：**
1. `auto` 模式的行为可能因模型而异
2. 模型可能不支持所有摘要级别

**改进建议：**
1. **模型能力检测**：自动检测当前模型支持的摘要级别
2. **成本提示**：显示不同摘要级别的预估成本
3. **摘要预览**：提供摘要内容的实时预览
4. **与 ReasoningEffort 集成**：高推理强度时自动建议详细摘要
5. **用户偏好学习**：根据用户行为自动调整默认摘要级别
6. **摘要导出**：支持导出推理摘要用于分析或文档
