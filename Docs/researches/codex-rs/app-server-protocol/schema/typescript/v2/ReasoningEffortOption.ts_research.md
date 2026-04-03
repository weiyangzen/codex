# ReasoningEffortOption.ts 研究文档

## 场景与职责

`ReasoningEffortOption.ts` 定义了模型推理努力程度选项的数据结构，用于在模型列表中展示不同推理努力级别及其描述。这是 Codex 模型配置系统的一部分，帮助用户理解和选择适合其需求的推理级别。

## 功能点目的

该类型用于：
1. **模型能力展示**：在模型列表中显示支持的推理努力选项
2. **用户引导**：通过描述帮助用户选择合适的推理级别
3. **配置界面**：为 TUI/IDE 提供类型化的选项数据
4. **API 一致性**：确保前后端对推理努力程度的理解一致

## 具体技术实现

### 数据结构定义

```typescript
import type { ReasoningEffort } from "../ReasoningEffort";

export type ReasoningEffortOption = { 
  reasoningEffort: ReasoningEffort,  // 推理努力级别
  description: string,               // 人类可读的描述
};
```

### 字段详解

| 字段 | 类型 | 说明 |
|------|------|------|
| reasoningEffort | ReasoningEffort | 推理努力级别枚举值 |
| description | string | 该级别的描述说明，用于 UI 展示 |

### ReasoningEffort 枚举

在 `codex-rs/protocol/src/openai_models.rs` 中定义：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "lowercase")]
#[ts(export_to = "v2/")]
pub enum ReasoningEffort {
    Low,     // 低推理努力，响应更快
    Medium,  // 中等推理努力，平衡速度和质量
    High,    // 高推理努力，最佳质量但较慢
}
```

### 服务端使用

在 `codex-rs/app-server/src/models.rs` 中，用于构建模型列表响应：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct Model {
    pub id: String,
    pub name: String,
    pub description: String,
    pub reasoning_effort_options: Vec<ReasoningEffortOption>,
    // ... 其他字段
}
```

### 典型选项值

```typescript
const effortOptions: ReasoningEffortOption[] = [
  { reasoningEffort: "low", description: "Faster responses with less detailed reasoning" },
  { reasoningEffort: "medium", description: "Balanced speed and reasoning quality" },
  { reasoningEffort: "high", description: "Most thorough reasoning, may be slower" },
];
```

## 关键代码路径与文件引用

### TypeScript 类型定义
- 文件：`codex-rs/app-server-protocol/schema/typescript/v2/ReasoningEffortOption.ts`

### Rust 协议定义
- V2 API：`codex-rs/app-server-protocol/src/protocol/v2.rs`
- 核心枚举：`codex-rs/protocol/src/openai_models.rs`
- 模型定义：`codex-rs/app-server/src/models.rs`

### 测试覆盖
- 模型列表测试：`codex-rs/app-server/tests/suite/v2/model_list.rs`

### 相关类型
- Model：`codex-rs/app-server-protocol/schema/typescript/v2/Model.ts`
- ReasoningEffort：`codex-rs/app-server-protocol/schema/typescript/ReasoningEffort.ts`

## 依赖与外部交互

### 上游依赖
- OpenAI API：定义了 reasoning_effort 参数
- 模型配置：每个模型定义其支持的推理选项

### 下游消费
- TUI 模型选择器：显示推理选项供用户选择
- IDE 扩展：在模型配置界面中展示
- 配置文件：用户可以通过配置文件设置默认推理级别

### 配置集成

在 `config.toml` 中：
```toml
model_reasoning_effort = "medium"
```

## 风险、边界与改进建议

### 边界情况
1. **空选项列表**：某些模型可能不支持推理努力配置
2. **无效值**：API 可能拒绝不支持的推理努力值
3. **动态变化**：模型支持的选项可能随版本变化

### 潜在风险
1. **描述本地化**：description 是英文，需要国际化支持
2. **模型差异**：不同模型对相同推理级别的响应可能不同
3. **成本影响**：高推理努力可能增加 API 调用成本

### 改进建议
1. **本地化支持**：添加多语言描述支持
2. **成本提示**：在描述中包含大致的成本影响
3. **动态获取**：从 API 动态获取模型支持的选项
4. **默认值提示**：标明推荐的默认选项
5. **性能指标**：添加典型的响应时间范围
