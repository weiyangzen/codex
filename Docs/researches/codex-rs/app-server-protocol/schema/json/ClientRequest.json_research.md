# ClientRequest.json 研究文档

## 1. 场景与职责

### 1.1 文件定位

`ClientRequest.json` 是 Codex App Server Protocol 的核心 JSON Schema 文件，位于：
- **路径**: `codex-rs/app-server-protocol/schema/json/ClientRequest.json`
- **生成来源**: 由 Rust 代码通过 `schemars` 和 `ts-rs` 宏自动生成
- **生成命令**: `just write-app-server-schema` 或 `cargo run --bin write_schema_fixtures`

### 1.2 核心职责

该 Schema 定义了**客户端向服务器发送的所有请求消息**的结构规范，是 Codex App Server 与客户端（如 VS Code 扩展、TUI、CLI）之间通信协议的基础契约。

**主要功能场景**:
1. **线程生命周期管理**: `thread/start`, `thread/resume`, `thread/fork`, `thread/archive`
2. **对话回合控制**: `turn/start`, `turn/steer`, `turn/interrupt`
3. **文件系统操作**: `fs/readFile`, `fs/writeFile`, `fs/createDirectory`, `fs/remove`, `fs/copy`
4. **命令执行**: `command/exec`, `command/exec/write`, `command/exec/terminate`, `command/exec/resize`
5. **配置管理**: `config/read`, `config/value/write`, `config/batchWrite`
6. **账户认证**: `account/login/start`, `account/logout`, `account/read`
7. **技能与插件**: `skills/list`, `plugin/list`, `plugin/install`, `plugin/uninstall`
8. **MCP 服务器**: `mcpServerStatus/list`, `mcpServer/oauth/login`

### 1.3 架构角色

```
┌─────────────────┐     JSON-RPC 2.0     ┌──────────────────┐
│  Client (VSCode)│ ◄──────────────────► │  Codex App Server│
│  TUI, CLI       │   (over stdio/ws)    │                  │
└─────────────────┘                      └──────────────────┘
         │                                          │
         │  ClientRequest.json 定义请求格式         │
         │  (方法名 + 参数 + ID)                    │
         ▼                                          ▼
┌─────────────────────────────────────────────────────────┐
│              JSON-RPC Message Envelope                  │
│  { id, method: "thread/start", params: {...} }         │
└─────────────────────────────────────────────────────────┘
```

---

## 2. 功能点目的

### 2.1 协议设计目标

| 目标 | 说明 |
|------|------|
| **双向通信** | 基于 JSON-RPC 2.0（省略 `"jsonrpc":"2.0"` 字段），支持 stdio 和 WebSocket 传输 |
| **类型安全** | 通过 JSON Schema 强约束，生成 TypeScript 类型定义供客户端使用 |
| **实验性 API 隔离** | 通过 `#[experimental(...)]` 属性标记不稳定接口，可过滤排除 |
| **向后兼容** | 保留 v1 API（如 `initialize`, `getConversationSummary`），同时发展 v2 API |

### 2.2 核心功能分类

#### 2.2.1 Thread 管理（对话线程）

```json
// thread/start - 创建新线程
{
  "id": 10,
  "method": "thread/start",
  "params": {
    "model": "gpt-5.1-codex",
    "cwd": "/Users/me/project",
    "approvalPolicy": "never",
    "sandbox": "workspaceWrite"
  }
}
```

**关键参数**:
- `model`, `modelProvider`: 指定模型和提供商
- `approvalPolicy`: 审批策略 (`never`, `onRequest`, `onFailure`, `granular`)
- `sandbox`: 沙箱模式 (`readOnly`, `workspaceWrite`, `dangerFullAccess`)
- `dynamicTools`: 实验性功能，动态工具规范

#### 2.2.2 Turn 管理（对话回合）

```json
// turn/start - 开始新回合
{
  "id": 20,
  "method": "turn/start",
  "params": {
    "threadId": "thr_123",
    "input": [{ "type": "text", "text": "Hello Codex" }],
    "approvalPolicy": null,
    "sandboxPolicy": null
  }
}
```

#### 2.2.3 文件系统操作

```json
// fs/readFile - 读取文件（base64 编码）
{
  "id": 30,
  "method": "fs/readFile",
  "params": {
    "path": "/absolute/path/to/file"
  }
}
// 响应: { "dataBase64": "SGVsbG8gV29ybGQh" }
```

#### 2.2.4 命令执行

```json
// command/exec - 在沙箱中执行命令
{
  "id": 40,
  "method": "command/exec",
  "params": {
    "command": ["ls", "-la"],
    "processId": "my-process-1",
    "streamStdoutStderr": true,
    "sandboxPolicy": { "type": "readOnly" }
  }
}
```

