# ChatgptAuthTokensRefreshParams.json 研究文档

## 场景与职责

`ChatgptAuthTokensRefreshParams` 是 Codex App Server Protocol v2 API 中用于**外部 ChatGPT 认证令牌刷新**的参数结构。当 Codex 使用外部提供的 ChatGPT 认证令牌（而非内部管理的 OAuth 流程）时，如果令牌过期或收到 401 Unauthorized 响应，通过此结构向客户端请求新的有效令牌。

**关键场景：**
- 外部宿主应用（如 VSCode Extension、桌面应用）管理 ChatGPT OAuth 流程
- Codex 后端请求返回 401 Unauthorized，需要刷新访问令牌
- 多工作区/账户场景下需要刷新特定账户的令牌
- 外部认证模式（`AuthMode::ChatgptAuthTokens`）下的令牌生命周期管理

## 功能点目的

### 1. 外部认证令牌刷新
支持外部宿主应用托管的认证模式：
- **触发原因**：明确刷新请求的触发条件（如 401 Unauthorized）
- **账户识别**：通过 `previous_account_id` 帮助客户端识别需要刷新的账户
- **无缝续期**：用户无感知地完成令牌刷新，不中断当前对话流程

### 2. 多账户支持
- 客户端可管理多个 ChatGPT 工作区/账户
- 通过 `previous_account_id` 精确定位需要刷新的令牌
- 支持账户切换场景（刷新后返回不同账户的令牌）

### 3. 错误处理与降级
- 刷新失败时优雅降级，通知用户重新登录
- 支持刷新超时处理（默认 10 秒）
- 刷新返回错误时终止当前 Turn

## 具体技术实现

### 数据结构定义

**JSON Schema 结构：**
```json
{
  "definitions": {
    "ChatgptAuthTokensRefreshReason": {
      "oneOf": [
        {
          "description": "Codex attempted a backend request and received `401 Unauthorized`.",
          "enum": ["unauthorized"],
          "type": "string"
        }
      ]
    }
  },
  "properties": {
    "previousAccountId": {
      "description": "Workspace/account identifier that Codex was previously using...",
      "type": ["string", "null"]
    },
    "reason": { "$ref": "#/definitions/ChatgptAuthTokensRefreshReason" }
  },
  "required": ["reason"]
}
```

**Rust 源码定义**（`codex-rs/app-server-protocol/src/protocol/v2.rs`）：
```rust
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub enum ChatgptAuthTokensRefreshReason {
    /// Codex attempted a backend request and received `401 Unauthorized`.
    Unauthorized,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, JsonSchema, TS)]
#[serde(rename_all = "camelCase")]
#[ts(export_to = "v2/")]
pub struct ChatgptAuthTokensRefreshParams {
    pub reason: ChatgptAuthTokensRefreshReason,
    /// Workspace/account identifier that Codex was previously using.
    #[ts(optional = nullable)]
    pub previous_account_id: Option<String>,
}
```

### 关键流程

**1. 刷新触发**（`message_processor.rs` 第 81-143 行）：
```rust
struct ExternalAuthRefreshBridge {
    outgoing: Arc<OutgoingMessageSender>,
}

#[async_trait]
impl ExternalAuthRefresher for ExternalAuthRefreshBridge {
    async fn refresh(
        &self,
        context: ExternalAuthRefreshContext,
    ) -> std::io::Result<ExternalAuthTokens> {
        let params = ChatgptAuthTokensRefreshParams {
            reason: Self::map_reason(context.reason),
            previous_account_id: context.previous_account_id,
        };

        let (request_id, rx) = self
            .outgoing
            .send_request(ServerRequestPayload::ChatgptAuthTokensRefresh(params))
            .await;

        let result = match timeout(EXTERNAL_AUTH_REFRESH_TIMEOUT, rx).await {
            Ok(result) => result.map_err(|err| {
                std::io::Error::other(format!("auth refresh request canceled: {err}"))
            })?,
            Err(_) => {
                let _canceled = self.outgoing.cancel_request(&request_id).await;
                return Err(std::io::Error::other("auth refresh request timed out"));
            }
        };
        
        let response: ChatgptAuthTokensRefreshResponse =
            serde_json::from_value(result).map_err(std::io::Error::other)?;
        
        Ok(ExternalAuthTokens {
            access_token: response.access_token,
            chatgpt_account_id: response.chatgpt_account_id,
            chatgpt_plan_type: response.chatgpt_plan_type,
        })
    }
}
```

**2. 请求注册**（`common.rs` 第 772-775 行）：
```rust
server_request_definitions! {
    ChatgptAuthTokensRefresh => "account/chatgptAuthTokens/refresh" {
        params: v2::ChatgptAuthTokensRefreshParams,
        response: v2::ChatgptAuthTokensRefreshResponse,
    },
    // ...
}
```

