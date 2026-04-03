# Research: `codex_app_server_protocol.v2.schemas.json`

## 1. 场景与职责

### 1.1 文件定位

`codex_app_server_protocol.v2.schemas.json` 是 Codex App Server Protocol v2 的 JSON Schema 定义文件，位于 `codex-rs/app-server-protocol/schema/json/` 目录下。该文件是**自动生成**的，作为 Rust 类型系统与外部客户端（TypeScript/其他语言）之间的契约定义。

### 1.2 核心职责

| 职责 | 说明 |
|------|------|
| **API 契约定义** | 定义客户端与 App Server 之间所有消息格式的 JSON Schema |
| **类型验证** | 为客户端提供运行时类型校验的依据 |
| **文档生成** | 作为自动生成 API 文档的基础 |
| **跨语言绑定** | 支持 TypeScript 类型定义生成（配套 `.ts` 文件） |
| **版本控制** | v2 协议与 v1 协议并行存在，v2 是活跃开发版本 |

### 1.3 使用场景

- **客户端开发**：VS Code 扩展、Web UI、CLI 等客户端通过此 schema 理解协议格式
- **服务端实现**：App Server 根据 Rust 类型生成此 schema，确保类型一致性
- **测试验证**：集成测试使用 schema 验证消息格式正确性
- **文档自动化**：生成 API 参考文档

---

## 2. 功能用途

### 2.1 协议覆盖范围

该 schema 定义了完整的 v2 协议消息类型，包括：

#### 请求/响应消息（Client → Server）
- **Thread 生命周期**：`ThreadStart`, `ThreadResume`, `ThreadFork`, `ThreadArchive`, `ThreadUnarchive`
- **Turn 管理**：`TurnStart`, `TurnInterrupt`, `TurnSteer`
- **文件系统操作**：`FsReadFile`, `FsWriteFile`, `FsReadDirectory`, `FsCreateDirectory`, `FsCopy`, `FsRemove`
- **命令执行**：`CommandExec`, `CommandExecWrite`, `CommandExecResize`, `CommandExecTerminate`
- **配置管理**：`ConfigRead`, `ConfigBatchWrite`
- **账户管理**：`LoginAccount`, `LogoutAccount`, `GetAccount`, `CancelLoginAccount`
- **MCP 集成**：`McpServerOauthLogin`, `ListMcpServerStatus`, `McpServerElicitationRequest`
- **技能管理**：`SkillsList`, `SkillsConfigWrite`
- **插件系统**：`PluginList`, `PluginRead`, `PluginInstall`, `PluginUninstall`
- **应用管理**：`AppsList`
- **实验性功能**：`ExperimentalFeatureList`

#### 服务器请求（Server → Client）
- **审批请求**：`ApplyPatchApproval`, `ExecCommandApproval`, `FileChangeRequestApproval`, `PermissionsRequestApproval`
- **工具调用**：`DynamicToolCall`, `ToolRequestUserInput`
- **MCP 服务发现**：`McpServerElicitationRequest`

#### 服务器通知（Server → Client）
- **生命周期通知**：`ThreadStarted`, `TurnStarted`, `TurnCompleted`, `ItemStarted`, `ItemCompleted`
- **状态变更**：`ThreadStatusChanged`, `AgentMessageDelta`, `ReasoningTextDelta`
- **文件变更**：`FileChangeOutputDelta`
- **命令输出**：`CommandExecOutputDelta`, `CommandExecutionOutputDelta`
- **Token 使用**：`ThreadTokenUsageUpdated`
- **计划更新**：`TurnPlanUpdated`, `PlanDeltaNotification`
- **错误通知**：`ErrorNotification`, `DeprecationNoticeNotification`
- **账户相关**：`AccountUpdated`, `AccountLoginCompleted`, `AccountRateLimitsUpdated`

### 2.2 核心数据模型

```json
// Thread - 对话线程
{
  "id": "string",
  "preview": "string",
  "ephemeral": "boolean",
  "modelProvider": "string",
  "createdAt": "integer (i64)",
  "updatedAt": "integer (i64)",
  "status": "ThreadStatus",
  "cwd": "string (PathBuf)",
  "turns": ["Turn"]
}

// Turn - 单次交互回合
{
  "id": "string",
  "items": ["ThreadItem"],
  "status": "TurnStatus (completed|interrupted|failed|inProgress)",
  "error": "TurnError | null"
}

// ThreadItem - 线程中的单个项目
{
  "oneOf": [
    "UserMessage",
    "AgentMessage", 
    "CommandExecution",
    "FileChangeItem",
    "ReasoningItem",
    // ... 更多变体
  ]
}
```

### 2.3 安全模型

```json
// SandboxPolicy - 沙箱策略
{
  "oneOf": [
    { "type": "dangerFullAccess" },
    { 
      "type": "readOnly",
      "access": "ReadOnlyAccess",
      "networkAccess": "boolean"
    },
    {
      "type": "workspaceWrite",
      "writableRoots": ["AbsolutePathBuf"],
      "networkAccess": "NetworkAccess"
    },
    {
      "type": "externalSandbox",
      "networkAccess": "NetworkAccess"
    }
  ]
}

// AskForApproval - 审批策略
{
  "oneOf": [
    { "type": "never" },
    { "type": "always" },
    { "type": "autoEdit" },
    { "type": "dynamic" }
  ]
}
```

