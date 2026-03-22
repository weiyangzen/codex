# connectors.rs 研究文档

## 场景与职责

`connectors.rs` 是 Codex 核心模块中负责管理 **App/Connector（应用连接器）** 的核心文件。在 Codex 架构中，Connectors 是指与外部服务（如 GitHub、Google Calendar、Slack 等）集成的 MCP (Model Context Protocol) 工具集合。

### 主要职责
1. **可访问连接器管理**：从 MCP 工具中发现并列出用户已授权（accessible）的连接器
2. **连接器目录服务**：从 ChatGPT 目录 API 获取所有可用连接器列表
3. **连接器状态管理**：管理连接器的启用/禁用状态、工具审批策略
4. **工具建议发现**：为工具推荐功能提供可发现但未安装的连接器列表
5. **连接器缓存**：实现内存缓存机制减少重复 API 调用

### 业务场景
- 用户在 Codex 中使用 `@github` 或 `@calendar` 等 mention 语法调用外部服务
- TUI/App-server 需要展示用户已安装/可用的应用列表
- 工具调用前需要检查应用是否启用以及审批策略

---

## 功能点目的

### 1. 可访问连接器发现 (`list_accessible_connectors_from_mcp_tools`)
从 MCP 工具元数据中提取用户已授权的连接器信息。这是通过检查 `codex_apps` MCP 服务器提供的工具来实现的。

### 2. 连接器缓存管理
- **缓存键设计**：基于 `chatgpt_base_url`、`account_id`、`chatgpt_user_id`、`is_workspace_account`
- **TTL**：3600秒（1小时），定义在 `codex_connectors::CONNECTORS_CACHE_TTL`
- **双级缓存**：支持强制刷新（force_refetch）和软读取

### 3. 工具策略评估 (`app_tool_policy`)
根据配置决定特定应用工具的启用状态和审批模式：
- **启用状态**：考虑全局默认、应用级覆盖、工具级覆盖
- **审批模式**：`Auto`（自动）、`Prompt`（提示）、`Approve`（需要审批）
- **注解感知**：根据工具的 `destructive_hint` 和 `open_world_hint` 自动决策

### 4. 连接器过滤
- **黑名单过滤**：排除特定 connector_id（如 OpenAI 内部连接器）
- **来源感知**：根据 originator（如 `codex_atlas`）应用不同的过滤规则

### 5. 连接器合并与增强
- 合并来自目录的连接器元数据和来自 MCP 的可访问状态
- 添加插件来源信息（`plugin_display_names`）

---

## 具体技术实现

### 关键数据结构

```rust
// 应用工具策略（启用状态 + 审批模式）
pub(crate) struct AppToolPolicy {
    pub enabled: bool,
    pub approval: AppToolApproval,  // Auto | Prompt | Approve
}

// 可访问连接器缓存键
struct AccessibleConnectorsCacheKey {
    chatgpt_base_url: String,
    account_id: Option<String>,
    chatgpt_user_id: Option<String>,
    is_workspace_account: bool,
}

// 缓存条目
struct CachedAccessibleConnectors {
    key: AccessibleConnectorsCacheKey,
    expires_at: Instant,
    connectors: Vec<AppInfo>,
}
```

### 关键流程

#### 1. 连接器发现流程
```rust
list_accessible_connectors_from_mcp_tools_with_options_and_status
├── 检查 Apps 功能是否启用 (config.features.apps_enabled_for_auth)
├── 尝试读取缓存 (read_cached_accessible_connectors)
├── 初始化 MCP 连接管理器 (McpConnectionManager::new)
├── 可选：强制刷新工具缓存 (hard_refresh_codex_apps_tools_cache)
├── 等待 codex_apps 服务器就绪 (wait_for_server_ready)
├── 从 MCP 工具提取可访问连接器 (accessible_connectors_from_mcp_tools)
├── 应用黑名单过滤 (filter_disallowed_connectors)
├── 写入缓存 (write_cached_accessible_connectors)
└── 返回 AccessibleConnectorsStatus { connectors, codex_apps_ready }
```

#### 2. 工具策略评估流程
```rust
app_tool_policy_from_apps_config
├── 读取用户配置 (read_user_apps_config)
├── 应用 requirements.toml 约束 (apply_requirements_apps_constraints)
├── 确定审批模式（工具级 → 应用级 → 全局默认）
├── 检查应用是否启用
├── 检查工具级启用覆盖
├── 根据注解评估默认启用（destructive_hint / open_world_hint）
└── 返回 AppToolPolicy { enabled, approval }
```

