# MCP Connection Manager 研究文档

## 文件信息
- **文件路径**: `codex-rs/core/src/mcp_connection_manager.rs`
- **代码行数**: 1741 行
- **主要功能**: Model Context Protocol (MCP) 服务器连接管理

---

## 一、场景与职责

### 1.1 核心定位
`McpConnectionManager` 是 Codex 与 MCP (Model Context Protocol) 服务器之间的核心连接管理层。它负责：

1. **多服务器连接管理**: 维护多个 MCP 服务器的客户端连接（`RmcpClient`）
2. **工具聚合与暴露**: 将所有服务器的工具聚合为统一的工具映射表
3. **生命周期管理**: 处理服务器的启动、初始化、故障恢复和关闭
4. **沙箱状态同步**: 向 MCP 服务器推送沙箱策略变更通知
5. **Elicitation 请求处理**: 处理 MCP 服务器的交互式请求（如 OAuth 授权表单）

### 1.2 使用场景
- **Codex CLI/TUI 启动时**: 初始化所有配置的 MCP 服务器连接
- **工具调用时**: 根据工具名称路由到对应的服务器执行
- **资源访问时**: 提供 MCP 资源的读取能力
- **动态配置更新**: 支持运行时更新请求头（如 token 刷新）

---

## 二、功能点目的

### 2.1 工具名称规范化与聚合

**目的**: 解决多服务器工具命名冲突，同时符合 OpenAI Responses API 的命名规范（`^[a-zA-Z0-9_-]+$`）

**实现策略**:
- 使用 `__` 作为分隔符，格式: `mcp__<server_name>__<tool_name>`
- 非法字符替换为下划线
- 超长名称（>64字符）使用 SHA1 哈希截断处理
- 冲突检测与去重

### 2.2 异步启动与缓存快照

**目的**: 避免启动时阻塞，提供即时可用性

**实现策略**:
- `AsyncManagedClient` 使用 `Shared<BoxFuture>` 包装异步初始化
- `startup_snapshot` 机制：从磁盘缓存加载工具列表，在连接建立前即可提供服务
- 后台任务完成实际连接初始化

### 2.3 Codex Apps 工具缓存

**目的**: 加速 `codex_apps` 服务器的工具列表获取（该服务器提供第三方应用连接器）

**实现策略**:
- 用户级缓存：基于 `account_id` + `chatgpt_user_id` 生成缓存键
- 缓存路径: `~/.codex/cache/codex_apps_tools/<sha1(user_key)>.json`
- 强制刷新 API: `hard_refresh_codex_apps_tools_cache()`
- Schema 版本控制（当前 v1）

### 2.4 工具过滤

**目的**: 允许用户细粒度控制可用工具

**实现策略**:
- `enabled_tools`: 白名单模式，仅允许列表中的工具
- `disabled_tools`: 黑名单模式，排除指定工具
- 白名单优先于黑名单

### 2.5 Elicitation 请求管理

**目的**: 支持 MCP 服务器的交互式授权流程（如 OAuth 登录表单）

**实现策略**:
- `ElicitationRequestManager` 维护请求 ID 到 oneshot channel 的映射
- 将 MCP 的 `CreateElicitationRequestParams` 转换为内部 `ElicitationRequest` 事件
- 支持策略控制：可通过 `AskForApproval` 配置禁用 elicitation

---

## 三、具体技术实现

### 3.1 关键数据结构

```rust
// 主管理器结构
pub(crate) struct McpConnectionManager {
    clients: HashMap<String, AsyncManagedClient>,
    server_origins: HashMap<String, String>,  // 服务器名称 -> 来源(origin)
    elicitation_requests: ElicitationRequestManager,
}

// 异步管理的客户端
struct AsyncManagedClient {
    client: Shared<BoxFuture<'static, Result<ManagedClient, StartupOutcomeError>>>,
    request_headers: Arc<StdMutex<Option<HeaderMap>>>,
    startup_snapshot: Option<Vec<ToolInfo>>,  // 启动时的缓存快照
    startup_complete: Arc<AtomicBool>,
    tool_plugin_provenance: Arc<ToolPluginProvenance>,
}

// 已初始化的客户端
struct ManagedClient {
    client: Arc<RmcpClient>,
    tools: Vec<ToolInfo>,
    tool_filter: ToolFilter,
    tool_timeout: Option<Duration>,
    server_supports_sandbox_state_capability: bool,
    codex_apps_tools_cache_context: Option<CodexAppsToolsCacheContext>,
}

// 工具信息
pub(crate) struct ToolInfo {
    pub(crate) server_name: String,
    pub(crate) tool_name: String,
    pub(crate) tool_namespace: String,
    pub(crate) tool: Tool,  // rmcp::model::Tool
    pub(crate) connector_id: Option<String>,
    pub(crate) connector_name: Option<String>,
    pub(crate) plugin_display_names: Vec<String>,
    pub(crate) connector_description: Option<String>,
}
```

### 3.2 关键流程

#### 3.2.1 初始化流程 (`McpConnectionManager::new`)

