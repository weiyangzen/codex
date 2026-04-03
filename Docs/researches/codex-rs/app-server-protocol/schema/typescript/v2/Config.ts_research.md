# Config.ts Research Document

## 场景与职责

`Config` 是 Codex 应用服务器协议 v2 中的核心配置类型，用于表示完整的 Codex 配置结构。它包含了模型设置、审批策略、沙盒模式、工具配置、用户画像等所有可配置选项，是客户端与服务器之间传递配置信息的主要载体。

该类型在以下场景中发挥关键作用：
- **配置读取**：`config/read` RPC 方法返回当前生效的配置
- **配置写入**：`config/write` RPC 方法接收配置更新
- **配置层管理**：支持多层级配置（MDM、System、User、Project、Session）的合并与覆盖
- **Profile 切换**：支持多个用户画像（profiles）的定义和切换
- **实验性功能**：承载各种实验性功能的配置开关

## 功能点目的

1. **集中配置管理**：将所有 Codex 配置选项统一到一个类型中
2. **分层配置支持**：支持从多个来源（MDM、系统、用户、项目、会话）加载配置
3. **Profile 机制**：允许用户定义和切换不同的配置画像
4. **扩展性**：通过 `additional` 字段支持自定义配置项
5. **向后兼容**：保留与旧版本配置的兼容性

## 具体技术实现

### 数据结构定义

```typescript
export type Config = {
  model: string | null,
  review_model: string | null,
  model_context_window: bigint | null,
  model_auto_compact_token_limit: bigint | null,
  model_provider: string | null,
  approval_policy: AskForApproval | null,
  /**
   * [UNSTABLE] Optional default for where approval requests are routed for
   * review.
   */
  approvals_reviewer: ApprovalsReviewer | null,
  sandbox_mode: SandboxMode | null,
  sandbox_workspace_write: SandboxWorkspaceWrite | null,
  forced_chatgpt_workspace_id: string | null,
  forced_login_method: ForcedLoginMethod | null,
  web_search: WebSearchMode | null,
  tools: ToolsV2 | null,
  profile: string | null,
  profiles: { [key in string]?: ProfileV2 },
  instructions: string | null,
  developer_instructions: string | null,
  compact_prompt: string | null,
  model_reasoning_effort: ReasoningEffort | null,
  model_reasoning_summary: ReasoningSummary | null,
  model_verbosity: Verbosity | null,
  service_tier: ServiceTier | null,
  analytics: AnalyticsConfig | null
} & ({ [key in string]?: number | string | boolean | Array<JsonValue> | { [key in string]?: JsonValue } | null });
```

### 关键字段说明

| 字段 | 类型 | 说明 | 实验性 |
|---|---|---|---|
| `model` | `string \| null` | 默认使用的 AI 模型 | 否 |
| `review_model` | `string \| null` | 用于代码审查的模型 | 否 |
| `model_context_window` | `bigint \| null` | 模型上下文窗口大小 | 否 |
| `model_auto_compact_token_limit` | `bigint \| null` | 自动压缩的 token 阈值 | 否 |
| `model_provider` | `string \| null` | 模型提供商 | 否 |
| `approval_policy` | `AskForApproval \| null` | 审批策略配置 | 是 (nested) |
| `approvals_reviewer` | `ApprovalsReviewer \| null` | 审批请求路由目标 | 是 (config/read.approvalsReviewer) |
| `sandbox_mode` | `SandboxMode \| null` | 沙盒执行模式 | 否 |
| `sandbox_workspace_write` | `SandboxWorkspaceWrite \| null` | 工作区写入配置 | 否 |
| `forced_chatgpt_workspace_id` | `string \| null` | 强制的 ChatGPT 工作区 ID | 否 |
| `forced_login_method` | `ForcedLoginMethod \| null` | 强制的登录方式 | 否 |
| `web_search` | `WebSearchMode \| null` | 网页搜索模式 | 否 |
| `tools` | `ToolsV2 \| null` | 工具配置 | 否 |
| `profile` | `string \| null` | 当前激活的 profile 名称 | 否 |
| `profiles` | `{ [key: string]?: ProfileV2 }` | 所有可用的 profiles | 是 (nested) |
| `instructions` | `string \| null` | 用户自定义指令 | 否 |
| `developer_instructions` | `string \| null` | 开发者指令 | 否 |
| `compact_prompt` | `string \| null` | 压缩提示词 | 否 |
| `model_reasoning_effort` | `ReasoningEffort \| null` | 模型推理努力程度 | 否 |
| `model_reasoning_summary` | `ReasoningSummary \| null` | 推理摘要模式 | 否 |
| `model_verbosity` | `Verbosity \| null` | 输出详细程度 | 否 |
| `service_tier` | `ServiceTier \| null` | 服务等级 | 否 |
| `analytics` | `AnalyticsConfig \| null` | 分析配置 | 否 |
| `additional` | `Record<string, JsonValue>` | 额外自定义配置 | 否 |