---

## 3. 技术实现

### 3.1 代码生成流程

```
Rust Types (src/protocol/v2.rs)
    ↓
#[derive(JsonSchema, TS)] 宏展开
    ↓
schemars 生成 JSON Schema
    ↓
ts-rs 生成 TypeScript 定义
    ↓
export.rs 聚合为最终文件
    ↓
schema/json/codex_app_server_protocol.v2.schemas.json
schema/typescript/v2/*.ts
```

### 3.2 关键源文件

| 文件 | 职责 |
|------|------|
| `src/protocol/v2.rs` | v2 协议类型定义（~4000 行），核心数据结构 |
| `src/protocol/common.rs` | 共享类型，宏定义 `client_request_definitions!` 等 |
| `src/protocol/mod.rs` | 模块组织，v1/v2 协议导出 |
| `src/export.rs` | Schema 生成与导出逻辑 |
| `src/experimental_api.rs` | 实验性 API 标记 trait 与 derive 宏 |
| `src/schema_fixtures.rs` | 测试 fixture 管理，确保 schema 与代码同步 |

### 3.3 实验性 API 机制

```rust
// 标记实验性方法
#[experimental("thread/start.dynamicTools")]
ThreadStart {
    params: ThreadStartParams,
    response: ThreadStartResponse,
}

// 标记实验性字段
#[derive(ExperimentalApi)]
pub struct ThreadStartParams {
    pub input: Vec<UserInput>,
    #[experimental("thread/start.dynamicTools")]
    pub dynamic_tools: Option<Vec<DynamicToolSpec>>,
}
```

实验性内容通过 `filter_experimental_schema()` 函数在生成时过滤。

### 3.4 Schema 结构

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "CodexAppServerProtocolV2",
  "type": "object",
  "definitions": {
    // ~200 个类型定义
    "ClientRequest": { "oneOf": [...] },
    "ServerNotification": { "oneOf": [...] },
    "Thread": { ... },
    "Turn": { ... },
    // ...
  }
}
```

### 3.5 命名约定

- **Rust**: `PascalCase` 类型，`snake_case` 字段（配置类型除外）
- **JSON Schema**: `PascalCase` 定义名，`camelCase` 字段名（通过 `#[serde(rename_all = "camelCase")]`）
- **TypeScript**: `PascalCase` 类型/接口，`camelCase` 属性

---

## 4. 关键代码路径

### 4.1 Schema 生成入口

```rust
// src/export.rs
pub fn generate_json_with_experimental(
    out_dir: &Path, 
    experimental_api: bool
) -> Result<()> {
    // 1. 收集所有需要生成 schema 的类型
    let envelope_emitters: Vec<JsonSchemaEmitter> = vec![
        |d| write_json_schema_with_return::<ClientRequest>(d, "ClientRequest"),
        |d| write_json_schema_with_return::<ServerNotification>(d, "ServerNotification"),
        // ... 更多核心类型
    ];
    
    // 2. 生成所有 param/response schema
    schemas.extend(export_client_param_schemas(out_dir)?);
    schemas.extend(export_client_response_schemas(out_dir)?);
    // ...
    
    // 3. 构建 bundle
    let mut bundle = build_schema_bundle(schemas)?;
    
    // 4. 过滤实验性内容（如需要）
    if !experimental_api {
        filter_experimental_schema(&mut bundle)?;
    }
    
    // 5. 生成扁平化 v2 schema
    let flat_v2_bundle = build_flat_v2_schema(&bundle)?;
    write_pretty_json(
        out_dir.join("codex_app_server_protocol.v2.schemas.json"),
        &flat_v2_bundle,
    )?;
}
```

### 4.2 类型定义示例

```rust
// src/protocol/v2.rs
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, TS)]
#[ts(export_to = "v2/")]
#[serde(rename_all = "camelCase")]
pub struct Thread {
    pub id: String,
    pub preview: String,
    pub ephemeral: bool,
    pub model_provider: String,
    pub created_at: i64,
    pub updated_at: i64,
    pub status: ThreadStatus,
    pub cwd: PathBuf,
    pub turns: Vec<Turn>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, TS)]
#[ts(export_to = "v2/")]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum ThreadStatus {
    NotLoaded,
    Idle,
    SystemError,
    Active { active_flags: Vec<ThreadActiveFlag> },
}
```

### 4.3 宏生成的请求枚举

```rust
// src/protocol/common.rs
client_request_definitions! {
    ThreadStart => "thread/start" {
        params: v2::ThreadStartParams,
        inspect_params: true,  // 启用字段级实验性检查
        response: v2::ThreadStartResponse,
    },
    TurnStart => "turn/start" {
        params: v2::TurnStartParams,
        response: v2::TurnStartResponse,
    },
    // ... 50+ 个方法
}
```

