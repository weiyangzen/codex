# ReasoningEffort.ts Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`ReasoningEffort` 定义了 AI 模型推理努力的级别，控制模型在推理任务上花费的计算资源和时间。

**使用场景：**
- 配置模型推理强度
- 根据任务复杂度选择合适的推理级别
- 在性能和成本之间取得平衡

**职责：**
- 提供标准化的推理努力级别
- 支持从字符串解析
- 与 OpenAI API 兼容

## 2. 功能点目的 (Purpose of This Type)

该类型的主要目的是：

1. **控制推理深度**：允许用户控制模型的推理深度和复杂度
2. **成本优化**：低推理强度可以降低成本和延迟
3. **质量保证**：高推理强度可以获得更好的推理结果

**推理努力级别（从低到高）：**
- `none`：无推理
- `minimal`：最小推理
- `low`：低推理强度
- `medium`：中等推理强度（默认）
- `high`：高推理强度
- `xhigh`：极高推理强度

## 3. 具体技术实现 (Technical Implementation Details)

**Rust 定义**（位于 `codex-rs/protocol/src/openai_models.rs` 第 24-59 行）：

```rust
/// See https://platform.openai.com/docs/guides/reasoning?api-mode=responses#get-started-with-reasoning
#[derive(
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
    EnumIter,
    Hash,
)]
#[serde(rename_all = "lowercase")]
#[strum(serialize_all = "lowercase")]
pub enum ReasoningEffort {
    None,
    Minimal,
    Low,
    #[default]
    Medium,
    High,
    XHigh,
}

impl FromStr for ReasoningEffort {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        serde_json::from_value(serde_json::Value::String(s.to_string()))
            .map_err(|_| format!("invalid reasoning_effort: {s}"))
    }
}
```

**TypeScript 生成定义：**

```typescript
/**
 * See https://platform.openai.com/docs/guides/reasoning?api-mode=responses#get-started-with-reasoning
 */
export type ReasoningEffort = "none" | "minimal" | "low" | "medium" | "high" | "xhigh";
```

**关键实现细节：**
- 实现了 `FromStr`，支持从字符串解析
- 实现了 `EnumIter`，支持遍历所有变体
- 默认值为 `Medium`
- 与 OpenAI API 的推理参数兼容

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

**Rust 源文件：**
- `/home/sansha/Github/codex/codex-rs/protocol/src/openai_models.rs`（第 24-59 行）：主要定义

**TypeScript 生成文件：**
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/ReasoningEffort.ts`

**使用位置：**
- `ModelPreset` 和 `ModelInfo`：作为模型配置的一部分
- `Settings` 和 `CollaborationMode`：用户会话配置
- `Op::UserTurn` 和 `Op::OverrideTurnContext`：操作参数
- `ReasoningEffortPreset`：模型支持的推理选项

**相关类型：**
- `ReasoningEffortPreset`：包含描述信息的推理选项
- `ReasoningSummary`：推理摘要配置

## 5. 依赖与外部交互 (Dependencies and External Interactions)

**依赖 crate：**
- `serde`：序列化/反序列化
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成
- `strum`：字符串枚举处理

**序列化格式：**
- JSON 中使用 lowercase：`"none"`, `"minimal"`, `"low"`, `"medium"`, `"high"`, `"xhigh"`

**与 OpenAI API 的交互：**
- 直接映射到 OpenAI API 的 `reasoning_effort` 参数
- 参考文档：https://platform.openai.com/docs/guides/reasoning

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

**潜在风险：**
1. **成本影响**：`xhigh` 推理强度可能导致显著更高的成本
2. **延迟增加**：高推理强度会增加响应时间
3. **模型兼容性**：不是所有模型都支持所有推理级别

**边界情况：**
1. 模型不支持：某些模型可能忽略推理努力设置
2. 字符串解析：无效的字符串输入会导致解析错误

**改进建议：**
1. **模型兼容性检查**：在 UI 中显示当前模型支持的推理级别
2. **成本估算**：显示不同推理级别的预估成本
3. **自动选择**：根据任务类型自动推荐推理级别
4. **推理摘要**：与 `ReasoningSummary` 结合，提供推理过程的可见性
5. **限制设置**：允许管理员限制某些用户组的最大推理级别
6. **性能基准**：提供不同推理级别的性能基准数据
