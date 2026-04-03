# ThreadStartParams 类型研究报告

## 场景与职责

`ThreadStartParams` 是 Codex App-Server Protocol v2 中的实验性 API 参数类型，用于在客户端发起创建新对话线程时，指定线程的完整初始配置。

**主要使用场景：**
- 客户端启动新的对话会话
- 创建具有特定配置的专用线程
- 程序化地启动带有预设参数的自动化任务
- 创建临时（ephemeral）线程用于一次性任务

**职责范围：**
- 配置模型和提供商参数
- 设置审批策略和审批人
- 定义沙箱安全策略
- 指定工作目录和环境
- 配置个性化和行为参数

**实验性特性：**
- 整个类型标记为 `ExperimentalApi`
- 包含多个实验性子字段
- 未来可能有不兼容变更

## 功能点目的

该类型的核心目的是为 `thread/start` RPC 调用提供全面的线程配置能力：

1. **模型配置**: 选择模型、提供商、服务层级、推理努力程度
2. **安全策略**: 配置沙箱模式、审批策略、审批人
3. **环境设置**: 指定工作目录、配置覆盖
4. **行为定制**: 个性化设置、指令定制、临时线程选项
5. **实验性功能**: 动态工具、原始事件流、扩展历史持久化

## 具体技术实现

### TypeScript 类型定义

```typescript
export type ThreadStartParams = {
  model?: string | null,
  modelProvider?: string | null,
  serviceTier?: ServiceTier | null | null,
  cwd?: string | null,
  approvalPolicy?: AskForApproval | null,
  /**
   * Override where approval requests are routed for review on this thread
   * and subsequent turns.
   */
  approvalsReviewer?: ApprovalsReviewer | null,
  sandbox?: SandboxMode | null,
  config?: { [key in string]?: JsonValue } | null,
  serviceName?: string | null,
  baseInstructions?: string | null,
  developerInstructions?: string | null,
  personality?: Personality | null,
  ephemeral?: boolean | null,
  /**
   * If true, opt into emitting raw Responses API items on the event stream.
   * This is for internal use only (e.g. Codex Cloud).
   */
  experimentalRawEvents: boolean,
  /**
   * If true, persist additional rollout EventMsg variants required to
   * reconstruct a richer thread history on resume/fork/read.
   */
  persistExtendedHistory: boolean
};
```

### Rust 源类型定义

```rust
#[derive(
    Serialize, Deserialize, Debug, Clone, PartialEq, Default, JsonSchema, TS, ExperimentalApi,
)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadStartParams {
    #[ts(optional = nullable)]
    pub model: Option<String>,
    #[ts(optional = nullable)]
    pub model_provider: Option<String>,
    #[serde(
        default,
        deserialize_with = "super::serde_helpers::deserialize_double_option",
        serialize_with = "super::serde_helpers::serialize_double_option",
        skip_serializing_if = "Option::is_none"
    )]
    #[ts(optional = nullable)]
    pub service_tier: Option<Option<ServiceTier>>,
    #[ts(optional = nullable)]
    pub cwd: Option<String>,
    #[experimental(nested)]
    #[ts(optional = nullable)]
    pub approval_policy: Option<AskForApproval>,
    /// Override where approval requests are routed for review on this thread
    /// and subsequent turns.
    #[ts(optional = nullable)]
    pub approvals_reviewer: Option<ApprovalsReviewer>,
    #[ts(optional = nullable)]
    pub sandbox: Option<SandboxMode>,
    #[ts(optional = nullable)]
    pub config: Option<HashMap<String, JsonValue>>,
    #[ts(optional = nullable)]
    pub service_name: Option<String>,
    #[ts(optional = nullable)]
    pub base_instructions: Option<String>,
    #[ts(optional = nullable)]
    pub developer_instructions: Option<String>,
    #[ts(optional = nullable)]
    pub personality: Option<Personality>,
    #[ts(optional = nullable)]
    pub ephemeral: Option<bool>,
    #[experimental("thread/start.dynamicTools")]
    #[ts(optional = nullable)]
    pub dynamic_tools: Option<Vec<DynamicToolSpec>>,
    /// Test-only experimental field used to validate experimental gating and
    /// schema filtering behavior in a stable way.
    #[experimental("thread/start.mockExperimentalField")]
    #[ts(optional = nullable)]
    pub mock_experimental_field: Option<String>,
    /// If true, opt into emitting raw Responses API items on the event stream.
    /// This is for internal use only (e.g. Codex Cloud).
    #[experimental("thread/start.experimentalRawEvents")]
    #[serde(default)]
    pub experimental_raw_events: bool,
    /// If true, persist additional rollout EventMsg variants required to
    /// reconstruct a richer thread history on resume/fork/read.
    #[experimental("thread/start.persistFullHistory")]
    #[serde(default)]
    pub persist_extended_history: bool,
}
```