```
1. 遍历所有启用的 MCP 服务器配置
2. 为每个服务器创建 AsyncManagedClient:
   a. 加载 startup_snapshot（如果是 codex_apps）
   b. 创建 Shared Future 包装异步初始化
   c. 如有 snapshot，spawn 后台任务预热
3. 创建 JoinSet 并行初始化所有服务器
4. 每个服务器初始化完成后:
   a. 发送 sandbox 状态通知
   b. 发送 McpStartupUpdateEvent
5. 所有服务器完成后，发送 McpStartupCompleteEvent
```

#### 3.2.2 工具列表获取流程 (`list_all_tools`)

```
1. 遍历所有 AsyncManagedClient
2. 调用 listed_tools():
   a. 如果 startup 未完成且存在 startup_snapshot: 返回 snapshot
   b. 否则等待 client 初始化完成，返回实际工具列表
3. 调用 annotate_tools() 添加插件来源信息
4. 使用 qualify_tools() 规范化工具名称
5. 合并所有服务器的工具到统一 HashMap
```

#### 3.2.3 工具调用流程 (`call_tool`)

```
1. 通过 server_name 获取 ManagedClient
2. 检查 tool_filter 是否允许该工具
3. 调用 RmcpClient::call_tool()
4. 转换结果为 CallToolResult
```

#### 3.2.4 Elicitation 处理流程

```
MCP Server -> CreateElicitationRequest -> RmcpClient
                                    |
                                    v
                          ElicitationRequestManager::make_sender
                                    |
                                    v
                          转换为 ElicitationRequest 事件
                                    |
                                    v
                          通过 tx_event 发送到 UI
                                    |
                                    v
                          用户响应 -> resolve_elicitation()
                                    |
                                    v
                          通过 oneshot channel 返回响应
```

### 3.3 协议与常量

```rust
// 工具名称分隔符（OpenAI 兼容）
const MCP_TOOL_NAME_DELIMITER: &str = "__";
const MAX_TOOL_NAME_LENGTH: usize = 64;

// 超时配置
pub const DEFAULT_STARTUP_TIMEOUT: Duration = Duration::from_secs(10);
const DEFAULT_TOOL_TIMEOUT: Duration = Duration::from_secs(120);

// 自定义 MCP 能力
pub const MCP_SANDBOX_STATE_CAPABILITY: &str = "codex/sandbox-state";
pub const MCP_SANDBOX_STATE_METHOD: &str = "codex/sandbox-state/update";

// 缓存配置
const CODEX_APPS_TOOLS_CACHE_SCHEMA_VERSION: u8 = 1;
const CODEX_APPS_TOOLS_CACHE_DIR: &str = "cache/codex_apps_tools";

// 指标名称
const MCP_TOOLS_LIST_DURATION_METRIC: &str = "codex.mcp.tools.list.duration_ms";
const MCP_TOOLS_FETCH_UNCACHED_DURATION_METRIC: &str = "codex.mcp.tools.fetch_uncached.duration_ms";
const MCP_TOOLS_CACHE_WRITE_DURATION_METRIC: &str = "codex.mcp.tools.cache_write.duration_ms";
```

---

## 四、关键代码路径与文件引用

### 4.1 内部依赖

| 文件 | 用途 |
|------|------|
| `codex-rs/core/src/mcp/mod.rs` | `CODEX_APPS_MCP_SERVER_NAME`, `ToolPluginProvenance` |
| `codex-rs/core/src/mcp/auth.rs` | `McpAuthStatusEntry` |
| `codex-rs/core/src/config/types.rs` | `McpServerConfig`, `McpServerTransportConfig` |
| `codex-rs/core/src/connectors.rs` | `is_connector_id_allowed`, `sanitize_name` |
| `codex-rs/core/src/codex.rs` | `INITIAL_SUBMIT_ID` |

### 4.2 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_rmcp_client` | `RmcpClient`, `OAuthCredentialsStoreMode`, `ElicitationResponse` |
| `rmcp` | MCP 协议类型: `Tool`, `Resource`, `ClientCapabilities`, `InitializeRequestParams` 等 |
| `codex_protocol` | 内部协议类型: `Event`, `EventMsg`, `McpStartupUpdateEvent`, `SandboxPolicy` |
| `codex_config` | `Constrained<AskForApproval>` |
| `codex_async_utils` | `CancelErr`, `OrCancelExt` |

### 4.3 关键函数路径

```
// 初始化
McpConnectionManager::new() -> (Self, CancellationToken)
  └─> AsyncManagedClient::new()
      └─> make_rmcp_client()  // 根据 transport 类型创建客户端
      └─> start_server_task()  // 初始化协议握手

// 工具管理
list_all_tools() -> HashMap<String, ToolInfo>
  └─> AsyncManagedClient::listed_tools()
      └─> ManagedClient::listed_tools() / startup_snapshot
  └─> qualify_tools()  // 规范化名称

call_tool(server, tool, arguments) -> Result<CallToolResult>
  └─> client_by_name()
  └─> RmcpClient::call_tool()

// 资源管理
list_all_resources() -> HashMap<String, Vec<Resource>>
list_all_resource_templates() -> HashMap<String, Vec<ResourceTemplate>>
read_resource(server, params) -> Result<ReadResourceResult>

// 缓存管理
load_cached_codex_apps_tools() -> CachedCodexAppsToolsLoad
write_cached_codex_apps_tools()
hard_refresh_codex_apps_tools_cache() -> Result<HashMap<String, ToolInfo>>
```

