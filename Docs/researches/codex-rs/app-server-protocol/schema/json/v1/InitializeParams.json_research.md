# InitializeParams.json 研究文档

## 场景与职责

`InitializeParams.json` 是 Codex App-Server Protocol v1 API 的初始化请求参数 JSON Schema 定义文件。它定义了客户端在建立与 App-Server 连接时必须发送的初始化参数结构，是整个协议握手过程的第一步。

该 Schema 文件属于 App-Server Protocol 的**协议契约层**，用于：
1. **客户端开发**：为 TypeScript/JavaScript 客户端提供类型定义和验证依据
2. **服务端验证**：App-Server 使用此 Schema 验证收到的初始化请求
3. **文档生成**：自动生成 API 文档和类型定义文件
4. **测试验证**：作为测试固件(fixture)确保协议一致性

## 功能点目的

### 1. 客户端信息传递 (`ClientInfo`)

```json
{
  "name": "codex_vscode",
  "title": "Codex VS Code Extension",
  "version": "0.1.0"
}
```

- **`name`** (必需): 客户端标识符，用于追踪请求来源、生成 User-Agent 字符串
- **`title`** (可选): 客户端的显示名称，用于日志和调试
- **`version`** (必需): 客户端版本号，用于兼容性检查

**关键用途**：
- 在 `message_processor.rs` 中，`client_info.name` 被用于设置默认的 HTTP Origin 头（通过 `set_default_originator`）
- 构建 User-Agent 字符串：`{name}/{version}` 格式
- 用于遥测和日志追踪，标识哪个客户端发起了请求

### 2. 能力协商 (`InitializeCapabilities`)

```json
{
  "experimentalApi": false,
  "optOutNotificationMethods": ["thread/started"]
}
```

- **`experimentalApi`** (默认 false): 是否启用实验性 API 方法和字段
- **`optOutNotificationMethods`** (可选): 客户端选择退出的通知方法列表

**关键用途**：
- **实验性功能控制**：当 `experimental_api` 为 true 时，客户端可以访问标记为 `#[experimental("...")]` 的 API 方法
- **通知过滤**：App-Server 会根据此列表过滤掉客户端不需要的通知，减少网络流量（见 `transport.rs` 中的 `opted_out_notification_methods` 处理）

## 具体技术实现

### 数据结构定义

