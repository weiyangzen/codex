# mod.rs 研究文档

## 场景与职责

`mod.rs` 是 Codex 项目中 MCP (Model Context Protocol) 模块的主入口文件，负责 MCP 服务器管理、工具名称解析、Codex Apps 集成以及工具快照收集等核心功能。它是 Codex 与外部 MCP 生态系统交互的中央协调器。

### 核心职责
1. **MCP 服务器生命周期管理**：配置加载、服务器发现、连接管理
2. **Codex Apps 集成**：内置 MCP 服务器（codex_apps）的动态配置生成
3. **工具命名与分组**：工具名称的限定/解析、按服务器分组
4. **工具快照收集**：聚合所有 MCP 服务器的工具、资源、模板信息
5. **插件来源追踪**：追踪工具来自哪个插件/连接器

---

## 功能点目的

### 1. 工具名称限定系统

**目的**：解决多 MCP 服务器间工具名称冲突问题，为 Responses API 提供合规的工具名称。

**命名格式**：`mcp__<server_name>__<tool_name>`
- 使用 `__` 作为分隔符（符合 `^[a-zA-Z0-9_-]+$` 规范）
- Codex Apps 工具使用特殊格式：`<namespace><tool_name>`（无前缀）

### 2. Codex Apps MCP 服务器

**目的**：为 Codex 提供内置的 Apps/Connectors 功能支持，动态生成 MCP 服务器配置。

**关键特性**：
- 根据 `chatgpt_base_url` 自动构建 Apps 端点 URL
- 支持 Bearer Token 认证（环境变量或 AuthManager）
- 支持 Account ID 头部传递

### 3. 插件与 MCP 服务器融合

**目的**：将用户配置的 MCP 服务器与插件声明的 MCP 服务器合并，用户配置优先。

**合并策略**：
```
最终服务器列表 = 用户配置 ∪ 插件配置
（用户配置优先级更高，不会被子插件覆盖）
```

### 4. 工具快照收集 (`collect_mcp_snapshot`)

**目的**：在会话初始化时收集所有可用 MCP 工具、资源、模板，供模型使用。

**收集内容**：
- Tools：所有服务器的可用工具
- Resources：可读取的资源列表
- Resource Templates：资源模板
- Auth Statuses：各服务器的认证状态

---

## 具体技术实现

### 关键数据结构

```rust
// 工具插件来源追踪
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ToolPluginProvenance {
    plugin_display_names_by_connector_id: HashMap<String, Vec<String>>,
    plugin_display_names_by_mcp_server_name: HashMap<String, Vec<String>>,
}

// MCP 管理器
pub struct McpManager {
    plugins_manager: Arc<PluginsManager>,
}

// 工具信息（内部使用）
pub(crate) struct ToolInfo {
    pub(crate) server_name: String,
    pub(crate) tool_name: String,
    pub(crate) tool_namespace: String,
    pub(crate) tool: Tool,
    pub(crate) connector_id: Option<String>,
    pub(crate) connector_name: Option<String>,
    pub(crate) plugin_display_names: Vec<String>,
    pub(crate) connector_description: Option<String>,
}
```

### 关键常量

```rust
const MCP_TOOL_NAME_PREFIX: &str = "mcp";
const MCP_TOOL_NAME_DELIMITER: &str = "__";
pub(crate) const CODEX_APPS_MCP_SERVER_NAME: &str = "codex_apps";
const CODEX_CONNECTORS_TOKEN_ENV_VAR: &str = "CODEX_CONNECTORS_TOKEN";
```

### 关键流程

#### 1. 工具名称解析流程
```rust
split_qualified_tool_name("mcp__alpha__do_thing")
  ├── 检查前缀是否为 "mcp"
  ├── 提取 server_name = "alpha"
  └── 提取 tool_name = "do_thing"

// 嵌套工具名支持
split_qualified_tool_name("mcp__alpha__nested__op")
  └── tool_name = "nested__op"（保留内部 __）
```

#### 2. Codex Apps URL 构建流程
```
codex_apps_mcp_url_for_base_url(base_url)
  ├── normalize_codex_apps_base_url
  │   ├── 移除尾部 /
  │   └── 如果是 chatgpt.com/chat.openai.com，追加 /backend-api
  └── 根据路径模式选择端点
      ├── /backend-api → /wham/apps
      ├── /api/codex → /apps
      └── 其他 → /api/codex/apps
```

