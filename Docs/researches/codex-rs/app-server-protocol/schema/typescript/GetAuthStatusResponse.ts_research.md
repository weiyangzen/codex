# GetAuthStatusResponse Research Document

## 1. 场景与职责 (Usage Scenario and Responsibility)

`GetAuthStatusResponse` 是 Codex 应用服务器协议中用于**获取认证状态响应**的返回类型。它包含当前会话的认证状态信息，包括认证方式、认证令牌和是否需要 OpenAI 认证等。

**典型使用场景：**
- 返回当前用户的认证方式（API Key / ChatGPT OAuth）
- 提供认证令牌供客户端使用
- 指示是否需要 OpenAI 认证
- 支持 UI 显示账户状态

**职责：**
- 封装认证状态信息
- 根据请求参数条件性返回敏感令牌
- 提供认证方式的元数据
- 支持客户端做出认证相关的决策

## 2. 功能点目的 (Purpose of This Type)

该类型的设计目的是：

1. **状态透明**：让客户端了解当前认证状态
2. **令牌提供**：在请求时提供认证令牌
3. **认证指导**：指示是否需要额外的认证步骤
4. **多方式支持**：支持多种认证方式的信息返回

## 3. 具体技术实现 (Technical Implementation Details)

### TypeScript 定义

```typescript
export type GetAuthStatusResponse = { 
  authMethod: AuthMode | null, 
  authToken: string | null, 
  requiresOpenaiAuth: boolean | null, 
};
```

### Rust 定义

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
pub struct GetAuthStatusResponse {
    pub auth_method: Option<AuthMode>,
    pub auth_token: Option<String>,
    pub requires_openai_auth: Option<bool>,
}
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `authMethod` | `AuthMode \| null` | 当前使用的认证方式 |
| `authToken` | `string \| null` | 认证令牌（仅在请求时包含） |
| `requiresOpenaiAuth` | `boolean \| null` | 是否需要 OpenAI 认证 |

### AuthMode 类型

```typescript
export type AuthMode = "apikey" | "chatgpt" | "chatgptAuthTokens";
```

| 值 | 说明 |
|----|------|
| `"apikey"` | 使用 OpenAI API Key 认证 |
| `"chatgpt"` | 使用 ChatGPT OAuth 认证（Codex 管理令牌） |
| `"chatgptAuthTokens"` | 使用外部托管的 ChatGPT 令牌（不稳定，内部使用） |

### 响应场景

| 场景 | authMethod | authToken | requiresOpenaiAuth |
|------|------------|-----------|-------------------|
| 未认证 | `null` | `null` | `true` |
| API Key 认证 | `"apikey"` | `"sk-..."` / `null` | `false` |
| ChatGPT 认证 | `"chatgpt"` | `"eyJ..."` / `null` | `false` |
| 需要重新认证 | `"chatgpt"` | `null` | `true` |

### 使用示例

```typescript
// 处理认证状态响应
function handleAuthStatusResponse(response: GetAuthStatusResponse) {
  const { authMethod, authToken, requiresOpenaiAuth } = response;
  
  // 1. 检查是否需要认证
  if (requiresOpenaiAuth || authMethod === null) {
    showLoginPrompt();
    return;
  }
  
  // 2. 根据认证方式显示状态
  switch (authMethod) {
    case "apikey":
      showStatus("已使用 API Key 认证");
      break;
    case "chatgpt":
      showStatus("已使用 ChatGPT 账户认证");
      break;
    case "chatgptAuthTokens":
      showStatus("使用外部令牌认证");
      break;
  }
  
  // 3. 使用令牌（如果提供）
  if (authToken) {
    storeToken(authToken);
  }
}
```

## 4. 关键代码路径与文件引用 (Key Code Paths and File References)

### 类型定义
- **TypeScript**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/schema/typescript/GetAuthStatusResponse.ts`
- **Rust**: `/home/sansha/Github/codex/codex-rs/app-server-protocol/src/protocol/v1.rs` (lines 176-191)

### 相关类型
- `GetAuthStatusParams` - 对应的请求参数
- `AuthMode` - 认证模式枚举（定义在 `common.rs`）

### 使用位置

1. **客户端请求定义**（`common.rs`）：
   ```rust
   client_request_definitions! {
       // ...
       /// DEPRECATED in favor of GetAccount
       GetAuthStatus {
           params: v1::GetAuthStatusParams,
           response: v1::GetAuthStatusResponse,
       },
       // ...
   }
   ```

2. **AuthMode 定义**：
   ```rust
   /// Authentication mode for OpenAI-backed providers.
   #[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, Display, JsonSchema, TS)]
   #[serde(rename_all = "lowercase")]
   pub enum AuthMode {
       ApiKey,
       Chatgpt,
       #[serde(rename = "chatgptAuthTokens")]
       #[ts(rename = "chatgptAuthTokens")]
       ChatgptAuthTokens,
   }
   ```

### 请求-响应流程

```
ClientRequest::GetAuthStatus
  params: GetAuthStatusParams { include_token, refresh_token }
  ↓
