# MCP 模块研究文档

## 概述

`codex-rs/core/src/mcp` 模块是 Codex 项目中负责 **Model Context Protocol (MCP)** 服务器管理的核心组件。MCP 是 OpenAI 推出的开放协议，用于标准化 AI 模型与外部工具、数据源之间的交互。本模块实现了 MCP 服务器的配置管理、连接生命周期管理、认证授权、以及 Skill 依赖的自动安装等功能。

---

## 场景与职责

### 核心职责

1. **MCP 服务器配置管理**
   - 管理用户配置的 MCP 服务器（通过 `config.toml`）
   - 整合 Plugin 提供的 MCP 服务器配置
   - 处理内置的 `codex_apps` MCP 服务器（用于连接 OpenAI 应用生态）

2. **MCP 连接生命周期管理**
   - 创建和管理与 MCP 服务器的连接（通过 `McpConnectionManager`）
   - 支持多种传输协议：Stdio 和 Streamable HTTP
   - 处理连接初始化、工具列表获取、资源发现

3. **认证与授权**
   - OAuth 2.0 登录流程支持
   - Bearer Token 管理
   - 认证状态计算和缓存

4. **Skill MCP 依赖管理**
   - 自动检测 Skill 声明的 MCP 依赖
   - 提示用户安装缺失的 MCP 服务器
   - 自动配置和 OAuth 登录

5. **工具命名与解析**
   - 定义工具命名规范（`mcp__<server>__<tool>`）
   - 处理工具名称冲突和规范化
   - 支持 Codex Apps 工具的特殊命名处理

### 使用场景

| 场景 | 说明 |
|------|------|
| 用户配置自定义 MCP 服务器 | 通过 `config.toml` 配置第三方 MCP 服务器 |
| Plugin 提供 MCP 能力 | Plugin 通过 `.mcp.json` 声明 MCP 服务器 |
| Skill 依赖 MCP 工具 | Skill 声明对特定 MCP 服务器的依赖，系统自动安装 |
| Codex Apps 集成 | 连接 OpenAI 应用生态（如 Gmail、GitHub 等）|
| 工具调用路由 | 将模型请求路由到正确的 MCP 服务器和工具 |

---

## 功能点目的

### 1. 服务器配置管理 (`mod.rs`)

**目的**：统一管理来自多个来源的 MCP 服务器配置

**关键功能**：
- `configured_mcp_servers()`：合并用户配置和 Plugin 提供的 MCP 服务器
- `effective_mcp_servers()`：在配置基础上添加/移除 `codex_apps` 服务器
- `with_codex_apps_mcp()`：根据功能开关动态启用 `codex_apps`

**配置优先级**：
1. 用户配置（`config.toml` 中的 `[mcp_servers]`）
2. Plugin 配置（`.mcp.json`）
3. 内置 `codex_apps`（当 `features.apps` 启用时）

### 2. 认证管理 (`auth.rs`)

**目的**：处理 MCP 服务器的 OAuth 认证流程

**关键功能**：
- `oauth_login_support()`：检测服务器是否支持 OAuth
- `discover_supported_scopes()`：发现服务器支持的 OAuth scopes
- `resolve_oauth_scopes()`：解析最终的 scopes（显式 > 配置 > 发现）
- `compute_auth_statuses()`：计算所有服务器的认证状态

**认证状态**：
```rust
pub enum McpAuthStatus {
    LoggedIn,       // 已登录
    LoggedOut,      // 未登录
    Unsupported,    // 不支持认证
}
```

### 3. Skill 依赖管理 (`skill_dependencies.rs`)

**目的**：自动处理 Skill 声明的 MCP 依赖

**关键功能**：
- `maybe_prompt_and_install_mcp_dependencies()`：检测并提示安装缺失依赖
- `collect_missing_mcp_dependencies()`：收集缺失的 MCP 依赖
- `maybe_install_mcp_dependencies()`：执行安装和 OAuth 登录

**流程**：
1. 解析 Skill 的 `dependencies.tools` 中类型为 `mcp` 的项
2. 检查是否已安装（通过 canonical key 匹配）
3. 提示用户是否安装（非全访问模式下）
4. 添加配置到全局 `config.toml`
5. 执行 OAuth 登录（如需要）
6. 刷新 MCP 服务器连接

### 4. 工具命名与解析 (`mod.rs`)

