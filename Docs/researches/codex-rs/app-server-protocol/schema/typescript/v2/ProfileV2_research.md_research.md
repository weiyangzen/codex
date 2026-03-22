# ProfileV2 研究文档

## 场景与职责

`ProfileV2` 是 Codex App Server Protocol v2 中用于定义用户配置档案的结构体。它允许用户保存和切换不同的 Codex 配置组合，包括模型选择、审批策略、工具配置等。

配置档案功能使用户能够快速切换不同的工作模式，例如：
- "快速模式"：使用轻量级模型，关闭详细输出
- "深度模式"：使用强模型，启用详细推理
- "安全模式"：严格的沙箱策略和审批要求

## 功能点目的

1. **配置组合管理**：将多个配置项组合为一个命名档案
2. **快速切换**：支持在运行时切换不同档案
3. **配置继承**：支持基础配置 + 档案特定覆盖
4. **实验性功能控制**：包含实验性功能的启用状态

## 具体技术实现

### 数据结构

```rust
// Rust 定义 (codex-rs/app-server-protocol/src/protocol/v2.rs)
#[derive(Serialize, Debug, Clone, PartialEq, JsonSchema, TS, ExperimentalApi)]
#[serde(rename_all = "snake_case")]
#[ts(export_to = "v2/")]
pub struct ProfileV2 {
    pub model: Option<String>,
    pub model_provider: Option<String>,
    #[experimental(nested)]
    pub approval_policy: Option<AskForApproval>,
    /// [UNSTABLE] Optional profile-level override for where approval requests
    /// are routed for review. If omitted, the enclosing config default is
    /// used.
    #[experimental("config/read.approvalsReviewer")]
    pub approvals_reviewer: Option<ApprovalsReviewer>,
    pub service_tier: Option<ServiceTier>,
    pub model_reasoning_effort: Option<ReasoningEffort>,
    pub model_reasoning_summary: Option<ReasoningSummary>,
    pub model_verbosity: Option<Verbosity>,
    pub web_search: Option<WebSearchMode>,
    pub tools: Option<ToolsV2>,
    pub chatgpt_base_url: Option<String>,
    #[serde(default, flatten)]
    pub additional: HashMap<String, JsonValue>,
}
```

```typescript
// TypeScript 生成类型 (schema/typescript/v2/ProfileV2.ts)
export type ProfileV2 = {
    model: string | null,
    model_provider: string | null,
    approval_policy: AskForApproval | null,
    approvals_reviewer: ApprovalsReviewer | null,
    service_tier: ServiceTier | null,
    model_reasoning_effort: ReasoningEffort | null,
    model_reasoning_summary: ReasoningSummary | null,
    model_verbosity: Verbosity | null,
    web_search: WebSearchMode | null,
    tools: ToolsV2 | null,
    chatgpt_base_url: string | null
} & { [key in string]?: number | string | boolean | Array<JsonValue> | { [key in string]?: JsonValue } | null };
```

### 字段说明

| 字段 | 类型 | 说明 | 实验性 |
|------|------|------|--------|
| `model` | `Option<String>` | 模型标识符 | 否 |
| `model_provider` | `Option<String>` | 模型提供商 | 否 |
| `approval_policy` | `Option<AskForApproval>` | 审批策略 | 是 |
| `approvals_reviewer` | `Option<ApprovalsReviewer>` | 审批审核者 | 是 |
| `service_tier` | `Option<ServiceTier>` | 服务层级 | 否 |
| `model_reasoning_effort` | `Option<ReasoningEffort>` | 推理努力程度 | 否 |
| `model_reasoning_summary` | `Option<ReasoningSummary>` | 推理摘要模式 | 否 |
| `model_verbosity` | `Option<Verbosity>` | 输出详细程度 | 否 |
| `web_search` | `Option<WebSearchMode>` | 网页搜索模式 | 否 |
| `tools` | `Option<ToolsV2>` | 工具配置 | 否 |
| `chatgpt_base_url` | `Option<String>` | ChatGPT API 基础 URL | 否 |
| `additional` | `HashMap<String, JsonValue>` | 额外配置项 | 否 |

### 实验性标记

- `#[experimental(nested)]`：表示该字段及其嵌套类型是实验性的
- `#[experimental("config/read.approvalsReviewer")]`：指定实验性功能标识符

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 588-610)
- **TypeScript 生成**: `codex-rs/app-server-protocol/schema/typescript/v2/ProfileV2.ts`

### 相关类型
- `Config`: 包含 `profiles: HashMap<String, ProfileV2>` 字段
- `AskForApproval`: 审批策略枚举
- `ApprovalsReviewer`: 审批审核者枚举
- `ToolsV2`: 工具配置结构体

### 使用场景
- 配置文件中的 `profile` 和 `profiles` 字段
- `ConfigReadResponse` 返回的配置信息
- `TurnStartParams` 中的运行时覆盖

## 依赖与外部交互

### 内部依赖
- `AskForApproval`: 审批策略
- `ApprovalsReviewer`: 审批审核者
- `ServiceTier`: 服务层级
- `ReasoningEffort`: 推理努力程度
- `ReasoningSummary`: 推理摘要
- `Verbosity`: 详细程度
- `WebSearchMode`: 网页搜索模式
- `ToolsV2`: 工具配置
- `serde`: 序列化（使用 `snake_case` 命名）
- `schemars`: JSON Schema 生成
- `ts_rs`: TypeScript 类型生成

### 协议交互

**配置文件示例**:
```toml
[profiles.fast]
model = "gpt-4o-mini"
model_reasoning_effort = "low"
model_verbosity = "concise"

[profiles.deep]
model = "o3-mini"
model_reasoning_effort = "high"
model_reasoning_summary = "detailed"
approval_policy = "on_request"
```

## 风险、边界与改进建议

### 当前限制
1. **实验性功能**：`approval_policy` 和 `approvals_reviewer` 为实验性，API 可能变化
2. **无验证**：类型本身不验证配置组合的有效性
3. **扁平化额外字段**：`additional` 字段使用扁平化序列化，可能与标准字段冲突

### 边界情况
1. **空档案**：所有字段为 `None` 的档案是合法的
2. **部分覆盖**：档案只覆盖指定的字段，其他使用默认值
3. **循环引用**：`additional` 字段中的 JSON 值可能包含循环引用

### 改进建议
1. **添加验证方法**：验证配置组合的有效性
2. **添加默认档案**：提供预设的常用档案模板
3. **档案继承**：支持档案之间的继承关系
4. **条件档案**：根据上下文自动选择档案
5. **稳定实验性功能**：将成熟的实验性功能标记为稳定

### 兼容性注意
- 使用 `snake_case` 命名与 `config.toml` 保持一致
- `additional` 字段使用 `#[serde(flatten)]` 确保额外配置项的正确序列化
- 实验性功能使用 `ExperimentalApi` trait 进行运行时检查