#### 3. 服务器配置合并流程
```
effective_mcp_servers(config, auth, plugins_manager)
  ├── configured_mcp_servers
  │   ├── 加载 config.mcp_servers
  │   └── 合并 plugins_manager.effective_mcp_servers()
  └── with_codex_apps_mcp
      ├── 检查 features.apps_enabled_for_auth(auth)
      └── 条件性插入 codex_apps 服务器配置
```

#### 4. 快照收集流程
```
collect_mcp_snapshot(config)
  ├── 创建 AuthManager
  ├── 创建 McpManager
  ├── 获取 effective_servers
  ├── compute_auth_statuses (并行计算认证状态)
  ├── 创建 McpConnectionManager
  └── collect_mcp_snapshot_from_manager
      ├── list_all_tools (并行)
      ├── list_all_resources (并行)
      ├── list_all_resource_templates (并行)
      └── 序列化/转换结果
```

### 工具分组算法

```rust
pub fn group_tools_by_server(
    tools: &HashMap<String, Tool>
) -> HashMap<String, HashMap<String, Tool>> {
    // 输入: {"mcp__alpha__tool1": Tool1, "mcp__beta__tool2": Tool2}
    // 输出: {"alpha": {"tool1": Tool1}, "beta": {"tool2": Tool2}}
}
```

---

## 关键代码路径与文件引用

### 模块结构

```
codex-rs/core/src/mcp/
├── mod.rs              # 主模块（本文件）
├── auth.rs             # OAuth 认证相关
├── skill_dependencies.rs  # Skill MCP 依赖安装
├── mod_tests.rs        # 模块测试
└── skill_dependencies_tests.rs  # 依赖测试
```

### 内部依赖关系

```
mod.rs
├── 使用: auth::{compute_auth_statuses, McpAuthStatusEntry}
├── 使用: skill_dependencies::maybe_prompt_and_install_mcp_dependencies
├── 被使用: 
│   ├── codex.rs (McpManager, collect_mcp_snapshot)
│   ├── mcp_connection_manager.rs (CODEX_APPS_MCP_SERVER_NAME, split_qualified_tool_name)
│   └── connectors.rs (工具调用处理)
```

### 外部依赖

```
codex_protocol
├── McpListToolsResponseEvent
├── Tool, Resource, ResourceTemplate
└── SandboxPolicy

codex_rmcp_client
├── RmcpClient
├── OAuthCredentialsStoreMode
└── ElicitationResponse

rmcp::model
├── ClientCapabilities
├── InitializeRequestParams
├── Tool, Resource, ResourceTemplate
└── ...
```

### 配置系统交互

```
codex-rs/core/src/config/types.rs
├── McpServerConfig
│   ├── transport: McpServerTransportConfig
│   ├── enabled: bool
│   ├── required: bool
│   ├── startup_timeout_sec: Option<Duration>
│   ├── tool_timeout_sec: Option<Duration>
│   ├── enabled_tools: Option<Vec<String>>
│   ├── disabled_tools: Option<Vec<String>>
│   ├── scopes: Option<Vec<String>>
│   └── oauth_resource: Option<String>
└── McpServerTransportConfig
    ├── Stdio { command, args, env, env_vars, cwd }
    └── StreamableHttp { url, bearer_token_env_var, http_headers, env_http_headers }
```

---

## 依赖与外部交互

### 与 McpConnectionManager 的交互

`mod.rs` 负责配置管理，`McpConnectionManager` 负责实际连接：

```rust
// mod.rs 提供配置和初始状态
let (mcp_connection_manager, cancel_token) = McpConnectionManager::new(
    &mcp_servers,                    // 来自 effective_mcp_servers()
    config.mcp_oauth_credentials_store_mode,
    auth_status_entries,             // 来自 compute_auth_statuses()
    &config.permissions.approval_policy,
    tx_event,
    sandbox_state,
    config.codex_home.clone(),
    codex_apps_tools_cache_key(auth.as_ref()),
    tool_plugin_provenance,          // 来自 tool_plugin_provenance()
).await;

// 委托实际工具列表获取
let tools = mcp_connection_manager.list_all_tools().await;
```

### 与 PluginsManager 的交互

