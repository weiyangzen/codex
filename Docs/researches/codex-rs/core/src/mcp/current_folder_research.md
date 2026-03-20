# DIR codex-rs/core/src/mcp 研究文档

## 概述

`codex-rs/core/src/mcp` 目录实现了 **Model Context Protocol (MCP)** 服务器的管理功能。MCP 是 OpenAI 推出的协议，用于标准化 AI 助手与外部工具、数据源之间的交互。本模块负责 MCP 服务器的配置管理、连接管理、认证处理以及 Skill 依赖的自动安装。

---

## 场景与职责

### 核心场景

1. **MCP 服务器生命周期管理**
   - 管理用户配置的 MCP 服务器（通过 `config.toml`）
   - 管理插件提供的 MCP 服务器
   - 管理内置的 Codex Apps MCP 服务器（当启用 Apps 功能时）

2. **工具发现与聚合**
   - 从所有配置的 MCP 服务器收集可用工具
   - 将工具名称转换为符合 OpenAI Responses API 格式的限定名（`mcp__<server>__<tool>`）
   - 处理工具名称冲突和长度限制

3. **认证管理**
   - 支持 Streamable HTTP 传输的 OAuth 认证
   - 支持通过环境变量传递 Bearer Token
   - 管理认证状态（已认证、未认证、不支持）

4. **Skill MCP 依赖自动安装**
   - 检测 Skill 声明的 MCP 工具依赖
   - 提示用户安装缺失的 MCP 服务器
   - 自动配置并持久化到全局配置

### 职责边界

| 模块 | 职责 |
|------|------|
| `mod.rs` | 核心管理逻辑、服务器配置合并、工具快照收集 |
| `auth.rs` | OAuth 认证流程、认证状态计算、Scope 解析 |
| `skill_dependencies.rs` | Skill MCP 依赖的检测、提示、安装 |
| `mcp_connection_manager.rs` | 实际的 MCP 连接管理（在父目录） |

---

## 功能点目的

### 1. McpManager - 中央管理器

```rust
pub struct McpManager {
    plugins_manager: Arc<PluginsManager>,
}
```

**目的**：提供统一的 MCP 服务器管理接口，整合用户配置、插件配置和内置 Codex Apps。

**关键方法**：
- `configured_servers()` - 获取所有配置的 MCP 服务器（用户配置 + 插件配置）
- `effective_servers()` - 获取实际生效的服务器（包含 Codex Apps，如果启用）
- `tool_plugin_provenance()` - 追踪工具来源（哪个插件提供了哪个 MCP 服务器）

### 2. 服务器配置合并策略

**优先级（从高到低）**：
1. 用户配置（`config.toml` 中的 `mcpServers`）
2. 插件配置（`.mcp.json`）
3. 内置 Codex Apps（当 `features.apps = true` 且用户已认证）

**关键函数**：
```rust
fn configured_mcp_servers(...) -> HashMap<String, McpServerConfig>
fn effective_mcp_servers(...) -> HashMap<String, McpServerConfig>
fn with_codex_apps_mcp(...) -> HashMap<String, McpServerConfig>
```

### 3. 工具名称处理

**限定名格式**：`mcp__<server_name>__<tool_name>`

**处理流程**：
1. 原始工具名 → 添加服务器前缀
2. 清理非法字符（只保留 `a-zA-Z0-9_-`）
3. 处理长度超过 64 字符的情况（使用 SHA1 截断）
4. 处理名称冲突（基于原始名的确定性哈希）

**关键函数**：
```rust
pub fn split_qualified_tool_name(qualified_name: &str) -> Option<(String, String)>
pub fn group_tools_by_server(...) -> HashMap<String, HashMap<String, Tool>>
```

### 4. 认证系统

**支持的方式**：
- **Bearer Token**: 通过 `CODEX_CONNECTORS_TOKEN` 环境变量
- **OAuth 2.0**: 自动发现 OAuth 端点，支持本地回调服务器
- **HTTP Headers**: 直接配置 `Authorization` 和 `ChatGPT-Account-ID`

**关键结构**：
```rust
pub struct McpAuthStatusEntry {
    pub config: McpServerConfig,
    pub auth_status: McpAuthStatus,  // Authenticated | Unauthenticated | Unsupported
}
```

**Scope 解析优先级**：
1. 显式配置的 scopes
2. 配置文件中配置的 scopes
3. OAuth 发现端点返回的 scopes
4. 空 scopes

### 5. Skill MCP 依赖安装

**流程**：
1. 解析 Skill 的 `SKILLS.md` 中声明的工具依赖
2. 检查依赖是否已安装（通过 canonical key 匹配）
3. 如未安装且用户同意，添加到全局配置
4. 如需认证，自动触发 OAuth 流程
5. 刷新 MCP 服务器连接

