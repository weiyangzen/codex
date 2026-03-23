# local_chatgpt_auth.rs 深度研究文档

## 场景与职责

`local_chatgpt_auth.rs` 负责从本地存储加载 ChatGPT 认证信息，用于 TUI 应用与 App Server 的认证流程。主要场景：

1. **本地认证加载**：从 `~/.codex/auth.json` 读取 ChatGPT 登录凭证
2. **工作区验证**：验证本地认证是否匹配强制要求的工作区 ID
3. **计划类型提取**：从 JWT token 中解析用户的 ChatGPT 计划类型（如 business、enterprise）
4. **认证模式区分**：区分 ChatGPT 登录认证与 API Key 认证

该模块是 TUI 应用认证流程的关键环节，确保只有有效的 ChatGPT 登录用户才能访问需要此类认证的功能。

## 功能点目的

### 1. `LocalChatgptAuth` - 本地 ChatGPT 认证结构

```rust
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct LocalChatgptAuth {
    pub(crate) access_token: String,
    pub(crate) chatgpt_account_id: String,
    pub(crate) chatgpt_plan_type: Option<String>,
}
```

包含：
- `access_token`：用于 API 请求的访问令牌
- `chatgpt_account_id`：ChatGPT 账户/工作区 ID
- `chatgpt_plan_type`：用户计划类型（小写，如 "business"、"enterprise"）

### 2. `to_refresh_response` - 转换为刷新响应

```rust
impl LocalChatgptAuth {
    pub(crate) fn to_refresh_response(&self) -> ChatgptAuthTokensRefreshResponse { ... }
}
```

将本地认证转换为 App Server 协议中的刷新响应格式，用于向 App Server 提供认证信息。

### 3. `load_local_chatgpt_auth` - 加载本地认证

```rust
pub(crate) fn load_local_chatgpt_auth(
    codex_home: &Path,
    auth_credentials_store_mode: AuthCredentialsStoreMode,
    forced_chatgpt_workspace_id: Option<&str>,
) -> Result<LocalChatgptAuth, String>
```

核心加载函数，执行以下验证：
1. 加载 `auth.json` 文件
2. 验证是 ChatGPT 登录而非 API Key
3. 提取 token 数据
4. 验证工作区 ID（如果强制指定）
5. 解析计划类型

## 具体技术实现

### 认证加载流程

```
codex_home
    ↓
load_auth_dot_json(...) → Result<Option<AuthDotJson>, _>
    ↓
检查 auth_mode 和 openai_api_key
    ↓
提取 tokens
    ↓
获取 access_token
    ↓
获取 chatgpt_account_id（优先 account_id，回退 id_token.chatgpt_account_id）
    ↓
验证 forced_chatgpt_workspace_id（如果指定）
    ↓
解析 plan_type（从 id_token，转为小写）
    ↓
返回 LocalChatgptAuth
```

### 关键验证逻辑

```rust
pub(crate) fn load_local_chatgpt_auth(...) -> Result<LocalChatgptAuth, String> {
    // 1. 加载 auth.json
    let auth = load_auth_dot_json(codex_home, auth_credentials_store_mode)
        .map_err(|err| format!("failed to load local auth: {err}"))?
        .ok_or_else(|| "no local auth available".to_string())?;
    
    // 2. 排除 API Key 认证
    if matches!(auth.auth_mode, Some(AuthMode::ApiKey)) || auth.openai_api_key.is_some() {
        return Err("local auth is not a ChatGPT login".to_string());
    }
    
    // 3. 提取 tokens
    let tokens = auth
        .tokens
        .ok_or_else(|| "local ChatGPT auth is missing token data".to_string())?;
    
    // 4. 获取 access_token
    let access_token = tokens.access_token;
    
    // 5. 获取 account_id（多种来源）
    let chatgpt_account_id = tokens
        .account_id
        .or(tokens.id_token.chatgpt_account_id.clone())
        .ok_or_else(|| "local ChatGPT auth is missing chatgpt account id".to_string())?;
    
    // 6. 验证强制工作区
    if let Some(expected_workspace) = forced_chatgpt_workspace_id
        && chatgpt_account_id != expected_workspace
    {
        return Err(format!(
            "local ChatGPT auth must use workspace {expected_workspace}, but found {chatgpt_account_id:?}"
        ));
    }
    
    // 7. 解析计划类型
    let chatgpt_plan_type = tokens
        .id_token
        .get_chatgpt_plan_type()
        .map(|plan_type| plan_type.to_ascii_lowercase());
    
    Ok(LocalChatgptAuth { ... })
}
```

### 数据结构依赖

```rust
// codex_core::auth::AuthDotJson
struct AuthDotJson {
    auth_mode: Option<AuthMode>,           // ApiKey 或 Chatgpt
    openai_api_key: Option<String>,        // API Key（如果存在）
    tokens: Option<TokenData>,             // ChatGPT token 数据
    last_refresh: Option<DateTime<Utc>>,
}

// codex_core::token_data::TokenData
struct TokenData {
    id_token: ChatgptIdTokenClaims,        // JWT 解析后的声明
    access_token: String,
    refresh_token: String,
    account_id: Option<String>,            // 显式账户 ID
}

// codex_core::token_data::ChatgptIdTokenClaims
struct ChatgptIdTokenClaims {
    chatgpt_account_id: Option<String>,    // JWT 中的账户 ID
    chatgpt_plan_type: Option<String>,     // JWT 中的计划类型
    // ... 其他 JWT 声明
}
```

