# 研究文档：codex-rs/core/src/mcp

## 目录
- [场景与职责](#场景与职责)
- [功能点目的](#功能点目的)
- [具体技术实现](#具体技术实现)
- [关键代码路径与文件引用](#关键代码路径与文件引用)
- [依赖与外部交互](#依赖与外部交互)
- [风险、边界与改进建议](#风险边界与改进建议)

---

## 场景与职责

### 核心定位
`codex-rs/core/src/mcp` 目录实现了 **Model Context Protocol (MCP)** 的客户端管理功能。MCP 是 OpenAI 推出的开放协议，用于标准化 AI 模型与外部工具、数据源之间的交互。该模块在 Codex 项目中充当** MCP 客户端管理器**的角色，负责：

1. **MCP 服务器生命周期管理**：连接、初始化、监控多个 MCP 服务器
2. **工具聚合与分发**：从多个 MCP 服务器收集工具，统一暴露给 AI 模型
3. **认证与授权**：处理 MCP 服务器的 OAuth 认证流程
4. **Skill 依赖管理**：自动检测和安装 Skill 所需的 MCP 依赖
5. **Codex Apps 集成**：特殊处理内置的 `codex_apps` MCP 服务器（用于连接 OpenAI 官方应用）

### 使用场景
- **本地开发**：通过 stdio 传输连接本地 MCP 服务器（如文件系统、数据库工具）
- **云端服务**：通过 Streamable HTTP 传输连接远程 MCP 服务（如 GitHub、Google Drive 连接器）
- **插件扩展**：通过 Plugin 系统动态注入 MCP 服务器配置
- **Skill 执行**：当用户使用某个 Skill 时，自动安装其声明的 MCP 依赖

---

## 功能点目的

### 1. MCP 服务器配置管理 (`mod.rs`)
| 功能 | 目的 |
|------|------|
| `McpManager` | 提供配置服务器和有效服务器的查询接口 |
| `configured_mcp_servers` | 合并用户配置和插件提供的 MCP 服务器 |
| `effective_mcp_servers` | 在配置基础上动态添加/移除 `codex_apps` 服务器 |
| `with_codex_apps_mcp` | 根据功能开关和认证状态控制 `codex_apps` 的启用 |
| `collect_mcp_snapshot` | 收集所有可用 MCP 工具、资源、资源模板的快照 |

### 2. 工具命名与分组 (`mod.rs`)
| 功能 | 目的 |
|------|------|
| `split_qualified_tool_name` | 解析完全限定工具名 `mcp__server__tool` |
| `group_tools_by_server` | 按服务器分组工具，便于管理和调用 |
| `ToolPluginProvenance` | 追踪工具来源（哪个插件/连接器提供） |

### 3. 认证管理 (`auth.rs`)
| 功能 | 目的 |
|------|------|
| `oauth_login_support` | 检测 MCP 服务器是否支持 OAuth 登录 |
| `discover_supported_scopes` | 自动发现服务器支持的 OAuth scopes |
| `resolve_oauth_scopes` | 按优先级解析 scopes（显式 > 配置 > 发现 > 空） |
| `compute_auth_statuses` | 计算所有服务器的认证状态 |
| `McpAuthStatusEntry` | 记录服务器认证状态条目 |

### 4. Skill MCP 依赖管理 (`skill_dependencies.rs`)
| 功能 | 目的 |
|------|------|
| `maybe_prompt_and_install_mcp_dependencies` | 检测缺失依赖并提示用户安装 |
| `collect_missing_mcp_dependencies` | 收集 Skill 声明但未安装的 MCP 依赖 |
| `maybe_install_mcp_dependencies` | 自动安装缺失的 MCP 服务器到全局配置 |
| `canonical_mcp_server_key` | 生成规范化的 MCP 服务器标识键 |
| `mcp_dependency_to_server_config` | 将 Skill 依赖转换为服务器配置 |

---

## 具体技术实现

### 1. 关键数据结构

#### MCP 服务器配置 (`McpServerConfig`)
```rust
// 位于 codex-rs/core/src/config/types.rs
pub struct McpServerConfig {
    pub transport: McpServerTransportConfig,
    pub enabled: bool,
    pub required: bool,
    pub disabled_reason: Option<McpServerDisabledReason>,
    pub startup_timeout_sec: Option<Duration>,
    pub tool_timeout_sec: Option<Duration>,
    pub enabled_tools: Option<Vec<String>>,   // 工具白名单
    pub disabled_tools: Option<Vec<String>>,  // 工具黑名单
    pub scopes: Option<Vec<String>>,          // OAuth scopes
    pub oauth_resource: Option<String>,       // RFC 8707 resource
}
```

#### 传输配置枚举
```rust
pub enum McpServerTransportConfig {
    Stdio { command, args, env, env_vars, cwd },
    StreamableHttp { url, bearer_token_env_var, http_headers, env_http_headers },
}
```

#### 工具信息 (`ToolInfo` - 位于 `mcp_connection_manager.rs`)
```rust
pub(crate) struct ToolInfo {
    pub(crate) server_name: String,
    pub(crate) tool_name: String,
    pub(crate) tool_namespace: String,
    pub(crate) tool: Tool,                    // rmcp::model::Tool
    pub(crate) connector_id: Option<String>,
    pub(crate) connector_name: Option<String>,
    pub(crate) plugin_display_names: Vec<String>,
    pub(crate) connector_description: Option<String>,
}
```

### 2. 关键流程

#### 2.1 MCP 快照收集流程 (`collect_mcp_snapshot`)
```
1. 获取认证信息 (AuthManager)
2. 创建 McpManager 实例
3. 获取有效服务器列表 (effective_servers)
4. 计算各服务器认证状态 (compute_auth_statuses)
5. 创建 McpConnectionManager 实例
6. 并行收集：
   - list_all_tools()         → 所有工具
   - list_all_resources()     → 所有资源
   - list_all_resource_templates() → 所有资源模板
7. 序列化并过滤结果
8. 返回 McpListToolsResponseEvent
```

#### 2.2 Skill MCP 依赖安装流程
```
1. 检查是否为一手客户端 (is_first_party_originator)
2. 检查功能开关 (Feature::SkillMcpDependencyInstall)
3. 获取已配置服务器列表
4. 收集缺失依赖 (collect_missing_mcp_dependencies)
5. 过滤已提示过的依赖
6. 提示用户确认安装 (should_install_mcp_dependencies)
7. 加载全局 MCP 配置
8. 添加缺失服务器到配置
9. 执行 OAuth 登录 (如需要)
10. 刷新 MCP 服务器连接
```

#### 2.3 OAuth 认证流程 (`auth.rs`)
```
1. 检测 OAuth 支持 (oauth_login_support)
   - 调用 discover_streamable_http_oauth()
   - 获取授权端点和 scopes
2. 解析 scopes 优先级
   - 显式 scopes > 配置 scopes > 发现 scopes > 空
3. 执行登录 (perform_oauth_login)
4. 错误处理：
   - 如果是 discovered scopes 被 provider 拒绝，
     重试不带 scopes
```

### 3. 工具命名规范

#### 完全限定工具名格式
```
mcp__<server_name>__<tool_name>
```
- 前缀：`mcp`
- 分隔符：`__` (双下划线)
- 示例：`mcp__github__create_issue`

#### 特殊处理：Codex Apps
对于 `codex_apps` 服务器（OpenAI 官方应用），工具命名采用不同策略：
```
<tool_namespace><tool_name>
```
- 工具名规范化：去除 connector 前缀
- 命名空间：`mcp__codex_apps__<connector_name>`

### 4. 工具过滤器 (`ToolFilter`)
```rust
pub(crate) struct ToolFilter {
    enabled: Option<HashSet<String>>,   // 白名单
    disabled: HashSet<String>,          // 黑名单
}

impl ToolFilter {
    fn allows(&self, tool_name: &str) -> bool {
        // 1. 检查白名单（如设置）
        // 2. 检查黑名单
    }
}
```

---

## 关键代码路径与文件引用

### 本目录文件

| 文件 | 职责 | 关键导出 |
|------|------|----------|
| `mod.rs` | 模块入口，MCP 配置管理 | `McpManager`, `ToolPluginProvenance`, `collect_mcp_snapshot` |
| `auth.rs` | OAuth 认证管理 | `McpOAuthLoginConfig`, `compute_auth_statuses`, `resolve_oauth_scopes` |
| `skill_dependencies.rs` | Skill MCP 依赖处理 | `maybe_prompt_and_install_mcp_dependencies`, `collect_missing_mcp_dependencies` |
| `mod_tests.rs` | 模块单元测试 | - |
| `skill_dependencies_tests.rs` | Skill 依赖测试 | - |

### 核心依赖文件

| 文件 | 职责 | 与本模块关系 |
|------|------|-------------|
| `mcp_connection_manager.rs` | MCP 连接生命周期管理 | 被 `collect_mcp_snapshot` 调用，管理实际连接 |
| `config/types.rs` | MCP 配置类型定义 | `McpServerConfig`, `McpServerTransportConfig` 定义 |
| `plugins/manager.rs` | 插件管理 | 提供 `PluginsManager` 获取插件 MCP 配置 |
| `skills/model.rs` | Skill 数据模型 | `SkillToolDependency` 定义 |

### 调用方文件

| 文件 | 调用点 | 用途 |
|------|--------|------|
| `codex.rs` | `McpManager::new`, `maybe_prompt_and_install_mcp_dependencies` | 初始化 MCP 管理器，处理 Skill 依赖 |
| `connectors.rs` | `McpManager::effective_servers` | 获取连接器配置 |
| `state/service.rs` | `collect_mcp_snapshot` | 收集 MCP 快照供前端展示 |
| `tools/router.rs` | `split_qualified_tool_name` | 解析工具调用 |
| `tools/handlers/mcp_resource.rs` | 资源相关操作 | 处理 MCP 资源读取 |

---

## 依赖与外部交互

### 内部 Crate 依赖

```
codex-rs/core/src/mcp
├── codex_protocol          # 协议类型 (McpListToolsResponseEvent, Tool, Resource)
├── codex_rmcp_client       # MCP 客户端实现 (RmcpClient, perform_oauth_login)
├── codex_config            # 配置管理 (Constrained)
└── crate::plugins          # 插件管理 (PluginsManager, PluginCapabilitySummary)
    └── crate::skills       # Skill 管理 (SkillMetadata, SkillToolDependency)
        └── crate::config   # 配置类型 (McpServerConfig)
```

### 外部协议依赖

| 协议/规范 | 用途 |
|-----------|------|
| MCP 2025-06-18 | Model Context Protocol 规范 |
| OAuth 2.0 | MCP 服务器认证 |
| RFC 8707 | Resource Indicators for OAuth 2.0 |

### 环境变量

| 变量 | 用途 |
|------|------|
| `CODEX_CONNECTORS_TOKEN` | Codex Apps MCP 服务器认证令牌 |
| `CHATGPT_BASE_URL` | 决定 `codex_apps` MCP URL |

---

## 风险、边界与改进建议

### 已知风险

1. **认证状态竞争条件**
   - 风险：OAuth 认证状态可能在请求过程中变化
   - 位置：`auth.rs` 的 `compute_auth_statuses`
   - 缓解：状态计算后缓存，定期刷新

2. **工具名冲突**
   - 风险：不同服务器的工具可能产生相同限定名
   - 位置：`mcp_connection_manager.rs` 的 `qualify_tools`
   - 缓解：使用 SHA1 哈希去重，但可能导致工具名不可读

3. **MCP 服务器启动超时**
   - 风险：慢速 MCP 服务器可能导致启动超时
   - 配置：`startup_timeout_sec` (默认 10s)
   - 缓解：用户可配置更长的超时

4. **Skill 依赖安装失败**
   - 风险：自动安装 MCP 依赖时可能失败（OAuth 拒绝、网络问题）
   - 位置：`skill_dependencies.rs`
   - 缓解：记录警告，允许用户手动重试

### 边界条件

1. **服务器名称限制**
   - 必须匹配正则：`^[a-zA-Z0-9_-]+$`
   - 验证位置：`mcp_connection_manager.rs` 的 `validate_mcp_server_name`

2. **工具名长度限制**
   - 最大 64 字符（Responses API 要求）
   - 超长时使用 SHA1 截断

3. **Codex Apps 缓存**
   - 缓存位置：`~/.codex/cache/codex_apps_tools/<hash>.json`
   - 缓存键：账户 ID + ChatGPT 用户 ID + 是否工作区账户

4. **Scope 解析优先级**
   ```
   explicit_scopes > configured_scopes > discovered_scopes > empty
   ```

### 改进建议

1. **增强错误处理**
   - 当前：OAuth 错误仅记录警告
   - 建议：向用户展示更友好的错误提示，提供重试机制

2. **工具名可读性**
   - 当前：冲突时使用 SHA1 哈希，难以阅读
   - 建议：使用数字后缀或服务器前缀保持可读性

3. **MCP 服务器健康检查**
   - 当前：仅在启动时检查
   - 建议：定期心跳检测，自动重连失败的服务器

4. **依赖安装原子性**
   - 当前：部分安装失败可能导致配置不一致
   - 建议：使用事务性配置更新，失败时回滚

5. **缓存失效策略**
   - 当前：Codex Apps 工具缓存无显式失效机制
   - 建议：添加 TTL 或手动刷新接口

6. **并发优化**
   - 当前：`collect_mcp_snapshot` 串行收集各服务器工具
   - 建议：并行化工具收集，减少启动延迟

---

## 附录：关键常量

```rust
// mod.rs
const MCP_TOOL_NAME_PREFIX: &str = "mcp";
const MCP_TOOL_NAME_DELIMITER: &str = "__";
pub(crate) const CODEX_APPS_MCP_SERVER_NAME: &str = "codex_apps";
const CODEX_CONNECTORS_TOKEN_ENV_VAR: &str = "CODEX_CONNECTORS_TOKEN";

// mcp_connection_manager.rs
const MCP_TOOL_NAME_DELIMITER: &str = "__";
const MAX_TOOL_NAME_LENGTH: usize = 64;
pub const DEFAULT_STARTUP_TIMEOUT: Duration = Duration::from_secs(10);
const DEFAULT_TOOL_TIMEOUT: Duration = Duration::from_secs(120);
const CODEX_APPS_TOOLS_CACHE_SCHEMA_VERSION: u8 = 1;
const CODEX_APPS_TOOLS_CACHE_DIR: &str = "cache/codex_apps_tools";
```

---

*研究完成时间：2026-03-21*
*研究范围：codex-rs/core/src/mcp 目录及其直接依赖*