### 2.3 实验性 API 机制

通过 `#[experimental("reason")]` 宏标记实验性功能:

```rust
// 在 common.rs 中定义
#[experimental("thread/realtime/start")]
ThreadRealtimeStart => "thread/realtime/start" {
    params: v2::ThreadRealtimeStartParams,
    response: v2::ThreadRealtimeStartResponse,
}
```

生成时可通过 `--experimental` 标志控制是否包含:
```bash
# 包含实验性 API
cargo run --bin write_schema_fixtures -- --experimental

# 不包含（默认）
cargo run --bin write_schema_fixtures
```

---

## 3. 具体技术实现

### 3.1 数据结构定义

#### 3.1.1 核心枚举（Rust 源码）

**位置**: `codex-rs/app-server-protocol/src/protocol/common.rs`

```rust
/// Request from the client to the server.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(tag = "method", rename_all = "camelCase")]
pub enum ClientRequest {
    Initialize {
        #[serde(rename = "id")]
        request_id: RequestId,
        params: v1::InitializeParams,
    },
    ThreadStart => "thread/start" {
        params: v2::ThreadStartParams,
        inspect_params: true,  // 部分字段实验性
        response: v2::ThreadStartResponse,
    },
    // ... 更多变体
}
```

#### 3.1.2 宏生成机制

使用 `client_request_definitions!` 宏批量生成:

```rust
client_request_definitions! {
    Initialize {
        params: v1::InitializeParams,
        response: v1::InitializeResponse,
    },
    ThreadStart => "thread/start" {
        params: v2::ThreadStartParams,
        inspect_params: true,
        response: v2::ThreadStartResponse,
    },
    // ...
}
```

宏自动生成:
- `ClientRequest` enum 及其序列化/反序列化实现
- `id()` 和 `method()` 方法
- `ExperimentalApi` trait 实现
- 响应类型导出函数

### 3.2 JSON Schema 生成流程

```
┌─────────────────┐
│   Rust Types    │  ← #[derive(JsonSchema, TS)]
│  (v1.rs, v2.rs) │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  schemars crate │  ← 生成 JSON Schema
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  export.rs      │  ← 过滤、打包、命名空间处理
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ ClientRequest.json│ ← 最终 Schema 文件
└─────────────────┘
```

### 3.3 关键类型定义

#### 3.3.1 RequestId

**位置**: `codex-rs/app-server-protocol/src/jsonrpc_lite.rs`

```rust
#[derive(Debug, Clone, PartialEq, PartialOrd, Ord, Deserialize, Serialize, Hash, Eq, JsonSchema, TS)]
#[serde(untagged)]
pub enum RequestId {
    String(String),
    #[ts(type = "number")]
    Integer(i64),
}
```

#### 3.3.2 ThreadStartParams

**位置**: `codex-rs/app-server-protocol/src/protocol/v2.rs`

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default, JsonSchema, TS, ExperimentalApi)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ThreadStartParams {
    #[ts(optional = nullable)]
    pub model: Option<String>,
    #[ts(optional = nullable)]
    pub model_provider: Option<String>,
    #[experimental(nested)]
    #[ts(optional = nullable)]
    pub approval_policy: Option<AskForApproval>,
    #[ts(optional = nullable)]
    pub approvals_reviewer: Option<ApprovalsReviewer>,
    // ...
}
```

### 3.4 序列化约定

| 约定 | 说明 | 示例 |
|------|------|------|
| `camelCase` | 字段命名 | `thread_id` → `threadId` |
| `snake_case` | 配置相关字段 | `model_reasoning_effort` |
| `kebab-case` | 枚举变体 | `workspace-write` |
| `#[ts(optional = nullable)]` | TypeScript 可选字段 | `cursor?: string \| null` |

---

## 4. 关键代码路径与文件引用

### 4.1 源文件结构

```
codex-rs/app-server-protocol/
├── src/
│   ├── lib.rs                    # 模块导出
│   ├── jsonrpc_lite.rs           # JSON-RPC 基础类型
│   ├── export.rs                 # Schema 生成与导出逻辑
│   ├── experimental_api.rs       # 实验性 API 标记
│   ├── schema_fixtures.rs        # Schema 固化文件管理
│   └── protocol/
│       ├── mod.rs                # 协议模块
│       ├── common.rs             # ClientRequest/ServerRequest 定义
│       ├── v1.rs                 # v1 API 类型
│       ├── v2.rs                 # v2 API 类型（主要）
│       ├── mappers.rs            # 类型转换
│       └── serde_helpers.rs      # 序列化辅助
├── schema/
│   ├── json/
│   │   ├── ClientRequest.json    # ★ 本研究对象
│   │   ├── ServerRequest.json    # 服务器请求
│   │   ├── ClientNotification.json
│   │   ├── ServerNotification.json
│   │   └── v2/                   # v2 专用类型
│   └── typescript/               # TypeScript 定义
└── tests/
    └── schema_fixtures.rs        # Schema 一致性测试
```

