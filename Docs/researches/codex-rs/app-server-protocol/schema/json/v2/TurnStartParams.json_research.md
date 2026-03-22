# TurnStartParams.json 研究文档

## 场景与职责

`TurnStartParams` 是 Codex App-Server Protocol v2 中用于启动一个新 Turn（对话轮次）的请求参数结构。它是 `turn/start` RPC 方法的核心输入，负责承载用户输入、线程标识以及各种可选的覆盖配置。

**核心职责：**
- 标识目标线程 (`thread_id`)
- 承载用户输入内容 (`input`) - 支持文本、图片、本地图片、Skill 引用和 Mention
- 允许在单次 Turn 中覆盖各种配置（工作目录、审批策略、沙箱策略、模型等）
- 支持实验性功能：协作模式 (`collaboration_mode`) 覆盖

## 功能点目的

### 1. 用户输入承载
`input` 字段是 `Vec<UserInput>` 类型，支持多种输入类型：
- **Text**: 普通文本输入，支持 `text_elements` 用于 UI 特殊元素标记
- **Image**: 通过 URL 引用图片
- **LocalImage**: 通过本地路径引用图片
- **Skill**: 引用 Skill 文件
- **Mention**: 提及/引用某个实体

### 2. 配置覆盖机制
所有覆盖字段都遵循"本次及后续 Turn 生效"的语义：
- `cwd`: 覆盖工作目录
- `approval_policy`: 覆盖审批策略（实验性）
- `approvals_reviewer`: 覆盖审批审核者
- `sandbox_policy`: 覆盖沙箱策略
- `model`: 覆盖模型选择
- `service_tier`: 覆盖服务层级
- `effort`: 覆盖推理努力程度
- `summary`: 覆盖推理摘要配置
- `personality`: 覆盖人格配置
- `output_schema`: 约束最终助手消息的 JSON Schema

### 3. 实验性协作模式
`collaboration_mode` 字段（实验性）允许设置预设协作模式，优先级高于 model/reasoning_effort/developer_instructions。

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Default, Clone, PartialEq, JsonSchema, TS, ExperimentalApi)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct TurnStartParams {
    pub thread_id: String,
    pub input: Vec<UserInput>,
    #[ts(optional = nullable)]
    pub cwd: Option<PathBuf>,
    #[experimental(nested)]
    #[ts(optional = nullable)]
    pub approval_policy: Option<AskForApproval>,
    #[ts(optional = nullable)]
    pub approvals_reviewer: Option<ApprovalsReviewer>,
    #[ts(optional = nullable)]
    pub sandbox_policy: Option<SandboxPolicy>,
    #[ts(optional = nullable)]
    pub model: Option<String>,
    #[serde(
        default,
        deserialize_with = "super::serde_helpers::deserialize_double_option",
        serialize_with = "super::serde_helpers::serialize_double_option",
        skip_serializing_if = "Option::is_none"
    )]
    #[ts(optional = nullable)]
    pub service_tier: Option<Option<ServiceTier>>,
    #[ts(optional = nullable)]
    pub effort: Option<ReasoningEffort>,
    #[ts(optional = nullable)]
    pub summary: Option<ReasoningSummary>,
    #[ts(optional = nullable)]
    pub personality: Option<Personality>,
    #[ts(optional = nullable)]
    pub output_schema: Option<JsonValue>,
    #[experimental("turn/start.collaborationMode")]
    #[ts(optional = nullable)]
    pub collaboration_mode: Option<CollaborationMode>,
}
```

### 关键流程

1. **请求验证**：在 `turn/start` 处理流程中，首先验证 `thread_id` 是否存在
2. **输入大小检查**：验证总输入字符数不超过 `MAX_USER_INPUT_TEXT_CHARS`
3. **配置覆盖应用**：将覆盖字段应用到线程配置中（本次及后续生效）
4. **Turn 创建**：创建新的 Turn 并返回 `TurnStartResponse`
5. **通知发送**：发送 `turn/started` 通知

### 依赖类型

- `UserInput`: 用户输入枚举，支持 Text/Image/LocalImage/Skill/Mention
- `TextElement`: 文本元素，包含 `byte_range` 和可选 `placeholder`
- `AskForApproval`: 审批策略枚举（实验性）
- `SandboxPolicy`: 沙箱策略，支持 DangerFullAccess/ReadOnly/ExternalSandbox/WorkspaceWrite
- `CollaborationMode`: 协作模式（实验性）

## 关键代码路径与文件引用

### 定义位置
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:3828`

