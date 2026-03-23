# token_data.rs 研究文档

## 场景与职责

`token_data.rs` 负责处理 Codex 的**认证令牌数据**，核心职责包括：

1. **JWT 解析**：从 `auth.json` 中解析 ID Token（JWT 格式），提取用户身份信息
2. **订阅计划识别**：识别用户的 ChatGPT 订阅类型（Free/Plus/Pro/Team/Business/Enterprise/Edu）
3. **工作区账户检测**：判断用户是否属于组织/工作区账户
4. **序列化支持**：支持 serde 序列化/反序列化，用于配置持久化

该模块是认证系统的数据层，为上层提供结构化的用户身份信息。

## 功能点目的

### 1. TokenData 结构体

```rust
#[derive(Deserialize, Serialize, Clone, Debug, PartialEq, Default)]
pub struct TokenData {
    #[serde(deserialize_with = "deserialize_id_token", serialize_with = "serialize_id_token")]
    pub id_token: IdTokenInfo,  // 从 JWT 解析的扁平信息
    pub access_token: String,    // JWT 访问令牌
    pub refresh_token: String,   // 刷新令牌
    pub account_id: Option<String>,
}
```

### 2. IdTokenInfo 结构体

```rust
#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize, Deserialize)]
pub struct IdTokenInfo {
    pub email: Option<String>,
    pub(crate) chatgpt_plan_type: Option<PlanType>,  // 订阅计划
    pub chatgpt_user_id: Option<String>,
    pub chatgpt_account_id: Option<String>,
    pub raw_jwt: String,  // 原始 JWT 字符串
}
```

### 3. PlanType 枚举

```rust
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(untagged)]
pub(crate) enum PlanType {
    Known(KnownPlan),    // 已知计划类型
    Unknown(String),     // 未知/新计划类型（前向兼容）
}
```

### 4. KnownPlan 枚举

```rust
#[serde(rename_all = "lowercase")]
pub(crate) enum KnownPlan {
    Free, Go, Plus, Pro, Team, Business, Enterprise, Edu,
}
```

## 具体技术实现

### JWT 解析流程

```rust
pub fn parse_chatgpt_jwt_claims(jwt: &str) -> Result<IdTokenInfo, IdTokenInfoError> {
    // 1. 分割 JWT：header.payload.signature
    let mut parts = jwt.split('.');
    let (_header_b64, payload_b64, _sig_b64) = match (parts.next(), parts.next(), parts.next()) {
        (Some(h), Some(p), Some(s)) if !h.is_empty() && !p.is_empty() && !s.is_empty() => (h, p, s),
        _ => return Err(IdTokenInfoError::InvalidFormat),
    };

    // 2. Base64 URL 解码 payload
    let payload_bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(payload_b64)?;
    
    // 3. JSON 反序列化
    let claims: IdClaims = serde_json::from_slice(&payload_bytes)?;
    
    // 4. 提取字段（支持多路径）
    let email = claims.email.or_else(|| claims.profile.and_then(|p| p.email));
    
    // 5. 构建 IdTokenInfo
    Ok(IdTokenInfo { ... })
}
```

### 计划类型解析

```rust
pub(crate) fn from_raw_value(raw: &str) -> Self {
    match raw.to_ascii_lowercase().as_str() {
        "free" => Self::Known(KnownPlan::Free),
        "go" => Self::Known(KnownPlan::Go),
        "plus" => Self::Known(KnownPlan::Plus),
        "pro" => Self::Known(KnownPlan::Pro),
        "team" => Self::Known(KnownPlan::Team),
        "business" => Self::Known(KnownPlan::Business),
        "enterprise" => Self::Known(KnownPlan::Enterprise),
        "education" | "edu" => Self::Known(KnownPlan::Edu),
        _ => Self::Unknown(raw.to_string()),  // 前向兼容
    }
}
```

### 工作区账户检测

```rust
pub fn is_workspace_account(&self) -> bool {
    matches!(
        self.chatgpt_plan_type,
        Some(PlanType::Known(
            KnownPlan::Team | KnownPlan::Business | KnownPlan::Enterprise | KnownPlan::Edu
        ))
    )
}
```

### 自定义序列化

```rust
// 反序列化：JWT 字符串 -> IdTokenInfo
fn deserialize_id_token<'de, D>(deserializer: D) -> Result<IdTokenInfo, D::Error>
where D: serde::Deserializer<'de>,
{
    let s = String::deserialize(deserializer)?;
    parse_chatgpt_jwt_claims(&s).map_err(serde::de::Error::custom)
}

// 序列化：IdTokenInfo -> JWT 字符串（保留原始值）
fn serialize_id_token<S>(id_token: &IdTokenInfo, serializer: S) -> Result<S::Ok, S::Error>
where S: serde::Serializer,
{
    serializer.serialize_str(&id_token.raw_jwt)
}
```

## 关键代码路径与文件引用

### JWT Claims 结构

```rust
#[derive(Deserialize)]
struct IdClaims {
    #[serde(default)]
    email: Option<String>,
    #[serde(rename = "https://api.openai.com/profile", default)]
    profile: Option<ProfileClaims>,
    #[serde(rename = "https://api.openai.com/auth", default)]
    auth: Option<AuthClaims>,
}

#[derive(Deserialize)]
struct AuthClaims {
    #[serde(default)]
    chatgpt_plan_type: Option<PlanType>,
    #[serde(default)]
    chatgpt_user_id: Option<String>,
    #[serde(default)]
    user_id: Option<String>,  // 备用字段
    #[serde(default)]
    chatgpt_account_id: Option<String>,
}
```

### 错误类型

```rust
#[derive(Debug, Error)]
pub enum IdTokenInfoError {
    #[error("invalid ID token format")]
    InvalidFormat,
    #[error(transparent)]
    Base64(#[from] base64::DecodeError),
    #[error(transparent)]
    Json(#[from] serde_json::Error),
}
```

### 外部依赖

| crate | 用途 |
|-------|------|
| `base64` | JWT payload 解码 |
| `serde` | 序列化/反序列化 |
| `thiserror` | 错误定义 |

## 依赖与外部交互

### 调用方

- **AuthManager**: 存储和提供 `TokenData`
- **配置系统**: 持久化认证信息
- **遥测系统**: 上报订阅类型等匿名统计

### JWT 来源

- OpenAI 认证服务返回的 `id_token`
- 存储在 `~/.codex/auth.json` 中

## 风险、边界与改进建议

### 安全风险

1. **JWT 验证**：当前仅解析不验证签名，依赖传输层安全
2. **敏感信息**：`raw_jwt` 包含完整令牌，日志中可能泄露

### 边界情况

1. **非标准 JWT**：缺少部分字段时优雅降级（使用 `#[serde(default)]`）
2. **新计划类型**：`Unknown(String)` 变体确保前向兼容
3. **大小写处理**：计划类型统一转小写匹配

### 改进建议

1. **JWT 验证**：考虑添加签名验证（需要公钥基础设施）
2. **字段扩展**：`user_id` 作为 `chatgpt_user_id` 的备用，逻辑可简化
3. **计划类型显示**：`get_chatgpt_plan_type()` 返回字符串，建议返回结构化类型
4. **测试覆盖**：增加无效 JWT 格式、特殊字符、超大 payload 的测试

### 代码统计

- 代码行数：179 行
- 结构体：5 个
- 枚举：3 个
- 错误类型：1 个