**3. 客户端处理**（`tui_app_server/src/app/app_server_adapter.rs` 第 297-359 行）：
```rust
async fn handle_chatgpt_auth_tokens_refresh_request(
    &mut self,
    app_server_client: &AppServerSession,
    request_id: RequestId,
    params: ChatgptAuthTokensRefreshParams,
) {
    let config = self.config.clone();
    let result = tokio::task::spawn_blocking(move || {
        resolve_chatgpt_auth_tokens_refresh_response(
            &config.codex_home,
            config.cli_auth_credentials_store_mode,
            config.forced_chatgpt_workspace_id.as_deref(),
            &params,
        )
    }).await;
    
    // 处理响应或错误...
}
```

### 认证模式对比

| 模式 | 令牌管理 | 刷新机制 | 适用场景 |
|------|---------|---------|---------|
| `ApiKey` | 用户提供，静态存储 | 无刷新 | 开发者/企业 API 使用 |
| `Chatgpt` | Codex 管理 OAuth 流程 | 内部自动刷新 | 标准用户场景 |
| `ChatgptAuthTokens` | 外部宿主应用提供 | `ChatgptAuthTokensRefresh` | 嵌入式/集成场景 |

## 关键代码路径与文件引用

### 核心定义文件
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | Rust 结构定义（第 1653-1675 行） |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | ServerRequest 注册（第 772-775 行） |
| `codex-rs/core/src/auth.rs` | 外部认证刷新器 trait 定义 |

### 服务器实现
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/src/message_processor.rs` | ExternalAuthRefreshBridge 实现（第 81-143 行） |

### 客户端实现
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/tui_app_server/src/app/app_server_adapter.rs` | TUI 刷新请求处理（第 169-177, 297-359 行） |
| `codex-rs/tui_app_server/src/local_chatgpt_auth.rs` | 本地 ChatGPT 认证加载 |
| `codex-rs/exec/src/lib.rs` | Exec CLI 刷新处理 |

### 测试文件
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server/tests/suite/v2/account.rs` | 外部认证刷新集成测试（第 312-807 行） |

### 生成文件
| 文件路径 | 说明 |
|---------|------|
| `codex-rs/app-server-protocol/schema/typescript/v2/ChatgptAuthTokensRefreshParams.ts` | TypeScript 类型定义 |
| `codex-rs/app-server-protocol/schema/typescript/v2/ChatgptAuthTokensRefreshReason.ts` | 刷新原因枚举 |

## 依赖与外部交互

### 上游依赖
1. **codex_core::auth::ExternalAuthRefreshContext** - 刷新上下文
2. **codex_core::auth::ExternalAuthRefresher** - 刷新器 trait
3. **codex_core::auth::ExternalAuthTokens** - 外部认证令牌

### 下游消费者
1. **TUI App Server** - 从本地 auth.json 加载并返回新令牌
2. **VSCode Extension** - 通过 OAuth 流程获取新令牌
3. **Exec CLI** - 处理刷新请求或失败

### 相关响应类型
- `ChatgptAuthTokensRefreshResponse` - 包含新令牌、账户 ID、计划类型

## 风险、边界与改进建议

### 已知限制
1. **单一刷新原因**：当前仅支持 `Unauthorized`，未来可能需要支持其他触发条件（如令牌即将过期）
2. **同步阻塞**：刷新操作阻塞当前 Turn，超时 10 秒可能导致用户体验下降
3. **账户不匹配**：刷新返回的账户 ID 与预期不符时会导致 Turn 失败

### 安全风险
1. **令牌泄露**：`access_token` 通过进程间通信传递，需确保通道安全
2. **账户劫持**：恶意客户端可能返回错误的 `chatgpt_account_id`，需服务端验证
3. **令牌有效性**：服务端需验证返回的 JWT 格式和签名

### 改进建议
1. **预刷新机制**：在令牌过期前主动触发刷新，避免请求中断
2. **异步刷新**：支持后台刷新，不阻塞用户操作
3. **刷新原因扩展**：添加 `TokenExpiringSoon`、`UserRequested` 等原因
4. **账户验证**：服务端强制验证返回的 `chatgpt_account_id` 与 `previous_account_id` 匹配
5. **刷新指标**：收集刷新成功率、延迟等指标，用于监控

### 测试覆盖
- `external_auth_refreshes_on_unauthorized` - 401 触发刷新成功场景
- `external_auth_refresh_error_fails_turn` - 刷新错误导致 Turn 失败
- `external_auth_refresh_mismatched_workspace_fails_turn` - 账户不匹配处理
- `external_auth_refresh_invalid_access_token_fails_turn` - 无效令牌处理
