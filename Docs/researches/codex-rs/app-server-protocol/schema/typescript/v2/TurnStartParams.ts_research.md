# TurnStartParams.ts Research

## 场景与职责

`TurnStartParams` 是 App-Server Protocol v2 中用于启动新 AI 回合（Turn）的请求参数类型。作为 **EXPERIMENTAL** API，它允许客户端发起一次用户与 AI 的交互回合，并可通过各种覆盖参数自定义该回合的执行行为。

主要使用场景包括：
- **发起对话**：用户发送消息后启动新的 AI 处理回合
- **参数覆盖**：针对特定回合覆盖线程级别的配置（如模型、沙箱策略等）
- **个性化设置**：为回合指定特定的人格（personality）或协作模式
- **结构化输出**：通过 outputSchema 约束 AI 的输出格式
- **测试验证**：测试框架验证回合启动和各种参数组合

## 功能点目的

该类型的核心目的是：

1. **回合启动**：提供启动新回合的标准化接口
2. **参数覆盖**：允许在回合级别覆盖各种配置参数
3. **灵活配置**：支持模型、策略、人格等多维度配置
4. **实验功能**：作为实验性 API，支持快速迭代新功能

与其他类型的关系：
- 与 `TurnStartResponse` 配对，形成完整的请求-响应循环
- 与 `TurnStartedNotification` 关联，服务器在接收请求后发送开始通知
- 与 `TurnCompletedNotification` 关联，标记回合完成

## 具体技术实现

### TypeScript 类型定义

```typescript
export type TurnStartParams = {
  threadId: string,
  input: Array<UserInput>,
  /**
   * Override the working directory for this turn and subsequent turns.
   */
  cwd?: string | null,
  /**
   * Override the approval policy for this turn and subsequent turns.
   */
  approvalPolicy?: AskForApproval | null,
  /**
   * Override where approval requests are routed for review on this turn and
   * subsequent turns.
   */
  approvalsReviewer?: ApprovalsReviewer | null,
  /**
   * Override the sandbox policy for this turn and subsequent turns.
   */
  sandboxPolicy?: SandboxPolicy | null,
  /**
   * Override the model for this turn and subsequent turns.
   */
  model?: string | null,
  /**
   * Override the service tier for this turn and subsequent turns.
   */
  serviceTier?: ServiceTier | null | null,
  /**
   * Override the reasoning effort for this turn and subsequent turns.
   */
  effort?: ReasoningEffort | null,
  /**
   * Override the reasoning summary for this turn and subsequent turns.
   */
  summary?: ReasoningSummary | null,
  /**
   * Override the personality for this turn and subsequent turns.
   */
  personality?: Personality | null,
  /**
   * Optional JSON Schema used to constrain the final assistant message for
   * this turn.
   */
  outputSchema?: JsonValue | null,
  /**
   * EXPERIMENTAL - Set a pre-set collaboration mode.
   * Takes precedence over model, reasoning_effort, and developer instructions if set.
   */
  collaborationMode?: CollaborationMode | null
};
```

### Rust 源码定义

