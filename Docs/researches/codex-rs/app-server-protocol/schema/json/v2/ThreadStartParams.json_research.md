# ThreadStartParams.json 研究文档

## 场景与职责

`ThreadStartParams` 是 Codex App-Server Protocol v2 中用于启动新线程（Thread）的请求参数结构。它是客户端调用 `thread/start` RPC 方法时必须提供的参数，定义了创建新对话线程所需的所有配置选项。

该结构体属于 App-Server 协议的核心部分，用于：
- 初始化一个新的 AI 对话线程
- 配置线程的模型、沙箱、审批策略等运行时参数
- 支持动态工具和实验性功能的高级配置

## 功能点目的

### 1. 核心配置字段

| 字段 | 类型 | 用途 |
|------|------|------|
| `model` | `Option<String>` | 指定使用的 AI 模型（如 "o3-mini"） |
| `model_provider` | `Option<String>` | 模型提供商（如 "openai"） |
| `service_tier` | `Option<Option<ServiceTier>>` | 服务层级（fast/flex），支持显式 null |
| `cwd` | `Option<String>` | 工作目录 |

### 2. 安全与审批配置

| 字段 | 类型 | 用途 |
|------|------|------|
| `approval_policy` | `Option<AskForApproval>` | 审批策略（实验性） |
| `approvals_reviewer` | `Option<ApprovalsReviewer>` | 审批请求路由目标（user/guardian_subagent） |
| `sandbox` | `Option<SandboxMode>` | 沙箱模式（read-only/workspace-write/danger-full-access） |

### 3. 指令与个性化

| 字段 | 类型 | 用途 |
|------|------|------|
| `base_instructions` | `Option<String>` | 基础系统指令 |
| `developer_instructions` | `Option<String>` | 开发者指令 |
| `personality` | `Option<Personality>` | 个性化设置（none/friendly/pragmatic） |

### 4. 实验性功能字段

| 字段 | 类型 | 实验标识 | 用途 |
|------|------|----------|------|
| `dynamic_tools` | `Option<Vec<DynamicToolSpec>>` | `thread/start.dynamicTools` | 动态工具规范 |
| `mock_experimental_field` | `Option<String>` | `thread/start.mockExperimentalField` | 测试用实验字段 |
| `experimental_raw_events` | `bool` | `thread/start.experimentalRawEvents` | 启用原始事件流 |
| `persist_extended_history` | `bool` | `thread/start.persistFullHistory` | 持久化完整历史 |

## 具体技术实现

### 数据结构定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default, JsonSchema, TS, ExperimentalApi)]
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
    // ... 其他字段
}
```

### 关键特性

1. **双重 Option 序列化**：`service_tier` 使用 `deserialize_double_option` 和 `serialize_double_option` 辅助函数，支持三种状态：
   - `None` - 未指定，使用默认值
   - `Some(None)` - 显式设置为 null
   - `Some(Some(tier))` - 显式设置具体值

2. **实验性字段标记**：使用 `#[experimental(...)]` 属性标记实验性功能，支持细粒度的 API 版本控制

3. **TypeScript 导出**：通过 `#[ts(export_to = "v2/")]` 自动生成 TypeScript 类型定义

### AskForApproval 枚举

支持两种模式：
- **简单模式**：`"untrusted" | "on-failure" | "on-request" | "never"`
- **细粒度模式**（实验性）：`{ granular: { sandbox_approval, rules, mcp_elicitations, request_permissions, skill_approval } }`

## 关键代码路径与文件引用

### 定义位置
- **主定义**：`codex-rs/app-server-protocol/src/protocol/v2.rs:2454-2508`
- **JSON Schema**：`codex-rs/app-server-protocol/schema/json/v2/ThreadStartParams.json`

### 相关类型定义
- `AskForApproval`：`codex-rs/app-server-protocol/src/protocol/v2.rs:201-265`
- `ApprovalsReviewer`：`codex-rs/app-server-protocol/src/protocol/v2.rs:267-296`
- `SandboxMode`：`codex-rs/app-server-protocol/src/protocol/v2.rs:298-325`
- `DynamicToolSpec`：`codex-rs/app-server-protocol/src/protocol/v2.rs:544-586`

### RPC 方法注册
- **位置**：`codex-rs/app-server-protocol/src/protocol/common.rs:214-218`
- **方法名**：`thread/start`
- **请求类型**：`ThreadStartParams`
- **响应类型**：`ThreadStartResponse`

### 序列化辅助函数
- **位置**：`codex-rs/app-server-protocol/src/protocol/serde_helpers.rs`
- `deserialize_double_option`：处理双重 Option 的反序列化
- `serialize_double_option`：处理双重 Option 的序列化

### 测试用例
- **位置**：`codex-rs/app-server-protocol/src/protocol/v2.rs:7871-7885`
- 验证 `service_tier` 显式 null 的保留行为
- 验证默认值的序列化省略

## 依赖与外部交互

### 内部依赖

| 依赖 | 用途 |
|------|------|
| `codex_protocol::config_types::*` | 核心配置类型（ServiceTier, Personality, SandboxMode） |
| `codex_protocol::protocol::AskForApproval` | 审批策略核心类型 |
| `codex_experimental_api_macros::ExperimentalApi` | 实验性 API 标记宏 |
| `schemars::JsonSchema` | JSON Schema 生成 |
| `ts_rs::TS` | TypeScript 类型生成 |

### 协议版本
- 属于 **App-Server Protocol v2**
- 通过 `#[ts(export_to = "v2/")]` 限定导出命名空间

### 调用流程
```
Client -> thread/start (ThreadStartParams) -> Server
Server -> ThreadStartResponse + ThreadStartedNotification -> Client
```

## 风险、边界与改进建议

### 已知风险

1. **实验性功能稳定性**
   - `approval_policy` 等字段标记为实验性，API 可能变动
   - 细粒度审批策略 (`askForApproval.granular`) 仍在迭代中

2. **双重 Option 复杂性**
   - `service_tier` 的三态逻辑增加了理解和使用复杂度
   - 需要客户端正确处理 `null` vs `undefined` 的语义差异

3. **沙箱配置安全风险**
   - `sandbox: "danger-full-access"` 模式绕过所有安全限制
   - 需要客户端明确警告用户此模式的风险

### 边界情况

1. **空值处理**
   - 所有字段均为 `Option<T>`，服务器需处理缺失情况
   - `config` 字段支持 `additionalProperties: true`，允许任意扩展

2. **实验性字段过滤**
   - 非实验模式下，实验性字段会被从 schema 中过滤
   - 使用 `generate_json_schema` 时需注意 `--experimental` 标志

### 改进建议

1. **文档完善**
   - 为 `dynamic_tools` 添加更详细的使用示例
   - 明确 `experimental_raw_events` 的事件格式规范

2. **类型安全**
   - 考虑将 `config` 从 `HashMap<String, JsonValue>` 改为更具体的结构化类型
   - 为 `service_tier` 的双层 Option 提供专门的构建器模式

3. **验证增强**
   - 添加 `model` 和 `model_provider` 的组合验证
   - 对 `cwd` 路径进行规范化验证

4. **向后兼容**
   - 监控 `expose_to_context` 到 `defer_loading` 的迁移使用情况
   - 考虑为废弃字段添加 deprecation 警告
