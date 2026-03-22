# Verbosity.ts 研究文档

## 1. 场景与职责

Verbosity 类型在 Codex 系统中用于控制 GPT-5 模型通过 Responses API 的输出长度和详细程度。它在以下场景中发挥作用：

- **输出长度控制**: 用户可以根据需求调整 AI 回复的详细程度
- **令牌优化**: 控制输出长度以优化令牌使用和成本
- **用户体验**: 不同场景下用户可能偏好简洁或详细的回复
- **模型配置**: 作为模型配置的一部分，影响所有模型输出

## 2. 功能点目的

Verbosity 提供三个详细程度级别：

1. **Low**: 简洁输出，适合快速获取要点
2. **Medium**: 平衡输出，默认级别，适合大多数场景
3. **High**: 详细输出，适合需要深入解释的场景

这个类型直接映射到 OpenAI API 的 verbosity 参数，用于控制模型的输出风格。

## 3. 具体技术实现

### TypeScript 类型定义

```typescript
/**
 * Controls output length/detail on GPT-5 models via the Responses API.
 * Serialized with lowercase values to match the OpenAI API.
 */
export type Verbosity = "low" | "medium" | "high";
```

### Rust 对应实现

位于 `/home/sansha/Github/codex/codex-rs/protocol/src/config_types.rs` (lines 27-50):

```rust
/// Controls output length/detail on GPT-5 models via the Responses API.
/// Serialized with lowercase values to match the OpenAI API.
#[derive(
    Hash,
    Debug,
    Serialize,
    Deserialize,
    Default,
    Clone,
    Copy,
    PartialEq,
    Eq,
    Display,
    JsonSchema,
    TS,
)]
#[serde(rename_all = "lowercase")]
#[strum(serialize_all = "lowercase")]
pub enum Verbosity {
    Low,
    #[default]
    Medium,
    High,
}
```

### 关键特性

1. **默认 Medium**: 使用 `#[default]` 指定 Medium 为默认值
2. **小写序列化**: 使用 `"low"`、`"medium"`、`"high"` 小写字符串与 OpenAI API 兼容
3. **Copy trait**: 实现 Copy，可以低成本传递
4. **Hash trait**: 支持在哈希集合中使用
5. **Display trait**: 支持格式化为字符串

### 在模型配置中的使用

在 `ModelInfo` 中 (openai_models.rs lines 263-264):

```rust
pub struct ModelInfo {
    // ...
    pub support_verbosity: bool,
    pub default_verbosity: Option<Verbosity>,
    // ...
}
```

在用户配置中 (v1.rs lines 193-208):

```rust
pub struct UserSavedConfig {
    // ...
    pub model_verbosity: Option<Verbosity>,
    // ...
}
```

## 4. 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `/home/sansha/Github/codex/codex-rs/protocol/src/config_types.rs` | Verbosity 定义 (lines 27-50) |
| `/home/sansha/Github/codex/codex-rs/protocol/src/openai_models.rs` | ModelInfo 中的使用 (lines 263-264) |
| `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v1.rs` | UserSavedConfig 中的使用 (lines 193-208) |
| `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/Verbosity.ts` | 自动生成的 TypeScript 类型 |

## 5. 依赖与外部交互

### 依赖

- **serde**: 序列化/反序列化
- **ts-rs**: TypeScript 类型生成
- **schemars**: JSON Schema 生成
- **strum**: Display 和序列化派生

### 外部交互

- **OpenAI API**: 直接映射到 OpenAI Responses API 的 verbosity 参数
- **模型元数据**: ModelInfo 指示模型是否支持 verbosity 控制
- **用户配置**: 用户可以在配置中设置默认 verbosity
- **UI 控件**: 前端提供 verbosity 选择器

## 6. 风险、边界与改进建议

### 风险

1. **模型支持**: 不是所有模型都支持 verbosity 控制
2. **主观性**: "Low"、"Medium"、"High" 的具体表现因模型而异
3. **提示冲突**: 用户提示中的长度要求可能与 verbosity 设置冲突

### 边界情况

1. **不支持模型**: 在不支持 verbosity 的模型上使用时的行为
2. **动态变更**: 会话中变更 verbosity 的即时效果
3. **组合效果**: verbosity 与其他参数（如 reasoning_effort）的组合效果

### 改进建议

1. **模型兼容性检查**: 在设置 verbosity 前检查模型支持情况
2. **预览功能**: 提供 verbosity 效果的预览或示例
3. **自适应 verbosity**: 基于查询类型自动建议 verbosity 级别
4. **细粒度控制**: 考虑添加更多级别或数值控制
5. **上下文感知**: 允许在单次会话中针对不同消息使用不同 verbosity
6. **成本估算**: 显示不同 verbosity 级别的预估令牌消耗
7. **学习偏好**: 基于用户反馈学习并推荐 verbosity 偏好