**Rust 源定义**（位于 `codex-rs/app-server-protocol/src/protocol/v2.rs` 第 689-727 行）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS, ExperimentalApi)]
#[serde(rename_all = "snake_case")]
#[ts(export_to = "v2/")]
pub struct Config {
    pub model: Option<String>,
    pub review_model: Option<String>,
    pub model_context_window: Option<i64>,
    pub model_auto_compact_token_limit: Option<i64>,
    pub model_provider: Option<String>,
    #[experimental(nested)]
    pub approval_policy: Option<AskForApproval>,
    /// [UNSTABLE] Optional default for where approval requests are routed for
    /// review.
    #[experimental("config/read.approvalsReviewer")]
    pub approvals_reviewer: Option<ApprovalsReviewer>,
    pub sandbox_mode: Option<SandboxMode>,
    pub sandbox_workspace_write: Option<SandboxWorkspaceWrite>,
    pub forced_chatgpt_workspace_id: Option<String>,
    pub forced_login_method: Option<ForcedLoginMethod>,
    pub web_search: Option<WebSearchMode>,
    pub tools: Option<ToolsV2>,
    pub profile: Option<String>,
    #[experimental(nested)]
    #[serde(default)]
    pub profiles: HashMap<String, ProfileV2>,
    pub instructions: Option<String>,
    pub developer_instructions: Option<String>,
    pub compact_prompt: Option<String>,
    pub model_reasoning_effort: Option<ReasoningEffort>,
    pub model_reasoning_summary: Option<ReasoningSummary>,
    pub model_verbosity: Option<Verbosity>,
    pub service_tier: Option<ServiceTier>,
    pub analytics: Option<AnalyticsConfig>,
    #[experimental("config/read.apps")]
    #[serde(default)]
    pub apps: Option<AppsConfig>,
    #[serde(default, flatten)]
    pub additional: HashMap<String, JsonValue>,
}
```

## 关键代码路径与文件引用

- **TypeScript 源文件**: `codex-rs/app-server-protocol/schema/typescript/v2/Config.ts`
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (第 689-727 行)
- **相关 RPC 方法**:
  - `config/read` - 读取配置
  - `config/write` - 写入配置
  - `config/batchWrite` - 批量写入配置
- **配置层定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (第 440-496 行)

## 依赖与外部交互

### 导入类型

```typescript
import type { ForcedLoginMethod } from "../ForcedLoginMethod";
import type { ReasoningEffort } from "../ReasoningEffort";
import type { ReasoningSummary } from "../ReasoningSummary";
import type { ServiceTier } from "../ServiceTier";
import type { Verbosity } from "../Verbosity";
import type { WebSearchMode } from "../WebSearchMode";
import type { JsonValue } from "../serde_json/JsonValue";
import type { AnalyticsConfig } from "./AnalyticsConfig";
import type { ApprovalsReviewer } from "./ApprovalsReviewer";
import type { AskForApproval } from "./AskForApproval";
import type { ProfileV2 } from "./ProfileV2";
import type { SandboxMode } from "./SandboxMode";
import type { SandboxWorkspaceWrite } from "./SandboxWorkspaceWrite";
import type { ToolsV2 } from "./ToolsV2";
```

### 配置层优先级

配置从多个层加载，优先级从低到高：

```
MDM (0) → System (10) → User (20) → Project (25) → SessionFlags (30) → LegacyManaged (40-50)
```

高优先级的配置会覆盖低优先级的同名配置。

### 使用示例

读取配置：

```typescript
const response: ConfigReadResponse = await client.call("config/read", {
  includeLayers: true,
  cwd: "/path/to/project"
});

const config: Config = response.config;
console.log(config.model); // "o3-mini"
console.log(config.approval_policy); // "on-request" | "never" | { granular: {...} }
```

## 风险、边界与改进建议

### 潜在风险

1. **实验性功能稳定性**：标记为 `#[experimental]` 的字段可能在未来的版本中发生变化
2. **配置验证**：`additional` 字段允许任意 JSON 值，可能导致无效配置
3. **大整数处理**：`model_context_window` 使用 `bigint`，在 JavaScript 中需要特殊处理

### 边界情况

1. **空配置**：所有字段都是可选的，需要处理全 null 的情况
2. **Profile 切换**：切换 profile 时需要重新加载相关配置
3. **配置冲突**：多层配置合并时可能出现意外的覆盖行为

### 改进建议

1. **配置验证**：添加 JSON Schema 验证，确保配置值的有效性
2. **默认值文档**：为每个字段提供清晰的默认值说明
3. **迁移指南**：实验性功能稳定后，提供配置迁移指南
4. **类型细化**：对于 `additional` 字段，考虑提供更具体的类型约束
5. **配置 diff**：支持配置变更的 diff 展示，便于用户理解变更影响
