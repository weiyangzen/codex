# connectors.rs 研究文档

## 场景与职责

`connectors.rs` 是 `codex-chatgpt` crate 中负责 **ChatGPT 应用连接器（App Connectors）管理**的核心模块。连接器是 ChatGPT 与外部服务（如 GitHub、Slack、Google Drive 等）集成的桥梁，该模块提供连接器的发现、缓存、过滤和状态管理功能。

### 核心使用场景

1. **连接器发现**：从 ChatGPT 目录 API 获取可用连接器列表
2. **权限检查**：确定用户已授权访问哪些连接器
3. **MCP 工具集成**：将连接器与 MCP（Model Context Protocol）工具关联
4. **插件应用管理**：管理通过插件配置添加的应用
5. **UI 展示**：为 TUI/CLI 提供格式化的连接器信息

## 功能点目的

### 1. list_connectors 主入口
获取完整连接器列表（目录 + 可访问）：
- 检查 `apps_enabled` 功能开关
- 并行获取目录连接器和可访问连接器
- 合并并添加启用状态

### 2. list_all_connectors / list_all_connectors_with_options
从 ChatGPT 目录 API 获取所有连接器：
- 支持强制刷新（`force_refetch`）
- 使用缓存减少 API 调用
- 合并插件应用

### 3. list_cached_all_connectors 缓存版本
快速获取缓存的连接器列表：
- 无网络调用
- 用于 UI 快速响应

### 4. list_accessible_connectors_from_mcp_tools MCP 集成
从 MCP 工具中发现可访问连接器：
- 启动 MCP 服务器
- 获取工具列表
- 提取连接器信息

### 5. 连接器过滤与合并
- `filter_disallowed_connectors`：过滤不允许的连接器 ID
- `merge_connectors`：合并目录和可访问连接器数据
- `merge_plugin_apps`：合并插件配置的应用
- `with_app_enabled_state`：应用用户配置的启用状态

## 具体技术实现

### 关键流程

#### 获取连接器列表

```
list_connectors
├── apps_enabled (检查功能开关)
├── tokio::join!(
│   ├── list_all_connectors          // 目录连接器
│   └── list_accessible_connectors_from_mcp_tools  // 可访问连接器
│)
├── merge_connectors_with_accessible // 合并数据
└── with_app_enabled_state           // 应用启用配置
```

#### 目录连接器获取

```
list_all_connectors_with_options
├── apps_enabled
├── init_chatgpt_token_from_auth
├── get_chatgpt_token_data
├── all_connectors_cache_key         // 构造缓存键
├── codex_connectors::list_all_connectors_with_options
│   ├── cached_all_connectors        // 检查缓存
│   ├── list_directory_connectors    // 分页获取目录
│   └── list_workspace_connectors    // 获取工作区连接器（如适用）
├── merge_plugin_apps                // 合并插件应用
└── filter_disallowed_connectors     // 过滤
```

### 数据结构

```rust
// 来自 codex_app_server_protocol
pub struct AppInfo {
    pub id: String,                          // 连接器 ID
    pub name: String,                        // 显示名称
    pub description: Option<String>,         // 描述
    pub logo_url: Option<String>,            // Logo URL
    pub logo_url_dark: Option<String>,       // 深色模式 Logo
    pub distribution_channel: Option<String>,
    pub branding: Option<AppBranding>,       // 品牌信息
    pub app_metadata: Option<AppMetadata>,   // 元数据
    pub labels: Option<HashMap<String, String>>,
    pub install_url: Option<String>,         // 安装链接
    pub is_accessible: bool,                 // 用户是否已授权
    pub is_enabled: bool,                    // 是否启用
    pub plugin_display_names: Vec<String>,   // 关联的插件名称
}

// 缓存键
pub struct AllConnectorsCacheKey {
    chatgpt_base_url: String,
    account_id: Option<String>,
    chatgpt_user_id: Option<String>,
    is_workspace_account: bool,
}

// 目录 API 响应
pub struct DirectoryListResponse {
    apps: Vec<DirectoryApp>,
    next_token: Option<String>,  // 分页令牌
}
```

### 连接器过滤规则

```rust
// 禁止的连接器 ID 列表
const DISALLOWED_CONNECTOR_IDS: &[&str] = &[
    "asdk_app_6938a94a61d881918ef32cb999ff937c",
    // ... 其他禁止 ID
];

// 禁止的前缀
const DISALLOWED_CONNECTOR_PREFIX: &str = "connector_openai_";

// First-Party Chat 额外的禁止 ID
const FIRST_PARTY_CHAT_DISALLOWED_CONNECTOR_IDS: &[&str] = 
    &["connector_0f9c9d4592e54d0a9a12b3f44a1e2010"];
```

### MCP 集成流程

```rust
list_accessible_connectors_from_mcp_tools_with_options_and_status
├── 检查 apps_enabled
├── 检查缓存
├── with_codex_apps_mcp              // 配置 MCP 服务器
├── McpConnectionManager::new        // 启动连接管理器
├── 等待服务器就绪
├── list_all_tools                   // 获取所有工具
├── accessible_connectors_from_mcp_tools  // 提取连接器
└── filter_disallowed_connectors
```

