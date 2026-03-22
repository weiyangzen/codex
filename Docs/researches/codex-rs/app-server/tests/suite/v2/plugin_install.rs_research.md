# plugin_install.rs 深入研究文档

## 场景与职责

`plugin_install.rs` 是 Codex App Server v2 协议测试套件中的插件安装测试模块。该模块测试了 `plugin/install` JSON-RPC 方法的完整功能，包括路径验证、市场文件验证、插件可用性检查、远程同步、分析事件追踪以及需要授权的应用检测。

该测试文件确保 Codex 能够安全、可靠地安装插件，正确处理各种边界情况和错误场景，并与后端 API 进行正确的交互。

## 功能点目的

### 1. 相对路径拒绝 (`plugin_install_rejects_relative_marketplace_paths`)
验证 API 拒绝相对路径的市场文件路径，返回错误码 `-32600` (Invalid Request)。这是安全要求，防止目录遍历攻击。

### 2. 缺失市场文件处理 (`plugin_install_returns_invalid_request_for_missing_marketplace_file`)
验证当指定的市场文件不存在时，返回清晰的错误消息指示文件不存在。

### 3. 不可用插件处理 (`plugin_install_returns_invalid_request_for_not_available_plugin`)
验证当插件的 `install_policy` 为 `NOT_AVAILABLE` 时，安装被拒绝。

### 4. 远程同步 (`plugin_install_force_remote_sync_enables_remote_plugin_before_local_install`)
验证 `force_remote_sync: true` 时：
- 先调用后端 API 启用远程插件
- 然后执行本地安装流程
- 验证后端 API 调用包含正确的认证头

### 5. 分析事件追踪 (`plugin_install_tracks_analytics_event`)
验证插件安装成功后，发送分析事件到分析服务器：
- 事件类型: `codex_plugin_installed`
- 包含插件 ID、名称、市场名称、技能数量、MCP 服务器数量、连接器 ID 列表

### 6. 需要授权的应用检测 (`plugin_install_returns_apps_needing_auth`)
验证当插件依赖的连接器需要用户授权时：
- 返回 `apps_needing_auth` 列表
- 包含应用 ID、名称、描述和安装 URL
- 根据 `auth_policy` 返回相应的策略

### 7. 授权策略过滤 (`plugin_install_filters_disallowed_apps_needing_auth`)
验证 `auth_policy: ON_USE` 时，只返回需要在安装时授权的应用，过滤掉不需要授权的应用。

## 具体技术实现

### 关键流程

#### 标准安装流程
```
Client -> Server: plugin/install
         Params: {
           marketplace_path: "/absolute/path/to/marketplace.json",
           plugin_name: "sample-plugin",
           force_remote_sync: false
         }

Server -> Backend API: (if force_remote_sync) POST /plugins/{plugin_id}/enable
Server -> Client: PluginInstallResponse {
         auth_policy: PluginAuthPolicy,
         apps_needing_auth: [AppSummary { id, name, description, install_url }, ...]
       }
```

#### 远程同步流程
```
1. Mock Backend API
   POST /backend-api/plugins/sample-plugin@debug/enable
   Headers: Authorization: Bearer {token}, chatgpt-account-id: {account_id}
   Response: { "id": "sample-plugin@debug", "enabled": true }

2. Client Request
   plugin/install { force_remote_sync: true, ... }

3. Server Actions
   - Call backend API to enable plugin
   - Copy plugin files to local cache
   - Update config.toml with plugin configuration

4. Verification
   - Plugin files exist in cache directory
   - config.toml contains [plugins."sample-plugin@debug"] section
```

#### 分析事件流程
```
1. Start analytics mock server
2. Install plugin
3. Verify analytics event:
   {
     "events": [{
       "event_type": "codex_plugin_installed",
       "event_params": {
         "plugin_id": "sample-plugin@debug",
         "plugin_name": "sample-plugin",
         "marketplace_name": "debug",
         "has_skills": false,
         "mcp_server_count": 0,
         "connector_ids": [],
         "product_client_id": "codex-app-server-tests"
       }
     }]
   }
```

### 数据结构