```rust
#[derive(
    Serialize, Deserialize, Debug, Default, Clone, PartialEq, JsonSchema, TS, ExperimentalApi,
)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TurnStartParams {
    pub thread_id: String,
    pub input: Vec<UserInput>,
    /// Override the working directory for this turn and subsequent turns.
    #[ts(optional = nullable)]
    pub cwd: Option<PathBuf>,
    /// Override the approval policy for this turn and subsequent turns.
    #[experimental(nested)]
    #[ts(optional = nullable)]
    pub approval_policy: Option<AskForApproval>,
    /// Override where approval requests are routed for review on this turn and
    /// subsequent turns.
    #[ts(optional = nullable)]
    pub approvals_reviewer: Option<ApprovalsReviewer>,
    /// Override the sandbox policy for this turn and subsequent turns.
    #[ts(optional = nullable)]
    pub sandbox_policy: Option<SandboxPolicy>,
    /// Override the model for this turn and subsequent turns.
    #[ts(optional = nullable)]
    pub model: Option<String>,
    /// Override the service tier for this turn and subsequent turns.
    #[serde(
        default,
        deserialize_with = "super::serde_helpers::deserialize_double_option",
        serialize_with = "super::serde_helpers::serialize_double_option",
        skip_serializing_if = "Option::is_none"
    )]
    #[ts(optional = nullable)]
    pub service_tier: Option<Option<ServiceTier>>,
    /// Override the reasoning effort for this turn and subsequent turns.
    #[ts(optional = nullable)]
    pub effort: Option<ReasoningEffort>,
    /// Override the reasoning summary for this turn and subsequent turns.
    #[ts(optional = nullable)]
    pub summary: Option<ReasoningSummary>,
    /// Override the personality for this turn and subsequent turns.
    #[ts(optional = nullable)]
    pub personality: Option<Personality>,
    /// Optional JSON Schema used to constrain the final assistant message for
    /// this turn.
    #[ts(optional = nullable)]
    pub output_schema: Option<JsonValue>,

    /// EXPERIMENTAL - Set a pre-set collaboration mode.
    /// Takes precedence over model, reasoning_effort, and developer instructions if set.
    #[experimental("turn/start.collaborationMode")]
    #[ts(optional = nullable)]
    pub collaboration_mode: Option<CollaborationMode>,
}
```

### 字段说明

| 字段 | 类型 | 实验性 | 说明 |
|------|------|--------|------|
| `threadId` | string | 否 | 目标线程 ID，回合将在该线程中执行 |
| `input` | UserInput[] | 否 | 用户输入内容，支持文本、图片、技能引用等 |
| `cwd` | string \| null | 否 | 覆盖工作目录 |
| `approvalPolicy` | AskForApproval \| null | **是** | 覆盖审批策略 |
| `approvalsReviewer` | ApprovalsReviewer \| null | 否 | 覆盖审批路由目标 |
| `sandboxPolicy` | SandboxPolicy \| null | 否 | 覆盖沙箱策略 |
| `model` | string \| null | 否 | 覆盖使用的 AI 模型 |
| `serviceTier` | ServiceTier \| null | 否 | 覆盖服务层级 |
| `effort` | ReasoningEffort \| null | 否 | 覆盖推理努力程度 |
| `summary` | ReasoningSummary \| null | 否 | 覆盖推理摘要设置 |
| `personality` | Personality \| null | 否 | 覆盖人格设置 |
| `outputSchema` | JsonValue \| null | 否 | JSON Schema 约束输出格式 |
| `collaborationMode` | CollaborationMode \| null | **是** | 预设协作模式 |

### 实验性标记说明

- `#[derive(ExperimentalApi)]`: 整个类型标记为实验性
- `#[experimental(nested)]`: `approval_policy` 字段为实验性
- `#[experimental("turn/start.collaborationMode")]`: `collaboration_mode` 字段标记为实验性

### 特殊序列化处理

`service_tier` 使用双重 Option 和自定义序列化：
- `Option<Option<ServiceTier>>` 支持三种状态：未指定、显式 null、具体值
- `skip_serializing_if = "Option::is_none"` 省略未指定的字段

## 关键代码路径与文件引用

### 协议定义

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs:3823-3879` | Rust 结构体定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/TurnStartParams.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/schema/json/v2/TurnStartParams.json` | JSON Schema 定义 |

### 方法注册

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/common.rs:351-355` | ClientRequest 枚举中的 `turn/start` 方法定义 |

### 服务器端处理

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/src/bespoke_event_handling.rs` | 回合启动请求处理 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 消息处理逻辑 |