#### 3. 连接器合并流程
```rust
merge_connectors(directory_connectors, accessible_connectors)
├── 将目录连接器标记为 is_accessible = false
├── 将可访问连接器标记为 is_accessible = true
├── 合并元数据（名称、描述、logo、分发渠道等）
├── 合并插件显示名称（去重排序）
├── 生成安装 URL (connector_install_url)
└── 排序：可访问优先，然后按名称、ID 排序
```

### 黑名单常量
```rust
const DISALLOWED_CONNECTOR_IDS: &[&str] = &[
    "asdk_app_6938a94a61d881918ef32cb999ff937c",
    "connector_2b0a9009c9c64bf9933a3dae3f2b1254",
    // ... 更多内部连接器
];
const DISALLOWED_CONNECTOR_PREFIX: &str = "connector_openai_";
```

---

## 关键代码路径与文件引用

### 核心文件
| 文件 | 说明 |
|------|------|
| `codex-rs/core/src/connectors.rs` | 本文件，连接器管理核心实现 |
| `codex-rs/core/src/connectors_tests.rs` | 单元测试 |
| `codex-rs/connectors/src/lib.rs` | 连接器目录 API 客户端 |
| `codex-rs/chatgpt/src/connectors.rs` | ChatGPT 特定的连接器逻辑 |

### 依赖类型定义
| 文件 | 类型 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | `AppInfo`, `AppToolApproval` |
| `codex-rs/core/src/config/types.rs` | `AppsConfigToml`, `AppConfig`, `AppToolConfig` |
| `codex-rs/core/src/config_loader.rs` | `AppsRequirementsToml` |

### 调用方
| 文件 | 用途 |
|------|------|
| `codex-rs/core/src/mcp_tool_call.rs` | 工具调用前检查策略 |
| `codex-rs/core/src/tools/handlers/tool_suggest.rs` | 工具推荐 |
| `codex-rs/tui/src/chatwidget.rs` | TUI 应用列表展示 |
| `codex-rs/app-server/src/codex_message_processor.rs` | App-server 应用列表 API |

---

## 依赖与外部交互

### 外部 crate 依赖
- `codex_connectors`：目录 API 客户端和共享缓存 TTL
- `codex_app_server_protocol`：`AppInfo`, `AppBranding`, `AppMetadata` 等类型
- `codex_protocol`：`SandboxPolicy`
- `rmcp::model::ToolAnnotations`：工具注解（destructive_hint, open_world_hint）

### 内部模块依赖
- `crate::config::Config`：配置访问
- `crate::mcp_connection_manager::McpConnectionManager`：MCP 连接管理
- `crate::mcp::CODEX_APPS_MCP_SERVER_NAME`：`codex_apps` 服务器名称常量
- `crate::plugins::PluginsManager`：插件管理
- `crate::AuthManager`：认证管理

### 外部 API 交互
- **ChatGPT 目录 API**：`GET /connectors/directory/list`
- **ChatGPT Workspace API**：`GET /connectors/directory/list_workspace`（仅工作区账户）

---

## 风险、边界与改进建议

### 已知风险

1. **缓存一致性风险**
   - 使用全局静态缓存（`ACCESSIBLE_CONNECTORS_CACHE`），在并发环境下可能存在竞态条件
   - 缓存 TTL 为1小时，用户授权状态变更后可能延迟感知

2. **MCP 服务器就绪超时**
   - 空工具列表时等待 codex_apps 就绪最多30秒（`CONNECTORS_READY_TIMEOUT_ON_EMPTY_TOOLS`）
   - 超时后返回空列表，可能影响用户体验

3. **硬编码黑名单**
   - `DISALLOWED_CONNECTOR_IDS` 和 `DISALLOWED_CONNECTOR_PREFIX` 硬编码在代码中
   - 需要发版才能更新黑名单

### 边界情况

1. **多账户场景**
   - 缓存键包含账户信息，切换账户时缓存隔离正确

2. **工作区账户**
   - 工作区账户额外获取 workspace 目录，可能包含私有连接器

3. **Requirements.toml 约束**
   - 云端或本地 requirements 可以强制禁用特定应用，优先级高于用户配置

### 改进建议

1. **配置化黑名单**
   - 将连接器黑名单移至配置文件或远程配置，支持动态更新

2. **缓存失效机制**
   - 添加主动缓存失效接口，在授权状态变更时立即刷新

3. **降级策略**
   - 目录 API 失败时，应仅返回可访问连接器而非空列表

4. **可观测性增强**
   - 添加更多指标：缓存命中率、API 延迟、连接器数量分布

5. **并发优化**
   - 考虑使用 `tokio::sync::RwLock` 替代 `std::sync::Mutex` 减少阻塞
