# CollaborationModeMask.ts 研究文档

## 场景与职责

`CollaborationModeMask.ts` 定义了协作模式预设元数据的类型，用于 `collaborationMode/list` API 的响应。该类型为客户端提供协作模式的配置模板，包括模式名称、模型选择、推理努力级别等预设参数。

该类型是 Codex 实验性协作功能的一部分，支持用户在不同协作场景（如代码审查、结对编程、代码解释等）之间快速切换。

## 功能点目的

### 核心功能

1. **协作模式预设**：提供预定义的协作模式配置
2. **模型绑定**：每个模式可以关联特定的 AI 模型
3. **推理配置**：支持设置推理努力级别（reasoning effort）
4. **客户端指导**：帮助 UI 展示可用的协作模式选项

### 类型定义

```typescript
import type { ModeKind } from "../ModeKind";
import type { ReasoningEffort } from "../ReasoningEffort";

/**
 * EXPERIMENTAL - collaboration mode preset metadata for clients.
 */
export type CollaborationModeMask = { 
  name: string, 
  mode: ModeKind | null, 
  model: string | null, 
  reasoning_effort: ReasoningEffort | null | null, 
};
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | `string` | 协作模式的显示名称 |
| `mode` | `ModeKind \| null` | 协作模式类型（如 agent、ask、edit 等） |
| `model` | `string \| null` | 推荐的 AI 模型标识符 |
| `reasoning_effort` | `ReasoningEffort \| null \| null` | 推理努力级别（低/中/高） |

### ModeKind 枚举

```typescript
type ModeKind = "agent" | "ask" | "edit" | "review" | "compact";
```

### ReasoningEffort 枚举

```typescript
type ReasoningEffort = "low" | "medium" | "high";
```

## 具体技术实现

### 代码生成来源

**Rust 源码位置**：`codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1797-1825)

```rust
/// EXPERIMENTAL - list collaboration mode presets.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CollaborationModeListParams {}

/// EXPERIMENTAL - collaboration mode preset metadata for clients.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CollaborationModeMask {
    pub name: String,
    pub mode: Option<ModeKind>,
    pub model: Option<String>,
    #[serde(rename = "reasoning_effort")]
    #[ts(rename = "reasoning_effort")]
    pub reasoning_effort: Option<Option<ReasoningEffort>>,
}

impl From<CoreCollaborationModeMask> for CollaborationModeMask {
    fn from(value: CoreCollaborationModeMask) -> Self {
        Self {
            name: value.name,
            mode: value.mode,
            model: value.model,
            reasoning_effort: value.reasoning_effort,
        }
    }
}
```

### 核心协议映射

该类型与 `codex_protocol::config_types::CollaborationModeMask` 进行转换：

| 字段 | Core Protocol | 说明 |
|------|---------------|------|
| `name` | `String` | 模式名称 |
| `mode` | `Option<ModeKind>` | 模式类型 |
| `model` | `Option<String>` | 模型标识符 |
| `reasoning_effort` | `Option<Option<ReasoningEffort>>` | 双重 Option 表示"未设置"和"显式设为 null" |

### 响应类型

```rust
/// EXPERIMENTAL - collaboration mode presets response.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct CollaborationModeListResponse {
    pub data: Vec<CollaborationModeMask>,
}
```

## 关键代码路径与文件引用

### 依赖关系

```
CollaborationModeMask.ts
  ├── ModeKind.ts (父目录)
  └── ReasoningEffort.ts (父目录)
```

### API 流程

```
Client                              Server
  |                                    |
  |-- collaborationMode/list -------->|
  |   CollaborationModeListParams      |
  |<-- CollaborationModeListResponse --|
  |   { data: CollaborationModeMask[] }
  |                                    |
  |-- thread/start ------------------->|
  |   (使用选中的 mode/model)           |
```

### 相关文件

| 文件 | 说明 |
|------|------|
| `CollaborationModeListParams.ts` | 列表请求参数（空对象） |
| `CollaborationModeListResponse.ts` | 列表响应包装器 |
| `ModeKind.ts` | 协作模式类型枚举 |
| `ReasoningEffort.ts` | 推理努力级别枚举 |

## 依赖与外部交互

### 协作模式系统

协作模式是 Codex 的高级功能，影响：

1. **系统提示词（System Prompt）**：
   - 不同模式使用不同的系统提示词模板
   - 影响 AI 的行为风格和响应格式

2. **工具可用性**：
   - 某些模式可能限制可用工具
   - 例如 "ask" 模式可能禁用文件修改工具

3. **审批策略**：
   - 不同模式可能有不同的默认审批设置
   - "agent" 模式可能需要更多审批

### 使用场景

| 模式 | 用途 | 典型配置 |
|------|------|----------|
| `agent` | 自主任务执行 | 高推理努力，强大模型 |
| `ask` | 问答和解释 | 中等推理，标准模型 |
| `edit` | 代码编辑辅助 | 低推理，快速模型 |
| `review` | 代码审查 | 高推理，分析型模型 |
| `compact` | 上下文压缩 | 专用压缩模型 |

## 风险、边界与改进建议

### 潜在风险

1. **实验性不稳定**：API 形状可能随时变更
2. **模式冲突**：用户配置与模式预设可能冲突
3. **模型可用性**：预设模型可能在当前环境中不可用

### 边界情况

1. **空模式列表**：服务器可能返回空列表
2. **无效模型**：`model` 字段可能引用已弃用或不可用的模型
3. **reasoning_effort 双重 null**：
   - `null`：未设置，使用默认值
   - `Some(null)`：显式禁用推理努力设置

### 改进建议

1. **添加描述字段**：
   ```typescript
   interface CollaborationModeMask {
     name: string;
     description?: string;  // 用户友好的描述
     mode: ModeKind | null;
     model: string | null;
     reasoning_effort: ReasoningEffort | null | null;
   }
   ```

2. **添加图标/颜色**：
   ```typescript
   interface CollaborationModeMask {
     // ...
     icon?: string;      // 图标标识符
     color?: string;     // 主题色
   }
   ```

3. **添加能力标记**：
   ```typescript
   interface CollaborationModeMask {
     // ...
     capabilities: {
       supportsFiles: boolean;
       supportsWebSearch: boolean;
       supportsExecution: boolean;
     };
   }
   ```

4. **模型回退策略**：
   - 当预设模型不可用时，提供替代模型建议
   - 添加 `fallback_models` 字段

### 版本兼容性

- 当前版本：v2
- 稳定性：**EXPERIMENTAL**（实验性）
- 变更风险：高
- 生产使用：不推荐，仅供测试和反馈

### 相关实验性功能

- `CollaborationModeListParams`
- `CollaborationModeListResponse`
- `ThreadStartParams` 中的 `personality` 字段

### 未来方向

1. **用户自定义模式**：允许用户创建和保存自己的协作模式预设
2. **模式切换**：支持在现有线程中动态切换模式
3. **模式组合**：支持组合多个模式的特性