### 使用位置
- `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/common.rs:351-355`
  - 注册为 `TurnStart => "turn/start"` 客户端请求
- `/home/sansha/Github/codex/codex-rs/app-server/tests/suite/v2/turn_start.rs`
  - 完整的集成测试覆盖

### 相关类型定义
- `TurnStartResponse`: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:3937`
- `UserInput`: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:4041-4066`
- `TextElement`: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v2.rs:3999-4007`

### Schema 生成
- 通过 `schemars::JsonSchema` derive 宏自动生成 JSON Schema
- 通过 `ts_rs::TS` derive 宏自动生成 TypeScript 类型
- 导出脚本: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs`

## 依赖与外部交互

### 上游依赖
- `codex_protocol::user_input::UserInput`: 核心用户输入类型
- `codex_protocol::config_types`: 配置类型（CollaborationMode, Personality 等）
- `codex_protocol::openai_models::ReasoningEffort`: 推理努力程度

### 下游消费
- App-Server 的 `turn/start` 请求处理器
- TUI 客户端通过 WebSocket 发送 turn/start 请求
- VSCode 扩展等第三方客户端

### 协议集成
- 作为 JSON-RPC 2.0 请求的 `params` 字段
- 方法名: `turn/start`
- 响应类型: `TurnStartResponse`

## 风险、边界与改进建议

### 已知风险

1. **输入大小限制**
   - 总输入字符数受 `MAX_USER_INPUT_TEXT_CHARS` 限制
   - 超限会导致 `-32602` (Invalid params) 错误
   - 错误信息包含 `input_error_code`, `max_chars`, `actual_chars`

2. **实验性功能稳定性**
   - `approval_policy` 和 `collaboration_mode` 标记为实验性
   - 使用 `#[experimental(nested)]` 和 `#[experimental("turn/start.collaborationMode")]` 标注
   - 未来 API 可能变化

3. **配置覆盖的持久性**
   - 覆盖配置会影响"本次及后续"Turn
   - 可能被误解为仅影响当前 Turn

### 边界情况

1. **空输入验证**
   - `input` 是必填字段，但必须包含至少一个元素
   - 每个 `UserInput` 变体有自己的验证规则

2. **路径处理**
   - `cwd` 必须是绝对路径（通过 `AbsolutePathBuf` 验证）
   - `LocalImage` 和 `Skill` 的路径处理依赖具体平台

3. **双重 Option 处理**
   - `service_tier` 使用 `Option<Option<ServiceTier>>` 表示三层状态：
     - `None`: 未指定（不覆盖）
     - `Some(None)`: 显式清除为 null
     - `Some(Some(tier))`: 覆盖为指定值

### 改进建议

1. **文档增强**
   - 为 `service_tier` 的双重 Option 语义添加更多文档示例
   - 明确说明各覆盖字段的"持久性"行为

2. **验证改进**
   - 考虑在 Schema 层面增加 `input` 非空约束
   - 为 `output_schema` 添加 JSON Schema 有效性验证

3. **类型安全**
   - 考虑为 `thread_id` 使用强类型（如 `ThreadId`）而非裸 `String`
   - 考虑为 `expected_turn_id`（在 TurnSteerParams 中）使用相同模式

4. **实验性功能**
   - 建议为实验性字段添加运行时警告或日志
   - 考虑提供特性检测机制让客户端知道服务器支持哪些实验性功能
