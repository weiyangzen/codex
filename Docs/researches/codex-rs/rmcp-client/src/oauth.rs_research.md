# oauth.rs 研究文档

## 场景与职责

`oauth.rs` 是 `codex-rmcp-client` crate 中负责 MCP OAuth 凭证管理的核心模块。该模块实现了 OAuth 2.0 凭证的安全存储、读取、刷新和删除功能，支持多种存储后端（系统密钥环和本地文件）。

核心职责：
1. **凭证安全存储**: 使用操作系统密钥环服务存储敏感凭证
2. **存储回退机制**: 密钥环不可用时自动回退到本地文件存储
3. **凭证生命周期管理**: 加载、保存、删除、刷新 OAuth tokens
4. **自动刷新管理**: 检测 token 过期并触发刷新
5. **跨平台支持**: 支持 macOS、Windows、Linux/FreeBSD/OpenBSD

## 功能点目的

### 1. 存储后端架构

```
┌─────────────────────────────────────────────────────────────┐
│                    OAuthCredentialsStoreMode                 │
├─────────────────────────────────────────────────────────────┤
│  Auto (默认)  │  优先 Keyring，失败回退到 File                │
│  File         │  仅使用文件存储 (CODEX_HOME/.credentials.json)│
│  Keyring      │  仅使用密钥环，失败报错                       │
└─────────────────────────────────────────────────────────────┘
```

### 2. 凭证数据结构

```rust
pub struct StoredOAuthTokens {
    pub server_name: String,           // MCP 服务器名称
    pub url: String,                   // 服务器 URL
    pub client_id: String,             // OAuth client ID
    pub token_response: WrappedOAuthTokenResponse,  // Token 响应
    pub expires_at: Option<u64>,       // 过期时间戳（毫秒）
}
```

### 3. 密钥环服务映射

| 操作系统 | 密钥环服务 |
|----------|------------|
| macOS | macOS Keychain (apple-native) |
| Windows | Windows Credential Manager (windows-native) |
| Linux | DBus Secret Service + keyutils (linux-native-async-persistent) |
| FreeBSD/OpenBSD | DBus Secret Service (sync-secret-service) |

## 具体技术实现

### 核心常量

```rust
const KEYRING_SERVICE: &str = "Codex MCP Credentials";  // 密钥环服务名
const REFRESH_SKEW_MILLIS: u64 = 30_000;                // 刷新提前量（30秒）
const FALLBACK_FILENAME: &str = ".credentials.json";    // 回退文件名
const MCP_SERVER_TYPE: &str = "http";                   // 服务器类型标识
```

### 存储模式枚举

```rust
#[derive(Debug, Default, Copy, Clone, PartialEq, Eq, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "lowercase")]
pub enum OAuthCredentialsStoreMode {
    #[default]
    Auto,     // 自动选择：Keyring > File
    File,     // 强制文件存储
    Keyring,  // 强制密钥环
}
```

### 凭证加载流程

```rust
pub(crate) fn load_oauth_tokens(
    server_name: &str,
    url: &str,
    store_mode: OAuthCredentialsStoreMode,
) -> Result<Option<StoredOAuthTokens>> {
    match store_mode {
        Auto => load_from_keyring_with_fallback(),
        File => load_from_file(),
        Keyring => load_from_keyring(),
    }
}
```

### 存储键计算

使用 SHA-256 哈希生成唯一存储键：

```rust
fn compute_store_key(server_name: &str, server_url: &str) -> Result<String> {
    let mut payload = JsonMap::new();
    payload.insert("type".to_string(), Value::String(MCP_SERVER_TYPE.to_string()));
    payload.insert("url".to_string(), Value::String(server_url.to_string()));
    payload.insert("headers".to_string(), Value::Object(JsonMap::new()));

    let truncated = sha_256_prefix(&Value::Object(payload))?;
    Ok(format!("{server_name}|{truncated}"))
}

fn sha_256_prefix(value: &Value) -> Result<String> {
    let serialized = serde_json::to_string(&value)?;
    let mut hasher = Sha256::new();
    hasher.update(serialized.as_bytes());
    let digest = hasher.finalize();
    let hex = format!("{digest:x}");
    Ok(hex[..16].to_string())  // 取前16字符
}
```