---

## 5. 依赖与外部交互

### 5.1 直接依赖

| Crate | 用途 |
|-------|------|
| `schemars` | JSON Schema 生成 |
| `ts-rs` | TypeScript 类型定义生成 |
| `serde` | 序列化/反序列化 |
| `inventory` | 实验性字段的编译时注册 |
| `codex_protocol` | 核心协议类型共享 |
| `codex_experimental_api_macros` | `#[experimental]` 宏实现 |

### 5.2 输出产物

| 产物 | 路径 | 用途 |
|------|------|------|
| 扁平 v2 Schema | `schema/json/codex_app_server_protocol.v2.schemas.json` | 单文件完整定义 |
| 命名空间 Schema | `schema/json/codex_app_server_protocol.schemas.json` | 按命名空间组织 |
| 单独类型 Schema | `schema/json/v2/*.json` | 单个类型定义 |
| TypeScript 定义 | `schema/typescript/v2/*.ts` | TypeScript 客户端 |

### 5.3 生成命令

```bash
# 重新生成所有 schema
just write-app-server-schema

# 包含实验性 API
just write-app-server-schema --experimental
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| **自动生成覆盖** | 手动修改 schema 文件会被 `just write-app-server-schema` 覆盖 | 所有修改必须通过 Rust 源码 |
| **实验性 API 漂移** | 实验性标记与实现可能不同步 | 使用 `inspect_params: true` 启用字段级检查 |
| **v1 协议债务** | v1 协议已弃用但仍需维护 | 逐步迁移客户端到 v2 |
| **Schema 体积** | 单文件 ~12,000 行，200+ 类型定义 | 使用单独类型文件进行按需加载 |

### 6.2 边界与限制

1. **JSON Schema Draft 07**: 使用较旧版本，某些现代 JSON Schema 特性不可用
2. **Tagged Unions**: 所有 Rust enum 映射为 `oneOf` + `type` 字段的 tagged union
3. **Option<T> 处理**: 映射为 `anyOf[{$ref}, {type: null}]` 而非 JSON Schema 的 `nullable`
4. **PathBuf 序列化**: 序列化为字符串，但格式依赖于平台

### 6.3 改进建议

#### 短期

1. **版本化 Schema 发布**
   - 将 schema 文件作为 npm 包发布，便于客户端版本锁定
   - 添加 schema 版本号到文件名或 `$id` 字段

2. **增强文档**
   - 为复杂类型添加 `description` 字段（通过 `#[schemars(description = "...")]`）
   - 添加使用示例到 schema

3. **验证工具**
   - 提供 CLI 工具验证消息是否符合 schema
   - 集成到 CI 检查客户端消息格式

#### 中期

4. **OpenAPI 支持**
   - 考虑生成 OpenAPI 3.0 规范，替代/补充 JSON Schema
   - 更好地与现有 API 工具链集成

5. **Schema 拆分**
   - 按功能模块拆分 schema（thread, fs, config 等）
   - 减少单文件体积，提高加载性能

6. **迁移辅助**
   - 提供 v1 → v2 的迁移指南和兼容性检查工具
   - 在 schema 中标记已弃用的字段

#### 长期

7. **IDL 优先设计**
   - 考虑使用 Protocol Buffers 或 GraphQL Schema 作为源
   - 生成 Rust/TypeScript 代码，而非反向生成

8. **运行时验证**
   - 在 App Server 中使用 schema 进行请求验证
   - 提供详细的验证错误信息

---

## 7. 附录

### 7.1 文件统计

```
codex_app_server_protocol.v2.schemas.json:
- 总行数: ~12,224 行
- 类型定义: ~200 个
- 请求方法: 50+ (ClientRequest)
- 通知类型: 40+ (ServerNotification)
- JSON Schema Draft: 07
```

### 7.2 相关文件索引

```
codex-rs/app-server-protocol/
├── src/
│   ├── lib.rs                    # 库入口
│   ├── export.rs                 # Schema 生成逻辑
│   ├── experimental_api.rs       # 实验性 API 支持
│   ├── schema_fixtures.rs        # 测试 fixture
│   └── protocol/
│       ├── mod.rs                # 模块组织
│       ├── common.rs             # 共享类型与宏
│       └── v2.rs                 # v2 协议定义 (~4000行)
├── schema/
│   ├── json/
│   │   ├── codex_app_server_protocol.v2.schemas.json  # [本文件]
│   │   ├── codex_app_server_protocol.schemas.json     # 命名空间版本
│   │   └── v2/                   # 单独类型 schema
│   └── typescript/
│       ├── v2/                   # TypeScript 定义
│       └── index.ts              # 导出索引
└── Cargo.toml
```

### 7.3 参考文档

- [AGENTS.md](../../../../../../AGENTS.md) - 项目级开发规范
- [app-server/README.md](../../../../../../codex-rs/app-server/README.md) - App Server 文档
- [schemars 文档](https://graham.cool/schemars/)
- [ts-rs 文档](https://github.com/Aleph-Alpha/ts-rs)