#### PluginInstallParams
```rust
pub struct PluginInstallParams {
    pub marketplace_path: AbsolutePathBuf,  // 必须是绝对路径
    pub plugin_name: String,
    #[serde(default)]
    pub force_remote_sync: bool,  // 是否先同步远程状态
}
```

#### PluginInstallResponse
```rust
pub struct PluginInstallResponse {
    pub auth_policy: PluginAuthPolicy,  // OnInstall, OnUse
    pub apps_needing_auth: Vec<AppSummary>,
}
```

#### PluginAuthPolicy
```rust
pub enum PluginAuthPolicy {
    #[serde(rename = "ON_INSTALL")]
    OnInstall,  // 安装时需要授权
    #[serde(rename = "ON_USE")]
    OnUse,      // 使用时需要授权
}
```

#### PluginInstallPolicy
```rust
pub enum PluginInstallPolicy {
    #[serde(rename = "NOT_AVAILABLE")]
    NotAvailable,      // 不可安装
    #[serde(rename = "AVAILABLE")]
    Available,         // 可安装
    #[serde(rename = "INSTALLED_BY_DEFAULT")]
    InstalledByDefault, // 默认已安装
}
```

#### AppSummary
```rust
pub struct AppSummary {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub install_url: Option<String>,  // 如 "https://chatgpt.com/apps/{id}/{id}"
}
```

### 测试辅助结构

#### AppsServerState
```rust
#[derive(Clone)]
struct AppsServerState {
    response: Arc<StdMutex<serde_json::Value>>,
}
```

#### PluginInstallMcpServer
实现了 `rmcp::handler::server::ServerHandler` 的测试 MCP 服务器：
```rust
#[derive(Clone)]
struct PluginInstallMcpServer {
    tools: Arc<StdMutex<Vec<Tool>>>,
}

impl ServerHandler for PluginInstallMcpServer {
    fn get_info(&self) -> ServerInfo { ... }
    fn list_tools(&self, ...) -> impl Future<Output = Result<ListToolsResult, ...>> { ... }
}
```

### 测试辅助函数

#### write_plugin_marketplace
创建测试用的市场配置文件：
```rust
fn write_plugin_marketplace(
    repo_root: &std::path::Path,
    marketplace_name: &str,
    plugin_name: &str,
    source_path: &str,
    install_policy: Option<&str>,  // "NOT_AVAILABLE", "AVAILABLE", etc.
    auth_policy: Option<&str>,     // "ON_INSTALL", "ON_USE"
) -> std::io::Result<()>
```

#### write_plugin_source
创建测试用的插件源文件：
```rust
fn write_plugin_source(
    repo_root: &std::path::Path,
    plugin_name: &str,
    app_ids: &[&str],  // 插件依赖的连接器 ID 列表
) -> Result<()>
```

#### start_apps_server
启动测试用的应用/连接器服务器：
```rust
async fn start_apps_server(
    connectors: Vec<AppInfo>,
    tools: Vec<Tool>,
) -> Result<(String, JoinHandle<()>)>
```

#### connector_tool
创建连接器工具：
```rust
fn connector_tool(connector_id: &str, connector_name: &str) -> Result<Tool>
```

### 配置生成函数

```rust
fn write_connectors_config(codex_home: &std::path::Path, base_url: &str) -> std::io::Result<()>
fn write_analytics_config(codex_home: &std::path::Path, base_url: &str) -> std::io::Result<()>
fn write_plugin_remote_sync_config(codex_home: &std::path::Path, base_url: &str) -> std::io::Result<()>
```

### 常量定义
```rust
const DEFAULT_TIMEOUT: Duration = Duration::from_secs(10);
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/app-server/tests/suite/v2/plugin_install.rs`: 本测试文件
- `codex-rs/app-server/tests/suite/v2/mod.rs`: v2 测试模块入口

### 协议定义
- `codex-rs/app-server-protocol/src/protocol/v2.rs`:
  - `PluginInstallParams` (line 3360)
  - `PluginInstallResponse` (line 3371)
  - `PluginAuthPolicy` (line 3263)
  - `PluginInstallPolicy` (line 3249)
  - `AppSummary` (line 2030)
  - `AppInfo` (line 2001)

