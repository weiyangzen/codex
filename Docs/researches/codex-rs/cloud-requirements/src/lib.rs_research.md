# Cloud Requirements 模块研究文档

## 文件信息

- **目标文件**: `codex-rs/cloud-requirements/src/lib.rs`
- **Crate 名称**: `codex-cloud-requirements`
- **文件行数**: 1930 行（含测试代码）
- **主要功能**: 从云端后端获取 `requirements.toml` 配置数据，作为本地文件系统加载配置的替代方案

---

## 1. 场景与职责

### 1.1 核心场景

Cloud Requirements 模块解决的核心场景是：**企业级用户（ChatGPT Business/Enterprise）的集中式配置管理**。

在企业环境中，IT 管理员需要：
1. 统一管控员工使用的 Codex 工具配置
2. 强制执行安全策略（如审批策略、沙箱模式）
3. 集中管理 MCP 服务器、网络代理等设置
4. 确保配置实时更新且不可被用户覆盖

### 1.2 模块职责

| 职责 | 说明 |
|------|------|
| **云端配置获取** | 从后端 API (`/wham/config/requirements` 或 `/api/codex/config/requirements`) 获取企业配置 |
| **身份验证** | 仅对 ChatGPT Business/Enterprise 账户启用云端配置获取 |
| **本地缓存** | 将获取的配置缓存到本地文件系统，支持离线使用 |
| **缓存刷新** | 后台定期刷新缓存（每 5 分钟检查一次） |
| **失败处理** | 对企业用户，获取失败时"fail closed"（拒绝加载配置而非继续无配置运行） |
| **安全验证** | 使用 HMAC-SHA256 签名验证缓存文件完整性，防止篡改 |

### 1.3 目标用户

- **Business 账户** (CBP - ChatGPT Business Plan)
- **Enterprise 账户** (Enterprise ChatGPT)
- 普通用户（Plus/Pro/Free）不启用此功能

---

## 2. 功能点目的

### 2.1 主要功能点

#### 2.1.1 配置获取与解析 (`fetch_requirements`)

```rust
#[async_trait]
trait RequirementsFetcher: Send + Sync {
    async fn fetch_requirements(
        &self,
        auth: &CodexAuth,
    ) -> Result<Option<String>, FetchAttemptError>;
}
```

**目的**: 
- 通过后端客户端获取 `requirements.toml` 内容
- 支持返回 `None` 表示该账户无云端配置
- 错误时返回详细的错误类型（可重试/未授权）

#### 2.1.2 重试与认证恢复 (`fetch_with_retries`)

**目的**:
- 实现指数退避重试机制（最多 5 次尝试）
- 处理 401 未授权错误时自动尝试刷新 Token
- 区分临时错误（网络问题）和永久错误（认证失效）

#### 2.1.3 本地缓存管理

**缓存文件**: `$CODEX_HOME/cloud-requirements-cache.json`

**目的**:
- 允许离线时使用最近的有效配置
- 缓存 TTL: 30 分钟
- 缓存刷新间隔: 5 分钟（后台任务）

**缓存结构**:
```rust
struct CloudRequirementsCacheFile {
    signed_payload: CloudRequirementsCacheSignedPayload,
    signature: String,  // HMAC-SHA256 签名
}

struct CloudRequirementsCacheSignedPayload {
    cached_at: DateTime<Utc>,
    expires_at: DateTime<Utc>,
    chatgpt_user_id: Option<String>,
    account_id: Option<String>,
    contents: Option<String>,  // TOML 内容
}
```

#### 2.1.4 安全签名验证

**目的**: 防止本地缓存被恶意篡改

```rust
const CLOUD_REQUIREMENTS_CACHE_WRITE_HMAC_KEY: &[u8] =
    b"codex-cloud-requirements-cache-v3-064f8542-75b4-494c-a294-97d3ce597271";
```

- 使用 HMAC-SHA256 对缓存内容进行签名
- 支持密钥轮换（`CLOUD_REQUIREMENTS_CACHE_READ_HMAC_KEYS` 数组）
- 验证失败时丢弃缓存，重新从云端获取

#### 2.1.5 后台刷新任务

**目的**: 保持缓存数据新鲜

```rust
async fn refresh_cache_in_background(&self) {
    loop {
        sleep(CLOUD_REQUIREMENTS_CACHE_REFRESH_INTERVAL).await;
        // 尝试刷新缓存...
    }
}
```

