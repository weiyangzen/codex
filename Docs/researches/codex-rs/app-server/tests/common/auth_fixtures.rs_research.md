# auth_fixtures.rs 研究文档

## 场景与职责

该文件提供了用于测试的 ChatGPT 认证 fixtures（测试夹具）。在 Codex 的集成测试中，需要模拟已登录用户的状态，但不应使用真实的 OpenAI 凭证。该模块实现了：
1. 构建伪造的 ChatGPT JWT token（ID token）
2. 创建完整的 `auth.json` 文件，包含 token、刷新 token 等
3. 支持自定义用户 claims（邮箱、计划类型、用户 ID 等）

这使得测试可以在不依赖外部认证服务的情况下，验证与认证相关的功能。

## 功能点目的

1. **JWT Token 生成**：创建结构有效但签名无效的 JWT（使用 `"none"` 算法）
2. **Auth 文件构建**：通过 Builder 模式构建认证配置
3. **Claims 自定义**：支持设置邮箱、计划类型、用户 ID、账户 ID 等
4. **持久化**：将认证状态写入 `CODEX_HOME/auth.json`

## 具体技术实现

### 核心数据结构

```rust
/// Builder for writing a fake ChatGPT auth.json in tests.
#[derive(Debug, Clone)]
pub struct ChatGptAuthFixture {
    access_token: String,
    refresh_token: String,
    account_id: Option<String>,
    claims: ChatGptIdTokenClaims,
    last_refresh: Option<Option<DateTime<Utc>>>,
}

#[derive(Debug, Clone, Default)]
pub struct ChatGptIdTokenClaims {
    pub email: Option<String>,
    pub plan_type: Option<String>,
    pub chatgpt_user_id: Option<String>,
    pub chatgpt_account_id: Option<String>,
}
```

### Builder 模式实现

```rust
impl ChatGptAuthFixture {
    pub fn new(access_token: impl Into<String>) -> Self
    pub fn refresh_token(mut self, refresh_token: impl Into<String>) -> Self
    pub fn account_id(mut self, account_id: impl Into<String>) -> Self
    pub fn plan_type(mut self, plan_type: impl Into<String>) -> Self
    pub fn chatgpt_user_id(mut self, chatgpt_user_id: impl Into<String>) -> Self
    pub fn chatgpt_account_id(mut self, chatgpt_account_id: impl Into<String>) -> Self
    pub fn email(mut self, email: impl Into<String>) -> Self
    pub fn last_refresh(mut self, last_refresh: Option<DateTime<Utc>>) -> Self
    pub fn claims(mut self, claims: ChatGptIdTokenClaims) -> Self
}
```

### JWT Token 编码

```rust
pub fn encode_id_token(claims: &ChatGptIdTokenClaims) -> Result<String> {
    let header = json!({ "alg": "none", "typ": "JWT" });
    let mut payload = serde_json::Map::new();
    
    // 标准 claims
    if let Some(email) = &claims.email {
        payload.insert("email".to_string(), json!(email));
    }
    
    // OpenAI 自定义 claims（在 https://api.openai.com/auth 命名空间下）
    let mut auth_payload = serde_json::Map::new();
    if let Some(plan_type) = &claims.plan_type {
        auth_payload.insert("chatgpt_plan_type".to_string(), json!(plan_type));
    }
    // ... 其他 claims
    
    if !auth_payload.is_empty() {
        payload.insert(
            "https://api.openai.com/auth".to_string(),
            serde_json::Value::Object(auth_payload),
        );
    }
    
    // Base64 URL 编码（无填充）
    let header_b64 = URL_SAFE_NO_PAD.encode(...);
    let payload_b64 = URL_SAFE_NO_PAD.encode(...);
    let signature_b64 = URL_SAFE_NO_PAD.encode(b"signature");
    
    Ok(format!("{header_b64}.{payload_b64}.{signature_b64}"))
}
```

### Auth 文件写入

