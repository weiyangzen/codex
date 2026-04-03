# McpServerOauthLoginParams.ts 研究文档

## 场景与职责

`McpServerOauthLoginParams.ts` 定义了 MCP (Model Context Protocol) 服务器 OAuth 登录请求的参数类型。该类型用于请求启动 OAuth 登录流程，获取授权 URL 以便用户进行身份验证。

此文件是 TypeScript 类型定义文件，由 Rust 的 `ts-rs` 工具从 Rust 源代码自动生成，用于在客户端与 app-server 之间进行类型安全的通信。

## 功能点目的

1. **OAuth 登录启动**: 请求启动特定 MCP 服务器的 OAuth 登录流程
2. **权限范围指定**: 允许指定所需的 OAuth 权限范围（scopes）
3. **超时控制**: 支持设置登录流程的超时时间
4. **服务器标识**: 明确指定需要登录的 MCP 服务器名称

## 具体技术实现

### 数据结构

```typescript
export type McpServerOauthLoginParams = { 
  name: string,                       // MCP 服务器名称
  scopes?: Array<string> | null,      // OAuth 权限范围列表
  timeoutSecs?: bigint | null,        // 超时时间（秒）
};
```

### 关键字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `name` | `string` | 是 | MCP 服务器的名称，用于标识需要登录的服务器 |
| `scopes` | `string[] \| null` | 否 | OAuth 权限范围列表，如 `["read", "write"]` |
| `timeoutSecs` | `bigint \| null` | 否 | 登录流程的超时时间（秒），null 表示使用默认值 |

### OAuth 流程

```
Client -> App Server: McpServerOauthLoginParams
App Server -> OAuth Provider: 请求授权 URL
App Server -> Client: McpServerOauthLoginResponse (authorizationUrl)
Client -> User: 打开 authorizationUrl
User -> OAuth Provider: 登录并授权
OAuth Provider -> App Server: 回调（authorization code）
App Server -> OAuth Provider: 交换 access token
App Server -> Client: 登录成功通知
```

### 生成来源

该文件由 Rust 结构体通过 `ts-rs` 自动生成：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct McpServerOauthLoginParams {
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional = nullable)]
    pub scopes: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    #[ts(optional = nullable)]
    pub timeout_secs: Option<u64>,
}
```

## 关键代码路径与文件引用

### 上游依赖（Rust 源文件）

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | 定义 Rust 类型 |
| `codex-rs/core/src/mcp_connection_manager.rs` | MCP 连接管理，处理 OAuth |
| `codex-rs/app-server/src/codex_message_processor.rs` | 处理 OAuth 登录请求 |

### 下游使用（TypeScript 消费者）

- VS Code 扩展的 OAuth 登录流程
- TUI 的登录提示界面
- 自动化脚本的身份验证

### 相关类型

| 类型 | 说明 |
|------|------|
| `McpServerOauthLoginResponse.ts` | OAuth 登录响应，包含授权 URL |
| `McpServerRefreshResponse.ts` | Token 刷新响应 |

### 相关测试

| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/suite/v2/mcp_server_oauth.rs` | OAuth 功能测试（如存在） |

## 依赖与外部交互

### 直接依赖

无直接依赖类型，这是一个独立的参数类型。

### 被依赖类型

- `McpServerOauthLoginResponse.ts`: 响应类型
- OAuth 登录流程的客户端实现

### MCP 协议集成

该类型用于实现 MCP 服务器的 OAuth 身份验证：
1. 客户端请求特定 MCP 服务器的 OAuth 登录
2. 服务器返回授权 URL
3. 用户在外部浏览器中完成登录
4. 服务器处理回调并获取 access token
5. 后续 MCP 工具调用使用获取的 token 进行身份验证

### 安全性考虑

1. **PKCE 支持**: 现代 OAuth 实现应使用 PKCE（Proof Key for Code Exchange）
2. **State 参数**: 使用 state 参数防止 CSRF 攻击
3. **Scope 最小化**: 只请求必要的权限范围
4. **Token 存储**: 安全存储 access token 和 refresh token

## 风险、边界与改进建议

### 风险点

1. **中间人攻击**: 授权 URL 可能被篡改，需要验证
2. **Token 泄露**: 存储的 token 需要加密保护
3. **Scope 滥用**: 请求过多的权限可能引起用户警觉
4. **超时处理**: 用户可能长时间不完成登录流程

### 边界情况

1. **无效服务器名称**: 指定的 MCP 服务器不存在
2. **不支持 OAuth**: 服务器不支持 OAuth 登录
3. **用户拒绝授权**: 用户在 OAuth 提供商处拒绝授权
4. **网络超时**: 与 OAuth 提供商通信超时
5. **重复登录**: 用户已登录，再次请求登录

### 改进建议

1. **添加回调 URL 指定**:
   ```typescript
   {
     name: string;
     scopes?: string[];
     timeoutSecs?: bigint;
     callbackUrl?: string;  // 自定义回调 URL
   }
   ```

2. **添加登录提示**:
   ```typescript
   {
     name: string;
     scopes?: string[];
     loginHint?: string;  // 预填充的用户名/邮箱提示
   }
   ```

3. **支持多种 OAuth 版本**:
   ```typescript
   {
     name: string;
     oauthVersion?: "2.0" | "2.1" | "1.0a";
   }
   ```

4. **添加强制重新登录**:
   ```typescript
   {
     name: string;
     forceReLogin?: boolean;  // 即使已登录也重新授权
   }
   ```

### 示例使用场景

```typescript
// 基本 OAuth 登录请求
const basicLogin: McpServerOauthLoginParams = {
  name: "github-server"
};

// 带权限范围的登录请求
const scopedLogin: McpServerOauthLoginParams = {
  name: "github-server",
  scopes: ["repo", "read:user", "write:discussion"]
};

// 带超时的登录请求
const timedLogin: McpServerOauthLoginParams = {
  name: "slack-server",
  scopes: ["chat:write", "users:read"],
  timeoutSecs: 300n  // 5 分钟超时
};
```