Server 检查认证状态
  - 查询当前认证方式
  - 根据 include_token 决定是否返回令牌
  - 根据 refresh_token 决定是否刷新
  ↓
GetAuthStatusResponse
  { auth_method, auth_token, requires_openai_auth }
```

## 5. 依赖与外部交互 (Dependencies and External Interactions)

### 协议集成
- 属于 app-server-protocol v1 类型（在 `v1.rs` 中定义）
- 通过 `ts-rs` 自动生成 TypeScript 类型
- 使用 camelCase 序列化
- 标记为 **DEPRECATED**，推荐使用 `GetAccount`

### 依赖类型
```typescript
import type { AuthMode } from "./AuthMode";
```

### 与 UserSavedConfig 的关系

```rust
pub struct UserSavedConfig {
    // ...
    pub forced_login_method: Option<ForcedLoginMethod>,
    // ...
}
```

`ForcedLoginMethod` 影响 `AuthMode` 的选择：
- `ForcedLoginMethod::Api` → `AuthMode::ApiKey`
- `ForcedLoginMethod::Chatgpt` → `AuthMode::Chatgpt`

### 外部交互

1. **服务器 → 客户端**：返回认证状态
2. **客户端 → UI**：显示认证状态
3. **客户端 → 存储**：安全存储令牌（如果提供）
4. **令牌刷新**：根据 `refresh_token` 参数刷新过期令牌

### 与 GetAccount (v2) 的关系

```rust
// v1 (DEPRECATED)
GetAuthStatus {
    params: v1::GetAuthStatusParams,
    response: v1::GetAuthStatusResponse,  // { auth_method, auth_token, requires_openai_auth }
}

// v2 (推荐)
GetAccount => "account/read" {
    params: v2::GetAccountParams,
    response: v2::GetAccountResponse,  // 更详细的账户信息
}
```

## 6. 风险、边界与改进建议 (Risks, Edge Cases, and Improvement Suggestions)

### 风险与边界

1. **已弃用状态**：
   - 该 API 已标记为 DEPRECATED
   - 新代码应使用 v2 的 `GetAccount`
   - 可能在未来的版本中被移除

2. **令牌安全**：
   - `authToken` 包含敏感信息
   - 只在 `includeToken: true` 时返回
   - 客户端需要安全存储

3. **空值处理**：
   - 所有字段都是 optional
   - 需要处理各种 null 组合

4. **requiresOpenaiAuth 语义**：
   - 含义不够明确
   - 可能表示：未认证、令牌过期、或需要重新授权

5. **chatgptAuthTokens 限制**：
   - 标记为 "UNSTABLE" 和 "FOR OPENAI INTERNAL USE ONLY"
   - 外部使用可能不稳定

### 改进建议

1. **迁移到 v2 API**：
   - 新客户端应实现 `GetAccount` 替代 `GetAuthStatus`
   - v2 API 提供更丰富的账户信息

2. **添加更多状态信息**：
   ```rust
   pub struct GetAuthStatusResponse {
       pub auth_method: Option<AuthMode>,
       pub auth_token: Option<String>,
       pub requires_openai_auth: Option<bool>,
       pub token_expires_at: Option<i64>,  // 令牌过期时间
       pub user_info: Option<UserInfo>,     // 用户信息
   }
   
   pub struct UserInfo {
       pub id: String,
       pub email: Option<String>,
       pub name: Option<String>,
   }
   ```

3. **明确状态语义**：
   ```rust
   pub struct GetAuthStatusResponse {
       pub auth_state: AuthState,  // 替换 requires_openai_auth
   }
   
   pub enum AuthState {
       Authenticated,
       Unauthenticated,
       TokenExpired,
       RefreshFailed(String),
   }
   ```

4. **令牌掩码**：
   ```rust
   pub struct GetAuthStatusResponse {
       pub auth_token: Option<String>,
       pub token_preview: Option<String>,  // 掩码后的令牌预览，如 "sk-...abcd"
   }
   ```

5. **添加速率限制信息**：
   ```rust
   pub struct GetAuthStatusResponse {
       // ...
       pub rate_limits: Option<RateLimitInfo>,
   }
   ```

### 测试建议
- 测试各种认证状态下的响应
- 验证令牌只在请求时返回
- 测试未认证状态的响应
- 验证令牌刷新后的响应
- 测试各种 `AuthMode` 的序列化

### 安全建议
- 避免在日志中记录完整令牌
- 使用 HTTPS 传输
- 实现令牌过期提醒
- 提供登出/清除令牌功能
- 考虑使用短期访问令牌
