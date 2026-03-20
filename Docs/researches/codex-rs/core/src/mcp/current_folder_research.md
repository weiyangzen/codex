# DIR Research: codex-rs/core/src/mcp

## 概述

`codex-rs/core/src/mcp` 目录实现了 Codex 的 **Model Context Protocol (MCP)** 核心管理功能。MCP 是 OpenAI 推出的标准化协议，用于让 AI 助手与外部工具和服务进行交互。该目录负责 MCP 服务器的配置管理、认证处理、工具聚合以及 Skill 依赖的自动安装。

---

## 场景与职责

### 核心场景

1. **MCP 服务器生命周期管理**
   - 管理用户配置的 MCP 服务器（通过 `config.toml`）
   - 管理插件提供的 MCP 服务器（通过 `.mcp.json`）
   - 管理内置的 Codex Apps MCP 服务器（`codex_apps`）

2. **工具发现与聚合**
   - 从多个 MCP 服务器收集可用工具
   - 为工具生成符合 OpenAI Responses API 规范的限定名（`mcp__{server}__{tool}`）
   - 处理工具名称冲突和规范化

3. **认证与授权**
   - 支持 OAuth 2.0 登录流程
   - 管理 Bearer Token 认证
   - 计算和缓存认证状态

4. **Skill MCP 依赖管理**
   - 自动检测 Skill 声明的 MCP 依赖
   - 提示用户安装缺失的 MCP 服务器
   - 自动配置和安装依赖

### 职责边界

| 组件 | 职责 | 不负责的职责 |
|------|------|-------------|
| `mcp/mod.rs` | 服务器配置聚合、工具快照收集、工具名处理 | 实际工具调用执行 |
| `mcp/auth.rs` | OAuth 发现、认证状态计算、Scope 解析 | 实际 HTTP 请求发送 |
| `mcp/skill_dependencies.rs` | Skill 依赖检测、用户提示、自动安装 | Skill 解析本身 |
| `mcp_connection_manager.rs` | MCP 连接管理、客户端生命周期、elicitation 处理 | 配置管理 |
| `mcp_tool_call.rs` | 实际工具调用执行、审批流程 | 工具发现 |

---

## 功能点目的

### 1. 服务器配置管理 (`mod.rs`)

**目的**：整合来自多个来源的 MCP 服务器配置

**配置来源优先级**（从高到低）：
1. 用户配置（`config.toml` 中的 `mcp_servers`）
2. 插件配置（`.mcp.json`）
3. 内置 Codex Apps（当 `features.apps` 启用时）

**关键函数**：
- `configured_mcp_servers()` - 收集用户配置和插件配置的服务器
- `effective_mcp_servers()` - 添加 Codex Apps 后的最终配置
- `with_codex_apps_mcp()` - 动态添加/移除 Codex Apps 服务器

### 2. 工具名规范化 (`mod.rs`)

**目的**：将 MCP 工具名转换为符合 OpenAI Responses API 规范的格式

**命名规则**：
- 格式：`mcp__{server_name}__{tool_name}`
- 分隔符：`__`（双下划线）
- 限制：仅允许 `a-zA-Z0-9_-`，其他字符替换为 `_`
- 长度限制：64 字符（超长时使用 SHA1 哈希截断）

**示例**：
```
原始: "my-server/my.tool"
规范化: "mcp__my_server__my_tool"
```

### 3. OAuth 认证管理 (`auth.rs`)

**目的**：处理 MCP 服务器的 OAuth 2.0 认证流程

**关键功能**：
- `oauth_login_support()` - 检测服务器是否支持 OAuth
- `discover_streamable_http_oauth()` - 自动发现 OAuth 配置
- `resolve_oauth_scopes()` - 解析请求的权限范围（优先级：显式 > 配置 > 发现）
- `compute_auth_statuses()` - 计算所有服务器的认证状态

**Scope 优先级**：
1. 显式提供的 scopes
2. 配置文件中配置的 scopes
3. 服务器发现的 scopes
4. 空列表（无特殊权限）

### 4. Skill MCP 依赖自动安装 (`skill_dependencies.rs`)

