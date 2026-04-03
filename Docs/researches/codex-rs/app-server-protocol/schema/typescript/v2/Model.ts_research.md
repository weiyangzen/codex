# Model.ts 研究文档

## 场景与职责

`Model.ts` 定义了 Codex 可用 AI 模型的类型。该类型包含模型的完整元数据，用于模型选择、显示和能力声明。

此文件是 TypeScript 类型定义文件，由 Rust 的 `ts-rs` 工具从 Rust 源代码自动生成，用于在客户端与 app-server 之间进行类型安全的通信。

## 功能点目的

1. **模型信息**: 提供模型的完整元数据
2. **模型选择**: 支持用户选择合适的模型
3. **能力声明**: 声明模型支持的功能
4. **升级提示**: 提供模型升级信息

## 具体技术实现

### 数据结构

```typescript
export type Model = { 
  id: string,                                    // 模型唯一标识
  model: string,                                 // 模型名称/ID
  upgrade: string | null,                        // 升级目标模型 ID
  upgradeInfo: ModelUpgradeInfo | null,          // 升级信息
  availabilityNux: ModelAvailabilityNux | null,  // 可用性提示
  displayName: string,                           // 显示名称
  description: string,                           // 描述
  hidden: boolean,                               // 是否在选择器中隐藏
  supportedReasoningEfforts: Array<ReasoningEffortOption>,  // 支持的推理努力级别
  defaultReasoningEffort: ReasoningEffort,       // 默认推理努力级别
  inputModalities: Array<InputModality>,         // 支持的输入模态
  supportsPersonality: boolean,                  // 是否支持个性化
  isDefault: boolean,                            // 是否为默认模型
};
```

### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | `string` | 模型的唯一标识符 |
| `model` | `string` | 实际的模型名称（如 "gpt-4"） |
| `upgrade` | `string \| null` | 推荐升级到的模型 ID |
| `upgradeInfo` | `ModelUpgradeInfo \| null` | 升级相关的详细信息 |
| `availabilityNux` | `ModelAvailabilityNux \| null` | 新用户引导提示 |
| `displayName` | `string` | 用户界面显示的名称 |
| `description` | `string` | 模型的描述信息 |
| `hidden` | `boolean` | 是否在选择列表中隐藏 |
| `supportedReasoningEfforts` | `ReasoningEffortOption[]` | 支持的推理努力级别选项 |
| `defaultReasoningEffort` | `ReasoningEffort` | 默认的推理努力级别 |
| `inputModalities` | `InputModality[]` | 支持的输入类型（文本、图像等） |
| `supportsPersonality` | `boolean` | 是否支持个性化设置 |
| `isDefault` | `boolean` | 是否为默认选中的模型 |

### 生成来源

该文件由 Rust 结构体通过 `ts-rs` 自动生成：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct Model {
    pub id: String,
    pub model: String,
    pub upgrade: Option<String>,
    pub upgrade_info: Option<ModelUpgradeInfo>,
    pub availability_nux: Option<ModelAvailabilityNux>,
    pub display_name: String,
    pub description: String,
    pub hidden: bool,
    pub supported_reasoning_efforts: Vec<ReasoningEffortOption>,
    pub default_reasoning_effort: ReasoningEffort,
    pub input_modalities: Vec<InputModality>,
    pub supports_personality: bool,
    pub is_default: bool,
}
```

## 关键代码路径与文件引用

### 上游依赖（Rust 源文件）

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 定义 Rust 类型 |
| `codex-rs/core/src/rollout/policy.rs` | 模型策略和路由 |
| `codex-rs/codex-api/src/rate_limits.rs` | 模型速率限制 |

### 下游使用（TypeScript 消费者）

- VS Code 扩展的模型选择器
- TUI 的模型配置界面
- 模型列表显示

### 相关类型

| 类型 | 说明 |
|------|------|
| `ModelUpgradeInfo.ts` | 模型升级信息 |
| `ModelAvailabilityNux.ts` | 可用性提示 |
| `ReasoningEffortOption.ts` | 推理努力选项 |
| `InputModality.ts` | 输入模态 |
| `ReasoningEffort.ts` | 推理努力级别 |

### 相关测试

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/model_list.rs` | 模型列表测试 |

## 依赖与外部交互

### 模型列表流程

```
Client -> App Server: ModelListParams
App Server -> Client: ModelListResponse { data: Model[] }
Client: 渲染模型列表
```

### 模型选择场景

1. **新会话**: 使用 `isDefault` 为 true 的模型
2. **模型切换**: 用户从列表中选择其他模型
3. **升级提示**: 显示 `upgradeInfo` 引导用户升级

## 风险、边界与改进建议

### 改进建议

1. **添加性能指标**:
   ```typescript
   {
     // ...
     performanceMetrics?: {
       typicalLatencyMs?: number;
       throughput?: string;
     };
   }
   ```

2. **添加定价信息**:
   ```typescript
   {
     // ...
     pricing?: {
       inputPricePerToken: number;
       outputPricePerToken: number;
       currency: string;
     };
   }
   ```

3. **添加限制信息**:
   ```typescript
   {
     // ...
     limits?: {
       maxContextTokens: number;
       maxOutputTokens: number;
       trainingCutoff?: string;
     };
   }
   ```

4. **添加标签/分类**:
   ```typescript
   {
     // ...
     tags: string[];  // ["coding", "analysis", "creative"]
     category: "fast" | "balanced" | "powerful";
   }
   ```
