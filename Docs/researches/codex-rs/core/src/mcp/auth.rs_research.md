# auth.rs 研究文档

## 场景与职责

`auth.rs` 是 Codex 项目中 MCP (Model Context Protocol) 模块的认证子模块，负责处理 MCP 服务器的 OAuth 认证状态检测、登录支持探测以及 OAuth Scope 的解析与决策。它是连接 Codex 与外部 MCP 服务器认证流程的核心桥梁。

### 核心职责
1. **OAuth 登录支持探测**：检测 MCP 服务器是否支持 OAuth 登录流程
2. **认证状态计算**：为每个配置的 MCP 服务器计算当前认证状态（已登录、未登录、不支持等）
3. **Scope 解析策略**：实现多优先级 Scope 来源的解析逻辑（显式配置 > 配置文件 > 自动发现）
4. **错误重试策略**：针对 OAuth Provider 错误的智能重试机制

---

## 功能点目的

### 1. OAuth 登录支持探测 (`oauth_login_support`)

**目的**：在尝试 OAuth 登录前，预先检测服务器是否支持 OAuth 流程，避免不必要的登录尝试。

**关键逻辑**：
- 仅支持 `StreamableHttp` 传输类型的服务器
- 如果配置了 `bearer_token_env_var`，则认为不需要 OAuth
- 调用底层 `discover_streamable_http_oauth` 进行 OAuth 服务端点发现

### 2. Scope 解析策略 (`resolve_oauth_scopes`)

**目的**：确定 OAuth 请求中应该使用哪些 Scope，支持多来源优先级决策。

**优先级顺序**（从高到低）：
1. **Explicit** - 代码中显式传入的 scopes
2. **Configured** - 服务器配置中定义的 scopes
3. **Discovered** - 通过 OAuth Discovery 端点发现的 scopes
4. **Empty** - 空列表（fallback）

### 3. 认证状态批量计算 (`compute_auth_statuses`)

**目的**：为所有配置的 MCP 服务器并行计算认证状态，用于 UI 展示和连接决策。

**输出状态** (`McpAuthStatus`)：
- `OAuth` - 已获取 OAuth Token
- `BearerToken` - 使用 Bearer Token 认证
- `NotLoggedIn` - 支持 OAuth 但未登录
- `Unsupported` - 不支持 OAuth

### 4. 智能重试机制 (`should_retry_without_scopes`)

**目的**：处理某些 OAuth Provider 不支持自动发现的 scopes 的情况，允许在无 scope 情况下重试。

**触发条件**：
- Scope 来源为 `Discovered`（非用户显式配置）
- 错误类型为 `OAuthProviderError`

---

## 具体技术实现

### 关键数据结构

```rust
// OAuth 登录配置
pub struct McpOAuthLoginConfig {
    pub url: String,
    pub http_headers: Option<HashMap<String, String>>,
    pub env_http_headers: Option<HashMap<String, String>>,
    pub discovered_scopes: Option<Vec<String>>,  // 从 Discovery 端点获取
}

// Scope 来源标记（用于追踪决策来源）
pub enum McpOAuthScopesSource {
    Explicit,    // 显式传入
    Configured,  // 配置文件
    Discovered,  // 自动发现
    Empty,       // 空列表
}

// Scope 解析结果
pub struct ResolvedMcpOAuthScopes {
    pub scopes: Vec<String>,
    pub source: McpOAuthScopesSource,
}

// 认证状态条目（用于批量计算）
pub struct McpAuthStatusEntry {
    pub config: McpServerConfig,
    pub auth_status: McpAuthStatus,  // 来自 codex_protocol
}
```

### 关键流程

#### 1. OAuth Discovery 流程
```
oauth_login_support(transport)
  ├── 检查 transport 类型是否为 StreamableHttp
  ├── 检查是否已配置 bearer_token_env_var
  └── discover_streamable_http_oauth(url, headers)
       └── 尝试发现 OAuth 授权服务端点
```

#### 2. Scope 解析流程
```
resolve_oauth_scopes(explicit, configured, discovered)
  ├── explicit.is_some() ? 返回 Explicit
  ├── configured.is_some() ? 返回 Configured
  ├── discovered 非空 ? 返回 Discovered
  └── 返回 Empty
```

#### 3. 批量认证状态计算
```
compute_auth_statuses(servers, store_mode)
  ├── 为每个服务器创建异步任务
  ├── join_all 并行执行
  └── 收集结果到 HashMap<server_name, McpAuthStatusEntry>
```

### 协议与外部交互

| 函数 | 依赖模块 | 功能 |
|------|---------|------|
| `discover_streamable_http_oauth` | `codex_rmcp_client` | OAuth Discovery 协议实现 |
| `determine_streamable_http_auth_status` | `codex_rmcp_client` | 认证状态检测 |
| `perform_oauth_login` | `codex_rmcp_client` | 实际 OAuth 登录流程 |

