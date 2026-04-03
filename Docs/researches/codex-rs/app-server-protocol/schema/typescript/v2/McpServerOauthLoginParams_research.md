# McpServerOauthLoginParams 研究文档

## 场景与职责

`McpServerOauthLoginParams` 是用于启动 MCP 服务器 OAuth 登录流程的请求参数类型。当用户需要为某个 MCP 服务器进行 OAuth 授权时，客户端通过此类型向 app-server 发送登录请求。

该类型支持配置 OAuth 授权的范围 (scopes) 和超时时间，使客户端能够灵活地控制授权行为，适应不同 MCP 服务器的认证需求。

## 功能点目的

1. **服务器标识**: 通过 `name` 字段指定需要进行 OAuth 授权的 MCP 服务器名称
2. **权限范围控制**: 通过 `scopes` 字段请求特定的 OAuth 权限范围
3. **超时配置**: 通过 `timeoutSecs` 设置授权流程的超时时间
4. **异步流程支持**: 支持启动独立的 OAuth 授权流程，通过通知机制返回结果

## 具体技术实现

### 数据结构

```typescript
export type McpServerOauthLoginParams = { 
  name: string, 
  scopes?: Array<string> | null, 
  timeoutSecs?: bigint | null, 
};
```

### 字段详解

| 字段 | 类型 | 可选 | 说明 |
|------|------|------|------|
| `name` | `string` | 必填 | MCP 服务器名称，用于标识需要授权的服务器 |
| `scopes` | `Array<string> \| null` | 可选 | 请求的 OAuth 权限范围列表，如 `["read", "write"]` |
| `timeoutSecs` | `bigint \| null` | 可选 | 授权流程的超时时间（秒），使用 bigint 类型支持大数值 |

### 响应类型

对应的响应类型为 `McpServerOauthLoginResponse`：
```typescript
export type McpServerOauthLoginResponse = { 
  authorization_url: string, 
};
```

### 完成通知

OAuth 登录完成后，服务器会发送 `McpServerOauthLoginCompletedNotification`：
```typescript
export type McpServerOauthLoginCompletedNotification = {
  name: string,
  success: boolean,
  error?: string,
};
```

### 生成信息

该文件为自动生成代码，由 [ts-rs](https://github.com/Aleph-Alpha/ts-rs) 从 Rust 源代码生成。

对应的 Rust 定义：
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct McpServerOauthLoginParams {
    pub name: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional = nullable)]
    pub scopes: Option<Vec<String>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional = nullable)]
    pub timeout_secs: Option<i64>,
}
```

## 关键代码路径与文件引用

### TypeScript 定义
- **文件**: `codex-rs/app-server-protocol/schema/typescript/v2/McpServerOauthLoginParams.ts`
- **响应类型**: `McpServerOauthLoginResponse.ts`
- **通知类型**: `McpServerOauthLoginCompletedNotification.ts`
- **索引**: `codex-rs/app-server-protocol/schema/typescript/v2/index.ts`

### Rust 源文件
- **主定义**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行号约 2077-2088)
- **响应定义**: 同一文件 (行号约 2090-2096)
- **通知定义**: 同一文件 (行号约 4957-4966)

### 协议注册

在 `codex-rs/app-server-protocol/src/protocol/common.rs` 中注册为客户端请求：
```rust
client_request_definitions! {
    // ...
    McpServerOauthLogin => "mcpServer/oauth/login" {
        params: v2::McpServerOauthLoginParams,
        response: v2::McpServerOauthLoginResponse,
    },
    // ...
}
```

### 核心使用位置

1. **App Server 消息处理**
   - 文件: `codex-rs/app-server/src/codex_message_processor.rs`
   - 导入: `use codex_app_server_protocol::McpServerOauthLoginParams;`
   - 功能: 处理 OAuth 登录请求

2. **测试套件**
   - 文件: `codex-rs/app-server/tests/suite/v2/` 相关测试
   - 功能: 验证 OAuth 登录流程

## 依赖与外部交互

### 完整 OAuth 流程

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      MCP Server OAuth 登录流程                           │
└─────────────────────────────────────────────────────────────────────────┘

  Client                      App Server                   MCP Server
    │                             │                            │
    │  1. mcpServer/oauth/login   │                            │
    │     {                       │                            │
    │       name: "github",       │                            │
    │       scopes: ["repo"],     │                            │
    │       timeoutSecs: 300      │                            │
    │     }                       │                            │
    │────────────────────────────▶│                            │
    │                             │                            │
    │                             │  2. 初始化 OAuth 流程        │
    │                             │───────────────────────────▶│
    │                             │                            │
    │  3. { authorization_url }   │                            │
    │◀────────────────────────────│                            │
    │                             │                            │
    │  4. 打开浏览器访问授权 URL   │                            │
    │─────────────────────────────────────────────────────────▶│
    │                             │                            │
    │                             │  5. 用户授权后回调           │
    │                             │◀───────────────────────────│
    │                             │                            │
    │  6. mcpServer/oauthLogin/   │                            │
    │     completed               │                            │
    │     { name, success }       │                            │
    │◀────────────────────────────│                            │
    │                             │                            │
```