```rust
// 从插件加载 MCP 服务器配置
let loaded_plugins = plugins_manager.plugins_for_config(config);
for (name, plugin_server) in loaded_plugins.effective_mcp_servers() {
    servers.entry(name).or_insert(plugin_server);  // 用户配置优先
}
```

### 与 Codex 主流程的交互

```rust
// codex.rs 中的调用
pub async fn refresh_mcp_servers_now(
    &self,
    turn_context: &TurnContext,
    servers: HashMap<String, McpServerConfig>,
    store_mode: OAuthCredentialsStoreMode,
) {
    // 使用 mod.rs 提供的服务器配置
}
```

---

## 风险、边界与改进建议

### 已知风险

1. **工具名称长度限制**
   - Responses API 限制工具名 `^[a-zA-Z0-9_-]+$` 且最大 64 字符
   - 长名称会被哈希截断，可能影响可读性
   - **缓解**：`mcp_connection_manager.rs` 中的 `sanitize_responses_api_tool_name` 和长度处理

2. **Codex Apps URL 硬编码逻辑**
   ```rust
   if base_url.contains("/backend-api") {
       format!("{base_url}/wham/apps")
   } else if base_url.contains("/api/codex") {
       format!("{base_url}/apps")
   } else {
       format!("{base_url}/api/codex/apps")
   }
   ```
   - 依赖特定路径模式，新增环境需修改代码
   - **建议**：考虑配置化或更灵活的 URL 模板

3. **快照收集阻塞**
   - `collect_mcp_snapshot` 是同步等待所有服务器响应
   - 单个慢服务器会拖慢整体启动
   - **建议**：增加超时控制或渐进式加载

4. **Token 环境变量处理**
   ```rust
   fn codex_apps_mcp_bearer_token_env_var() -> Option<String> {
       match env::var(CODEX_CONNECTORS_TOKEN_ENV_VAR) {
           Ok(value) if !value.trim().is_empty() => Some(...),
           Ok(_) => None,  // 空值视为未设置
           Err(env::VarError::NotPresent) => None,
           Err(env::VarError::NotUnicode(_)) => Some(...),  // 非 Unicode 仍返回变量名
       }
   }
   ```
   - 非 Unicode 值的处理可能令人困惑

### 边界情况

| 场景 | 当前行为 | 评估 |
|------|---------|------|
| 插件与用户配置冲突 | 用户配置优先 | ✅ 合理 |
| codex_apps 被用户显式禁用 | 从 servers 中移除 | ✅ 合理 |
| 工具名包含非法字符 | 替换为 `_` | ✅ 符合 API 要求 |
| 重复工具名 | 跳过并警告 | ⚠️ 可能导致工具不可用 |
| 空的 MCP 服务器列表 | 返回空快照 | ✅ 合理 |

### 改进建议

1. **工具名称冲突解决**
   ```rust
   // 当前：简单跳过
   if !seen_raw_names.insert(qualified_name_raw.clone()) {
       warn!("skipping duplicated tool {}", qualified_name_raw);
       continue;
   }
   
   // 建议：增加服务器来源标记
   let disambiguated = format!("{}_{}", qualified_name, server_name_hash);
   ```

2. **Codex Apps 配置外部化**
   ```toml
   # 建议：支持在配置中自定义 Apps 端点
   [codex_apps]
   base_path = "/custom/apps"
   enabled = true
   ```

3. **快照收集性能优化**
   - 增加服务器级超时
   - 支持部分结果返回（先返回已就绪的服务器）
   - 缓存不频繁变更的工具列表

4. **增强插件来源追踪**
   - 当前仅追踪 display name
   - 建议增加插件版本、来源 URL 等信息

5. **错误隔离**
   ```rust
   // 建议：单个服务器失败不影响其他服务器
   let results: Vec<_> = futures::future::join_all(futures)
       .await
       .into_iter()
       .filter_map(|r| r.ok())  // 忽略失败
       .collect();
   ```

### 测试覆盖

当前测试（`mod_tests.rs`）：
- ✅ `split_qualified_tool_name` 解析逻辑
- ✅ `group_tools_by_server` 分组逻辑
- ✅ `ToolPluginProvenance` 来源追踪
- ✅ `codex_apps_mcp_url_for_base_url` URL 构建
- ✅ `effective_mcp_servers` 配置合并

建议补充：
- 工具名称长度限制边界测试
- 并发快照收集测试
- 插件与用户配置冲突场景测试
- Codex Apps 认证失败回退测试
