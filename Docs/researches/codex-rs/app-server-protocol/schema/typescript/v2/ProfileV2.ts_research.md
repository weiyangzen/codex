# ProfileV2 研究文档

## 场景与职责

`ProfileV2` 是 Codex App Server Protocol v2 中用于定义用户配置档案（Profile）的核心类型。该类型封装了与 AI 模型交互的各种配置选项，允许用户创建和管理多个不同的配置档案。

**核心使用场景：**
- 用户创建自定义的配置档案以适配不同工作场景
- 在 `config.toml` 中定义多个 profile 配置
- 动态切换不同的模型参数和行为策略
- 支持实验性功能（如 `approvals_reviewer`）的配置

**职责定位：**
- 作为 `Config` 类型中 `profiles` 字段的值类型
- 提供模型选择、审批策略、工具配置等全方位配置
- 支持通过 `additional` 字段扩展自定义配置

## 功能点目的

### 1. 模型配置（Model Configuration）

| 字段 | 类型 | 说明 |
|------|------|------|
| `model` | `string \| null` | 使用的 AI 模型标识符 |
| `model_provider` | `string \| null` | 模型提供商（如 openai） |
| `service_tier` | `ServiceTier \| null` | 服务层级（如 auto, flex） |

**目的**：
- 允许用户为不同场景选择不同的 AI 模型
- 支持多提供商架构
- 控制服务质量和成本

### 2. 审批策略（Approval Policy）

| 字段 | 类型 | 实验性 | 说明 |
|------|------|--------|------|
| `approval_policy` | `AskForApproval \| null` | 是 | 审批策略配置 |
| `approvals_reviewer` | `ApprovalsReviewer \| null` | 是 | 审批请求路由目标 |

**目的**：
- 控制何时需要用户审批敏感操作
- 支持将审批请求路由到 Guardian Subagent 进行自动评估
- 提供细粒度的安全控制

### 3. 模型推理配置（Reasoning Configuration）

| 字段 | 类型 | 说明 |
|------|------|------|
| `model_reasoning_effort` | `ReasoningEffort \| null` | 推理努力程度（low/medium/high） |
| `model_reasoning_summary` | `ReasoningSummary \| null` | 推理摘要模式 |
| `model_verbosity` | `Verbosity \| null` | 输出详细程度 |

**目的**：
- 控制模型的推理深度和输出风格
- 平衡响应质量与 token 消耗
- 支持不同场景的信息密度需求

### 4. 工具配置（Tools Configuration）

| 字段 | 类型 | 说明 |
|------|------|------|
| `web_search` | `WebSearchMode \| null` | 网页搜索功能配置 |
| `tools` | `ToolsV2 \| null` | 工具集配置（如 view_image） |

**目的**：
- 启用/禁用特定工具功能
- 配置工具的行为参数
- 控制外部资源访问

### 5. 扩展配置（ChatGPT Base URL）

| 字段 | 类型 | 说明 |
|------|------|------|
| `chatgpt_base_url` | `string \| null` | ChatGPT API 的基础 URL |

**目的**：
- 支持自定义 API 端点
- 便于企业部署和代理配置

### 6. 动态扩展（Additional Properties）

```rust
#[serde(default, flatten)]
pub additional: HashMap<String, JsonValue>,
```

**目的**：
- 允许添加未在正式字段中定义的配置
- 支持向前兼容和实验性功能
- 在 TypeScript 中表示为 `Record<string, any>`

## 具体技术实现

### Rust 源码定义

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

### TypeScript 生成代码