### 客户端实现

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui_app_server/src/app_server_session.rs` | TUI App Server 会话实现 |
| `codex-rs/tui/src/app.rs` | TUI 客户端回合启动 |
| `codex-rs/app-server-client/src/lib.rs` | 客户端库 |

### 测试覆盖

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/tests/suite/v2/turn_start.rs` | 回合启动完整测试套件 |
| `codex-rs/app-server/tests/suite/v2/turn_interrupt.rs` | 中断测试（依赖回合启动） |
| `codex-rs/app-server/tests/suite/v2/output_schema.rs` | outputSchema 参数测试 |
| `codex-rs/app-server/tests/suite/v2/thread_shell_command.rs` | cwd 参数测试 |

## 依赖与外部交互

### 内部依赖

```
TurnStartParams
├── thread_id: String
├── input: Vec<UserInput>
│   ├── Text { text, text_elements }
│   ├── Image { url }
│   ├── LocalImage { path }
│   ├── Skill { name, path }
│   └── Mention { name, path }
├── cwd: Option<PathBuf>
├── approval_policy: Option<AskForApproval> [experimental]
├── approvals_reviewer: Option<ApprovalsReviewer>
├── sandbox_policy: Option<SandboxPolicy>
├── model: Option<String>
├── service_tier: Option<Option<ServiceTier>>
├── effort: Option<ReasoningEffort>
├── summary: Option<ReasoningSummary>
├── personality: Option<Personality>
├── output_schema: Option<JsonValue>
├── collaboration_mode: Option<CollaborationMode> [experimental]
├── ExperimentalApi (派生宏)
├── serde (Serialize, Deserialize)
├── schemars (JsonSchema)
└── ts_rs (TS)
```

### 协议集成

- **JSON-RPC 方法**：`turn/start`
- **请求类型**：`ClientRequest::TurnStart`
- **响应类型**：`TurnStartResponse`
- **通知序列**：`turn/started` -> ... -> `turn/completed`

### 参数覆盖优先级

```
TurnStartParams 覆盖值 > 线程级别配置 > 全局配置 > 默认值
```

特别说明：`collaborationMode` 如果设置，会优先于 `model`、`effort` 和 developer instructions。

## 风险、边界与改进建议

### 潜在风险

1. **实验性 API 不稳定**：标记为实验性的字段可能在未来版本中变更或移除
2. **参数验证复杂**：大量可选参数增加了验证逻辑的复杂度
3. **覆盖行为不一致**：部分参数覆盖"本回合及后续回合"，可能不符合用户预期
4. **权限绕过**：某些覆盖参数（如 sandboxPolicy）可能被恶意利用

### 边界情况

| 场景 | 行为 |
|------|------|
| 空 input 数组 | 可能返回错误或启动空回合 |
| 无效 threadId | 返回错误，指示线程不存在 |
| 线程已有活跃回合 | 返回错误，需等待或中断当前回合 |
| 所有参数为 null/未指定 | 使用线程默认配置 |
| 同时指定 model 和 collaborationMode | collaborationMode 优先 |

### 改进建议

1. **参数分组**：将相关参数组织为嵌套结构，提高可读性
   ```typescript
   overrides?: {
     model?: string;
     effort?: ReasoningEffort;
     // ...
   }
   ```

2. **验证增强**：
   - 添加参数组合验证（如某些参数互斥）
   - 验证 outputSchema 是否为有效的 JSON Schema
   - 验证 model 是否为支持的模型

3. **原子性保证**：确保参数覆盖要么全部生效，要么全部失败

4. **文档完善**：
   - 明确每个参数的默认值
   - 详细说明"本回合及后续回合"的覆盖行为
   - 提供参数最佳实践指南

5. **性能优化**：
   - 缓存常用配置组合
   - 延迟加载可选参数

6. **安全加固**：
   - 敏感参数（如 sandboxPolicy）需要额外权限验证
   - 添加参数变更审计日志

### 实验性功能管理

1. **功能开关**：为实验性功能添加运行时开关
2. **降级策略**：实验性功能失败时优雅降级到稳定功能
3. **反馈收集**：收集实验性功能的使用反馈和指标
4. **版本规划**：明确实验性功能的 GA（正式发布）时间表
