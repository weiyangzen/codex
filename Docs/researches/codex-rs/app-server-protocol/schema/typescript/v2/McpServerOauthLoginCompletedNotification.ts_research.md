# McpServerOauthLoginCompletedNotification.ts Research Document

## 场景与职责

`McpServerOauthLoginCompletedNotification` 是 MCP 服务器 OAuth 登录流程完成后的通知类型。当用户通过浏览器完成 OAuth 授权流程后，服务器通过此通知向客户端告知登录结果。

该类型在以下场景中使用：
- 用户点击 `McpServerOauthLoginResponse` 返回的 `authorizationUrl` 完成授权
- OAuth 流程成功或失败后，服务器需要通知客户端状态变更
- 客户端需要更新 UI 以反映 MCP 服务器的认证状态

## 功能点目的

1. **登录结果通知**: 异步通知客户端 OAuth 登录流程的最终结果
2. **错误传播**: 在登录失败时传递错误信息，帮助客户端诊断问题
3. **状态同步**: 触发客户端刷新 MCP 服务器状态（如 `McpServerStatus`）
4. **UI 更新驱动**: 驱动客户端更新登录按钮、状态指示器等 UI 元素

## 具体技术实现

### 数据结构定义

```typescript
export type McpServerOauthLoginCompletedNotification = { 
  name: string, 
  success: boolean, 
  error?: string, 
};
```

### 关键字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `name` | `string` | 是 | MCP 服务器的唯一标识名称，与 `McpServerOauthLoginParams` 中的 `name` 对应 |
| `success` | `boolean` | 是 | OAuth 登录是否成功。`true` 表示授权完成，`false` 表示失败 |
| `error` | `string` | 否 | 可选的错误信息。当 `success` 为 `false` 时，包含失败原因描述 |

### 字段详细说明

#### `name`
- 用于标识哪个 MCP 服务器的登录流程已完成
- 客户端使用此字段匹配对应的登录请求
- 应与 `mcpServer/oauthLogin` 调用时传入的 `name` 参数一致

#### `success`
- 布尔值，表示 OAuth 授权流程的最终状态
- `true`: 用户成功授权，服务器已获得有效的访问令牌
- `false`: 授权失败，可能是用户拒绝、超时或发生错误

#### `error`
- 可选字段，仅在 `success` 为 `false` 时有意义
- 包含人类可读的错误描述
- 可能的错误场景：
  - 用户在授权页面点击"拒绝"
  - 授权码交换失败
  - 网络连接问题
  - 授权超时

## 关键代码路径与文件引用

- **TypeScript 源文件**: `codex-rs/app-server-protocol/schema/typescript/v2/McpServerOauthLoginCompletedNotification.ts`
- **Rust 源文件**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (第 4960-4966 行)
- **相关类型**:
  - `McpServerOauthLoginParams.ts` - 登录请求参数
  - `McpServerOauthLoginResponse.ts` - 登录响应（包含授权 URL）

### Rust 实现详情

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

注意 Rust 实现中使用了 `#[serde(skip_serializing_if = "Option::is_none")]`，这意味着当 `error` 为 `None` 时，该字段不会出现在序列化后的 JSON 中。

## 依赖与外部交互

### 依赖类型

无直接依赖类型，使用原生 TypeScript 类型 (`string`, `boolean`)。

### 相关流程

```
┌─────────────────┐     mcpServer/oauthLogin      ┌─────────────────┐
│     Client      │ ─────────────────────────────>│     Server      │
│                 │  (McpServerOauthLoginParams)  │                 │
│                 │                               │                 │
│                 │ <─────────────────────────────│                 │
│                 │  (McpServerOauthLoginResponse)│                 │
│                 │       authorizationUrl        │                 │
│                 │                               │                 │
│                 │  [User opens URL in browser   │                 │
│                 │   and completes OAuth flow]   │                 │
│                 │                               │                 │
│                 │ <─────────────────────────────│                 │
│                 │(McpServerOauthLoginCompleted  │                 │
│                 │       Notification)           │                 │
└─────────────────┘                               └─────────────────┘
```

### 使用场景

1. **成功流程**:
   ```typescript
   { name: "github", success: true }
   ```

2. **失败流程**:
   ```typescript
   { name: "github", success: false, error: "User denied authorization" }
   ```

## 风险、边界与改进建议

### 潜在风险

1. **通知丢失**: 如果客户端在 OAuth 流程完成前断开连接，可能错过此通知。建议客户端在重连后主动查询服务器状态。

2. **名称不匹配**: `name` 字段必须与登录请求时的名称完全匹配（包括大小写），否则客户端无法正确关联。

3. **错误信息泄露**: `error` 字段可能包含敏感信息，应确保只包含安全的、用户友好的错误描述。

### 边界情况

1. **重复通知**: 服务器应确保每个 OAuth 流程只发送一次完成通知，但客户端应能优雅地处理重复通知。

2. **超时处理**: OAuth 流程可能有时间限制，客户端应实现超时逻辑，不应无限期等待此通知。

3. **并发登录**: 如果同时发起多个 MCP 服务器的登录请求，客户端需要通过 `name` 字段正确区分通知。

### 改进建议

1. **添加请求 ID**: 考虑添加 `requestId` 字段，使客户端能更可靠地匹配请求和通知：
   ```typescript
   export type McpServerOauthLoginCompletedNotification = { 
     name: string;
     requestId: string;  // 新增
     success: boolean;
     error?: string;
   };
   ```

2. **错误码标准化**: 除了人类可读的错误消息，添加机器可读的错误码：
   ```typescript
   export type McpServerOauthLoginCompletedNotification = { 
     name: string;
     success: boolean;
     error?: string;
     errorCode?: "user_denied" | "timeout" | "network_error" | "server_error";
   };
   ```

3. **添加时间戳**: 帮助客户端判断通知的时效性：
   ```typescript
   export type McpServerOauthLoginCompletedNotification = { 
     name: string;
     success: boolean;
     error?: string;
     completedAt: number;  // Unix timestamp
   };
   ```

4. **令牌过期提示**: 如果成功但令牌有较短的有效期，可以添加提示：
   ```typescript
   export type McpServerOauthLoginCompletedNotification = { 
     name: string;
     success: boolean;
     error?: string;
     expiresAt?: number;  // 可选的过期时间提示
   };
   ```