**目的**：当用户使用需要特定 MCP 服务器的 Skill 时，自动提示并安装

**流程**：
1. 检测 Skill 声明的 MCP 依赖（`SkillToolDependency`）
2. 检查哪些依赖尚未安装（使用 canonical key 匹配）
3. 向用户显示安装提示（非全访问模式下）
4. 用户确认后，将配置写入全局 `config.toml`
5. 执行 OAuth 登录（如需要）
6. 刷新 MCP 服务器连接

**Canonical Key 生成**：
```
stdio: mcp__stdio__{command}
streamable_http: mcp__streamable_http__{url}
```

### 5. 工具快照收集 (`mod.rs`)

**目的**：在会话启动时收集所有可用工具的快照

**流程**：
1. 加载认证信息
2. 获取有效的 MCP 服务器配置
3. 创建 `McpConnectionManager`
4. 并行收集：工具列表、资源列表、资源模板列表
5. 转换和过滤工具格式
6. 返回 `McpListToolsResponseEvent`

---

## 具体技术实现

### 关键数据结构

#### `McpServerConfig` (`config/types.rs`)

```rust
pub struct McpServerConfig {
    pub transport: McpServerTransportConfig,  // 传输配置
    pub enabled: bool,                        // 是否启用
    pub required: bool,                       // 是否必需（失败时退出）
    pub disabled_reason: Option<McpServerDisabledReason>,
    pub startup_timeout_sec: Option<Duration>,
    pub tool_timeout_sec: Option<Duration>,
    pub enabled_tools: Option<Vec<String>>,   // 白名单
    pub disabled_tools: Option<Vec<String>>,  // 黑名单
    pub scopes: Option<Vec<String>>,          // OAuth scopes
    pub oauth_resource: Option<String>,       // OAuth 资源参数
}
```

#### `McpServerTransportConfig` (`config/types.rs`)

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

#### `ToolPluginProvenance` (`mod.rs`)

```rust
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ToolPluginProvenance {
    plugin_display_names_by_connector_id: HashMap<String, Vec<String>>,
    plugin_display_names_by_mcp_server_name: HashMap<String, Vec<String>>,
}
```

用于追踪工具来自哪个插件，在工具描述中附加插件来源信息。

### 关键流程

#### 1. 工具名解析流程

```
输入: "mcp__alpha__do_thing"
  ↓
split_qualified_tool_name()
  ↓
前缀检查: "mcp" ✓
服务器名: "alpha"
工具名: "do_thing"
  ↓
输出: ("alpha", "do_thing")
```

#### 2. OAuth 认证状态计算流程

```
compute_auth_statuses(servers)
  ↓
for each server:
  if stdio transport:
    status = Unsupported
  if streamable_http:
    determine_streamable_http_auth_status()
      ↓
    check cached credentials
      ↓
    if expired:
      return LoggedOut
    if valid:
      return LoggedIn
    if no auth required:
      return Unsupported
```

#### 3. Skill MCP 依赖安装流程

```
maybe_prompt_and_install_mcp_dependencies()
  ↓
检查: 是否 first-party originator ✓
检查: SkillMcpDependencyInstall feature 启用 ✓
  ↓
collect_missing_mcp_dependencies()
  - 解析 Skill 依赖
  - 生成 canonical key
  - 对比已安装服务器
  ↓
filter_prompted_mcp_dependencies()
  - 过滤已提示过的依赖
  ↓
should_install_mcp_dependencies()
  - 全访问模式: 自动确认
  - 否则: 显示用户提示
  ↓
maybe_install_mcp_dependencies()
  - 加载全局配置
  - 添加缺失的服务器配置
  - 执行 OAuth 登录
  - 刷新 MCP 连接
```

### 协议与规范

#### MCP 协议支持

1. **stdio 传输**：通过标准输入/输出与子进程通信
2. **Streamable HTTP 传输**：HTTP SSE 流式通信
3. **OAuth 2.0**：支持授权码流程和 PKCE

#### 自定义 MCP 扩展