## 关键代码路径与文件引用

### 内部依赖

| 模块 | 路径 | 用途 |
|------|------|------|
| `chatgpt_token` | `chatgpt_token.rs` | 令牌初始化/获取 |
| `chatgpt_client` | `chatgpt_client.rs` | API 调用 |

### 外部依赖

| Crate | 模块 | 用途 |
|-------|------|------|
| `codex_connectors` | `lib.rs` | 目录连接器 API 客户端 |
| `codex_core` | `connectors.rs` | 核心连接器逻辑 |
| `codex_core` | `plugins` | 插件管理 |
| `codex_core` | `mcp` | MCP 协议集成 |
| `codex_core` | `features` | 功能开关 |

### 核心连接器常量

```rust
const DIRECTORY_CONNECTORS_TIMEOUT: Duration = Duration::from_secs(60);
const CONNECTORS_READY_TIMEOUT_ON_EMPTY_TOOLS: Duration = Duration::from_secs(30);
```

### 调用链

```
TUI/App Server
└── list_connectors
    ├── codex_connectors::list_all_connectors_with_options
    │   ├── /connectors/directory/list
    │   └── /connectors/directory/list_workspace
    └── list_accessible_connectors_from_mcp_tools
        └── McpConnectionManager
```

## 依赖与外部交互

### 1. ChatGPT 目录 API

端点：
- `GET /connectors/directory/list?tier=categorized&external_logos=true`
- `GET /connectors/directory/list_workspace?external_logos=true`

支持分页（`next_token`）

### 2. MCP 服务器

`codex_apps` MCP 服务器：
- 提供连接器授权状态
- 暴露连接器相关工具
- 需要 OAuth 认证

### 3. 配置系统

依赖配置项：
- `features.apps_enabled`：功能开关
- `chatgpt_base_url`：API 基础 URL
- `codex_home`：认证文件位置
- `apps`：用户应用配置（启用/禁用状态）

### 4. 缓存系统

- 内存缓存（`ALL_CONNECTORS_CACHE`）
- TTL：3600 秒（1 小时）
- 缓存键包含用户标识，确保多用户安全

## 风险、边界与改进建议

### 风险点

1. **MCP 服务器启动延迟**
   - 首次获取可访问连接器需要启动 MCP 服务器
   - 超时 30 秒可能导致用户体验问题
   - 建议：后台预热缓存

2. **缓存一致性问题**
   - 连接器授权状态变更后缓存不会立即更新
   - 用户可能需要等待 1 小时或强制刷新
   - 建议：提供 `force_refetch` 的 UI 暴露

3. **工作区连接器失败**
   ```rust
   async fn list_workspace_connectors(...) {
       match response {
           Ok(response) => Ok(...),
           Err(_) => Ok(Vec::new()),  // 静默忽略错误
       }
   }
   ```
   工作区查询失败时静默返回空列表

4. **过滤器硬编码**
   - 禁止的连接器 ID 列表是编译时常量
   - 需要发布新版本才能更新
   - 建议：支持远程配置

### 边界条件

1. **功能关闭**
   ```rust
   if !apps_enabled(config).await {
       return Ok(Vec::new());
   }
   ```
   功能关闭时返回空列表

2. **未登录用户**
   - `init_chatgpt_token_from_auth` 失败
   - 缓存版本返回 `None`
   - 非缓存版本返回错误

3. **空工具列表**
   - MCP 服务器返回空工具时等待超时
   - 可能误判为服务器未就绪

4. **插件应用不存在**
   ```rust
   fn plugin_app_to_app_info(connector_id: AppConnectorId) -> AppInfo
   ```
   为不存在的连接器创建占位信息

### 改进建议

1. **后台缓存刷新**
   ```rust
   pub async fn start_background_refresh(config: &Config) {
       tokio::spawn(async move {
           loop {
               tokio::time::sleep(CACHE_REFRESH_INTERVAL).await;
               let _ = list_all_connectors_with_options(config, true).await;
           }
       });
   }
   ```

2. **增量更新**
   - 支持 ETag 或 Last-Modified 检查
   - 减少不必要的数据传输

3. **更好的错误处理**
   ```rust
   pub enum ConnectorsError {
       Network(reqwest::Error),
       Auth(AuthError),
       Mcp(McpError),
       Timeout,
   }
   ```

4. **连接器状态流**
   - 使用事件驱动模型
   - 连接器状态变更时主动推送

5. **性能优化**
   - 目录连接器数量可能很大
   - 考虑分页或流式加载

### 测试覆盖

当前已有较好的单元测试覆盖：
- `allows_asdk_connectors`：ASDK 连接器白名单
- `filters_openai_prefixed_connectors`：前缀过滤
- `filters_disallowed_connector_ids`：ID 黑名单
- `merge_connectors_with_accessible`：合并逻辑
- `connectors_for_plugin_apps`：插件应用过滤

建议添加：
- 并发安全测试
- 缓存过期测试
- MCP 集成测试（Mock）