```rust
pub fn write_chatgpt_auth(
    codex_home: &Path,
    fixture: ChatGptAuthFixture,
    cli_auth_credentials_store_mode: AuthCredentialsStoreMode,
) -> Result<()> {
    let id_token_raw = encode_id_token(&fixture.claims)?;
    let id_token = parse_chatgpt_jwt_claims(&id_token_raw).context("parse id token")?;
    
    let tokens = TokenData {
        id_token,
        access_token: fixture.access_token,
        refresh_token: fixture.refresh_token,
        account_id: fixture.account_id,
    };

    let auth = AuthDotJson {
        auth_mode: Some(AuthMode::Chatgpt),
        openai_api_key: None,
        tokens: Some(tokens),
        last_refresh: fixture.last_refresh.unwrap_or_else(|| Some(Utc::now())),
    };

    save_auth(codex_home, &auth, cli_auth_credentials_store_mode)
        .context("write auth.json")
}
```

## 关键代码路径与文件引用

### 当前文件
- `codex-rs/app-server/tests/common/auth_fixtures.rs`

### 导出位置
- `lib.rs`: `pub use auth_fixtures::{ChatGptAuthFixture, ChatGptIdTokenClaims, encode_id_token, write_chatgpt_auth};`

### 依赖的 Codex 内部类型
- `codex_core::auth::{AuthCredentialsStoreMode, AuthDotJson, save_auth}`
- `codex_core::token_data::{TokenData, parse_chatgpt_jwt_claims}`
- `codex_app_server_protocol::AuthMode`

### 使用示例

```rust
// 测试代码中创建认证 fixture
write_chatgpt_auth(
    codex_home.path(),
    ChatGptAuthFixture::new("test-access-token")
        .email("test@example.com")
        .plan_type("plus")
        .chatgpt_user_id("user-123")
        .chatgpt_account_id("acct-456"),
    AuthCredentialsStoreMode::Plaintext,
)?;
```

## 依赖与外部交互

### 外部 crate 依赖
- `anyhow` - 错误处理
- `base64` - Base64 URL 编码（URL_SAFE_NO_PAD）
- `chrono` - UTC 时间处理
- `serde_json` - JSON 构造

### Codex 内部依赖
```
auth_fixtures.rs
├── codex_core::auth           (AuthDotJson, save_auth)
├── codex_core::token_data     (TokenData, parse_chatgpt_jwt_claims)
└── codex_app_server_protocol  (AuthMode)
```

### JWT Claims 结构

生成的 JWT payload 结构：
```json
{
  "email": "user@example.com",
  "https://api.openai.com/auth": {
    "chatgpt_plan_type": "plus",
    "chatgpt_user_id": "user-123",
    "chatgpt_account_id": "acct-456"
  }
}
```

## 风险、边界与改进建议

### 风险
1. **不安全的 JWT**：使用 `"alg": "none"` 和假签名，虽然仅用于测试，但如果被误用到生产环境会有安全风险
2. **Claims 硬编码**：OpenAI 的 claims 命名空间 `https://api.openai.com/auth` 是硬编码的，如果服务端变化需要同步更新
3. **时间敏感性**：`last_refresh` 默认使用当前时间，可能导致测试在特定时间条件下行为不一致

### 边界
- 仅支持 ChatGPT 认证模式，不支持 API key 认证
- 生成的 token 无法通过真实 OpenAI 服务的验证（因为签名无效）
- 不支持设置 token 过期时间（exp claim）

### 改进建议

1. **支持过期时间控制**：
```rust
impl ChatGptAuthFixture {
    pub fn expires_at(mut self, timestamp: i64) -> Self {
        // 允许测试过期 token 场景
    }
}
```

2. **API Key 认证支持**：
```rust
pub struct ApiKeyAuthFixture { ... }
pub fn write_api_key_auth(codex_home: &Path, api_key: &str) -> Result<()> { ... }
```

3. **Token 验证辅助**：
```rust
impl ChatGptAuthFixture {
    /// 验证生成的 token 结构是否正确
    pub fn validate(&self) -> Result<()> { ... }
}
```

4. **预定义用户配置**：
```rust
impl ChatGptAuthFixture {
    pub fn free_user() -> Self { ... }
    pub fn plus_user() -> Self { ... }
    pub fn pro_user() -> Self { ... }
}
```

5. **文档增强**：添加更多示例说明不同测试场景下的使用方法