---

## 五、依赖与外部交互

### 5.1 配置依赖

**McpServerConfig** (来自 `config/types.rs`):
```rust
pub struct McpServerConfig {
    pub transport: McpServerTransportConfig,  // Stdio | StreamableHttp
    pub enabled: bool,
    pub required: bool,
    pub startup_timeout_sec: Option<Duration>,
    pub tool_timeout_sec: Option<Duration>,
    pub enabled_tools: Option<Vec<String>>,   // 白名单
    pub disabled_tools: Option<Vec<String>>,  // 黑名单
    pub scopes: Option<Vec<String>>,          // OAuth scopes
}
```

### 5.2 传输层支持

**Stdio Transport**:
- 启动本地命令作为 MCP 服务器
- 通过 stdin/stdout 进行 JSON-RPC 通信

**Streamable HTTP Transport**:
- 连接到远程 HTTP 端点
- 支持 Bearer Token 认证（环境变量或硬编码）
- 支持自定义 HTTP Headers

### 5.3 事件系统交互

通过 `async_channel::Sender<Event>` 向上层发送：
- `McpStartupUpdateEvent`: 单个服务器启动状态更新
- `McpStartupCompleteEvent`: 所有服务器启动完成摘要
- `ElicitationRequestEvent`: 需要用户交互的请求

### 5.4 沙箱集成

```rust
pub struct SandboxState {
    pub sandbox_policy: SandboxPolicy,
    pub codex_linux_sandbox_exe: Option<PathBuf>,
    pub sandbox_cwd: PathBuf,
    pub use_legacy_landlock: bool,
}
```

服务器初始化完成后，自动发送 `codex/sandbox-state/update` 通知。

---

## 六、风险、边界与改进建议

### 6.1 已知风险

1. **工具名称冲突**
   - 风险: 不同服务器的工具规范化后可能产生相同名称
   - 缓解: 使用 SHA1 哈希去重，但可能导致工具丢失
   - 建议: 添加监控告警，记录被跳过的冲突工具

2. **缓存失效**
   - 风险: `codex_apps` 工具缓存可能过期，导致新安装的应用不可用
   - 缓解: 提供 `hard_refresh_codex_apps_tools_cache()` API
   - 建议: 添加缓存 TTL 机制

3. **启动超时**
   - 风险: 慢速 MCP 服务器可能导致整体启动超时
   - 缓解: 可配置的 `startup_timeout_sec`，支持后台继续初始化
   - 建议: 添加健康检查端点

4. **Elicitation 竞争条件**
   - 风险: 多个并发 elicitation 请求可能相互干扰
   - 缓解: 使用 `(server_name, request_id)` 元组作为唯一键
   - 建议: 添加请求超时清理机制

### 6.2 边界条件

| 边界 | 处理 |
|------|------|
| 空工具列表 | 正常处理，返回空 HashMap |
| 服务器启动失败 | 记录错误，继续初始化其他服务器（除非 `required: true`） |
| 重复工具名称 | 跳过重复项，保留第一个 |
| 超长工具名 (>64) | SHA1 哈希截断 |
| 非法字符 | 替换为下划线 |
| 取消初始化 | 通过 CancellationToken 传播，返回 `StartupOutcomeError::Cancelled` |

### 6.3 改进建议

1. **连接池优化**
   - 当前: 每个服务器一个独立连接
   - 建议: 对高并发场景支持连接池

2. **工具变更热更新**
   - 当前: 工具列表在启动时固定
   - 建议: 支持服务器推送工具变更通知

3. **更细粒度的超时控制**
   - 当前: 全局 tool_timeout
   - 建议: 支持按工具配置超时

4. **可观测性增强**
   - 当前: 基础指标（list duration, cache hit/miss）
   - 建议: 添加工具调用延迟分布、错误率、服务器健康状态等指标

5. **缓存策略优化**
   - 当前: 仅 codex_apps 有缓存
   - 建议: 为所有 MCP 服务器提供可选缓存层

6. **错误处理细化**
   - 当前: 部分错误信息较为笼统
   - 建议: 区分网络错误、认证错误、协议错误，提供更有针对性的用户提示

---

## 七、测试覆盖

测试文件: `mcp_connection_manager_tests.rs`

主要测试场景:
- 工具名称规范化与冲突处理
- 工具过滤逻辑（白名单/黑名单）
- Codex Apps 工具缓存读写
- 启动快照机制
- Elicitation 策略控制
- 错误消息格式化
- 传输层 origin 提取

---

*文档生成时间: 2026-03-23*
*基于代码版本: codex-rs/core/src/mcp_connection_manager.rs (1741 lines)*