**关键函数**：
```rust
pub(crate) async fn maybe_prompt_and_install_mcp_dependencies(...)
pub(crate) async fn maybe_install_mcp_dependencies(...)
pub(crate) fn collect_missing_mcp_dependencies(...) -> HashMap<String, McpServerConfig>
```

---

## 具体技术实现

### 关键数据结构

#### McpServerConfig
```rust
pub struct McpServerConfig {
    pub transport: McpServerTransportConfig,
    pub enabled: bool,
    pub required: bool,
    pub disabled_reason: Option<McpServerDisabledReason>,
    pub startup_timeout_sec: Option<Duration>,
    pub tool_timeout_sec: Option<Duration>,
    pub enabled_tools: Option<Vec<String>>,   // 允许列表
    pub disabled_tools: Option<Vec<String>>,  // 禁止列表
    pub scopes: Option<Vec<String>>,          // OAuth scopes
    pub oauth_resource: Option<String>,       // RFC 8707 resource
}
```

#### McpServerTransportConfig
```rust
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

#### ToolPluginProvenance
```rust
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ToolPluginProvenance {
    plugin_display_names_by_connector_id: HashMap<String, Vec<String>>,
    plugin_display_names_by_mcp_server_name: HashMap<String, Vec<String>>,
}
```

### 关键流程

#### 1. 收集 MCP 快照
```rust
pub async fn collect_mcp_snapshot(config: &Config) -> McpListToolsResponseEvent
```

流程：
1. 初始化 AuthManager 获取认证信息
2. 创建 McpManager 和 PluginsManager
3. 获取 effective_servers（所有生效的 MCP 服务器）
4. 计算每个服务器的认证状态
5. 创建 McpConnectionManager 并连接到所有服务器
6. 并行收集：tools、resources、resource_templates
7. 转换为协议格式并返回

#### 2. OAuth 登录流程
```rust
pub async fn oauth_login_support(transport: &McpServerTransportConfig) -> McpOAuthLoginSupport
```

流程：
1. 检查是否为 Streamable HTTP 传输
2. 检查是否已配置 bearer_token_env_var（如有则跳过 OAuth）
3. 调用 `discover_streamable_http_oauth()` 发现 OAuth 端点
4. 返回支持状态（Supported/Unsupported/Unknown）

#### 3. Skill 依赖安装流程
```rust
async fn maybe_install_mcp_dependencies(...)
```

流程：
1. 检查功能开关 `SkillMcpDependencyInstall`
2. 加载全局 MCP 服务器配置
3. 收集缺失的依赖
4. 写入全局配置（通过 `ConfigEditsBuilder`）
5. 对每个新服务器触发 OAuth 认证（如需要）
6. 刷新 MCP 服务器连接

### 协议与命令

#### MCP 协议版本
- 基于 Model Context Protocol 规范（2025-06-18）
- 支持传输：stdio、streamable-http

#### 工具调用流程
1. 工具名格式：`mcp__<server>__<tool>`
2. 通过 `split_qualified_tool_name()` 解析
3. 路由到对应 MCP 服务器的 `tools/call` 端点
4. 返回 `CallToolResult`

---

## 关键代码路径与文件引用

### 核心文件

| 文件 | 行数 | 职责 |
|------|------|------|
| `mod.rs` | 448 | 主模块，McpManager 实现，配置合并，快照收集 |
| `auth.rs` | 288 | OAuth 认证，认证状态计算，Scope 解析 |
| `skill_dependencies.rs` | 464 | Skill MCP 依赖检测与自动安装 |
| `mod_tests.rs` | 263 | 主模块单元测试 |
| `skill_dependencies_tests.rs` | 107 | 依赖安装模块测试 |

### 关键代码路径

#### 1. 服务器配置加载路径
```
codex.rs:221 -> mcp/mod.rs:182 with_codex_apps_mcp
              -> mcp/mod.rs:238 effective_mcp_servers
              -> mcp/mod.rs:226 configured_mcp_servers
              -> plugins/manager.rs plugins_for_config
```

#### 2. 工具调用路径
```
tools/handlers/mcp.rs -> mcp_tool_call.rs
                     -> mcp_connection_manager.rs::call_tool()
```

#### 3. Skill 依赖安装路径
```
codex.rs:220 -> mcp/skill_dependencies.rs:136 maybe_prompt_and_install_mcp_dependencies
             -> mcp/skill_dependencies.rs:174 maybe_install_mcp_dependencies
             -> mcp/skill_dependencies.rs:349 collect_missing_mcp_dependencies
```

#### 4. 认证状态计算路径
```
mcp/mod.rs:252 collect_mcp_snapshot
       -> mcp/auth.rs:126 compute_auth_statuses
       -> mcp/auth.rs:155 compute_auth_status
       -> codex_rmcp_client::determine_streamable_http_auth_status