### 字段说明

| 字段 | 类型 | 可选 | 实验性 | 说明 |
|------|------|------|--------|------|
| `model` | `string \| null` | ✓ | ✗ | 模型标识符（如 "o3-mini"） |
| `modelProvider` | `string \| null` | ✓ | ✗ | 模型提供商（如 "openai"） |
| `serviceTier` | `ServiceTier \| null \| null` | ✓ | ✗ | 服务层级（fast/flex） |
| `cwd` | `string \| null` | ✓ | ✗ | 工作目录路径 |
| `approvalPolicy` | `AskForApproval \| null` | ✓ | ✓ (nested) | 审批策略 |
| `approvalsReviewer` | `ApprovalsReviewer \| null` | ✓ | ✗ | 审批请求路由目标 |
| `sandbox` | `SandboxMode \| null` | ✓ | ✗ | 沙箱模式 |
| `config` | `object \| null` | ✓ | ✗ | 配置覆盖 |
| `serviceName` | `string \| null` | ✓ | ✗ | 服务名称 |
| `baseInstructions` | `string \| null` | ✓ | ✗ | 基础指令 |
| `developerInstructions` | `string \| null` | ✓ | ✗ | 开发者指令 |
| `personality` | `Personality \| null` | ✓ | ✗ | 个性化设置 |
| `ephemeral` | `boolean \| null` | ✓ | ✗ | 是否为临时线程 |
| `dynamicTools` | `DynamicToolSpec[] \| null` | ✓ | ✓ | 动态工具规范 |
| `mockExperimentalField` | `string \| null` | ✓ | ✓ | 测试用实验字段 |
| `experimentalRawEvents` | `boolean` | ✗ | ✓ | 输出原始 Responses API 事件 |
| `persistExtendedHistory` | `boolean` | ✗ | ✓ | 持久化扩展历史记录 |

### 实验性字段详解

1. **`approvalPolicy`** (`#[experimental(nested)]`):
   - 整个字段是实验性的
   - 使用细粒度审批配置

2. **`dynamicTools`** (`#[experimental("thread/start.dynamicTools")]`):
   - 允许在启动时注册动态工具
   - 工具规范在 `DynamicToolSpec` 中定义

3. **`mockExperimentalField`** (`#[experimental("thread/start.mockExperimentalField")]`):
   - 仅用于测试
   - 验证实验性功能门控和模式过滤

4. **`experimentalRawEvents`** (`#[experimental("thread/start.experimentalRawEvents")]`):
   - 在事件流中输出原始 Responses API 项目
   - 内部使用（如 Codex Cloud）

5. **`persistExtendedHistory`** (`#[experimental("thread/start.persistFullHistory")]`):
   - 持久化额外的 EventMsg 变体
   - 支持更丰富的历史记录重建

### 特殊序列化处理

`serviceTier` 字段使用双重 Option 和自定义序列化：

```rust
#[serde(
    default,
    deserialize_with = "super::serde_helpers::deserialize_double_option",
    serialize_with = "super::serde_helpers::serialize_double_option",
    skip_serializing_if = "Option::is_none"
)]
#[ts(optional = nullable)]
pub service_tier: Option<Option<ServiceTier>>,
```

这支持三种状态：
- `None`: 未指定，使用默认值
- `Some(None)`: 明确设置为 null
- `Some(Some(tier))`: 明确设置为特定层级

## 关键代码路径与文件引用

### TypeScript 定义文件
- **路径**: `codex-rs/app-server-protocol/schema/typescript/v2/ThreadStartParams.ts`
- **生成工具**: ts-rs (自动从 Rust 代码生成)

### Rust 源文件
- **路径**: `codex-rs/app-server-protocol/src/protocol/v2.rs`
- **行号**: 2449-2508

### 依赖类型文件
| 类型 | 路径 |
|------|------|
| ServiceTier | `codex-rs/app-server-protocol/schema/typescript/ServiceTier.ts` |
| AskForApproval | `codex-rs/app-server-protocol/schema/typescript/v2/AskForApproval.ts` |
| ApprovalsReviewer | `codex-rs/app-server-protocol/schema/typescript/v2/ApprovalsReviewer.ts` |
| SandboxMode | `codex-rs/app-server-protocol/schema/typescript/v2/SandboxMode.ts` |
| Personality | `codex-rs/app-server-protocol/schema/typescript/Personality.ts` |
| DynamicToolSpec | `codex-rs/app-server-protocol/schema/typescript/v2/DynamicToolSpec.ts` |
| ThreadStartResponse | `codex-rs/app-server-protocol/schema/typescript/v2/ThreadStartResponse.ts` |