**键格式**: `{server_name}|{sha256_prefix_16}`

示例: `my-server|a1b2c3d4e5f67890`

### OAuthPersistor - 运行时凭证管理

```rust
pub(crate) struct OAuthPersistor {
    inner: Arc<OAuthPersistorInner>,
}

struct OAuthPersistorInner {
    server_name: String,
    url: String,
    authorization_manager: Arc<Mutex<AuthorizationManager>>,
    store_mode: OAuthCredentialsStoreMode,
    last_credentials: Mutex<Option<StoredOAuthTokens>>,
}
```

**核心方法**：

#### `persist_if_needed()` - 条件持久化

```rust
pub(crate) async fn persist_if_needed(&self) -> Result<()> {
    // 1. 从 AuthorizationManager 获取最新凭证
    // 2. 与 last_credentials 比较
    // 3. 如果不同，保存到存储
    // 4. 如果凭证被删除，从存储移除
}
```

**优化点**: 通过比较 `WrappedOAuthTokenResponse` 避免不必要的写入

#### `refresh_if_needed()` - 条件刷新

```rust
pub(crate) async fn refresh_if_needed(&self) -> Result<()> {
    // 1. 检查 expires_at 是否需要刷新（提前30秒）
    // 2. 调用 AuthorizationManager::refresh_token()
    // 3. 刷新成功后调用 persist_if_needed()
}
```

### 文件回退存储格式

```rust
type FallbackFile = BTreeMap<String, FallbackTokenEntry>;

struct FallbackTokenEntry {
    server_name: String,
    server_url: String,
    client_id: String,
    access_token: String,
    expires_at: Option<u64>,
    refresh_token: Option<String>,
    scopes: Vec<String>,
}
```

**文件位置**: `CODEX_HOME/.credentials.json`

**权限设置** (Unix):
```rust
let perms = fs::Permissions::from_mode(0o600);
fs::set_permissions(&path, perms)?;
```

### 过期时间管理

```rust
fn compute_expires_at_millis(response: &OAuthTokenResponse) -> Option<u64> {
    let expires_in = response.expires_in()?;
    let now = SystemTime::now().duration_since(UNIX_EPOCH).ok()?;
    let expiry = now.checked_add(expires_in)?;
    Some(expiry.as_millis() as u64)
}

fn token_needs_refresh(expires_at: Option<u64>) -> bool {
    let expires_at = expires_at?;
    let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default();
    now.as_millis() as u64 + REFRESH_SKEW_MILLIS >= expires_at
}
```

## 关键代码路径与文件引用

### 内部调用关系

```
oauth.rs
├── 被 lib.rs 导出
│   ├── OAuthCredentialsStoreMode (pub)
│   ├── StoredOAuthTokens (pub)
│   ├── WrappedOAuthTokenResponse (pub)
│   ├── delete_oauth_tokens (pub)
│   ├── load_oauth_tokens (pub(crate))
│   └── save_oauth_tokens (pub)
├── 被 auth_status.rs 调用
│   └── has_oauth_tokens()
├── 被 perform_oauth_login.rs 调用
│   ├── save_oauth_tokens()
│   └── compute_expires_at_millis()
└── 被 rmcp_client.rs 使用
    ├── OAuthPersistor
    ├── load_oauth_tokens()
    └── OAuthCredentialsStoreMode
```

### 外部依赖

| Crate | 用途 |
|-------|------|
| `codex_keyring_store` | 密钥环存储抽象 |
| `codex_utils_home_dir` | 获取 CODEX_HOME |
| `keyring` | 系统密钥环访问 |
| `oauth2` | OAuth 2.0 类型（AccessToken, RefreshToken 等） |
| `rmcp` | `AuthorizationManager`, `OAuthTokenResponse` |
| `sha2` | SHA-256 哈希 |