```

### 外部依赖

| Crate | 用途 |
|-------|------|
| `codex_rmcp_client` | MCP 客户端实现，OAuth 流程 |
| `rmcp` | MCP 协议模型定义 |
| `codex_protocol` | 内部协议类型（Tool, Resource, CallToolResult） |
| `codex_protocol::protocol::McpAuthStatus` | 认证状态枚举 |

---

## 依赖与外部交互

### 上游依赖（调用本模块）

| 模块 | 用途 |
|------|------|
| `codex.rs` | 主 Codex 逻辑，初始化 McpManager，触发依赖安装 |
| `connectors.rs` | 连接器管理，使用 McpManager 获取服务器列表 |
| `thread_manager.rs` | 线程管理，创建 McpManager 实例 |
| `state/service.rs` | 服务状态，持有 McpManager Arc |
| `tools/handlers/mcp.rs` | MCP 工具调用处理 |
| `tools/handlers/tool_suggest.rs` | 工具建议，使用 CODEX_APPS_MCP_SERVER_NAME |
| `apps/render.rs` | App 渲染，使用 CODEX_APPS_MCP_SERVER_NAME |
| `plugins/injection.rs` | 插件注入，使用 CODEX_APPS_MCP_SERVER_NAME |

### 下游依赖（本模块调用）

| 模块 | 用途 |
|------|------|
| `mcp_connection_manager.rs` | 实际的 MCP 连接管理，工具调用执行 |
| `config/types.rs` | McpServerConfig, McpServerTransportConfig 定义 |
| `config/edit.rs` | ConfigEditsBuilder，用于持久化 MCP 配置 |
| `plugins/manager.rs` | PluginsManager，获取插件提供的 MCP 服务器 |
| `skills/model.rs` | SkillMetadata, SkillToolDependency 定义 |
| `auth.rs` | AuthManager，获取用户认证信息 |
| `features.rs` | Feature 标志，检查 Apps/SkillMcpDependencyInstall 等 |

### 配置交互

**读取**：
- `config.mcp_servers` - 用户配置的 MCP 服务器
- `config.features.apps_enabled_for_auth()` - 是否启用 Apps
- `config.chatgpt_base_url` - Codex Apps URL 基础

**写入**：
- `ConfigEditsBuilder::replace_mcp_servers()` - 持久化 Skill 依赖的 MCP 服务器

---

## 风险、边界与改进建议

### 已知风险

1. **OAuth 认证失败处理**
   - 当前对 discovered scopes 的 provider 错误会重试无 scopes 的认证
   - 但其他类型的 OAuth 错误仅记录警告，可能导致工具调用时认证失败

2. **工具名称冲突**
   - 64 字符长度限制可能导致不同工具被截断为相同名称
   - 虽然使用 SHA1 哈希处理，但仍有极小概率冲突

3. **MCP 服务器启动超时**
   - 默认 10 秒启动超时，某些慢启动服务器可能失败
   - 用户可通过 `startup_timeout_sec` 配置调整

4. **Skill 依赖重复提示**
   - 使用 canonical key 去重，但不同 Skill 可能声明相同 MCP 的不同配置
   - 当前实现会跳过已提示的 key，但配置差异可能导致困惑

### 边界条件

1. **Codex Apps 启用条件**
   - 需要 `features.apps = true`
   - 需要用户已认证（`auth.is_some_and(CodexAuth::is_chatgpt_auth)`）
   - 服务器名固定为 `codex_apps`

2. **Transport 互斥**
   - Stdio 和 Streamable HTTP 配置互斥
   - 反序列化时会验证字段冲突

3. **Scope 解析优先级**
   - 显式 > 配置 > 发现 > 空
   - 空 scopes 可能导致某些 OAuth 服务器拒绝

### 改进建议

1. **增强错误处理**
   - 为 OAuth 失败提供更详细的用户指导
   - 添加 MCP 服务器健康检查机制

2. **优化工具名称生成**
   - 考虑使用更短的哈希算法（如 xxhash）
   - 添加工具名称冲突的显式警告

3. **改进 Skill 依赖管理**
   - 支持 MCP 服务器版本锁定
   - 添加依赖冲突检测（不同 Skill 要求冲突配置）

4. **性能优化**
   - MCP 快照收集可添加缓存机制
   - 并行初始化多个 MCP 服务器

5. **可观测性**
   - 添加 MCP 服务器连接状态的指标
   - 记录工具调用延迟和成功率

---

## 附录：常量定义

```rust
const MCP_TOOL_NAME_PREFIX: &str = "mcp";
const MCP_TOOL_NAME_DELIMITER: &str = "__";
pub(crate) const CODEX_APPS_MCP_SERVER_NAME: &str = "codex_apps";
const CODEX_CONNECTORS_TOKEN_ENV_VAR: &str = "CODEX_CONNECTORS_TOKEN";
```

## 附录：Feature 标志

| Feature | 默认值 | 说明 |
|---------|--------|------|
| `Apps` | false | 启用 Codex Apps MCP 服务器 |
| `SkillMcpDependencyInstall` | true | 允许自动安装 Skill MCP 依赖 |
| `Plugins` | false | 启用插件系统 |
