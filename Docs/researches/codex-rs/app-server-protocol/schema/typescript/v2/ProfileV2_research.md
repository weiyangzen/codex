# ProfileV2 研究文档

## 场景与职责

`ProfileV2` 是 Codex app-server-protocol v2 协议中的配置文件类型，定义了用户可自定义的各种 AI 模型和行为设置。它支持模型选择、审批策略、服务等级、推理设置等多种配置选项，是 Codex 配置系统的核心组成部分。

在 Codex 的配置体系中，`ProfileV2` 承担以下职责：
1. **个性化配置**：允许用户定义多组不同的配置预设（profiles）
2. **模型定制**：配置 AI 模型、提供商、推理努力程度等
3. **安全策略**：设置审批策略（approval_policy）和审批审核者（approvals_reviewer）
4. **工具控制**：配置 Web 搜索、工具使用等行为
5. **向后兼容**：通过 `additional` 字段支持未来扩展

## 功能点目的

### 核心功能
- **模型配置**：`model`, `model_provider`, `model_reasoning_effort` 等
- **审批控制**：`approval_policy` 控制何时需要用户审批
- **服务等级**：`service_tier` 配置 API 服务等级
- **工具配置**：`tools`, `web_search` 控制工具使用
- **扩展支持**：`additional` HashMap 支持任意额外配置

### 实验性功能
- `approval_policy`：标记为 `#[experimental(nested)]`，表示整个嵌套结构是实验性的
- `approvals_reviewer`：标记为 `#[experimental("config/read.approvalsReviewer")]`

## 具体技术实现

### 数据结构定义

**TypeScript 定义**（`ProfileV2.ts`）：
```typescript
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
} & ({ [key in string]?: number | string | boolean | Array<JsonValue> | { [key in string]?: JsonValue } | null });
```

**Rust 定义**（`v2.rs` 行 588-610）：
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS, ExperimentalApi)]
#[serde(rename_all = "snake_case")]
#[ts(export_to = "v2/")]
pub struct ProfileV2 {
    pub model: Option<String>,
    pub model_provider: Option<String>,
    #[experimental(nested)]
    pub approval_policy: Option<AskForApproval>,
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

### 关键字段说明

| 字段 | 类型 | 实验性 | 说明 |
|------|------|--------|------|
| `model` | `string \| null` | 否 | AI 模型标识（如 "o3-mini", "gpt-4"） |
| `model_provider` | `string \| null` | 否 | 模型提供商（如 "openai"） |
| `approval_policy` | `AskForApproval \| null` | 是 | 审批策略（如 "unless-trusted", "never"） |
| `approvals_reviewer` | `ApprovalsReviewer \| null` | 是 | 审批审核者（如 "user", "guardian-subagent"） |
| `service_tier` | `ServiceTier \| null` | 否 | 服务等级（如 "auto", "flex", "default"） |
| `model_reasoning_effort` | `ReasoningEffort \| null` | 否 | 推理努力程度（如 "low", "medium", "high"） |
| `model_reasoning_summary` | `ReasoningSummary \| null` | 否 | 推理摘要设置 |
| `model_verbosity` | `Verbosity \| null` | 否 | 输出详细程度 |
| `web_search` | `WebSearchMode \| null` | 否 | Web 搜索模式 |
| `tools` | `ToolsV2 \| null` | 否 | 工具配置 |
| `chatgpt_base_url` | `string \| null` | 否 | ChatGPT API 基础 URL |
| `additional` | `object` | 否 | 额外配置字段（扁平化） |

### 实验性 API 标记

`ProfileV2` 实现了 `ExperimentalApi` trait（行 6820-6830）：

```rust
impl crate::experimental_api::ExperimentalApi for ProfileV2 {
    fn experimental_reason(&self) -> Option<&'static str> {
        // 如果任何实验性字段被设置，返回 "nested"
        if self.approval_policy.is_some() || self.approvals_reviewer.is_some() {
            Some("nested")
        } else {
            None
        }
    }
}
```

## 关键代码路径与文件引用

### 定义位置
- **Rust 定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs` 行 588-610
- **TypeScript 生成**：`codex-rs/app-server-protocol/schema/typescript/v2/ProfileV2.ts`
- **JSON Schema**：`codex-rs/app-server-protocol/schema/json/v2/ConfigReadResponse.json`

### 使用位置
- **Config**：`v2.rs` 行 713 - 作为 `profiles` HashMap 的值类型
- **测试用例**：`v2.rs` 行 6935, 6990 - 构造测试数据
- **ConfigReadResponse**：作为配置读取响应的一部分

### 相关类型
- `AskForApproval`：审批策略枚举（行 201-223）
- `ApprovalsReviewer`：审批审核者枚举（行 275-278）
- `ServiceTier`：服务等级枚举（来自 `codex_protocol`）
- `ReasoningEffort`：推理努力程度枚举（来自 `codex_protocol`）
- `ToolsV2`：工具配置类型（行 539-543）
- `Config`：包含 `profiles: HashMap<String, ProfileV2>`（行 692-727）

## 依赖与外部交互

### 依赖项
- `AskForApproval`：审批策略
- `ApprovalsReviewer`：审批审核者
- `ServiceTier`, `ReasoningEffort`, `ReasoningSummary`, `Verbosity`：来自 `codex_protocol`
- `WebSearchMode`：Web 搜索模式
- `ToolsV2`：工具配置
- `serde`：序列化/反序列化
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成
- `codex_experimental_api_macros::ExperimentalApi`：实验性 API 标记

### 上游依赖
- `ConfigToml`（核心配置）：`core/src/config/mod.rs`

### 下游使用
- `Config`：作为 `profiles` 字段的值类型
- `ConfigReadResponse`：配置读取响应
- `ThreadStartParams`：线程启动时可指定 profile

### 协议集成
- 通过 `config/read` RPC 方法获取
- 通过 `config/value/write` 或 `config/batchWrite` 修改
- 序列化为 JSON 格式通过 WebSocket 传输

## 风险、边界与改进建议

### 潜在风险
1. **实验性功能依赖**：`approval_policy` 和 `approvals_reviewer` 是实验性的，可能变更
2. **配置冲突**：`additional` 字段可能与标准字段冲突
3. **验证缺失**：缺乏对字段值的严格验证（如 `chatgpt_base_url` 的 URL 格式）

### 边界情况
1. **空 Profile**：所有字段为 `null` 时的默认行为
2. **无效模型**：`model` 指向不存在的模型
3. **策略不兼容**：某些审批策略与特定模型不兼容

### 改进建议
1. **验证增强**：
   - 添加字段值验证（如 URL 格式、模型存在性）
   - 验证 `additional` 字段不与标准字段冲突
   - 添加 profile 间一致性检查

2. **结构优化**：
   - 将 `additional` 改为命名空间形式（如 `extra: { [namespace: string]: JsonValue }`）
   - 添加 `name` 和 `description` 字段用于 profile 展示
   - 添加 `created_at` 和 `updated_at` 时间戳

3. **功能扩展**：
   - 添加 `inherits` 字段支持 profile 继承
   - 添加 `tags` 字段支持分类
   - 添加 `is_default` 布尔字段标记默认 profile

4. **文档完善**：
   - 为每个字段添加更详细的说明文档
   - 提供常见配置示例
   - 明确实验性字段的稳定化时间表

5. **向后兼容**：
   - 考虑添加版本字段 `schema_version`
   - 提供配置迁移工具