```typescript
import type { ReasoningEffort } from "../ReasoningEffort";
import type { ReasoningSummary } from "../ReasoningSummary";
import type { ServiceTier } from "../ServiceTier";
import type { Verbosity } from "../Verbosity";
import type { WebSearchMode } from "../WebSearchMode";
import type { JsonValue } from "../serde_json/JsonValue";
import type { ApprovalsReviewer } from "./ApprovalsReviewer";
import type { AskForApproval } from "./AskForApproval";
import type { ToolsV2 } from "./ToolsV2";

export type ProfileV2 = {
    model: string | null, 
    model_provider: string | null, 
    approval_policy: AskForApproval | null, 
    /**
     * [UNSTABLE] Optional profile-level override for where approval requests
     * are routed for review. If omitted, the enclosing config default is
     * used.
     */
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

### 关键属性详解

#### ExperimentalApi 标记

```rust
#[derive(..., ExperimentalApi)]
```

- 整个 `ProfileV2` 类型被标记为实验性 API
- 表示该类型及其字段可能在未来版本中变更
- 客户端应谨慎依赖这些接口

#### 字段级实验性标记

```rust
#[experimental(nested)]
pub approval_policy: Option<AskForApproval>,

#[experimental("config/read.approvalsReviewer")]
pub approvals_reviewer: Option<ApprovalsReviewer>,
```

- `#[experimental(nested)]`：表示该字段的类型本身包含实验性内容
- `#[experimental("config/read.approvalsReviewer")]`：表示特定功能路径的实验性

#### 命名规范

| 场景 | 规范 | 示例 |
|------|------|------|
| Rust 字段 | `snake_case` | `model_provider` |
| JSON 字段 | `snake_case` | `"model_provider"` |
| TypeScript 属性 | `snake_case`（保持与 JSON 一致） | `model_provider` |

## 关键代码路径与文件引用

### 定义位置
- **Rust 源码**：`codex-rs/app-server-protocol/src/protocol/v2.rs`
  - 行号：588-610

### 在 Config 中的使用
- **文件**：`codex-rs/app-server-protocol/src/protocol/v2.rs`
  - 行号：711-713

```rust
#[experimental(nested)]
#[serde(default)]
pub profiles: HashMap<String, ProfileV2>,
```

### 生成的 TypeScript 文件
- **文件**：`codex-rs/app-server-protocol/schema/typescript/v2/ProfileV2.ts`

### 测试引用
- **文件**：`codex-rs/app-server-protocol/src/protocol/v2.rs`
  - 行号：6820, 6935, 6990（实验性 API 测试）

### 相关类型

| 类型 | 文件 | 关系 |
|------|------|------|
| `Config` | `v2.rs:692` | 包含 `profiles: HashMap<String, ProfileV2>` |
| `AskForApproval` | `v2.rs:201` | `approval_policy` 字段类型 |
| `ApprovalsReviewer` | `v2.rs:275` | `approvals_reviewer` 字段类型 |
| `ReasoningEffort` | 外部导入 | `model_reasoning_effort` 字段类型 |
| `ReasoningSummary` | 外部导入 | `model_reasoning_summary` 字段类型 |
| `ServiceTier` | 外部导入 | `service_tier` 字段类型 |
| `Verbosity` | 外部导入 | `model_verbosity` 字段类型 |
| `WebSearchMode` | 外部导入 | `web_search` 字段类型 |
| `ToolsV2` | `v2.rs:539` | `tools` 字段类型 |

## 依赖与外部交互

### 内部依赖

| 依赖项 | 来源 | 用途 |
|--------|------|------|
| `AskForApproval` | `v2.rs` | 审批策略枚举 |
| `ApprovalsReviewer` | `v2.rs` | 审批路由目标 |
| `ToolsV2` | `v2.rs` | 工具配置 |
| `ReasoningEffort` | `codex_protocol::openai_models` | 推理努力程度 |
| `ReasoningSummary` | `codex_protocol::config_types` | 推理摘要模式 |
| `ServiceTier` | `codex_protocol::config_types` | 服务层级 |
| `Verbosity` | `codex_protocol::config_types` | 输出详细度 |
| `WebSearchMode` | `codex_protocol::config_types` | 网页搜索模式 |
| `ExperimentalApi` | `codex_experimental_api_macros` | 实验性标记宏 |

