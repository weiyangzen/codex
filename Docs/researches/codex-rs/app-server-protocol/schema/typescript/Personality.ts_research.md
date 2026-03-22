# Personality.ts Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`Personality` 定义了 AI 代理的沟通风格/个性类型，允许用户选择 AI 的交互方式。

**使用场景：**
- 用户配置中选择 AI 的沟通风格
- 模型指令生成时根据个性类型注入不同的系统提示
- TUI 设置中切换个性模式

**职责：**
- 提供标准化的个性类型定义
- 支持模型指令的个性化定制
- 向后兼容（`none` 选项表示不使用个性）

## 2. 功能点目的 (Purpose of This Type)

该类型的主要目的是：

1. **个性化体验**：让用户选择符合自己偏好的 AI 沟通风格
2. **模型指令定制**：根据个性类型注入不同的系统提示
3. **灵活性**：支持不使用个性（`none`）的默认行为

**个性类型：**
- `none`：不使用特定个性（默认）
- `friendly`：友好的沟通风格
- `pragmatic`：务实的沟通风格

## 3. 具体技术实现 (Technical Implementation Details)

**Rust 定义**（位于 `codex-rs/protocol/src/config_types.rs` 第 97-118 行）：

```rust
#[derive(
    Debug,
    Serialize,
    Deserialize,
    Clone,
    Copy,
    PartialEq,
    Eq,
    Display,
    JsonSchema,
    TS,
    PartialOrd,
    Ord,
    EnumIter,
)]
#[serde(rename_all = "lowercase")]
#[strum(serialize_all = "lowercase")]
pub enum Personality {
    None,
    Friendly,
    Pragmatic,
}
```

**TypeScript 生成定义：**

```typescript
export type Personality = "none" | "friendly" | "pragmatic";
```

**关键实现细节：**
- 使用 `lowercase` 序列化格式
- 实现了 `EnumIter`，支持遍历所有变体
- 实现了 `Display` trait，便于格式化输出
- 在 `ModelInstructionsVariables` 中使用（openai_models.rs 第 369-394 行）

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

**Rust 源文件：**
- `/home/sansha/Github/codex/codex-rs/protocol/src/config_types.rs`（第 97-118 行）：主要定义

**TypeScript 生成文件：**
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/Personality.ts`

**使用位置：**
- `ModelInstructionsVariables`（openai_models.rs 第 369-394 行）
- `Op::UserTurn` 和 `Op::OverrideTurnContext`（protocol.rs）
- `DeveloperInstructions::personality_spec_message`（models.rs 第 583-588 行）

**相关类型：**
- `ModelInstructionsVariables`：包含各个性类型的具体指令
- `ModelPreset`：包含 `supports_personality` 标志

## 5. 依赖与外部交互 (Dependencies and External Interactions)

**依赖 crate：**
- `serde`：序列化/反序列化
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成
- `strum`：字符串枚举处理和遍历

**序列化格式：**
- JSON 中使用 lowercase：`"none"`, `"friendly"`, `"pragmatic"`

**与模型指令的交互：**
- 在 `ModelInstructionsVariables` 中，每个个性对应不同的指令文本
- 使用 `{{ personality }}` 占位符替换为具体个性指令

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

**潜在风险：**
1. **模型支持**：不是所有模型都支持个性定制
2. **一致性**：个性效果可能因模型而异
3. **过度依赖**：用户可能过度依赖个性设置而忽略清晰的指令

**边界情况：**
1. 模型不支持：需要检查 `ModelInfo.supports_personality()`
2. 模板缺失：如果 `instructions_template` 不包含占位符，个性设置将被忽略

**改进建议：**
1. **添加更多个性**：如 `professional`、`casual`、`technical` 等
2. **自定义个性**：允许用户定义自己的个性提示
3. **个性预览**：在 TUI 中提供个性效果的预览
4. **模型兼容性检查**：明确显示当前模型是否支持个性
5. **个性组合**：支持组合多个个性特征
6. **上下文感知**：根据任务类型自动调整个性