### 使用场景
- 与 `ThreadStartResponse` 配对使用
- 创建新线程的主要入口点
- 支持高度定制的线程配置

## 依赖与外部交互

### 内部依赖

1. **模型相关类型**: `ServiceTier`、`Personality`
2. **安全相关类型**: `AskForApproval`、`ApprovalsReviewer`、`SandboxMode`
3. **工具类型**: `DynamicToolSpec`
4. **序列化辅助**: 双重 Option 的自定义序列化器

### 外部交互

1. **与 ThreadStartResponse 的交互**:
   - 发送启动参数
   - 返回创建的线程对象和初始配置

2. **与 ThreadResumeParams 的关系**:
   - 两者都提供线程配置
   - `ThreadStartParams` 用于创建新线程
   - `ThreadResumeParams` 用于恢复现有线程

3. **与 ThreadForkParams 的关系**:
   - `ThreadForkParams` 继承了许多相同的配置选项
   - 支持在 fork 时覆盖配置

### 配置继承和默认值

```
ThreadStartParams
├── model: 默认从配置读取
├── modelProvider: 默认从配置读取
├── serviceTier: 默认 null
├── cwd: 默认当前工作目录
├── approvalPolicy: 默认 "on-request"
├── approvalsReviewer: 默认 "user"
├── sandbox: 默认 "read-only"
├── config: 默认空
├── personality: 默认 "none"
├── ephemeral: 默认 false
└── ...
```

## 风险、边界与改进建议

### 潜在风险

1. **实验性 API 风险**:
   - 整个类型标记为实验性
   - 未来可能有不兼容变更
   - 生产环境使用需谨慎

2. **配置复杂性**:
   - 大量可选字段可能导致配置错误
   - 字段间可能存在冲突（如 sandbox 与 approvalPolicy）

3. **安全风险**:
   - `ephemeral: false` 可能意外持久化敏感数据
   - `sandbox: "danger-full-access"` 需要额外确认

4. **性能影响**:
   - `persistExtendedHistory: true` 增加存储开销
   - `experimentalRawEvents: true` 增加网络传输

### 边界情况

1. **无效组合**: 某些配置组合可能无效
   - 例如：不支持的模型和提供商组合
2. **权限不足**: 请求的配置超出用户权限
3. **资源限制**: 临时线程数量限制
4. **并发创建**: 大量线程同时创建

### 改进建议

1. **配置验证**:
   ```rust
   impl ThreadStartParams {
       pub fn validate(&self) -> Result<(), ValidationError> {
           // 检查模型和提供商兼容性
           if let (Some(model), Some(provider)) = (&self.model, &self.model_provider) {
               validate_model_provider(model, provider)?;
           }
           // 检查沙箱和审批策略一致性
           if let (Some(sandbox), Some(policy)) = (&self.sandbox, &self.approval_policy) {
               validate_sandbox_policy(sandbox, policy)?;
           }
           Ok(())
       }
   }
   ```

2. **配置模板**:
   ```typescript
   export const ThreadStartTemplates = {
     safe: { sandbox: "read-only", approvalPolicy: "on-request" },
     development: { sandbox: "workspace-write", approvalPolicy: "on-failure" },
     automation: { ephemeral: true, approvalPolicy: "never" },
   };
   ```

3. **响应增强**:
   ```typescript
   export type ThreadStartResponse = {
     thread: Thread,
     appliedConfig: {
       // 实际应用的配置（包含默认值）
       model: string,
       sandbox: SandboxMode,
       // ...
     },
     warnings?: string[],  // 配置警告
   };
   ```

4. **渐进式配置**:
   ```rust
   pub struct ThreadStartParams {
       // 基础配置（稳定）
       pub basic: ThreadStartBasicParams,
       // 高级配置（实验性）
       #[experimental]
       pub advanced: Option<ThreadStartAdvancedParams>,
   }
   ```

5. **配置文档**:
   - 为每个字段提供详细文档
   - 包含配置示例和最佳实践
   - 说明字段间的依赖关系

6. **审计和日志**:
   - 记录所有线程创建操作
   - 包含完整配置（去除敏感信息）
   - 支持配置变更追踪

7. **配额管理**:
   ```rust
   pub struct ThreadStartParams {
       // ...
       pub quota_limits: Option<QuotaLimits>,  // 资源限制
   }
   ```

8. **向后兼容策略**:
   - 明确实验性字段的稳定性路线图
   - 提供迁移工具和文档
   - 考虑功能标志控制