## 关键代码路径与文件引用

### 调用方

| 文件 | 用途 |
|------|------|
| `src/lib.rs` | 在启动流程中加载本地认证 |
| `src/onboarding/login_screen.rs` | 登录流程中验证和使用本地认证 |

### 依赖模块

| 模块 | 路径 | 用途 |
|------|------|------|
| `codex_core::auth` | `codex-rs/core/src/auth.rs` | `load_auth_dot_json`, `save_auth` |
| `codex_core::token_data` | `codex-rs/core/src/token_data.rs` | `TokenData`, `ChatgptIdTokenClaims` |
| `codex_app_server_protocol` | `codex-rs/app-server-protocol/` | `AuthMode`, `ChatgptAuthTokensRefreshResponse` |

## 依赖与外部交互

### 文件系统交互

```
~/.codex/
└── auth.json          # 加密的认证存储（由 keyring 或文件模式管理）
```

### 认证存储模式

```rust
pub enum AuthCredentialsStoreMode {
    File,       // 明文存储（开发/测试用）
    Keyring,    // 系统密钥环存储（生产用）
}
```

### 错误处理策略

| 错误场景 | 错误消息 |
|---------|---------|
| 文件读取失败 | `"failed to load local auth: {err}"` |
| 无认证数据 | `"no local auth available"` |
| API Key 认证 | `"local auth is not a ChatGPT login"` |
| 缺少 token 数据 | `"local ChatGPT auth is missing token data"` |
| 缺少账户 ID | `"local ChatGPT auth is missing chatgpt account id"` |
| 工作区不匹配 | `"local ChatGPT auth must use workspace {expected}, but found {actual}"` |

## 风险、边界与改进建议

### 已知风险

1. **JWT 解析依赖**：计划类型从 JWT 解析，如果 JWT 格式变更可能失败
2. **大小写敏感**：工作区 ID 比较是大小写敏感的，可能导致误判
3. **单点失败**：认证加载失败会阻止整个 TUI 启动

### 测试覆盖

现有测试使用 `tempfile::TempDir` 创建隔离的测试环境：

```rust
#[test]
fn loads_local_chatgpt_auth_from_managed_auth() { ... }

#[test]
fn rejects_missing_local_auth() { ... }

#[test]
fn rejects_api_key_auth() { ... }

#[test]
fn prefers_managed_auth_over_external_ephemeral_tokens() { ... }
```

测试辅助函数 `fake_jwt` 生成测试用的 JWT token：
```rust
fn fake_jwt(email: &str, account_id: &str, plan_type: &str) -> String {
    // 构造 JWT: base64(header) + "." + base64(payload) + "." + base64(signature)
    let header = json!({ "alg": "none", "typ": "JWT" });
    let payload = json!({
        "email": email,
        "https://api.openai.com/auth": {
            "chatgpt_account_id": account_id,
            "chatgpt_plan_type": plan_type,
        },
    });
    // ...
}
```

### 边界情况

| 情况 | 处理 |
|------|------|
| `account_id` 和 `id_token.chatgpt_account_id` 不一致 | 优先使用 `account_id` |
| 计划类型大写 | 转换为小写存储 |
| 无计划类型 | `chatgpt_plan_type = None` |
| 强制工作区为 None | 跳过验证 |

### 改进建议

1. **工作区 ID 规范化**：
   ```rust
   // 添加大小写不敏感比较选项
   if !chatgpt_account_id.eq_ignore_ascii_case(expected_workspace) {
       // ...
   }
   ```

2. **更详细的错误信息**：
   ```rust
   // 区分 "文件不存在" 和 "文件解析失败"
   match load_auth_dot_json(...) {
       Err(AuthLoadError::NotFound) => Err("auth.json not found".to_string()),
       Err(AuthLoadError::InvalidJson(e)) => Err(format!("corrupted auth.json: {e}")),
       // ...
   }
   ```

3. **JWT 验证增强**：
   ```rust
   // 验证 token 是否过期
   if tokens.id_token.exp < Utc::now() {
       return Err("token expired".to_string());
   }
   ```

4. **遥测集成**：
   ```rust
   // 记录认证加载事件（不包含敏感信息）
   tracing::info!(
       account_id = %chatgpt_account_id,
       plan_type = ?chatgpt_plan_type,
       "loaded local chatgpt auth"
   );
   ```

5. **缓存机制**：
   ```rust
   // 避免频繁读取文件
   pub struct LocalAuthCache {
       last_modified: SystemTime,
       cached_auth: Option<LocalChatgptAuth>,
   }
   ```

### 安全考虑

1. **敏感信息日志**：确保 `access_token` 不会意外记录到日志
2. **内存安全**：`access_token` 在内存中以 `String` 存储，考虑使用 `secrecy::SecretString`
3. **文件权限**：`auth.json` 应设置为仅所有者可读（Unix 模式 0o600）