- `codex-rs/app-server-protocol/src/protocol/common.rs`:
  - `ClientRequest::PluginInstall` (line 343)

### 核心实现
- `codex-rs/app-server/src/plugin/...`: 插件管理实现
- `codex-rs/app-server/src/analytics/...`: 分析事件发送

### 测试支持
- `codex-rs/app-server/tests/common/mcp_process.rs`:
  - `McpProcess::send_plugin_install_request()`
  - `McpProcess::send_raw_request()`
  - `McpProcess::read_stream_until_error_message()`

- `codex-rs/app-server/tests/common/auth_fixtures.rs`:
  - `ChatGptAuthFixture`
  - `write_chatgpt_auth()`

- `codex-rs/app-server/tests/common/analytics_server.rs`:
  - `start_analytics_events_server()`

## 依赖与外部交互

### 外部依赖
| 依赖 | 用途 |
|------|------|
| `wiremock::{MockServer, Mock, ResponseTemplate}` | 模拟后端 API |
| `wiremock::matchers::{header, method, path}` | 请求匹配 |
| `axum::{Router, Json}` | 测试 MCP 服务器 |
| `rmcp::handler::server::ServerHandler` | MCP 服务器接口 |
| `rmcp::transport::StreamableHttpService` | MCP HTTP 传输 |
| `tokio::net::TcpListener` | 绑定测试服务器端口 |
| `serde_json::json!` | JSON 构造 |

### 内部依赖
| 模块 | 用途 |
|------|------|
| `app_test_support::*` | 测试支持库 |
| `codex_app_server_protocol::*` | 协议类型 |
| `codex_core::auth::AuthCredentialsStoreMode` | 认证存储模式 |
| `codex_utils_absolute_path::AbsolutePathBuf` | 绝对路径类型 |

### 测试架构
```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Test Client   │────▶│  codex-app-server │────▶│  Backend API    │
│  (McpProcess)   │◀────│   (MCP Server)    │◀────│  (MockServer)   │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                               │
                               │
                               ▼
                        ┌──────────────────┐
                        │  Apps MCP Server │
                        │ (PluginInstall   │
                        │   McpServer)     │
                        └──────────────────┘
                               │
                               ▼
                        ┌──────────────────┐
                        │ Analytics Server │
                        │  (MockServer)    │
                        └──────────────────┘
```

## 风险、边界与改进建议

### 已知风险

1. **Mock 服务器竞争**
   - 多个测试使用 `MockServer::start().await`
   - 随机端口分配可能冲突（虽然概率低）

2. **文件系统依赖**
   - 测试创建实际文件和目录
   - 在只读文件系统上无法运行

3. **认证 Fixtures 过期**
   - 使用硬编码的测试令牌
   - 如果验证逻辑改变，测试可能失败

4. **时序敏感**
   - 分析事件测试轮询等待请求
   - 在慢速系统上可能超时

### 边界情况

1. **并发安装**
   - 未测试同一插件的并发安装
   - 未测试不同插件的并发安装

2. **网络中断**
   - 未测试后端 API 不可用时的情况
   - 未测试分析服务器不可用时的情况

3. **部分失败**
   - 远程同步成功但本地安装失败的回滚
   - 分析事件发送失败不影响安装结果

4. **大文件处理**
   - 未测试大型插件的安装
   - 未测试大量连接器的插件

### 改进建议

1. **增加并发测试**
   ```rust
   // 建议添加
   async fn concurrent_plugin_installs()
   async fn install_while_another_in_progress()
   ```

2. **错误恢复测试**
   ```rust
   // 建议添加
   async fn plugin_install_rollback_on_failure()
   async fn plugin_install_survives_analytics_failure()
   ```

3. **边界值测试**
   ```rust
   // 建议添加
   async fn plugin_install_with_many_apps()
   async fn plugin_install_with_long_name()
   ```

4. **安全测试**
   ```rust
   // 建议添加
   async fn plugin_install_rejects_path_traversal()
   async fn plugin_install_validates_plugin_signature()
   ```

5. **性能基准**
   - 插件安装时间基准测试
   - 大量连接器检测性能测试

6. **测试隔离改进**
   - 使用临时数据库而非文件系统
   - 或使用内存文件系统加速测试
