# McpServerOauthLoginCompletedNotification.json 研究文档

## 场景与职责

`McpServerOauthLoginCompletedNotification` 是 Codex App-Server Protocol v2 中的服务器通知类型，用于通知客户端 MCP（Model Context Protocol）服务器的 OAuth 登录流程已完成。该通知在 `mcpServer/oauthLogin/completed` 方法下发送。

## 功能点目的

1. **异步通知**：OAuth 登录是异步流程，服务器通过通知告知客户端登录结果
2. **状态反馈**：通知客户端特定 MCP 服务器的 OAuth 认证成功或失败
3. **错误传递**：在登录失败时传递错误信息供客户端展示

## 具体技术实现

### 数据结构

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct McpServerOauthLoginCompletedNotification {
    pub name: String,
    pub success: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    #[ts(optional)]
    pub error: Option<String>,
}
```

### 关键字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `name` | string | 是 | MCP 服务器名称 |
| `success` | boolean | 是 | OAuth 登录是否成功 |
| `error` | string \| null | 否 | 失败时的错误信息 |

### 协议映射

- **ServerNotification**: `McpServerOauthLoginCompleted => "mcpServer/oauthLogin/completed"`
- **通知参数**: `McpServerOauthLoginCompletedNotification`

## 关键代码路径与文件引用

### 定义位置
- `codex-rs/app-server-protocol/src/protocol/v2.rs` (lines 4960-4966)

### 协议注册
- `codex-rs/app-server-protocol/src/protocol/common.rs` (line 907):
```rust
McpServerOauthLoginCompleted => "mcpServer/oauthLogin/completed" (v2::McpServerOauthLoginCompletedNotification),
```

### 相关类型
- `McpServerOauthLoginParams`：登录请求参数（v2.rs lines 2080-2088）
- `McpServerOauthLoginResponse`：登录请求响应（v2.rs lines 2090-2095）

### 使用位置
- `codex-rs/app-server/src/codex_message_processor.rs`：处理 MCP 相关请求

## 依赖与外部交互

### 上游依赖
- `schemars`：JSON Schema 生成
- `ts-rs`：TypeScript 类型生成
- `serde`：序列化/反序列化

### 下游消费者
- App-Server 客户端（TUI、VS Code 扩展等）

### OAuth 登录流程
1. 客户端发送 `McpServerOauthLogin` 请求（带服务器名称、作用域等）
2. 服务器返回 `McpServerOauthLoginResponse`，包含 `authorizationUrl`
3. 客户端打开浏览器访问授权 URL
4. 用户完成 OAuth 授权
5. 服务器发送 `McpServerOauthLoginCompleted` 通知，告知结果

## 风险、边界与改进建议

### 风险点
1. **通知丢失**：如果客户端在登录完成前断开连接，可能错过通知
2. **状态同步**：客户端需要维护待处理的 OAuth 登录请求状态
3. **错误信息安全**：`error` 字段可能包含敏感信息，需要注意日志处理

### 边界情况
1. **重复通知**：服务器可能因重试机制发送重复通知
2. **超时处理**：客户端需要处理长时间未收到通知的情况
3. **服务器名称变更**：MCP 服务器名称变更可能导致通知无法匹配

### 改进建议
1. **添加请求 ID**：关联原始登录请求，便于客户端匹配
2. **添加时间戳**：帮助客户端判断通知时效性
3. **错误码标准化**：使用结构化错误码替代纯文本错误信息
4. **重试机制**：客户端实现通知确认机制，服务器支持重发