**目的**：定义标准化的工具命名规范，支持工具路由

**命名格式**：`mcp__<server_name>__<tool_name>`

**关键函数**：
- `split_qualified_tool_name()`：解析完整工具名
- `group_tools_by_server()`：按服务器分组工具

**Codex Apps 特殊处理**：
- 工具名规范化（去除 connector 前缀）
- Namespace 特殊处理（`mcp__codex_apps__<connector>`）

---

## 具体技术实现

### 关键数据结构

#### 1. MCP 服务器配置 (`McpServerConfig`)

```rust
// 位置: codex-rs/core/src/config/types.rs:67-111
pub struct McpServerConfig {
    pub transport: McpServerTransportConfig,
    pub enabled: bool,
    pub required: bool,
    pub disabled_reason: Option<McpServerDisabledReason>,
    pub startup_timeout_sec: Option<Duration>,
    pub tool_timeout_sec: Option<Duration>,
    pub enabled_tools: Option<Vec<String>>,   // 白名单
    pub disabled_tools: Option<Vec<String>>,  // 黑名单
    pub scopes: Option<Vec<String>>,          // OAuth scopes
    pub oauth_resource: Option<String>,       // RFC 8707 resource
}
```

#### 2. 传输配置 (`McpServerTransportConfig`)

```rust
// 位置: codex-rs/core/src/config/types.rs:247-277
pub enum McpServerTransportConfig {
    Stdio {
        command: String,
        args: Vec<String>,
        env: Option<HashMap<String, String>>,
        env_vars: Vec<String>,
        cwd: Option<PathBuf>,
    },
    StreamableHttp {
        url: String,
        bearer_token_env_var: Option<String>,
        http_headers: Option<HashMap<String, String>>,
        env_http_headers: Option<HashMap<String, String>>,
    },
}
```

#### 3. 工具信息 (`ToolInfo`)

```rust
// 位置: codex-rs/core/src/mcp_connection_manager.rs:201-212
pub(crate) struct ToolInfo {
    pub(crate) server_name: String,
    pub(crate) tool_name: String,
    pub(crate) tool_namespace: String,
    pub(crate) tool: Tool,                    // rmcp Tool
    pub(crate) connector_id: Option<String>,
    pub(crate) connector_name: Option<String>,
    pub(crate) plugin_display_names: Vec<String>,
    pub(crate) connector_description: Option<String>,
}
```

#### 4. 工具来源追踪 (`ToolPluginProvenance`)

```rust
// 位置: codex-rs/core/src/mcp/mod.rs:36-92
pub struct ToolPluginProvenance {
    plugin_display_names_by_connector_id: HashMap<String, Vec<String>>,
    plugin_display_names_by_mcp_server_name: HashMap<String, Vec<String>>,
}
```

### 关键流程

#### 1. MCP 服务器初始化流程

```
McpConnectionManager::new()
├── 为每个启用的服务器创建 AsyncManagedClient
│   └── AsyncManagedClient::new()
│       ├── 加载启动缓存（如果是 codex_apps）
│       └── 启动异步初始化任务
│           ├── make_rmcp_client()
│           │   ├── Stdio: RmcpClient::new_stdio_client()
│           │   └── StreamableHttp: RmcpClient::new_streamable_http_client()
│           └── start_server_task()
│               ├── client.initialize() - MCP 协议握手
│               ├── list_tools_for_client_uncached() - 获取工具列表
│               └── write_cached_codex_apps_tools_if_needed() - 缓存工具
└── 启动监控任务，等待所有服务器就绪
    └── 发送 McpStartupCompleteEvent
```

#### 2. Skill MCP 依赖安装流程

```
maybe_prompt_and_install_mcp_dependencies()
├── 检查：是否第一方客户端、功能开关、是否有提及的 Skill
├── 获取已配置的 MCP 服务器
├── collect_missing_mcp_dependencies() - 收集缺失依赖
│   ├── 遍历 Skill 的 dependencies.tools
│   ├── 筛选类型为 "mcp" 的依赖
│   ├── 生成 canonical key（mcp__<transport>__<identifier>）
│   └── 检查是否已安装
├── filter_prompted_mcp_dependencies() - 过滤已提示过的
├── should_install_mcp_dependencies() - 提示用户（非全访问模式）
└── maybe_install_mcp_dependencies()
    ├── 加载全局 MCP 配置
    ├── 添加缺失的服务器配置
    ├── ConfigEditsBuilder::replace_mcp_servers() - 持久化配置
    ├── 对每个需要 OAuth 的服务器执行登录
    │   └── perform_oauth_login()
    └── refresh_mcp_servers_now() - 刷新连接
```