### 4.2 关键代码路径

#### 4.2.1 ClientRequest 定义

**文件**: `codex-rs/app-server-protocol/src/protocol/common.rs`
**行号**: 85-541

```rust
// 宏定义 ClientRequest enum
client_request_definitions! {
    Initialize { ... },
    ThreadStart => "thread/start" { ... },
    // ... 约 60+ 个方法
}
```

#### 4.2.2 Schema 生成入口

**文件**: `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs`

```rust
fn main() -> Result<()> {
    codex_app_server_protocol::write_schema_fixtures_with_options(
        &schema_root,
        args.prettier.as_deref(),
        SchemaFixtureOptions {
            experimental_api: args.experimental,
        },
    )
}
```

#### 4.2.3 JSON 生成逻辑

**文件**: `codex-rs/app-server-protocol/src/export.rs`
**关键函数**: `generate_json_with_experimental`

```rust
pub fn generate_json_with_experimental(out_dir: &Path, experimental_api: bool) -> Result<()> {
    // 1. 生成信封类型 Schema
    let envelope_emitters: Vec<JsonSchemaEmitter> = vec![
        |d| write_json_schema_with_return::<ClientRequest>(d, "ClientRequest"),
        // ...
    ];
    
    // 2. 生成参数和响应 Schema
    schemas.extend(export_client_param_schemas(out_dir)?);
    schemas.extend(export_client_response_schemas(out_dir)?);
    
    // 3. 过滤实验性 API
    if !experimental_api {
        filter_experimental_schema(&mut bundle)?;
    }
    
    // 4. 写入文件
    write_pretty_json(out_dir.join("codex_app_server_protocol.schemas.json"), &bundle)?;
}
```

#### 4.2.4 消息处理入口

**文件**: `codex-rs/app-server/src/message_processor.rs`

```rust
use codex_app_server_protocol::ClientRequest;

// 处理传入的 JSON-RPC 请求
async fn handle_request(&self, request: JSONRPCRequest) -> Result<()> {
    let client_request: ClientRequest = serde_json::from_value(...)?;
    match client_request {
        ClientRequest::ThreadStart { request_id, params } => {
            self.handle_thread_start(request_id, params).await
        }
        // ...
    }
}
```

### 4.3 测试覆盖

**文件**: `codex-rs/app-server-protocol/tests/schema_fixtures.rs`

```rust
#[test]
fn json_schema_fixtures_match_generated() -> Result<()> {
    assert_schema_fixtures_match_generated("json", |output_dir| {
        generate_json_with_experimental(output_dir, false)
    })
}
```

运行测试:
```bash
cargo test -p codex-app-server-protocol
```

---

## 5. 依赖与外部交互

### 5.1 内部依赖

| Crate | 用途 |
|-------|------|
| `codex-protocol` | 核心协议类型（ThreadId, ResponseItem 等） |
| `codex-core` | Config, AuthManager, ThreadManager |
| `codex-utils-absolute-path` | AbsolutePathBuf 类型 |
| `codex-experimental-api-macros` | `#[experimental]` 宏 |

### 5.2 外部依赖

| Crate | 版本 | 用途 |
|-------|------|------|
| `schemars` | ^0.8 | JSON Schema 生成 |
| `ts-rs` | ^7.0 | TypeScript 类型生成 |
| `serde` | ^1.0 | 序列化/反序列化 |
| `strum_macros` | ^0.26 | 枚举字符串化 |

### 5.3 客户端消费者

| 客户端 | 路径 | 使用方式 |
|--------|------|----------|
| VS Code 扩展 | `codex-vscode/` | 通过 TypeScript 类型调用 |
| TUI | `codex-rs/tui/` | 通过 Rust 类型调用 |
| CLI | `codex-rs/cli/` | 直接调用 |

### 5.4 传输层