- `codex/sandbox-state` capability：服务器支持接收沙箱状态更新
- `codex/sandbox-state/update` method：推送沙箱策略变更

---

## 关键代码路径与文件引用

### 核心文件

| 文件 | 行数 | 主要职责 |
|------|------|---------|
| `mod.rs` | 448 | 服务器配置聚合、工具快照、工具名处理 |
| `auth.rs` | 288 | OAuth 认证、Scope 解析、认证状态计算 |
| `skill_dependencies.rs` | 464 | Skill MCP 依赖检测与自动安装 |
| `mod_tests.rs` | 263 | 单元测试 |
| `skill_dependencies_tests.rs` | 107 | 依赖安装测试 |

### 关键代码路径

#### 1. 服务器配置加载路径

```
McpManager::effective_servers()
  → effective_mcp_servers()
    → configured_mcp_servers()  // 用户配置 + 插件配置
    → with_codex_apps_mcp()     // 添加 Codex Apps
```

#### 2. 工具调用路径

```
ToolHandler::handle() [tools/handlers/mcp.rs]
  → handle_mcp_tool_call() [mcp_tool_call.rs]
    → Session::call_tool()
      → McpConnectionManager::call_tool()
        → RmcpClient::call_tool()
```

#### 3. Skill 依赖安装触发路径

```
Codex::submit_turn()
  → maybe_prompt_and_install_mcp_dependencies() [mcp/mod.rs]
    → maybe_prompt_and_install_mcp_dependencies() [mcp/skill_dependencies.rs]
      → collect_missing_mcp_dependencies()
      → should_install_mcp_dependencies()
      → maybe_install_mcp_dependencies()
```

#### 4. 认证状态检查路径

```
McpConnectionManager::new()
  → compute_auth_statuses() [mcp/auth.rs]
    → compute_auth_status()
      → determine_streamable_http_auth_status() [codex_rmcp_client]
```

### 外部接口

#### 与 `mcp_connection_manager.rs` 的交互

- `McpConnectionManager::new()` - 创建连接管理器
- `collect_mcp_snapshot_from_manager()` - 从管理器收集工具快照
- `McpAuthStatusEntry` - 认证状态条目

#### 与 `plugins/manager.rs` 的交互

- `PluginsManager::plugins_for_config()` - 获取插件配置
- `LoadedPlugins::effective_mcp_servers()` - 获取插件提供的 MCP 服务器

#### 与 `codex.rs` 的交互

- `maybe_prompt_and_install_mcp_dependencies()` - 在提交 turn 时调用
- `Session::refresh_mcp_servers_now()` - 刷新 MCP 服务器连接

---

## 依赖与外部交互

### 内部依赖

```
mcp/
├── mod.rs
│   ├── auth.rs                    # 认证子模块
│   ├── skill_dependencies.rs      # Skill 依赖子模块
│   └── mod_tests.rs               # 测试
│
依赖的同级模块:
├── mcp_connection_manager.rs      # MCP 连接管理
├── mcp_tool_call.rs               # 工具调用执行
├── connectors.rs                  # Codex Apps 连接器
├── plugins/manager.rs             # 插件管理
├── config/types.rs                # 配置类型
└── codex.rs                       # 主 Codex 逻辑
```

### 外部 Crate 依赖

| Crate | 用途 |
|-------|------|
| `codex_rmcp_client` | MCP 客户端实现、OAuth 流程 |
| `codex_protocol` | 协议类型定义（`McpListToolsResponseEvent`, `McpAuthStatus`） |
| `rmcp` | MCP 协议模型（`Tool`, `Resource`, `RequestId`） |
| `async_channel` | 异步事件通道 |

### 配置依赖

- `config.toml` 中的 `[mcp_servers]` 段
- `config.toml` 中的 `[features]` 段（`apps`, `skill_mcp_dependency_install`）
- 环境变量 `CODEX_CONNECTORS_TOKEN`（可选的 Bearer Token）

---

## 风险、边界与改进建议

### 已知风险

#### 1. 工具名冲突

**风险**：不同 MCP 服务器的工具可能生成相同的规范化名称

**缓解措施**：
- 使用 SHA1 哈希处理超长名称
- 检测重复名称并跳过冲突工具