#### 3. 工具调用流程

```
McpHandler::handle() (tools/handlers/mcp.rs)
└── handle_mcp_tool_call() (mcp_tool_call.rs)
    ├── 解析服务器名和工具名
    ├── 获取 McpConnectionManager
    ├── mcp_connection_manager.call_tool()
    │   ├── client_by_name() - 获取 ManagedClient
    │   ├── tool_filter.allows() - 检查工具是否被允许
    │   └── client.call_tool() - 调用 rmcp 客户端
    └── 处理结果并返回
```

### 协议与规范

#### 1. MCP 协议版本

- 使用 **MCP 2025-06-18** 协议版本
- 通过 `rmcp` crate 实现协议层

#### 2. 工具命名规范

- 分隔符：`__`（双下划线）
- 前缀：`mcp`
- 格式：`mcp__<server_name>__<tool_name>`
- 限制：符合 OpenAI Responses API 的 `^[a-zA-Z0-9_-]+$` 模式

#### 3. OAuth 2.0 支持

- 支持 PKCE 扩展
- 支持 RFC 8707 Resource Indicators
- 本地回调服务器（端口可配置）

#### 4. 沙箱状态通知

- 自定义 MCP 方法：`codex/sandbox-state/update`
- 能力声明：`codex/sandbox-state`
- 通知内容：`SandboxState` 结构体

---

## 关键代码路径与文件引用

### 本模块文件

| 文件 | 职责 | 关键导出 |
|------|------|----------|
| `mod.rs` | 模块入口，服务器配置管理，工具命名 | `McpManager`, `ToolPluginProvenance`, `collect_mcp_snapshot` |
| `auth.rs` | OAuth 认证和认证状态管理 | `compute_auth_statuses`, `resolve_oauth_scopes` |
| `skill_dependencies.rs` | Skill MCP 依赖自动安装 | `maybe_prompt_and_install_mcp_dependencies` |
| `mod_tests.rs` | 模块单元测试 | - |
| `skill_dependencies_tests.rs` | Skill 依赖测试 | - |

### 相关外部文件

| 文件 | 职责 | 与本模块关系 |
|------|------|-------------|
| `mcp_connection_manager.rs` | MCP 连接生命周期管理 | 被 `mod.rs` 调用创建连接 |
| `config/types.rs` | 配置类型定义 | `McpServerConfig`, `McpServerTransportConfig` |
| `codex.rs` | 核心会话逻辑 | 调用 `maybe_prompt_and_install_mcp_dependencies` |
| `plugins/manager.rs` | Plugin 管理 | 提供 Plugin 的 MCP 服务器配置 |
| `tools/handlers/mcp.rs` | MCP 工具调用处理器 | 使用 MCP 连接执行工具调用 |
| `rmcp-client/src/lib.rs` | MCP 客户端库 | 底层 MCP 协议实现 |

### 关键常量

```rust
// mod.rs
const MCP_TOOL_NAME_PREFIX: &str = "mcp";
const MCP_TOOL_NAME_DELIMITER: &str = "__";
pub(crate) const CODEX_APPS_MCP_SERVER_NAME: &str = "codex_apps";
const CODEX_CONNECTORS_TOKEN_ENV_VAR: &str = "CODEX_CONNECTORS_TOKEN";

// mcp_connection_manager.rs
const MCP_TOOL_NAME_DELIMITER: &str = "__";
const MAX_TOOL_NAME_LENGTH: usize = 64;
pub const MCP_SANDBOX_STATE_CAPABILITY: &str = "codex/sandbox-state";
pub const MCP_SANDBOX_STATE_METHOD: &str = "codex/sandbox-state/update";
```

---

## 依赖与外部交互

### 内部依赖

```
codex-rs/core/src/mcp/
├── codex_protocol::mcp::*          # MCP 协议类型
├── codex_protocol::protocol::*     # 事件和协议类型
├── crate::config::types::*         # 配置类型
├── crate::mcp_connection_manager::* # 连接管理
├── crate::plugins::*               # Plugin 管理
├── crate::AuthManager              # 认证管理
└── crate::skills::*                # Skill 元数据
```