### OAuth Discovery 协议

遵循 RFC 8414 (OAuth 2.0 Authorization Server Metadata) 规范：
- 请求 `/.well-known/oauth-authorization-server` 端点
- 检查响应中是否包含 `authorization_endpoint` 和 `token_endpoint`
- 提取 `scopes_supported` 字段作为可选 scope 列表

---

## 关键代码路径与文件引用

### 内部依赖

```
auth.rs
├── 依赖: crate::config::types::{McpServerConfig, McpServerTransportConfig}
├── 依赖: codex_protocol::protocol::McpAuthStatus
└── 被依赖: 
    ├── mod.rs (通过 pub mod auth 导出)
    ├── skill_dependencies.rs (OAuth 登录支持检测)
    └── mcp_connection_manager.rs (认证状态计算)
```

### 外部依赖

```
codex_rmcp_client
├── determine_streamable_http_auth_status()
├── discover_streamable_http_oauth()
├── perform_oauth_login()
└── OAuthProviderError (错误类型)
```

### 配置类型定义

```
codex-rs/core/src/config/types.rs
├── McpServerConfig (服务器配置)
│   ├── transport: McpServerTransportConfig
│   ├── scopes: Option<Vec<String>>
│   └── oauth_resource: Option<String>
└── McpServerTransportConfig
    ├── Stdio { command, args, env, ... }
    └── StreamableHttp { url, bearer_token_env_var, http_headers, env_http_headers }
```

---

## 依赖与外部交互

### 与 rmcp-client 的交互

`auth.rs` 是 `codex_rmcp_client` 的高级封装层：

1. **Discovery 阶段**：调用 `discover_streamable_http_oauth` 探测服务器能力
2. **状态检测阶段**：调用 `determine_streamable_http_auth_status` 获取当前状态
3. **登录阶段**：由调用方（如 `skill_dependencies.rs`）使用 `perform_oauth_login` 完成登录

### 与配置系统的交互

```rust
// 从配置中读取 Scope
server_config.scopes  // Option<Vec<String>>

// 从 Discovery 结果获取 Scope
oauth_config.discovered_scopes  // Option<Vec<String>>
```

### 与协议层的交互

`McpAuthStatus` 定义在 `codex_protocol` crate 中，用于跨进程/跨网络的状态传递：

```rust
// codex-rs/protocol/src/protocol.rs
pub enum McpAuthStatus {
    OAuth,
    BearerToken,
    NotLoggedIn,
    Unsupported,
}
```

---

## 风险、边界与改进建议

### 已知风险

1. **Discovery 超时风险**
   - `DISCOVERY_TIMEOUT` 固定为 5 秒
   - 网络延迟高的环境可能导致误判为不支持 OAuth
   - **建议**：考虑根据网络环境动态调整或支持配置

2. **Scope 冲突风险**
   - 自动发现的 scopes 可能与服务器实际要求不匹配
   - 已提供 `should_retry_without_scopes` 作为缓解措施
   - **建议**：增加 scope 验证机制，在登录前测试 scope 有效性

3. **并发登录竞争**
   - `compute_auth_statuses` 并行执行多个 Discovery 请求
   - 可能触发服务器的速率限制
   - **建议**：增加并发控制或退避机制

### 边界情况

| 场景 | 当前行为 | 评估 |
|------|---------|------|
| bearer_token_env_var 已设置 | 直接返回 Unsupported（跳过 OAuth） | ✅ 合理 |
| Discovery 端点返回错误 | 返回 Unknown(error) | ✅ 合理 |
| Scope 列表为空 | 返回 Empty 来源 | ✅ 合理 |
| 显式传入空 Vec | 返回 Explicit 来源 | ⚠️ 需确认是否符合预期 |

### 改进建议

1. **增加缓存机制**
   ```rust
   // 建议：缓存 Discovery 结果避免重复请求
   struct OAuthDiscoveryCache {
       url: String,
       result: StreamableHttpOAuthDiscovery,
       timestamp: Instant,
   }
   ```

2. **增强错误分类**
   - 当前 `McpOAuthLoginSupport::Unknown` 包含所有错误
   - 建议细分为：网络错误、解析错误、超时错误等

3. **支持 Scope 优先级覆盖**
   - 当前优先级固定：Explicit > Configured > Discovered
   - 建议允许配置文件中指定优先级策略

4. **增加遥测指标**
   - Discovery 成功率/延迟
   - Scope 来源分布统计
   - 重试次数分布

### 测试覆盖

当前测试覆盖（`mod tests`）：
- ✅ `resolve_oauth_scopes` 各优先级路径
- ✅ 显式空列表与 None 的区别
- ✅ `should_retry_without_scopes` 条件判断

建议补充：
- OAuth Discovery 集成测试（使用 mock server）
- 并发 `compute_auth_statuses` 测试
- 错误恢复路径测试
