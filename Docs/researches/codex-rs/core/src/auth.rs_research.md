# auth.rs 深度研究文档

## 一、场景与职责

`auth.rs` 是 Codex CLI 的核心认证模块，负责管理用户身份验证的整个生命周期。该模块处理两种主要的认证方式：

1. **API Key 认证** (`ApiKeyAuth`) - 使用 OpenAI API Key 进行认证
2. **ChatGPT OAuth 认证** (`ChatgptAuth`) - 使用 ChatGPT 账号的 OAuth 令牌进行认证
3. **外部 ChatGPT Token 认证** (`ChatgptAuthTokens`) - 由外部系统管理的 ChatGPT 令牌

### 核心职责

- **认证状态管理**：加载、缓存、刷新和持久化用户认证信息
- **Token 刷新**：自动处理 OAuth access token 和 refresh token 的刷新
- **多存储后端支持**：支持文件、系统密钥环(keyring)、内存(ephemeral)三种存储方式
- **未授权恢复**：当 API 返回 401 时，自动尝试恢复认证状态
- **登录限制强制执行**：支持强制使用特定登录方式或限制特定工作空间

## 二、功能点目的

### 2.1 认证模式枚举 (`AuthMode`)

```rust
pub enum AuthMode {
    ApiKey,   // API Key 认证
    Chatgpt,  // ChatGPT OAuth 认证
}
```

用于区分内部使用的认证模式，决定 API 请求的基础 URL 和行为差异。

### 2.2 认证类型 (`CodexAuth`)

```rust
pub enum CodexAuth {
    ApiKey(ApiKeyAuth),
    Chatgpt(ChatgptAuth),
    ChatgptAuthTokens(ChatgptAuthTokens),
}
```

统一封装三种认证方式，提供统一的接口获取 token、account_id、email 等信息。

### 2.3 Token 刷新机制

- **刷新间隔**：固定 8 天 (`TOKEN_REFRESH_INTERVAL = 8`)
- **刷新端点**：`https://auth.openai.com/oauth/token`
- **可覆盖**：通过 `CODEX_REFRESH_TOKEN_URL_OVERRIDE` 环境变量可覆盖刷新 URL

### 2.4 未授权恢复状态机 (`UnauthorizedRecovery`)

当 API 返回 401 时，按以下步骤尝试恢复：

1. **Managed 模式**：
   - `Reload`：从磁盘重新加载 auth.json（如果 account_id 匹配）
   - `RefreshToken`：使用 refresh_token 向授权服务器请求新 token
   - `Done`：恢复流程结束

2. **External 模式**：
   - `ExternalRefresh`：调用外部刷新器获取新 token
   - `Done`：恢复流程结束

### 2.5 登录限制 (`enforce_login_restrictions`)

支持两种强制限制：

1. **强制登录方式** (`forced_login_method`)：
   - `Api`：强制使用 API Key
   - `Chatgpt`：强制使用 ChatGPT 登录

2. **强制工作空间** (`forced_chatgpt_workspace_id`)：
   - 限制只能使用特定 ChatGPT 工作空间账号

## 三、具体技术实现

### 3.1 关键数据结构

#### `ChatgptAuthState` - ChatGPT 认证状态

```rust
struct ChatgptAuthState {
    auth_dot_json: Arc<Mutex<Option<AuthDotJson>>>,  // 认证数据缓存
    client: CodexHttpClient,                          // HTTP 客户端
}
```

#### `AuthManager` - 认证管理器

```rust
pub struct AuthManager {
    codex_home: PathBuf,
    inner: RwLock<CachedAuth>,
    enable_codex_api_key_env: bool,
    auth_credentials_store_mode: AuthCredentialsStoreMode,
    forced_chatgpt_workspace_id: RwLock<Option<String>>,
}
```

`AuthManager` 是认证的单例管理器，提供：
- 线程安全的认证状态缓存
- Token 自动刷新
- 外部认证刷新器注册

### 3.2 认证加载优先级

`load_auth` 函数按以下优先级加载认证：

