# ChatgptAuthTokensRefreshResponse.json 研究文档

## 场景与职责

`ChatgptAuthTokensRefreshResponse` 是 Codex App Server Protocol v2 API 中用于**外部 ChatGPT 认证令牌刷新响应**的数据结构。当客户端收到 `ChatgptAuthTokensRefresh` 请求后，通过此结构将新的认证令牌回传给服务器，以完成令牌刷新流程并恢复后端 API 请求。

**关键场景：**
- 响应 `account/chatgptAuthTokens/refresh` 请求
- 提供新的有效访问令牌（JWT）
- 确认工作区/账户标识符
- 可选地提供计划类型信息

## 功能点目的

### 1. 令牌传递
提供刷新后的完整认证信息：
- **accessToken**：新的 JWT 访问令牌，用于后续 API 请求
- **chatgptAccountId**：工作区/账户标识符，用于多账户场景
- **chatgptPlanType**：可选的计划类型（如 pro、business、enterprise）

### 2. 账户一致性验证
- 服务端验证返回的 `chatgptAccountId` 与请求中的 `previous_account_id` 匹配
- 防止账户混淆和潜在的安全风险
- 不匹配时触发 Turn 失败

### 3. 计划类型推断
- 客户端可提供计划类型，避免服务端再次解析 JWT
- 如未提供，服务端尝试从访问令牌的 claims 中推断
- 无法推断时默认为 `unknown`

## 具体技术实现

### 数据结构定义

**JSON Schema 结构：**
```json
{
  "properties": {
    "accessToken": { "type": "string" },
    "chatgptAccountId": { "type": "string" },
    "chatgptPlanType": { "type": ["string", "null"] }
  },
  "required": ["accessToken", "chatgptAccountId"]
}
```

**Rust 源码定义**（`codex-rs/app-server-protocol/src/protocol/v2.rs`）：
```rust
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ChatgptAuthTokensRefreshResponse {
    pub access_token: String,
    pub chatgpt_account_id: String,
    pub chatgpt_plan_type: Option<String>,
}
```

### 关键流程

**1. 响应处理**（`message_processor.rs` 第 134-141 行）：
```rust
let response: ChatgptAuthTokensRefreshResponse =
    serde_json::from_value(result).map_err(std::io::Error::other)?;

Ok(ExternalAuthTokens {
    access_token: response.access_token,
    chatgpt_account_id: response.chatgpt_account_id,
    chatgpt_plan_type: response.chatgpt_plan_type,
})
```

**2. 令牌验证与使用**（`codex-rs/core/src/auth.rs`）：
```rust
// 验证访问令牌格式（JWT）
// 提取账户 ID 和计划类型
// 更新内部认证状态
// 重试失败的 API 请求
```

**3. TUI 客户端响应生成**（`tui_app_server/src/local_chatgpt_auth.rs` 第 15-22 行）：
```rust
impl LocalChatgptAuth {
    pub(crate) fn to_refresh_response(&self) -> ChatgptAuthTokensRefreshResponse {
        ChatgptAuthTokensRefreshResponse {
            access_token: self.access_token.clone(),
            chatgpt_account_id: self.chatgpt_account_id.clone(),
            chatgpt_plan_type: self.chatgpt_plan_type.clone(),
        }
    }
}
```

**4. 账户匹配验证**（`tui_app_server/src/app/app_server_adapter.rs` 第 524-537 行）：
```rust
fn resolve_chatgpt_auth_tokens_refresh_response(
    codex_home: &Path,
    auth_credentials_store_mode: AuthCredentialsStoreMode,
    forced_chatgpt_workspace_id: Option<&str>,
    params: &ChatgptAuthTokensRefreshParams,
) -> Result<ChatgptAuthTokensRefreshResponse, String> {
    let auth = load_local_chatgpt_auth(...)?;
    if let Some(previous_account_id) = params.previous_account_id.as_deref()
        && previous_account_id != auth.chatgpt_account_id
    {
        return Err(format!(
            "local ChatGPT auth refresh account mismatch: expected `{previous_account_id}`, got `{}`",
            auth.chatgpt_account_id
        ));
    }
    Ok(auth.to_refresh_response())
}
```

### 数据流

```
┌─────────────────┐     401 Unauthorized      ┌─────────────────┐
│   Codex Core    │ ─────────────────────────> │   App Server    │
│  (Backend API)  │                            │  (Message Proc) │
└─────────────────┘                            └────────┬────────┘
                                                        │
                              account/chatgptAuthTokens/refresh
                                                        │
                                                        v
┌─────────────────┐     ChatgptAuthTokensRefreshResponse    ┌─────────────────┐
│   Codex Core    │ <────────────────────────────────────────│  Client (TUI)   │
│ (Retry Request) │                                          │ (Load auth.json)│
└─────────────────┘                                          └─────────────────┘
```

## 关键代码路径与文件引用

### 核心定义文件
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构定义（第 1677-1684 行） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ServerRequest 响应类型注册 |

### 服务器实现
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/src/message_processor.rs` | 响应解析与令牌提取（第 134-141 行） |
| `codex-rs/core/src/auth.rs` | 外部认证令牌处理 |

### 客户端实现
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui_app_server/src/local_chatgpt_auth.rs` | 本地认证加载与响应生成（第 15-22 行） |
| `codex-rs/tui_app_server/src/app/app_server_adapter.rs` | 刷新请求处理与账户验证（第 518-538 行） |
| `codex-rs/exec/src/lib.rs` | Exec CLI 响应处理 |

### 测试文件
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/tests/suite/v2/account.rs` | 集成测试（第 312-807 行） |

### 生成文件
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/schema/typescript/v2/ChatgptAuthTokensRefreshResponse.ts` | TypeScript 类型定义 |

## 依赖与外部交互

### 上游依赖
1. **ChatgptAuthTokensRefreshParams** - 对应的请求参数
2. **codex_core::auth::ExternalAuthTokens** - 内部令牌表示

### 下游消费者
1. **codex_core::auth::AuthManager** - 更新认证状态
2. **codex_core::default_client** - 使用新令牌重试请求
3. **codex_protocol::account::PlanType** - 计划类型解析

### 相关类型
- `ExternalAuthRefreshContext` - 刷新请求上下文
- `ExternalAuthRefreshReason` - 刷新触发原因

## 风险、边界与改进建议

### 已知限制
1. **JWT 验证延迟**：响应中的 `access_token` 在首次使用前未验证，可能导致后续请求再次失败
2. **计划类型可选**：`chatgpt_plan_type` 为可选字段，服务端需处理缺失情况
3. **字符串类型**：`chatgpt_plan_type` 使用原始字符串而非枚举，缺乏类型安全

### 安全风险
1. **令牌泄露**：响应通过 JSON-RPC 传输，需确保传输层安全（WebSocket/TLS）
2. **令牌伪造**：服务端需验证 JWT 签名，防止客户端返回伪造令牌
3. **账户劫持**：必须验证 `chatgpt_account_id` 匹配，防止切换到恶意账户

### 改进建议
1. **早期验证**：服务端在返回前验证 JWT 格式和基本 claims
2. **计划类型枚举**：将 `chatgptPlanType` 改为枚举类型，限制有效值
3. **过期时间**：添加 `expires_at` 字段，帮助服务端预判刷新时机
4. **作用域信息**：添加 `scope` 字段，明确令牌权限范围
5. **刷新令牌**：考虑支持 refresh token 模式，而非直接返回新 access token

### 测试覆盖
- 正常刷新场景测试
- 账户不匹配错误处理
- 无效 JWT 格式处理
- 超时场景处理
- 并发刷新请求处理