```
ClientRequest
    │
    ▼
┌─────────────────┐
│ JSON-RPC 2.0    │  ← jsonrpc_lite.rs
│ (stdio/ws)      │
└────────┬────────┘
         │
    ┌────┴────┐
    ▼         ▼
┌───────┐  ┌────────┐
│ stdio │  │WebSocket│ ← codex-rs/app-server/src/transport/
└───────┘  └────────┘
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 实验性 API 稳定性

**风险**: 标记为 `#[experimental(...)]` 的 API 可能随时变更或移除
**影响**: 依赖实验性 API 的客户端可能在不升级时失效
**缓解**:
- 客户端需显式声明 `experimentalApi: true` 才能接收实验性方法
- Schema 生成时默认过滤实验性 API

#### 6.1.2 版本兼容性

**风险**: v1 和 v2 API 并存，可能导致混淆
**示例**:
- `initialize` 使用 v1 类型
- `thread/start` 使用 v2 类型
- 旧方法如 `getConversationSummary` 已标记为 DEPRECATED

#### 6.1.3 大文件传输

**风险**: `fs/readFile` 和 `fs/writeFile` 使用 base64 编码，大文件内存开销大
**边界**: 无内置大小限制，依赖底层传输层

### 6.2 边界条件

| 边界 | 说明 |
|------|------|
| **RequestId 唯一性** | 同一连接内必须唯一，字符串或整数 |
| **Method 命名** | 使用 `camelCase` 或 `snake_case/path` 格式 |
| **Params 可选性** | 无参数请求使用 `Option<()>` 或空对象 |
| **线程生命周期** | 未订阅的线程可能被自动卸载 |

### 6.3 改进建议

#### 6.3.1 Schema 版本管理

**现状**: 单文件包含所有版本
**建议**: 考虑按版本分离 Schema 文件，如:
```
schema/json/
  ├── v1/
  │   └── ClientRequest.json
  └── v2/
      └── ClientRequest.json
```

#### 6.3.2 文档内嵌

**现状**: 描述分散在 Rust doc 和 README
**建议**: 在 Schema 的 `description` 字段增加更多使用示例

#### 6.3.3 性能优化

**现状**: 大文件 base64 编解码
**建议**: 
- 考虑支持分块传输
- 或增加流式文件传输 API

#### 6.3.4 类型安全增强

**现状**: 部分字段使用 `JsonValue`（任意 JSON）
**建议**: 
- 逐步替换为强类型结构
- 如 `config` 字段可使用 `Config` 类型替代 `HashMap<String, JsonValue>`

#### 6.3.5 测试覆盖

**现状**: 已有 Schema 一致性测试
**建议**:
- 增加模糊测试（fuzzing）验证边界条件
- 增加端到端序列化/反序列化测试

### 6.4 监控与调试

**日志**: 设置 `RUST_LOG=debug` 查看原始消息
**追踪**: 支持 W3C Trace Context 进行分布式追踪
**Schema 验证**: 使用生成的 Schema 验证客户端消息

---

## 附录：关键方法清单

### Thread 相关（18 个）
- `thread/start`, `thread/resume`, `thread/fork`
- `thread/archive`, `thread/unarchive`
- `thread/list`, `thread/loaded/list`, `thread/read`
- `thread/metadata/update`, `thread/setName`
- `thread/unsubscribe`, `thread/rollback`
- `thread/compact/start`, `thread/shellCommand`
- `thread/increment_elicitation`, `thread/decrement_elicitation` (experimental)
- `thread/backgroundTerminals/clean` (experimental)

### Turn 相关（3 个）
- `turn/start`, `turn/steer`, `turn/interrupt`

### Realtime 相关（4 个，experimental）
- `thread/realtime/start`, `thread/realtime/appendAudio`
- `thread/realtime/appendText`, `thread/realtime/stop`

### 文件系统（6 个）
- `fs/readFile`, `fs/writeFile`, `fs/createDirectory`
- `fs/getMetadata`, `fs/readDirectory`, `fs/remove`, `fs/copy`

### 命令执行（4 个）
- `command/exec`, `command/exec/write`
- `command/exec/terminate`, `command/exec/resize`

### 配置（5 个）
- `config/read`, `config/value/write`, `config/batchWrite`
- `configRequirements/read`, `config/mcpServer/reload`

### 账户（5 个）
- `account/login/start`, `account/login/cancel`, `account/logout`
- `account/read`, `account/rateLimits/read`

### 其他
- `initialize`, `review/start`, `model/list`
- `experimentalFeature/list`, `collaborationMode/list` (experimental)
- `skills/list`, `skills/config/write`
- `plugin/list`, `plugin/read`, `plugin/install`, `plugin/uninstall`
- `app/list`, `mcpServerStatus/list`, `mcpServer/oauth/login`
- `feedback/upload`, `windowsSandbox/setupStart`
- `externalAgentConfig/detect`, `externalAgentConfig/import`
- `fuzzyFileSearch` (deprecated)