### 与 MCP 服务器状态的关系

OAuth 登录成功后，会影响 `McpServerStatus` 中的 `auth_status` 字段：
```typescript
type McpServerStatus = {
  name: string,
  auth_status: McpAuthStatus,  // 会从 NotLoggedIn 变为 OAuth
  // ...
};
```

### 相关枚举

`McpAuthStatus` 定义了 MCP 服务器的认证状态：
```rust
pub enum McpAuthStatus {
    Unsupported,    // 服务器不支持认证
    NotLoggedIn,    // 未登录
    BearerToken,    // 使用 Bearer Token
    OAuth,          // 使用 OAuth
}
```

## 风险、边界与改进建议

### 已知风险

1. **bigint 类型兼容性**: TypeScript 中使用 `bigint` 类型，在某些 JSON 序列化场景中可能有问题
   - 风险: 某些 JavaScript 环境可能不支持 bigint
   - 缓解: 确保序列化时使用字符串表示

2. **超时处理**: 用户可能在浏览器中完成授权，但客户端已超时
   - 风险: 状态不一致
   - 缓解: 服务器端维护授权状态，客户端可以查询

3. **Scope 验证**: 请求的 scopes 可能在服务器端被拒绝
   - 风险: 授权成功但权限不足
   - 缓解: 在响应或通知中明确返回实际授权的 scopes

### 边界情况

1. **重复登录**: 用户已登录时再次发起登录请求
   - 应返回当前授权状态或重新授权

2. **无效服务器名称**: `name` 字段指定的服务器不存在
   - 应返回明确的错误信息

3. **授权被拒绝**: 用户在浏览器中拒绝授权
   - 通过 `McpServerOauthLoginCompletedNotification` 通知客户端

4. **网络中断**: 授权过程中网络问题
   - 需要重试机制和状态恢复

5. **超时边界**: `timeoutSecs` 为 0 或负数时的处理
   - 应使用默认值或返回错误

### 改进建议

1. **添加 state 参数**:
   ```typescript
   state?: string;  // 用于防止 CSRF 攻击的随机状态值
   ```

2. **支持强制重新授权**:
   ```typescript
   force?: boolean;  // 即使已登录也重新授权
   ```

3. **返回更多信息**:
   ```typescript
   // 在响应中添加
   serverName?: string;  // 确认的服务器名称
   requestedScopes?: string[];  // 请求的权限列表
   ```

4. **支持 PKCE**:
   ```typescript
   usePkce?: boolean;  // 是否使用 PKCE 扩展增强安全性
   ```

5. **添加回调配置**:
   ```typescript
   redirectUri?: string;  // 自定义回调地址
   ```

### 安全建议

1. **URL 验证**: 确保 `authorization_url` 来自可信源
2. **Scope 限制**: 服务器端应限制可请求的 scope 范围
3. **状态验证**: 实现 state 参数防止 CSRF
4. **Token 存储**: 安全存储获取的 OAuth token

### 测试建议

1. **单元测试**:
   - 参数序列化/反序列化
   - 字段验证（必填、可选）

2. **集成测试**:
   - 完整的 OAuth 流程
   - 超时处理
   - 错误处理

3. **安全测试**:
   - CSRF 防护
   - Scope 注入攻击
   - 重放攻击防护

### 配置建议

在 `Config` 中添加 OAuth 相关配置：
```toml
[mcp.oauth]
default_timeout_secs = 300
allowed_scopes = ["read", "write"]
auto_redirect = true
```
