# LoginAccountParams.json 研究文档

## 场景与职责

`LoginAccountParams` 是 Codex App Server Protocol v2 中定义的客户端请求参数类型，用于 `account/login/start` 方法。该参数支持多种登录方式，包括 API Key、ChatGPT OAuth 和 ChatGPT Auth Tokens（内部使用）。

这是 Codex 认证系统的核心入口，支持不同的认证模式以适应不同的部署场景。

## 功能点目的

1. **多模式认证**：支持 API Key、ChatGPT OAuth 和外部 Token 三种认证方式
2. **灵活部署**：适应从个人开发到企业集成的不同场景
3. **安全登录**：通过 OAuth 流程实现安全的第三方认证
4. **内部集成**：支持 OpenAI 内部系统的 Token 认证

## 具体技术实现

### 数据结构（Tagged Union）

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "oneOf": [
    {
      "title": "ApiKeyv2::LoginAccountParams",
      "properties": {
        "apiKey": { "type": "string" },
        "type": { "enum": ["apiKey"] }
      },
      "required": ["apiKey", "type"]
    },
    {
      "title": "Chatgtpv2::LoginAccountParams",
      "properties": {
        "type": { "enum": ["chatgpt"] }
      },
      "required": ["type"]
    },
    {
      "title": "ChatgptAuthTokensv2::LoginAccountParams",
      "description": "[UNSTABLE] FOR OPENAI INTERNAL USE ONLY...",
      "properties": {
        "accessToken": { "type": "string" },
        "chatgptAccountId": { "type": "string" },
        "chatgptPlanType": { "type": ["string", "null"] },
        "type": { "enum": ["chatgptAuthTokens"] }
      },
      "required": ["accessToken", "chatgptAccountId", "type"]
    }
  ]
}
```

### 登录方式详解

#### 1. API Key 模式

```json
{
  "type": "apiKey",
  "apiKey": "sk-..."
}
```

- **适用场景**: 个人开发者、自动化脚本
- **特点**: 简单直接，API Key 存储在本地
- **安全性**: API Key 持久化存储，需妥善保管

#### 2. ChatGPT OAuth 模式

```json
{
  "type": "chatgpt"
}
```

- **适用场景**: 普通用户，使用 ChatGPT 账户
- **流程**: 
  1. 客户端发送请求
  2. 服务器返回 `authUrl` 和 `loginId`
  3. 客户端打开浏览器完成 OAuth
  4. 服务器通过通知返回结果
- **特点**: 无需手动输入密钥，更安全

#### 3. ChatGPT Auth Tokens 模式（内部使用）

```json
{
  "type": "chatgptAuthTokens",
  "accessToken": "eyJ...",
  "chatgptAccountId": "account-123",
  "chatgptPlanType": "plus"
}
```

- **适用场景**: OpenAI 内部系统、外部宿主应用
- **警告**: `[UNSTABLE] FOR OPENAI INTERNAL USE ONLY - DO NOT USE`
- **特点**: 
  - Token 只存储在内存中
  - Token 刷新由外部宿主应用处理
  - 需要与 Codex 管理的 ChatGPT auth tokens 相同的 scope

### 协议映射

Rust 结构体定义（v2.rs）：

```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS, ExperimentalApi)]
#[serde(tag = "type")]
#[ts(tag = "type")]
#[ts(export_to = "v2/")]
pub enum LoginAccountParams {
    #[serde(rename = "apiKey", rename_all = "camelCase")]
    #[ts(rename = "apiKey", rename_all = "camelCase")]
    ApiKey {
        #[serde(rename = "apiKey")]
        #[ts(rename = "apiKey")]
        api_key: String,
    },
    #[serde(rename = "chatgpt")]
    #[ts(rename = "chatgpt")]
    Chatgpt,
    /// [UNSTABLE] FOR OPENAI INTERNAL USE ONLY...
    #[experimental("account/login/start.chatgptAuthTokens")]
    #[serde(rename = "chatgptAuthTokens", rename_all = "camelCase")]
    #[ts(rename = "chatgptAuthTokens", rename_all = "camelCase")]
    ChatgptAuthTokens {
        access_token: String,
        chatgpt_account_id: String,
        #[ts(optional = nullable)]
        chatgpt_plan_type: Option<String>,
    },
}
```

客户端请求定义（common.rs）：
```rust
client_request_definitions! {
    LoginAccount => "account/login/start" {
        params: v2::LoginAccountParams,
        inspect_params: true,
        response: v2::LoginAccountResponse,
    },
}
```

注意 `inspect_params: true` 表示某些字段是实验性的，需要特殊处理。

### 服务器处理逻辑

在 `codex_message_processor.rs` 中（行 908-931）：

```rust
async fn login_v2(&mut self, request_id: ConnectionRequestId, params: LoginAccountParams) {
    match params {
        LoginAccountParams::ApiKey { api_key } => {
            self.login_api_key_v2(request_id, LoginApiKeyParams { api_key }).await;
        }
        LoginAccountParams::Chatgpt => {
            self.login_chatgpt_v2(request_id).await;
        }
        LoginAccountParams::ChatgptAuthTokens { access_token, chatgpt_account_id, chatgpt_plan_type } => {
            self.login_chatgpt_auth_tokens(request_id, access_token, chatgpt_account_id, chatgpt_plan_type).await;
        }
    }
}
```

## 关键代码路径与文件引用

### 核心定义文件

1. **JSON Schema**: `codex-rs/app-server-protocol/schema/json/v2/LoginAccountParams.json`
2. **Rust 结构体**: `codex-rs/app-server-protocol/src/protocol/v2.rs` (行 1568-1601)
3. **协议枚举**: `codex-rs/app-server-protocol/src/protocol/common.rs` (行 430-434)

### 响应类型

- **LoginAccountResponse**: `v2.rs` 行 1603-1623
  - `ApiKey`: 空对象
  - `Chatgpt`: 包含 `loginId` 和 `authUrl`
  - `ChatgptAuthTokens`: 空对象

### 服务器处理代码

- **主处理**: `codex-rs/app-server/src/codex_message_processor.rs` 行 908-931
- **API Key 登录**: 行 942-984
- **ChatGPT OAuth 登录**: 行 1042-1108
- **ChatGPT Auth Tokens 登录**: 行 1110-1142

### 测试文件

- `codex-rs/app-server/tests/suite/v2/account.rs`
- `codex-rs/app-server/tests/suite/v2/realtime_conversation.rs`
- `codex-rs/app-server/tests/suite/v2/rate_limits.rs`
- `codex-rs/app-server/tests/suite/auth.rs`
- `codex-rs/tui_app_server/src/onboarding/auth.rs`

### 生成产物

- TypeScript: `typescript/v2/LoginAccountParams.ts`
- TypeScript: `typescript/v2/LoginAccountResponse.ts`

## 依赖与外部交互

### 内部依赖

1. **认证库**: `codex_core::auth` 模块
2. **登录服务**: `codex_login` 用于 OAuth 流程
3. **ChatGPT 连接器**: `codex_chatgpt::connectors`

### 外部交互

| 组件 | 交互 | 说明 |
|------|------|------|
| OpenAI API | HTTPS | API Key 验证 |
| ChatGPT OAuth | HTTPS | OAuth 流程 |
| 浏览器 | 重定向 | OAuth 用户授权 |

### 登录流程对比

| 方式 | 输入 | 响应 | 后续步骤 |
|------|------|------|----------|
| API Key | `apiKey` | 空对象 | 立即完成 |
| ChatGPT OAuth | 无 | `loginId`, `authUrl` | 浏览器授权 → 等待通知 |
| ChatGPT Tokens | `accessToken`, `accountId` | 空对象 | 立即完成 |

## 风险、边界与改进建议

### 安全风险

1. **API Key 泄露**: API Key 在请求中明文传输（HTTPS 加密），但存储在本地
2. **Token 过期**: ChatGPT Auth Tokens 模式需要外部处理 Token 刷新
3. **中间人攻击**: OAuth 流程依赖浏览器，需确保 `authUrl` 来自可信源

### 边界情况

1. **无效 API Key**: 返回 401 错误
2. **OAuth 取消**: 用户可能取消浏览器授权
3. **超时**: OAuth 流程有 10 分钟超时（`LOGIN_CHATGPT_TIMEOUT`）
4. **强制登录方法**: 配置可能强制使用特定登录方法

### 配置限制

```rust
// 强制 ChatGPT 登录
if matches!(self.config.forced_login_method, Some(ForcedLoginMethod::Chatgpt)) {
    return Err(JSONRPCErrorError {
        code: INVALID_REQUEST_ERROR_CODE,
        message: "API key login is disabled. Use ChatGPT login instead.".to_string(),
        data: None,
    });
}
```

### 改进建议

1. **MFA 支持**: 添加多因素认证支持
2. **SSO 集成**: 支持企业 SSO（SAML/OIDC）
3. **Token 刷新**: ChatGPT Auth Tokens 模式添加自动刷新机制
4. **登录历史**: 记录登录历史，支持审计
5. **设备授权**: 添加设备授权流程，提高安全性

### 客户端实现建议

```typescript
class AuthManager {
  async loginWithApiKey(apiKey: string): Promise<void> {
    const response = await this.client.request({
      method: 'account/login/start',
      params: {
        type: 'apiKey',
        apiKey
      }
    });
    
    // API Key 登录立即完成
    this.emit('loginCompleted', { success: true });
  }
  
  async loginWithChatgpt(): Promise<void> {
    const response = await this.client.request({
      method: 'account/login/start',
      params: { type: 'chatgpt' }
    });
    
    // 打开浏览器进行 OAuth
    await this.openBrowser(response.authUrl);
    
    // 等待服务器通知
    this.serverNotifications.once('account/login/completed', (result) => {
      if (result.success) {
        this.emit('loginCompleted', result);
      } else {
        this.emit('loginFailed', result.error);
      }
    });
  }
  
  // 取消进行中的登录
  async cancelLogin(loginId: string): Promise<void> {
    await this.client.request({
      method: 'account/login/cancel',
      params: { loginId }
    });
  }
}
```

### 实验性 API 警告

`ChatgptAuthTokens` 变体被标记为实验性：

```rust
#[experimental("account/login/start.chatgptAuthTokens")]
```

客户端应：
1. 避免在生产环境使用此模式
2. 关注官方 API 变更通知
3. 实现降级策略