**Rust 源码位置**: `codex-rs/app-server-protocol/src/protocol/v1.rs`

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
pub struct InitializeParams {
    pub client_info: ClientInfo,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub capabilities: Option<InitializeCapabilities>,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Default, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
pub struct ClientInfo {
    pub name: String,
    pub title: Option<String>,
    pub version: String,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Default, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
pub struct InitializeCapabilities {
    #[serde(default)]
    pub experimental_api: bool,
    #[ts(optional = nullable)]
    pub opt_out_notification_methods: Option<Vec<String>>,
}
```

### 关键处理流程

**1. 初始化请求处理** (`codex-rs/app-server/src/message_processor.rs:512-603`)

```rust
ClientRequest::Initialize { request_id, params } => {
    // 1. 检查是否已初始化
    if session.initialized {
        return error("Already initialized");
    }

    // 2. 解析能力配置
    let (experimental_api_enabled, opt_out_notification_methods) = 
        match params.capabilities {
            Some(capabilities) => (
                capabilities.experimental_api,
                capabilities.opt_out_notification_methods.unwrap_or_default(),
            ),
            None => (false, Vec::new()),
        };

    // 3. 存储会话状态
    session.experimental_api_enabled = experimental_api_enabled;
    session.opted_out_notification_methods = opt_out_notification_methods.into_iter().collect();

    // 4. 设置客户端名称和版本
    let ClientInfo { name, title: _title, version } = params.client_info;
    session.app_server_client_name = Some(name.clone());
    session.client_version = Some(version.clone());

    // 5. 验证并设置 Origin
    if let Err(error) = set_default_originator(name.clone()) {
        match error {
            SetOriginatorError::InvalidHeaderValue => {
                return error("Invalid clientInfo.name: Must be a valid HTTP header value.");
            }
            SetOriginatorError::AlreadyInitialized => { /* 环境变量已设置，忽略 */ }
        }
    }

    // 6. 构建 User-Agent
    let user_agent_suffix = format!("{name}; {version}");
    if let Ok(mut suffix) = USER_AGENT_SUFFIX.lock() {
        *suffix = Some(user_agent_suffix);
    }

    // 7. 返回 InitializeResponse
    let response = InitializeResponse {
        user_agent: get_codex_user_agent(),
        platform_family: std::env::consts::FAMILY.to_string(),
        platform_os: std::env::consts::OS.to_string(),
    };
    
    session.initialized = true;
}
```

**2. 实验性 API 检查** (`message_processor.rs:616-626`)

```rust
if let Some(reason) = codex_request.experimental_reason()
    && !session.experimental_api_enabled
{
    let error = JSONRPCErrorError {
        code: INVALID_REQUEST_ERROR_CODE,
        message: experimental_required_message(reason),
        data: None,
    };
    self.outgoing.send_error(connection_request_id, error).await;
    return;
}
```

**3. 通知过滤** (`transport.rs` 中的 `OutboundConnectionState`)

```rust
pub(crate) fn should_send_notification(&self, method: &str) -> bool {
    if let Ok(opted_out) = self.opted_out_notification_methods.read() {
        !opted_out.contains(method)
    } else {
        true // 默认发送
    }
}
```

### Schema 生成流程

**生成工具**: `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs`

```rust
pub fn write_schema_fixtures_with_options(
    schema_root: &Path,
    prettier: Option<&Path>,
    options: SchemaFixtureOptions,
) -> Result<()> {
    // 生成 JSON Schema
    generate_json_with_experimental(&json_out_dir, options.experimental_api)?;
    // ...
}
```

**生成逻辑** (`export.rs:195-244`):

1. 使用 `schemars` crate 从 Rust 类型生成 JSON Schema
2. 通过 `export_client_param_schemas` 导出客户端请求参数 Schema
3. 应用实验性 API 过滤（如果未启用）
4. 写入 `schema/json/v1/InitializeParams.json`

## 关键代码路径与文件引用

### 核心定义
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v1.rs:26-53` | `InitializeParams`, `ClientInfo`, `InitializeCapabilities` 定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs:205-209` | `ClientRequest::Initialize` 枚举变体定义 |

### 处理实现
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/src/message_processor.rs:512-603` | 初始化请求处理逻辑 |
| `codex-rs/app-server/src/message_processor.rs:156-163` | `ConnectionSessionState` 会话状态定义 |
| `codex-rs/app-server/src/transport.rs` | 通知过滤和连接状态管理 |

### Schema 生成
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/export.rs:195-244` | JSON Schema 生成主逻辑 |
| `codex-rs/app-server-protocol/src/schema_fixtures.rs:82-109` | Schema 固件写入 |
| `codex-rs/app-server-protocol/src/bin/write_schema_fixtures.rs` | CLI 工具 |

### 测试
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/initialize.rs` | 初始化功能集成测试 |
| `codex-rs/app-server-protocol/src/protocol/common.rs:995-1036` | 序列化/反序列化单元测试 |
| `codex-rs/app-server-protocol/tests/schema_fixtures.rs` | Schema 固件一致性测试 |

## 依赖与外部交互

### 上游依赖

1. **schemars**: 从 Rust 类型派生 JSON Schema
2. **ts-rs**: 生成 TypeScript 类型定义
3. **serde**: JSON 序列化/反序列化

### 下游消费者

1. **TypeScript 客户端**: VS Code 扩展、Web UI 等
2. **App-Server 服务端**: 请求验证和处理
3. **测试框架**: 验证协议兼容性

### 运行时依赖

1. **codex_core::default_client**: 
   - `set_default_originator()`: 设置 HTTP Origin 头
   - `get_codex_user_agent()`: 获取 User-Agent 字符串
   - `USER_AGENT_SUFFIX`: 存储客户端版本信息

2. **会话状态管理**:
   - `ConnectionSessionState`: 存储每个连接的能力配置

## 风险、边界与改进建议

### 已知风险

1. **Origin 设置竞争条件**:
   ```rust
   // message_processor.rs:568-574
   SetOriginatorError::AlreadyInitialized => {
       // No-op. This is expected to happen if the originator is already set via env var.
       // TODO(owen): Once we remove support for CODEX_INTERNAL_ORIGINATOR_OVERRIDE,
       // this will be an unexpected state...
   }
   ```
   环境变量 `CODEX_INTERNAL_ORIGINATOR_OVERRIDE` 可能导致意外的 Origin 设置。

2. **实验性 API 作用域问题**:
   ```rust
   // message_processor.rs:527-532
   // TODO(maxj): Revisit capability scoping for `experimental_api_enabled`.
   // Current behavior is per-connection. Reviewer feedback notes this can
   // create odd cross-client behavior...
   ```
   当前实验性 API 是每连接级别的，可能导致跨客户端行为不一致。

3. **客户端名称验证**:
   - 仅验证是否为有效的 HTTP Header 值
   - 不验证格式、长度或其他约束

### 边界情况

1. **重复初始化**: 如果客户端发送多次 Initialize 请求，服务端返回错误 "Already initialized"
2. **未初始化访问**: 除 Initialize 外，所有其他请求在未初始化状态下返回 "Not initialized" 错误
3. **空能力配置**: `capabilities` 为 `null` 时，使用默认值（`experimental_api: false`, 空通知过滤列表）

### 改进建议

1. **增强验证**:
   - 添加 `name` 和 `version` 的格式验证（如语义化版本检查）
   - 限制 `opt_out_notification_methods` 的最大长度，防止滥用

2. **能力协商扩展**:
   - 考虑支持协议版本协商
   - 添加客户端支持的功能列表（如压缩、加密等）

3. **监控与遥测**:
   - 记录客户端版本分布
   - 追踪实验性 API 的使用情况

4. **文档改进**:
   - 添加 `opt_out_notification_methods` 的完整有效值列表
   - 明确 `title` 字段的使用场景和限制