### 存储流程图

```
保存凭证
├── Keyring 模式
│   ├── 序列化 StoredOAuthTokens
│   ├── 计算存储键
│   ├── 保存到密钥环
│   └── 删除文件回退（如果存在）
└── File 模式（或 Keyring 失败回退）
    ├── 读取现有 .credentials.json
    ├── 更新/插入条目
    └── 写回文件（设置 0o600 权限）

加载凭证
├── Keyring 模式
│   ├── 尝试密钥环读取
│   ├── 失败/不存在 → 尝试文件回退
│   └── 恢复 expires_in 从 expires_at
└── File 模式
    └── 直接读取 .credentials.json

删除凭证
├── 计算存储键
├── 删除密钥环条目
└── 删除文件条目
```

## 依赖与外部交互

### 与 rmcp SDK 的集成

`OAuthPersistor` 与 `rmcp::transport::auth::AuthorizationManager` 协作：

```rust
// 从 AuthorizationManager 获取凭证
let (client_id, maybe_credentials) = guard.get_credentials().await?;

// 刷新 token
guard.refresh_token().await?;
```

### 与系统密钥环的交互

使用 `keyring` crate 的跨平台抽象：

```rust
// 保存
keyring_store.save(KEYRING_SERVICE, &key, &serialized)?;

// 加载
keyring_store.load(KEYRING_SERVICE, &key)?;

// 删除
keyring_store.delete(KEYRING_SERVICE, &key)?;
```

## 风险、边界与改进建议

### 安全风险

1. **文件权限竞争条件**: 设置 0o600 权限是在写入后进行的，存在短暂窗口
   - 建议：使用原子写入模式

2. **密钥环回退**: Auto 模式下密钥环失败自动回退到文件，可能不符合用户安全预期
   - 建议：增加警告日志或确认机制

3. **凭证内存驻留**: `WrappedOAuthTokenResponse` 包含敏感数据，内存中无额外保护

### 边界情况

1. **时钟回拨**: `token_needs_refresh` 依赖系统时间，时钟回拨可能导致误判
2. **expires_at 溢出**: `compute_expires_at_millis` 处理了 u128 到 u64 的溢出（返回 u64::MAX）
3. **空文件处理**: `.credentials.json` 为空时返回空 BTreeMap

### 测试覆盖

| 测试用例 | 描述 |
|----------|------|
| `load_oauth_tokens_reads_from_keyring_when_available` | 密钥环读取 |
| `load_oauth_tokens_falls_back_when_missing_in_keyring` | 密钥环缺失回退 |
| `load_oauth_tokens_falls_back_when_keyring_errors` | 密钥环错误回退 |
| `save_oauth_tokens_prefers_keyring_when_available` | 密钥环保存优先 |
| `save_oauth_tokens_writes_fallback_when_keyring_fails` | 密钥环失败回退 |
| `delete_oauth_tokens_removes_all_storage` | 全存储删除 |
| `refresh_expires_in_from_timestamp_restores_future_durations` | 过期时间恢复 |
| `refresh_expires_in_from_timestamp_clears_expired_tokens` | 过期 token 清除 |

### 改进建议

1. **加密文件存储**: 回退文件可使用用户主密码加密
2. **凭证迁移工具**: 提供 Keyring ↔ File 的迁移命令
3. **过期通知**: 在 token 即将过期时主动通知用户
4. **并发控制**: 文件存储添加文件锁防止并发写入冲突
5. **存储统计**: 添加指标收集（存储操作次数、失败率等）

### 代码质量

1. **复杂函数拆分**: `persist_if_needed()` 超过 50 行，可提取子函数
2. **错误上下文**: 已使用 `anyhow::Context` 增强错误信息
3. **文档完善**: 模块级文档详细说明了各平台密钥环实现
