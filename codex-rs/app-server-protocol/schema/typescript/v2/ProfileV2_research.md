# ProfileV2 研究文档

## 1. 场景与职责

`ProfileV2` 是Codex配置系统中的配置文件类型，定义了用户可自定义的各种AI模型和行为设置。它支持模型选择、审批策略、服务等级、推理设置等多种配置选项。

**使用场景：**
- 用户个性化设置：保存用户的AI交互偏好
- 多配置文件管理：支持创建多个配置文件用于不同场景
- 配置导入导出：在不同设备间同步设置
- 实验性功能：包含标记为UNSTABLE的实验性配置

## 2. 功能点目的

该类型的核心目的是：

1. **模型配置**：选择AI模型和提供商
2. **审批控制**：配置命令执行的审批策略
3. **服务质量**：设置服务等级（如auto/default）
4. **推理优化**：配置推理努力和摘要选项
5. **交互风格**：设置输出详细程度和搜索模式
6. **工具配置**：管理可用工具集
7. **扩展性**：支持额外的自定义配置

## 3. 具体技术实现

### TypeScript 定义
```typescript
import type { ApprovalsReviewer } from "./ApprovalsReviewer.js";
import type { AskForApproval } from "./AskForApproval.js";
import type { JsonValue } from "../common/JsonValue.js";
import type { ReasoningEffort } from "./ReasoningEffort.js";
import type { ReasoningSummary } from "./ReasoningSummary.js";
import type { ServiceTier } from "./ServiceTier.js";
import type { ToolsV2 } from "./ToolsV2.js";
import type { Verbosity } from "./Verbosity.js";
import type { WebSearchMode } from "./WebSearchMode.js";

export type ProfileV2 = {
  model: string | null;
  model_provider: string | null;
  approval_policy: AskForApproval | null;
  /**
   * [UNSTABLE] Optional profile-level override for where approval requests
   * are routed for review. If omitted, the enclosing config default is
   * used.
   */
  approvals_reviewer: ApprovalsReviewer | null;
  service_tier: ServiceTier | null;
  model_reasoning_effort: ReasoningEffort | null;
  model_reasoning_summary: ReasoningSummary | null;
  model_verbosity: Verbosity | null;
  web_search: WebSearchMode | null;
  tools: ToolsV2 | null;
  chatgpt_base_url: string | null;
  additional: { [key: string]: JsonValue };
};
```

### Rust 源实现
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS, ExperimentalApi)]
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

### 关键字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `model` | `string \| null` | AI模型名称（如 "gpt-4"） |
| `model_provider` | `string \| null` | 模型提供商 |
| `approval_policy` | `AskForApproval \| null` | 命令执行审批策略（实验性） |
| `approvals_reviewer` | `ApprovalsReviewer \| null` | 审批请求路由目标 **[UNSTABLE]** |
| `service_tier` | `ServiceTier \| null` | 服务等级（auto/default） |
| `model_reasoning_effort` | `ReasoningEffort \| null` | 模型推理努力程度 |
| `model_reasoning_summary` | `ReasoningSummary \| null` | 推理摘要模式 |
| `model_verbosity` | `Verbosity \| null` | 输出详细程度 |
| `web_search` | `WebSearchMode \| null` | 网络搜索模式 |
| `tools` | `ToolsV2 \| null` | 可用工具配置 |
| `chatgpt_base_url` | `string \| null` | ChatGPT API基础URL |
| `additional` | `Record<string, JsonValue>` | 额外的自定义配置 |

## 4. 关键代码路径与文件引用

**主要定义位置：**
- `codex-rs/app-server-protocol/src/protocol/v2.rs` 行588-610

**使用的类型定义：**
- `AskForApproval`：审批策略枚举
- `ApprovalsReviewer`：审批路由目标
- `ServiceTier`：服务等级枚举
- `ReasoningEffort`：推理努力枚举
- `ReasoningSummary`：推理摘要枚举
- `Verbosity`：详细程度枚举
- `WebSearchMode`：搜索模式枚举
- `ToolsV2`：工具配置类型
- `JsonValue`：JSON值类型

## 5. 依赖与外部交互

**导入依赖：**
- `ReasoningEffort`, `ReasoningSummary`：推理相关设置
- `ServiceTier`：服务等级
- `Verbosity`：输出详细程度
- `WebSearchMode`：网络搜索模式
- `JsonValue`：额外配置的JSON值类型
- `ApprovalsReviewer`：审批路由
- `AskForApproval`：审批策略
- `ToolsV2`：工具配置

**使用场景：**
- 配置读写API
- 用户设置管理

## 6. 风险、边界与改进建议

### 潜在风险
1. **实验性功能**：`approval_policy` 和 `approvals_reviewer` 标记为实验性，可能不稳定
2. **配置冲突**：多个字段之间可能存在冲突（如某些工具需要特定的model_provider）
3. **验证缺失**：additional字段允许任意JSON，可能导致无效配置

### 边界情况
- 所有字段都可能为null：使用系统默认值
- additional包含未知字段：需要客户端和服务端都能处理
- URL格式错误：chatgpt_base_url可能包含无效URL

### 改进建议
1. **添加配置验证**：在服务器端验证配置的有效性
2. **添加字段依赖检查**：检查字段间的依赖关系
3. **稳定实验性功能**：将成熟的实验性功能标记为稳定
4. **添加配置模板**：提供常用场景的预设配置
5. **添加配置迁移**：支持从旧版本配置文件迁移
6. **添加文档链接**：为每个字段提供详细的配置文档链接
