# auth_status.rs 研究文档

## 场景与职责

`auth_status.rs` 是 `codex-rmcp-client` crate 中的认证状态检测模块，负责确定 Streamable HTTP MCP 服务器的认证状态。该模块实现了 MCP (Model Context Protocol) 服务器的 OAuth 2.0 发现机制，帮助客户端判断服务器支持的认证方式。

核心职责：
1. **认证状态判定**：根据配置和存储的凭证，确定服务器的认证状态（Bearer Token、OAuth、未登录、不支持）
2. **OAuth 发现**：实现 RFC 8414 标准的 OAuth 2.0 授权服务器发现协议
3. **多路径探测**：尝试多个 well-known 路径来发现 OAuth 元数据

## 功能点目的

### 1. 认证状态枚举 (`McpAuthStatus`)

定义在 `codex_protocol::protocol` 中的状态枚举：
- `Unsupported` - 服务器不支持 OAuth 认证
- `NotLoggedIn` - 服务器支持 OAuth 但用户未登录
- `BearerToken` - 使用 Bearer Token 认证（通过环境变量或 HTTP 头配置）
- `OAuth` - 已存储 OAuth 凭证

### 2. OAuth 发现流程

```
determine_streamable_http_auth_status()
├── 检查 bearer_token_env_var → BearerToken
├── 检查 Authorization HTTP 头 → BearerToken
├── 检查已存储的 OAuth tokens → OAuth
└── 执行 OAuth 发现探测
    ├── 成功发现 → NotLoggedIn
    ├── 未发现 → Unsupported
    └── 错误 → Unsupported (记录日志)
```

### 3. 发现路径策略

实现 RFC 8414 Section 3.1 的发现路径：
- `/.well-known/oauth-authorization-server/{base_path}`
- `/{base_path}/.well-known/oauth-authorization-server`
- `/.well-known/oauth-authorization-server` (根路径回退)

## 具体技术实现

### 关键数据结构

```rust
/// OAuth 发现结果
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StreamableHttpOAuthDiscovery {
    pub scopes_supported: Option<Vec<String>>,
}

/// OAuth 发现元数据（反序列化用）
#[derive(Debug, Deserialize)]
struct OAuthDiscoveryMetadata {
    authorization_endpoint: Option<String>,
    token_endpoint: Option<String>,
    scopes_supported: Option<Vec<String>>,
}
```

### 核心函数实现

#### `determine_streamable_http_auth_status()`

```rust
pub async fn determine_streamable_http_auth_status(
    server_name: &str,
    url: &str,
    bearer_token_env_var: Option<&str>,
    http_headers: Option<HashMap<String, String>>,
    env_http_headers: Option<HashMap<String, String>>,
    store_mode: OAuthCredentialsStoreMode,
) -> Result<McpAuthStatus>
```

**决策逻辑**：
1. 优先检查 `bearer_token_env_var` - 如果配置，直接返回 `BearerToken`
2. 检查 HTTP 头中是否包含 `Authorization` - 如果存在，返回 `BearerToken`
3. 调用 `has_oauth_tokens()` 检查本地存储 - 如果有，返回 `OAuth`
4. 执行 OAuth 发现探测 - 根据结果返回 `NotLoggedIn` 或 `Unsupported`

#### `discover_streamable_http_oauth_with_headers()`

```rust
async fn discover_streamable_http_oauth_with_headers(
    url: &str,
    default_headers: &HeaderMap,
) -> Result<Option<StreamableHttpOAuthDiscovery>>
```

**实现细节**：
- 使用 `no_proxy()` 避免系统代理配置导致的 panic（参考 issue #8912）
- 5 秒超时 (`DISCOVERY_TIMEOUT`)
- 发送 `MCP-Protocol-Version: 2024-11-05` 请求头
- 遍历 `discovery_paths()` 返回的所有候选路径
- 验证响应必须包含 `authorization_endpoint` 和 `token_endpoint`

#### `discovery_paths()` - RFC 8414 实现

```rust
fn discovery_paths(base_path: &str) -> Vec<String>
```

根据基础路径生成候选发现路径，确保去重。