1. `CODEX_API_KEY` 环境变量（如果启用）
2. Ephemeral 存储中的外部认证 token
3. 配置的持久化存储（File/Keyring/Auto）

### 3.3 Token 刷新流程

```rust
async fn request_chatgpt_token_refresh(
    refresh_token: String,
    client: &CodexHttpClient,
) -> Result<RefreshResponse, RefreshTokenError>
```

1. 构造刷新请求（`client_id`, `grant_type=refresh_token`, `refresh_token`）
2. 发送 POST 请求到刷新端点
3. 解析响应，处理错误分类
4. 持久化新 token

### 3.4 错误分类

刷新 token 失败时，根据后端返回的错误码分类：

| 错误码 | 原因 | 用户消息 |
|--------|------|----------|
| `refresh_token_expired` | `Expired` | "Your access token could not be refreshed because your refresh token has expired..." |
| `refresh_token_reused` | `Exhausted` | "Your access token could not be refreshed because your refresh token was already used..." |
| `refresh_token_invalidated` | `Revoked` | "Your access token could not be refreshed because your refresh token was revoked..." |
| 其他 | `Other` | "Your access token could not be refreshed..." |

### 3.5 存储后端抽象

通过 `AuthStorageBackend` trait 抽象存储：

```rust
pub(super) trait AuthStorageBackend: Debug + Send + Sync {
    fn load(&self) -> std::io::Result<Option<AuthDotJson>>;
    fn save(&self, auth: &AuthDotJson) -> std::io::Result<()>;
    fn delete(&self) -> std::io::Result<bool>;
}
```

实现包括：
- `FileAuthStorage`：文件存储（`$CODEX_HOME/auth.json`）
- `KeyringAuthStorage`：系统密钥环存储
- `AutoAuthStorage`：自动选择（优先 keyring）
- `EphemeralAuthStorage`：内存存储（全局 HashMap）

## 四、关键代码路径与文件引用

### 4.1 核心文件结构

```
codex-rs/core/src/
├── auth.rs                 # 主认证逻辑（本文件）
├── auth/
│   └── storage.rs          # 存储后端实现
├── auth_env_telemetry.rs   # 认证环境遥测
├── auth_tests.rs           # 单元测试
├── token_data.rs           # Token 数据结构
├── error.rs                # 错误类型定义
└── util.rs                 # 工具函数（try_parse_error_message）
```

### 4.2 关键代码路径

#### 认证加载流程

```
AuthManager::new()
  └── load_auth()
      ├── read_codex_api_key_from_env()     # 检查环境变量
      ├── create_auth_storage(Ephemeral)    # 检查临时存储
      └── create_auth_storage(configured)   # 检查持久化存储
          └── CodexAuth::from_auth_dot_json()
```

#### Token 刷新流程

```
AuthManager::auth() 
  └── refresh_if_stale()
      └── refresh_and_persist_chatgpt_token()
          └── request_chatgpt_token_refresh()
              └── persist_tokens()
```

#### 401 恢复流程

```
UnauthorizedRecovery::next()
  ├── Reload -> reload_if_account_id_matches()
  ├── RefreshToken -> refresh_token_from_authority()
  └── ExternalRefresh -> refresh_external_auth()
```

### 4.3 关键常量

| 常量 | 值 | 说明 |
|------|-----|------|
| `TOKEN_REFRESH_INTERVAL` | 8 (天) | Token 刷新间隔 |
| `CLIENT_ID` | `"app_EMoamEEZ73f0CkXaXp7hrann"` | OAuth client ID |
| `REFRESH_TOKEN_URL` | `https://auth.openai.com/oauth/token` | 刷新端点 |
| `REFRESH_TOKEN_URL_OVERRIDE_ENV_VAR` | `CODEX_REFRESH_TOKEN_URL_OVERRIDE` | 覆盖环境变量 |
| `OPENAI_API_KEY_ENV_VAR` | `OPENAI_API_KEY` | API Key 环境变量 |
| `CODEX_API_KEY_ENV_VAR` | `CODEX_API_KEY` | Codex API Key 环境变量 |