**代码位置**：`mcp_connection_manager.rs:155-199`

#### 2. OAuth 认证失败

**风险**：OAuth 流程可能因 scope 不匹配而失败

**缓解措施**：
- 实现 `should_retry_without_scopes()` 逻辑
- 当 discovered scopes 被拒绝时，重试无 scope 请求

**代码位置**：`auth.rs:115-118`

#### 3. 循环依赖提示

**风险**：用户多次使用相同 Skill 时重复提示安装

**缓解措施**：
- `filter_prompted_mcp_dependencies()` 记录已提示的依赖
- 使用 canonical key 去重

**代码位置**：`skill_dependencies.rs:49-63`

### 边界情况

#### 1. 全访问模式

当 `AskForApproval::Never` 且沙箱策略为 `DangerFullAccess` 或 `ExternalSandbox` 时：
- 自动安装 MCP 依赖，不提示用户
- 代码：`skill_dependencies.rs:35-41`

#### 2. 非 First-Party 客户端

仅支持 first-party 客户端使用 Skill MCP 依赖安装功能：
- 检查：`is_first_party_originator()`
- 代码：`skill_dependencies.rs:142-146`

#### 3. 配置优先级

用户配置始终优先于插件配置：
```rust
// mod.rs:231-234
for (name, plugin_server) in loaded_plugins.effective_mcp_servers() {
    servers.entry(name).or_insert(plugin_server);  // or_insert = 不覆盖已有
}
```

### 改进建议

#### 1. 增强错误处理

**现状**：OAuth 错误仅记录警告日志
**建议**：向用户显示友好的错误提示，包含重试选项

#### 2. 支持 MCP 服务器热重载

**现状**：配置变更后需要重启会话
**建议**：实现文件监听，自动检测 `config.toml` 变更并重新加载 MCP 服务器

#### 3. 工具使用统计

**现状**：无工具使用频率追踪
**建议**：添加工具调用计数，用于优化工具列表排序（常用工具优先）

#### 4. 改进 Scope 管理

**现状**：Scope 冲突处理较为简单
**建议**：
- 实现 scope 权限预览界面
- 支持细粒度的权限授予/拒绝

#### 5. 缓存优化

**现状**：Codex Apps 工具缓存基于用户 key
**建议**：
- 添加缓存失效策略（TTL）
- 支持手动刷新缓存的命令

#### 6. 测试覆盖

**现状**：测试主要覆盖基础功能
**建议**：
- 添加 OAuth 流程的 mock 测试
- 添加并发场景测试（多个 MCP 服务器同时初始化）
- 添加错误恢复测试（服务器启动失败后重连）

---

## 附录：关键常量

| 常量 | 值 | 说明 |
|------|-----|------|
| `MCP_TOOL_NAME_PREFIX` | `"mcp"` | 工具名前缀 |
| `MCP_TOOL_NAME_DELIMITER` | `"__"` | 分隔符 |
| `CODEX_APPS_MCP_SERVER_NAME` | `"codex_apps"` | 内置服务器名 |
| `CODEX_CONNECTORS_TOKEN_ENV_VAR` | `"CODEX_CONNECTORS_TOKEN"` | Token 环境变量 |
| `MAX_TOOL_NAME_LENGTH` | `64` | 工具名最大长度 |
| `DEFAULT_STARTUP_TIMEOUT` | `10s` | 默认启动超时 |
| `DEFAULT_TOOL_TIMEOUT` | `120s` | 默认工具调用超时 |

---

## 附录：配置示例

### config.toml

```toml
[features]
apps = true
skill_mcp_dependency_install = true

[mcp_servers.my-server]
type = "http"
url = "https://example.com/mcp"
scopes = ["read", "write"]

[mcp_servers.local-tool]
type = "stdio"
command = "/usr/local/bin/mcp-server"
args = ["--port", "8080"]
```

### Skill 依赖声明 (SKILL.md)

```yaml
dependencies:
  tools:
    - type: mcp
      value: github
      transport: streamable_http
      url: https://github.com/mcp
```