#### `normalize_scopes()` - Scope 规范化

- 去除空白字符
- 去重
- 过滤空字符串
- 如果全部为空则返回 `None`

## 关键代码路径与文件引用

### 内部依赖

| 依赖项 | 路径 | 用途 |
|--------|------|------|
| `OAuthCredentialsStoreMode` | `crate` (lib.rs) | 凭证存储模式配置 |
| `has_oauth_tokens` | `crate::oauth` | 检查已存储的 OAuth tokens |
| `build_default_headers` | `crate::utils` | 构建默认 HTTP 头 |
| `apply_default_headers` | `crate::utils` | 应用默认 HTTP 头到客户端 |

### 外部依赖

| 依赖项 | 用途 |
|--------|------|
| `codex_protocol::protocol::McpAuthStatus` | 认证状态枚举定义 |
| `reqwest::Client` | HTTP 客户端 |
| `serde::Deserialize` | OAuth 元数据反序列化 |

### 调用关系

```
auth_status.rs
├── 被 lib.rs 导出
│   ├── determine_streamable_http_auth_status
│   ├── discover_streamable_http_oauth
│   └── supports_oauth_login
├── 调用 oauth.rs
│   └── has_oauth_tokens()
└── 调用 utils.rs
    ├── build_default_headers()
    └── apply_default_headers()
```

## 依赖与外部交互

### HTTP 协议交互

**请求**：
```http
GET /.well-known/oauth-authorization-server/mcp HTTP/1.1
Host: example.com
MCP-Protocol-Version: 2024-11-05
```

**期望响应**：
```http
HTTP/1.1 200 OK
Content-Type: application/json

{
  "authorization_endpoint": "https://example.com/oauth/authorize",
  "token_endpoint": "https://example.com/oauth/token",
  "scopes_supported": ["profile", "email"]
}
```

### 配置来源

1. **bearer_token_env_var**: 从环境变量读取 Bearer Token
2. **http_headers**: 静态配置的 HTTP 头
3. **env_http_headers**: 从环境变量动态读取的 HTTP 头
4. **store_mode**: OAuth 凭证存储模式（Keyring/File/Auto）

## 风险、边界与改进建议

### 已知风险

1. **系统代理 Bug**: 使用 `no_proxy()` 规避 `system-configuration` crate 的 panic 问题
   - 位置：`discover_streamable_http_oauth_with_headers()` 第 89 行
   - 参考：#8912

2. **错误处理策略**: OAuth 发现失败时静默返回 `Unsupported` 状态
   - 仅记录 debug 日志，可能掩盖配置问题
   - 第 54-59 行

3. **环境变量操作**: 测试中使用 `unsafe` 修改环境变量
   - `EnvVarGuard` 实现（第 242-272 行）
   - 使用 `serial_test::serial` 注解避免并发问题

### 边界情况

1. **空 Scope 处理**: `normalize_scopes()` 正确处理空字符串和全空白 scope
2. **路径边界**: `discovery_paths()` 处理根路径和嵌套路径的各种组合
3. **超时控制**: 5 秒硬编码超时，可能影响慢速网络环境

### 测试覆盖

| 测试用例 | 描述 |
|----------|------|
| `determine_auth_status_uses_bearer_token_when_authorization_header_present` | 验证 Authorization 头优先 |
| `determine_auth_status_uses_bearer_token_when_env_authorization_header_present` | 验证环境变量头解析 |
| `discover_streamable_http_oauth_returns_normalized_scopes` | Scope 规范化（去重、trim） |
| `discover_streamable_http_oauth_ignores_empty_scopes` | 空 scope 处理 |
| `supports_oauth_login_does_not_require_scopes_supported` | scopes_supported 可选性 |

### 改进建议

1. **可配置超时**: 将 `DISCOVERY_TIMEOUT` 改为可配置参数
2. **错误暴露**: 考虑在特定场景下将发现错误暴露给调用方，而非静默处理
3. **重试机制**: 为发现请求添加指数退避重试
4. **缓存机制**: 缓存发现结果避免重复请求
5. **协议版本协商**: 当前硬编码 `2024-11-05`，未来可支持版本协商