## 五、依赖与外部交互

### 5.1 内部依赖

| 模块 | 用途 |
|------|------|
| `auth::storage` | 存储后端实现 |
| `token_data` | Token 数据结构（`TokenData`, `IdTokenInfo`） |
| `error` | 错误类型（`RefreshTokenFailedError`, `RefreshTokenFailedReason`） |
| `util` | `try_parse_error_message` 错误解析 |
| `config::Config` | 配置信息（`forced_login_method`, `forced_chatgpt_workspace_id`） |
| `default_client` | 创建 HTTP 客户端 |

### 5.2 外部 crate 依赖

| Crate | 用途 |
|-------|------|
| `async_trait` | 异步 trait 支持 |
| `chrono` | 时间处理（`DateTime<Utc>`） |
| `reqwest` | HTTP 客户端 |
| `serde` | 序列化/反序列化 |
| `thiserror` | 错误定义 |
| `tracing` | 日志追踪 |
| `codex_app_server_protocol` | API 协议类型（`AuthMode`） |
| `codex_otel` | 遥测（`TelemetryAuthMode`） |
| `codex_client` | HTTP 客户端（`CodexHttpClient`） |
| `codex_protocol` | 协议类型（`ForcedLoginMethod`, `PlanType`） |
| `codex_keyring_store` | 密钥环存储 |

### 5.3 外部系统交互

1. **OAuth 授权服务器**：`auth.openai.com/oauth/token`
   - 刷新 access token
   - 返回新的 id_token, access_token, refresh_token

2. **系统密钥环**：通过 `codex_keyring_store`
   - 服务名：`"Codex Auth"`
   - 键：基于 codex_home 路径的 SHA256 哈希（前16位）

## 六、风险、边界与改进建议

### 6.1 已知风险

1. **Token 刷新竞争条件**
   - 多个进程同时尝试刷新可能导致 refresh token 被标记为 reused
   - 缓解：`reload_if_account_id_matches` 在刷新前检查磁盘状态

2. **外部认证刷新器缺失**
   - `ChatgptAuthTokens` 模式需要外部刷新器，否则 401 无法恢复
   - 检查：`has_external_auth_refresher()`

3. **环境变量 API Key 优先级**
   - `CODEX_API_KEY` 会覆盖所有其他认证方式
   - 可能导致用户困惑

4. **Token 过期检测**
   - 当前使用固定 8 天刷新间隔，而非解析 JWT 的 exp 字段
   - TODO 注释：`// TODO(pakrym): use token exp field to check for expiration instead`

### 6.2 边界情况

1. **Account ID 不匹配**
   - 如果磁盘上的 auth.json 属于不同账号，reload 会跳过
   - 防止跨账号 token 混淆

2. **强制工作空间不匹配**
   - 如果当前 token 不属于强制工作空间，自动登出
   - 调用 `logout_all_stores` 清除所有存储

3. **Ephemeral 存储**
   - 外部 token 始终存储在 ephemeral 中
   - 进程退出后丢失，需要外部系统重新提供

### 6.3 改进建议

1. **JWT exp 字段解析**
   - 实现基于 exp 字段的精确过期检测
   - 避免固定 8 天间隔导致的过早/过晚刷新

2. **刷新退避策略**
   - 当前刷新失败立即返回错误
   - 建议增加指数退避重试

3. **Token 刷新事件通知**
   - 当前刷新后仅内部更新
   - 建议增加事件通知机制，让 UI 感知认证状态变化

4. **存储迁移工具**
   - 用户可能需要在 File/Keyring 之间迁移
   - 建议提供显式迁移命令

5. **刷新 token 加密**
   - 当前 refresh token 以明文存储
   - 建议增加可选的加密层

6. **测试覆盖率**
   - 外部认证刷新器 (`ExternalAuthRefresher`) 的集成测试较少
   - 建议增加 mock 外部刷新器的测试
