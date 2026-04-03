# McpServerOauthLoginParams.json 研究文档

## 场景与职责

`McpServerOauthLoginParams` 是 Codex App-Server Protocol v2 中 MCP（Model Context Protocol）服务器 OAuth 登录流程的请求参数类型，用于 `mcpServer/oauth/login` 方法。该类型定义了启动 OAuth 登录所需的参数。

## 功能点目的

1. **指定目标服务器**：通过 `name` 字段指定要认证的 MCP 服务器
2. **权限控制**：通过 `scopes` 字段请求特定的 OAuth 作用域
3. **超时配置**：通过 `timeoutSecs` 字段配置登录流程的超时时间

## 具体技术实现

### 数据结构

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

### 关键字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `name` | string | 是 | MCP 服务器名称，标识要认证的目标服务器 |
| `scopes` | string[] \| null | 否 | 请求的 OAuth 作用域列表 |
| `timeoutSecs` | integer \| null | 否 | 登录流程超时时间（秒） |

### 协议映射

- **ClientRequest**: `McpServerOauthLogin => "mcpServer/oauth/login"`
- **请求参数**: `McpServerOauthLoginParams`
- **响应类型**: `McpServerOauthLoginResponse`

## 关键代码路径与文件引用

### 定义位置
- `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 2080-2088)

### 协议注册
- `codex-rs/app-server-protocol/src/protocol/common.rs` (lines 410-412):
```rust
McpServerOauthLogin => "mcpServer/oauth/login" {
    params: v2::McpServerOauthLoginParams,
    response: v2::McpServerOauthLoginResponse,
}
```

### 相关类型
- `McpServerOauthLoginResponse`：登录请求响应（v2.rs lines 2090-2095）
- `McpServerOauthLoginCompletedNotification`：登录完成通知（v2.rs lines 4960-4966）

### 使用位置
- `codex-rs/app-server/src/codex_message_processor.rs`：处理 MCP OAuth 登录请求

## 依赖与外部交互

### 上游依赖
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成
- `serde`：序列化/反序列化

### 下游消费者
- App-Server 客户端（TUI、VS Code 扩展等）

### OAuth 登录流程
1. 客户端构造 `McpServerOauthLoginParams`，指定目标服务器名称
2. 可选配置 `scopes` 和 `timeoutSecs`
3. 发送 `McpServerOauthLogin` 请求
4. 服务器返回 `McpServerOauthLoginResponse`，包含授权 URL
5. 客户端打开浏览器完成 OAuth 流程
6. 服务器异步发送 `McpServerOauthLoginCompleted` 通知

## 风险、边界与改进建议

### 风险点
1. **服务器名称有效性**：`name` 必须是已配置的 MCP 服务器，否则请求失败
2. **作用域兼容性**：`scopes` 必须与目标服务器支持的 OAuth 作用域匹配
3. **超时处理**：`timeoutSecs` 过长可能导致资源占用，过短可能导致用户来不及完成授权

### 边界情况
1. **空作用域**：`scopes` 为 null 时，使用服务器默认作用域
2. **零超时**：`timeoutSecs` 为 0 或负数时的处理逻辑
3. **并发登录**：同一服务器的多次登录请求处理

### 改进建议
1. **添加回调 URL**：支持客户端指定自定义回调 URL
2. **状态保持**：添加 `state` 参数用于防止 CSRF 攻击
3. **作用域验证**：在请求阶段验证作用域有效性，提前返回错误
4. **默认超时**：为 `timeoutSecs` 设置合理的默认值（如 300 秒）
