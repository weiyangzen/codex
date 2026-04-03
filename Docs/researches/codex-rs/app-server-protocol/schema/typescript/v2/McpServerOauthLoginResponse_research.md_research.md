# McpServerOauthLoginResponse 研究文档

## 场景与职责

`McpServerOauthLoginResponse` 是 MCP (Model Context Protocol) 服务器 OAuth 登录流程的响应类型。当客户端请求对某个 MCP 服务器进行 OAuth 认证时，服务器返回此响应包含授权 URL，客户端需要引导用户访问该 URL 完成授权流程。

## 功能点目的

该类型的核心功能是：
1. **传递授权 URL**: 包含用户需要访问的 OAuth 授权页面地址
2. **支持 MCP 服务器认证**: 允许用户通过 OAuth 流程授权 Codex 访问第三方 MCP 服务器
3. **解耦认证流程**: 服务器只负责生成授权 URL，实际的浏览器跳转和回调处理由客户端完成

## 具体技术实现

### 数据结构

```typescript
export type McpServerOauthLoginResponse = { 
  authorizationUrl: string 
};
```

### Rust 源码定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct McpServerOauthLoginResponse {
    pub authorization_url: String,
}
```

### 关联的请求类型

`McpServerOauthLoginParams` 定义了登录请求的参数：
```rust
pub struct McpServerOauthLoginParams {
    pub name: String,
    pub scopes: Option<Vec<String>>,
    pub timeout_secs: Option<i64>,
}
```

### 完整认证流程

1. 客户端调用 `mcpServer/oauth/login` 方法，传入 `McpServerOauthLoginParams`
2. 服务器返回 `McpServerOauthLoginResponse` 包含 `authorizationUrl`
3. 客户端打开浏览器让用户访问授权 URL
4. 用户完成授权后，服务器通过 `McpServerOauthLoginCompletedNotification` 通知客户端

## 关键代码路径与文件引用

| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 类型定义，行 2090-2095 |
| `codex-rs/app-server-protocol/schema/typescript/v2/McpServerOauthLoginResponse.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 客户端请求定义，包含 `McpServerOauthLogin` 方法 |

## 依赖与外部交互

### 依赖类型
- `McpServerOauthLoginParams`: 对应的请求参数类型
- `McpServerOauthLoginCompletedNotification`: 登录完成的通知类型

### 协议集成
- 属于 App-Server Protocol v2 API
- 通过 JSON-RPC 2.0 协议传输
- 方法名: `mcpServer/oauth/login`

### MCP 集成
- 与 `McpServerStatus` 关联，认证状态通过 `McpAuthStatus` 枚举表示
- 支持 `OAuth` 和 `BearerToken` 两种认证方式

## 风险、边界与改进建议

### 安全风险
1. **URL 安全性**: `authorizationUrl` 可能包含敏感参数，需要确保传输通道安全 (WebSocket/WSS)
2. **超时处理**: OAuth 流程可能耗时较长，需要合理的超时配置

### 边界情况
1. **空 URL**: 如果服务器无法生成授权 URL，应该返回错误而非空字符串
2. **重复请求**: 同一服务器的多个并发 OAuth 请求需要妥善处理

### 改进建议
1. 考虑添加 `state` 参数用于防止 CSRF 攻击
2. 可以添加 `expiresAt` 字段指示授权 URL 的过期时间
3. 考虑支持 PKCE (Proof Key for Code Exchange) 增强安全性