### 2.2 配置加载流程

```
┌─────────────────────────────────────────────────────────────┐
│                     配置加载流程                              │
├─────────────────────────────────────────────────────────────┤
│  1. 检查用户身份                                              │
│     └─> 非 ChatGPT 认证 → 跳过云端配置                         │
│     └─> 非 Business/Enterprise → 跳过云端配置                  │
│                                                             │
│  2. 尝试读取本地缓存                                          │
│     └─> 缓存存在且未过期且签名有效 → 使用缓存                  │
│     └─> 否则 → 继续步骤 3                                     │
│                                                             │
│  3. 从云端获取配置（带重试）                                   │
│     └─> 成功 → 保存到缓存 → 返回配置                          │
│     └─> 失败 → 根据错误类型处理                                │
│         ├─> 超时/网络错误 → 返回错误（企业用户 fail closed）  │
│         ├─> 认证错误 → 尝试刷新 Token → 重试                   │
│         └─> 其他错误 → 返回错误                               │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 错误类型

```rust
#[derive(Clone, Debug, Eq, PartialEq)]
enum FetchAttemptError {
    Retryable(RetryableFailureKind),  // 可重试错误
    Unauthorized {                    // 认证错误
        status_code: Option<u16>,
        message: String,
    },
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum RetryableFailureKind {
    BackendClientInit,           // 后端客户端初始化失败
    Request { status_code: Option<u16> },  // HTTP 请求失败
}
```

#### 3.1.2 缓存加载状态

```rust
enum CacheLoadStatus {
    AuthIdentityIncomplete,      // 认证身份不完整
    CacheFileNotFound,           // 缓存文件不存在
    CacheReadFailed(String),     // 读取失败
    CacheParseFailed(String),    // 解析失败
    CacheSignatureInvalid,       // 签名验证失败
    CacheIdentityIncomplete,     // 缓存身份不完整
    CacheIdentityMismatch,       // 身份不匹配（用户切换）
    CacheExpired,                // 缓存过期
}
```

#### 3.1.3 服务结构

```rust
struct CloudRequirementsService {
    auth_manager: Arc<AuthManager>,
    fetcher: Arc<dyn RequirementsFetcher>,
    cache_path: PathBuf,
    timeout: Duration,
}
```

### 3.2 关键流程

#### 3.2.1 初始化流程 (`cloud_requirements_loader`)

```rust
pub fn cloud_requirements_loader(
    auth_manager: Arc<AuthManager>,
    chatgpt_base_url: String,
    codex_home: PathBuf,
) -> CloudRequirementsLoader {
    let service = CloudRequirementsService::new(
        auth_manager,
        Arc::new(BackendRequirementsFetcher::new(chatgpt_base_url)),
        codex_home,
        CLOUD_REQUIREMENTS_TIMEOUT,  // 15 秒
    );
    
    // 启动两个异步任务
    let task = tokio::spawn(async move { service.fetch_with_timeout().await });
    let refresh_task = tokio::spawn(async move { 
        refresh_service.refresh_cache_in_background().await 
    });
    
    // 保存刷新任务句柄（支持替换旧任务）
    let mut refresher_guard = refresher_task_slot().lock().unwrap_or_else(|err| {
        tracing::warn!("cloud requirements refresher task slot was poisoned");
        err.into_inner()
    });
    if let Some(existing_task) = refresher_guard.replace(refresh_task) {
        existing_task.abort();
    }
    
    CloudRequirementsLoader::new(async move { task.await? })
}
```

#### 3.2.2 带超时的获取 (`fetch_with_timeout`)

```rust
async fn fetch_with_timeout(
    &self,
) -> Result<Option<ConfigRequirementsToml>, CloudRequirementsLoadError> {
    let _timer = codex_otel::start_global_timer(
        "codex.cloud_requirements.fetch.duration_ms", &[]
    );
    
    let fetch_result = timeout(self.timeout, self.fetch()).await
        .map_err(|_| CloudRequirementsLoadError::new(
            CloudRequirementsLoadErrorCode::Timeout,
            None,
            format!("timed out waiting for cloud requirements after {}s", self.timeout.as_secs()),
        ))?;
    
    // 记录指标和日志...
    Ok(result)
}
```

#### 3.2.3 带重试的获取 (`fetch_with_retries`)

核心逻辑：
1. 最多 5 次尝试
2. 可重试错误使用指数退避延迟
3. 401 错误触发认证恢复流程
4. 认证恢复成功后使用新 Token 重试

```rust
async fn fetch_with_retries(
    &self,
    mut auth: CodexAuth,
    trigger: &'static str,
) -> Result<Option<ConfigRequirementsToml>, CloudRequirementsLoadError> {
    let mut attempt = 1;
    let mut auth_recovery = self.auth_manager.unauthorized_recovery();
    
    while attempt <= CLOUD_REQUIREMENTS_MAX_ATTEMPTS {
        match self.fetcher.fetch_requirements(&auth).await {
            Ok(contents) => { /* 成功处理 */ },
            Err(FetchAttemptError::Retryable(status)) => { /* 重试逻辑 */ },
            Err(FetchAttemptError::Unauthorized { .. }) => {
                // 尝试认证恢复
                if auth_recovery.has_next() {
                    match auth_recovery.next().await {
                        Ok(_) => { auth = refreshed_auth; continue; }
                        Err(RefreshTokenError::Permanent(failed)) => { /* 返回错误 */ }
                        Err(RefreshTokenError::Transient(recovery_err)) => { /* 重试 */ }
                    }
                }
            }
        }
    }
}
```

#### 3.2.4 缓存保存 (`save_cache`)

```rust
async fn save_cache(
    &self,
    chatgpt_user_id: Option<String>,
    account_id: Option<String>,
    contents: Option<String>,
) -> Result<(), CloudRequirementsError> {
    let now = Utc::now();
    let expires_at = now
        .checked_add_signed(ChronoDuration::from_std(CLOUD_REQUIREMENTS_CACHE_TTL)?)
        .ok_or(CloudRequirementsError::CacheWrite)?;
    
    let signed_payload = CloudRequirementsCacheSignedPayload {
        cached_at: now,
        expires_at,
        chatgpt_user_id,
        account_id,
        contents,
    };
    
    // 序列化并签名
    let payload_bytes = cache_payload_bytes(&signed_payload)?;
    let signature = sign_cache_payload(&payload_bytes)?;
    
    let cache_file = CloudRequirementsCacheFile {
        signed_payload,
        signature,
    };
    
    // 写入文件
    fs::write(&self.cache_path, serde_json::to_vec_pretty(&cache_file)?).await?;
    Ok(())
}
```

### 3.3 协议与 API

#### 3.3.1 后端 API 端点

```rust
// codex-backend-client/src/client.rs
pub async fn get_config_requirements_file(
    &self,
) -> std::result::Result<ConfigFileResponse, RequestError> {
    let url = match self.path_style {
        PathStyle::CodexApi => format!("{}/api/codex/config/requirements", self.base_url),
        PathStyle::ChatGptApi => format!("{}/wham/config/requirements", self.base_url),
    };
    let req = self.http.get(&url).headers(self.headers());
    let (body, ct) = self.exec_request_detailed(req, "GET", &url).await?;
    self.decode_json::<ConfigFileResponse>(&url, &ct, &body)
        .map_err(RequestError::from)
}
```

#### 3.3.2 响应类型

```rust
// 来自 codex_backend_openapi_models
pub struct ConfigFileResponse {
    pub contents: Option<String>,  // TOML 格式的配置内容
}
```

### 3.4 常量配置

```rust
const CLOUD_REQUIREMENTS_TIMEOUT: Duration = Duration::from_secs(15);           // 请求超时
const CLOUD_REQUIREMENTS_MAX_ATTEMPTS: usize = 5;                               // 最大重试次数
const CLOUD_REQUIREMENTS_CACHE_FILENAME: &str = "cloud-requirements-cache.json"; // 缓存文件名
const CLOUD_REQUIREMENTS_CACHE_REFRESH_INTERVAL: Duration = Duration::from_secs(5 * 60); // 刷新间隔
const CLOUD_REQUIREMENTS_CACHE_TTL: Duration = Duration::from_secs(30 * 60);    // 缓存有效期
```

---

## 4. 关键代码路径与文件引用

### 4.1 本模块文件

| 文件 | 说明 |
|------|------|
| `codex-rs/cloud-requirements/src/lib.rs` | 主实现文件，包含所有核心逻辑和测试 |
| `codex-rs/cloud-requirements/Cargo.toml` | 模块依赖配置 |

### 4.2 调用方（使用者）

| 文件 | 使用方式 |
|------|----------|
| `codex-rs/tui/src/lib.rs` | `cloud_requirements_loader()` 初始化，传递给配置加载 |
| `codex-rs/exec/src/lib.rs` | `cloud_requirements_loader()` 初始化 |
| `codex-rs/app-server/src/lib.rs` | `cloud_requirements_loader()` 初始化 |
| `codex-rs/tui_app_server/src/lib.rs` | `cloud_requirements_loader_for_storage()` 初始化 |

### 4.3 被调用方（依赖）

| 文件 | 依赖内容 |
|------|----------|
| `codex-rs/backend-client/src/client.rs` | `BackendClient::get_config_requirements_file()` |
| `codex-rs/backend-client/src/types.rs` | `ConfigFileResponse` 类型 |
| `codex-rs/core/src/config_loader/mod.rs` | `CloudRequirementsLoader` 类型定义（实际在 config crate） |
| `codex-rs/config/src/cloud_requirements.rs` | `CloudRequirementsLoader` 实际定义 |
| `codex-rs/config/src/config_requirements.rs` | `ConfigRequirementsToml` 配置结构 |
| `codex-rs/core/src/auth.rs` | `AuthManager`, `CodexAuth` |

### 4.4 配置加载集成

```rust
// codex-rs/core/src/config_loader/mod.rs
pub async fn load_config_layers_state(
    codex_home: &Path,
    cwd: Option<AbsolutePathBuf>,
    cli_overrides: &[(String, TomlValue)],
    overrides: LoaderOverrides,
    cloud_requirements: CloudRequirementsLoader,
) -> io::Result<ConfigLayerStack> {
    let mut config_requirements_toml = ConfigRequirementsWithSources::default();

    // 1. 加载云端配置（最高优先级）
    if let Some(requirements) = cloud_requirements.get().await.map_err(io::Error::other)? {
        config_requirements_toml
            .merge_unset_fields(RequirementSource::CloudRequirements, requirements);
    }

    // 2. 加载 macOS MDM 托管配置
    #[cfg(target_os = "macos")]
    macos::load_managed_admin_requirements_toml(...).await?;

    // 3. 加载系统 requirements.toml
    load_requirements_toml(&mut config_requirements_toml, requirements_toml_file).await?;

    // 4. 加载其他配置层...
}
```

---

## 5. 依赖与外部交互

### 5.1 Crate 依赖

```toml
[dependencies]
async-trait = { workspace = true }
base64 = { workspace = true }
chrono = { workspace = true, features = ["serde"] }
codex-backend-client = { workspace = true }
codex-core = { workspace = true }
codex-otel = { workspace = true }
codex-protocol = { workspace = true }
hmac = "0.12.1"
serde = { workspace = true, features = ["derive"] }
serde_json = { workspace = true }
sha2 = { workspace = true }
thiserror = { workspace = true }
tokio = { workspace = true, features = ["fs", "sync", "time"] }
toml = { workspace = true }
tracing = { workspace = true }
```

### 5.2 外部系统交互

| 系统 | 交互方式 | 说明 |
|------|----------|------|
| ChatGPT Backend API | HTTP GET | 获取配置内容，端点 `/wham/config/requirements` |
| Codex Backend API | HTTP GET | 获取配置内容，端点 `/api/codex/config/requirements` |
| 本地文件系统 | 异步文件 IO | 读写缓存文件 `$CODEX_HOME/cloud-requirements-cache.json` |
| OpenTelemetry | 指标上报 | 上报获取延迟、成功/失败次数等指标 |

### 5.3 指标上报

```rust
const CLOUD_REQUIREMENTS_FETCH_ATTEMPT_METRIC: &str = "codex.cloud_requirements.fetch_attempt";
const CLOUD_REQUIREMENTS_FETCH_FINAL_METRIC: &str = "codex.cloud_requirements.fetch_final";
const CLOUD_REQUIREMENTS_LOAD_METRIC: &str = "codex.cloud_requirements.load";
```

指标标签：
- `trigger`: "startup" | "refresh"
- `attempt`: 尝试次数
- `outcome`: "success" | "error" | "unauthorized"
- `status_code`: HTTP 状态码
- `reason`: 失败原因（如 "auth_recovery_unavailable"）

---

## 6. 风险、边界与改进建议

### 6.1 潜在风险

#### 6.1.1 高严重性风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| **企业用户启动失败** | 云端配置获取失败时，企业用户无法启动 Codex | 已实现缓存机制，但首次启动仍需网络 |
| **缓存篡改** | 本地缓存文件被恶意修改 | HMAC-SHA256 签名验证 |
| **密钥泄露** | `CLOUD_REQUIREMENTS_CACHE_WRITE_HMAC_KEY` 硬编码在二进制中 | 密钥轮换机制支持（`CLOUD_REQUIREMENTS_CACHE_READ_HMAC_KEYS`） |

#### 6.1.2 中等严重性风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| **后台任务堆积** | 多次调用 `cloud_requirements_loader` 可能创建多个刷新任务 | 使用 `OnceLock` + `Mutex` 确保单例刷新任务，新任务会中止旧任务 |
| **超时配置不当** | 15 秒超时在某些网络环境下可能过短 | 暂无动态调整机制 |
| **缓存身份不匹配** | 用户切换账户后缓存仍保留 | 缓存包含 user_id 和 account_id，不匹配时丢弃 |

### 6.2 边界情况

#### 6.2.1 已处理的边界情况

1. **空内容处理**: 云端返回空内容或空白内容时，视为无配置（`Ok(None)`）
2. **TOML 解析失败**: 解析错误不触发重试，直接返回错误
3. **身份不完整**: 缓存写入时允许不完整身份，但读取时要求完整
4. **任务中止**: 应用重启时旧的后台刷新任务会被中止

#### 6.2.2 潜在的边界情况

1. **时钟回拨**: 系统时间回拨可能导致缓存被认为未过期（实际已过期）
2. **磁盘满**: 缓存写入失败仅记录警告，不影响主流程
3. **并发写入**: 无文件锁机制，多进程同时写入可能导致缓存损坏

### 6.3 改进建议

#### 6.3.1 高优先级

1. **文件锁机制**
   ```rust
   // 建议：使用 fs2 或类似 crate 实现文件锁
   use fs2::FileExt;
   file.try_lock_exclusive()?;
   ```

2. **动态超时配置**
   ```rust
   // 建议：从环境变量或配置中读取超时设置
   const CLOUD_REQUIREMENTS_TIMEOUT: Duration = Duration::from_secs(
       std::env::var("CODEX_CLOUD_REQUIREMENTS_TIMEOUT")
           .ok()
           .and_then(|s| s.parse().ok())
           .unwrap_or(15)
   );
   ```

3. **缓存损坏自动修复**
   ```rust
   // 建议：检测到缓存损坏时自动删除并重新获取
   Err(CacheLoadStatus::CacheParseFailed(_)) => {
       tracing::warn!("Cache corrupted, removing and refetching");
       let _ = fs::remove_file(&self.cache_path).await;
       self.fetch_with_retries(auth, trigger).await
   }
   ```

#### 6.3.2 中优先级

1. **缓存压缩**: 大型配置文件可考虑压缩存储
2. **增量更新**: 支持 ETag 或 Last-Modified 实现增量更新
3. **更细粒度的指标**: 按账户类型、网络环境等维度细分指标

#### 6.3.3 低优先级

1. **缓存加密**: 对敏感配置内容进行加密存储
2. **多后端支持**: 支持配置多个后端地址实现故障转移
3. **配置预取**: 应用空闲时主动预取配置更新

### 6.4 测试覆盖

模块包含 30+ 个单元测试，覆盖：

- 非 ChatGPT 认证跳过
- 非 Business/Enterprise 计划跳过
- 超时处理
- 重试机制
- 认证恢复
- 缓存读写
- 签名验证
- 身份匹配
- 过期处理
- 篡改检测

测试文件位置：`codex-rs/cloud-requirements/src/lib.rs` (内联测试，第 818-1930 行)

---

## 7. 总结

Cloud Requirements 模块是 Codex 企业级功能的核心组件，实现了：

1. **安全的企业配置分发**: 通过后端 API 获取管理员配置
2. **可靠的离线支持**: 本地缓存 + 签名验证
3. **优雅的错误处理**: 重试、认证恢复、fail-closed 策略
4. **可观测性**: 完整的指标和日志记录

该模块的设计充分考虑了企业用户的需求，在安全性、可靠性和用户体验之间取得了良好的平衡。