### 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_rmcp_client` | MCP 客户端实现，OAuth 支持 |
| `rmcp` | MCP 协议模型定义 |
| `serde_json` | JSON 序列化 |
| `async_channel` | 异步事件通道 |

### 调用方

| 调用方 | 调用内容 | 目的 |
|--------|----------|------|
| `codex.rs` | `maybe_prompt_and_install_mcp_dependencies` | 处理 Skill MCP 依赖 |
| `mcp_connection_manager.rs` | `CODEX_APPS_MCP_SERVER_NAME` | 识别 codex_apps 服务器 |
| `tools/handlers/mcp.rs` | MCP 工具调用 | 执行 MCP 工具 |
| `cli/src/mcp_cmd.rs` | MCP 命令处理 | CLI MCP 子命令 |
| `app-server` | MCP 相关 API | 提供 MCP 管理能力 |

---

## 风险、边界与改进建议

### 已知风险

1. **OAuth 登录失败处理**
   - 当前实现会在 OAuth 失败时记录警告但继续执行
   - 建议：增加重试机制和更明确的错误提示

2. **工具名称冲突**
   - 使用 SHA1 哈希解决冲突，但可能导致工具名不可读
   - 建议：增加工具名冲突的日志记录和监控

3. **缓存失效**
   - `codex_apps` 工具缓存可能过期，但仅在启动时检查
   - 建议：增加缓存 TTL 或手动刷新机制

4. **并发安全**
   - `ElicitationRequestManager` 使用 `StdMutex` 存储 approval_policy
   - 建议：评估是否需要使用 `tokio::sync::RwLock` 提高并发性

### 边界情况

1. **服务器名称验证**
   - 必须匹配 `^[a-zA-Z0-9_-]+$` 正则
   - 非法名称会导致服务器启动失败

2. **工具过滤优先级**
   - `enabled_tools`（白名单）优先于 `disabled_tools`（黑名单）
   - 空白名单表示允许所有工具（除了黑名单）

3. **OAuth Scope 解析优先级**
   - 显式 scopes > 配置 scopes > 发现 scopes > 空
   - 显式设置空数组会覆盖其他来源

4. **Canonical Key 生成**
   - 用于去重和匹配：`mcp__<transport>__<identifier>`
   - identifier 对于 HTTP 是 URL，对于 Stdio 是 command

### 改进建议

1. **可观测性增强**
   - 增加 MCP 服务器健康检查指标
   - 添加工具调用延迟和成功率监控

2. **配置热更新**
   - 当前 MCP 服务器配置变更需要重启
   - 建议：支持运行时动态添加/移除服务器

3. **依赖版本管理**
   - Skill MCP 依赖目前没有版本概念
   - 建议：增加 MCP 服务器版本兼容性检查

4. **错误处理优化**
   - 区分网络错误、认证错误、配置错误
   - 提供用户友好的错误消息和修复建议

5. **性能优化**
   - `list_all_tools()` 每次都会遍历所有客户端
   - 建议：增加工具列表缓存和增量更新机制

---

## 测试覆盖

### 单元测试

| 测试文件 | 测试内容 |
|----------|----------|
| `mod_tests.rs` | 工具命名解析、分组、Codex Apps URL 生成、Plugin 配置合并 |
| `skill_dependencies_tests.rs` | 缺失依赖检测、canonical key 去重 |
| `auth.rs` (内联) | OAuth scope 解析优先级、重试逻辑 |

### 集成测试

- `mcp_connection_manager_tests.rs`：连接管理器集成测试
- `codex-rs/rmcp-client/tests/`：MCP 客户端协议测试

---

## 总结

`codex-rs/core/src/mcp` 模块是 Codex 与外部工具生态集成的关键桥梁。它通过标准化的 MCP 协议，实现了：

1. **灵活的服务器配置**：支持用户配置、Plugin 提供、内置服务多种来源
2. **完善的认证体系**：OAuth 2.0 + Bearer Token 双轨支持
3. **自动化的依赖管理**：Skill 声明依赖后自动安装和配置
4. **规范化的工具路由**：统一的命名和解析机制

该模块的设计充分考虑了扩展性和可维护性，通过清晰的职责分离（配置、连接、认证、依赖）和完善的错误处理，为 Codex 提供了稳定可靠的 MCP 能力支撑。