### 配置层级关系

```
Config (顶层配置)
├── model: Option<String>                    # 默认模型
├── approval_policy: Option<AskForApproval>  # 默认审批策略
├── ...
└── profiles: HashMap<String, ProfileV2>     # 命名档案集合
    ├── "default": ProfileV2 { ... }
    ├── "coding": ProfileV2 { ... }
    └── "writing": ProfileV2 { ... }
```

### 配置合并逻辑

当使用特定 profile 时，配置按以下优先级合并：

1. Profile 特定配置（最高优先级）
2. 顶层默认配置
3. 系统默认值（最低优先级）

### 与 Core 协议的映射

```rust
// ProfileV2 与 Core Profile 的转换
impl ProfileV2 {
    pub fn to_core(&self) -> CoreProfile {
        CoreProfile {
            model: self.model.clone(),
            model_provider: self.model_provider.clone(),
            // ... 其他字段映射
        }
    }
}
```

## 风险、边界与改进建议

### 潜在风险

1. **实验性 API 不稳定**
   - 风险：`ProfileV2` 及其字段标记为实验性，可能在未来版本变更
   - 影响：依赖这些 API 的客户端可能需要频繁更新
   - 缓解：
     - 客户端实现应做好向后兼容处理
     - 关注版本更新日志

2. **additional 字段的类型安全**
   - 风险：`additional: HashMap<String, JsonValue>` 允许任意 JSON 数据
   - 影响：类型错误只能在运行时发现
   - 缓解：
     - 客户端应验证 additional 字段的内容
     - 文档明确说明支持的扩展字段

3. **配置冲突**
   - 风险：profile 与顶层配置可能存在不一致
   - 影响：用户可能困惑于实际生效的配置
   - 缓解：
     - 清晰的配置优先级文档
     - 提供配置验证和预览功能

4. **空值处理**
   - 风险：所有字段都是 `Option<T>`，可能全部为 `None`
   - 影响：空 profile 的行为可能不明确
   - 缓解：定义空 profile 的默认行为

### 边界情况

| 场景 | 预期行为 |
|------|----------|
| Profile 不存在 | 使用顶层默认配置 |
| 所有字段为 `null` | 继承所有顶层配置 |
| `additional` 包含未知字段 | 保留但可能产生警告 |
| Profile 名称冲突 | 后定义的配置覆盖先定义的 |
| 运行时切换 Profile | 新对话使用新配置，当前对话保持原配置 |

### 改进建议

1. **添加验证注解**
   ```rust
   #[serde(validate = "::validators::url")]
   pub chatgpt_base_url: Option<String>,
   ```

2. **添加 profile 元数据**
   ```rust
   pub description: Option<String>,  // Profile 描述
   pub created_at: Option<i64>,      // 创建时间
   pub updated_at: Option<i64>,      // 更新时间
   ```

3. **支持配置继承**
   ```rust
   pub extends: Option<String>,  // 继承自其他 profile
   ```

4. **添加版本字段**
   ```rust
   pub version: Option<String>,  // Profile 格式版本
   ```

5. **改进实验性功能标记**
   - 提供更详细的实验性功能说明
   - 添加实验性功能的启用/禁用开关

6. **TypeScript 类型优化**
   ```typescript
   // 当前：交叉类型
   type ProfileV2 = { ... } & Record<string, any>
   
   // 建议：使用接口继承
   interface ProfileV2Base { ... }
   interface ProfileV2 extends ProfileV2Base {
     [key: string]: JsonValue | undefined;
   }
   ```

7. **文档完善**
   - 每个字段的详细说明和使用示例
   - 配置最佳实践指南
   - Profile 切换的性能影响说明

---

*文档生成时间：2026-03-22*
*基于版本：codex-rs/app-server-protocol 最新主分支*
