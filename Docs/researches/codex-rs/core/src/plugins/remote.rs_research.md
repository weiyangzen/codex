# remote.rs 研究文档

## 场景与职责

`remote.rs` 是 Codex 插件系统中负责 **远程插件状态同步** 的模块。它处理与 ChatGPT/OpenAI 后端服务的通信，实现插件状态的远程获取、启用/禁用操作，以及精选插件 ID 的获取。

### 核心场景

1. **远程插件状态同步**：获取用户在 ChatGPT 后端已安装/启用的插件列表
2. **精选插件发现**：获取推荐的精选插件 ID 列表
3. **远程插件操作**：向后端发送启用/禁用/卸载插件的请求
4. **跨设备同步**：确保 Codex 本地插件状态与 ChatGPT 账户保持一致

---

## 功能点目的

### 1. 远程插件状态获取 (`fetch_remote_plugin_status`)

**目的**：从 ChatGPT 后端获取用户已启用的插件列表。

**关键特性**：
- 需要 ChatGPT 认证（OAuth token）
- 不支持 API Key 认证
- 30 秒超时
- 返回插件名称、市场名称和启用状态

### 2. 精选插件获取 (`fetch_remote_featured_plugin_ids`)

**目的**：获取推荐的精选插件 ID 列表。

**关键特性**：
- 可选认证（未认证也能获取公共列表）
- 10 秒超时
- 用于插件发现功能

### 3. 远程插件操作 (`enable_remote_plugin` / `uninstall_remote_plugin`)

**目的**：向后端发送插件启用/卸载请求。

**关键特性**：
- 需要 ChatGPT 认证
- 30 秒超时
- 验证响应中的插件 ID 和启用状态

---

## 具体技术实现

### 数据结构

```rust
/// 远程插件状态摘要
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub(crate) struct RemotePluginStatusSummary {
    pub(crate) name: String,
    #[serde(default = "default_remote_marketplace_name")]
    pub(crate) marketplace_name: String,
    pub(crate) enabled: bool,
}

/// 远程插件变更响应
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RemotePluginMutationResponse {
    pub id: String,
    pub enabled: bool,
}
```

### 错误类型体系

#### `RemotePluginFetchError` - 获取错误

```rust
pub enum RemotePluginFetchError {
    AuthRequired,           // 需要 ChatGPT 认证
    UnsupportedAuthMode,    // API Key 认证不支持
    AuthToken(std::io::Error),      // 读取 token 失败
    Request { url, source },        // 请求发送失败
    UnexpectedStatus { url, status, body },  // 非 2xx 响应
    Decode { url, source },         // JSON 解析失败
}
```

#### `RemotePluginMutationError` - 变更错误

在 `RemotePluginFetchError` 基础上增加：
```rust
InvalidBaseUrl(url::ParseError),     // URL 解析失败
InvalidBaseUrlPath,                  // URL 路径无效
UnexpectedPluginId { expected, actual },  // 响应 ID 不匹配
UnexpectedEnabledState { plugin_id, expected_enabled, actual_enabled },  // 状态不匹配
```

### 核心函数实现

#### `fetch_remote_plugin_status`

```rust
pub(crate) async fn fetch_remote_plugin_status(
    config: &Config,
    auth: Option<&CodexAuth>,
) -> Result<Vec<RemotePluginStatusSummary>, RemotePluginFetchError> {
    // 1. 验证 ChatGPT 认证
    let Some(auth) = auth else { return Err(AuthRequired); };
    if !auth.is_chatgpt_auth() { return Err(UnsupportedAuthMode); }
    
    // 2. 构建请求
    let url = format!("{}/plugins/list", config.chatgpt_base_url);
    let client = build_reqwest_client();
    let token = auth.get_token()?;
    let mut request = client.get(&url).timeout(REMOTE_PLUGIN_FETCH_TIMEOUT).bearer_auth(token);
    
    // 3. 添加 account_id header（如果存在）
    if let Some(account_id) = auth.get_account_id() {
        request = request.header("chatgpt-account-id", account_id);
    }
    
    // 4. 发送请求并处理响应
    let response = request.send().await?;
    let body = response.text().await.unwrap_or_default();
    serde_json::from_str(&body)
}
```

#### `post_remote_plugin_mutation`

```rust
async fn post_remote_plugin_mutation(
    config: &Config,
    auth: Option<&CodexAuth>,
    plugin_id: &str,
    action: &str,  // "enable" 或 "uninstall"
) -> Result<RemotePluginMutationResponse, RemotePluginMutationError> {
    // 1. 验证认证
    let auth = ensure_chatgpt_auth(auth)?;
    
    // 2. 构建 URL（使用 url crate 安全拼接）
    let url = remote_plugin_mutation_url(config, plugin_id, action)?;
    
    // 3. 发送 POST 请求
    let response = client.post(&url).bearer_auth(token).send().await?;
    
    // 4. 解析并验证响应
    let parsed: RemotePluginMutationResponse = serde_json::from_str(&body)?;
    if parsed.id != plugin_id { return Err(UnexpectedPluginId { ... }); }
    if parsed.enabled != expected_enabled { return Err(UnexpectedEnabledState { ... }); }
    
    Ok(parsed)
}
```

### URL 构建安全实现

```rust
fn remote_plugin_mutation_url(
    config: &Config,
    plugin_id: &str,
    action: &str,
) -> Result<String, RemotePluginMutationError> {
    let mut url = Url::parse(config.chatgpt_base_url.trim_end_matches('/'))?;
    {
        let mut segments = url.path_segments_mut()
            .map_err(|()| RemotePluginMutationError::InvalidBaseUrlPath)?;
        segments.pop_if_empty();
        segments.push("plugins");
        segments.push(plugin_id);
        segments.push(action);
    }
    Ok(url.to_string())
}
```

---

## 关键代码路径与文件引用

### 调用关系图

```
remote.rs
    ├── manager.rs 调用:
    │   ├── fetch_remote_plugin_status (同步远程状态)
    │   ├── fetch_remote_featured_plugin_ids (获取精选插件)
    │   ├── enable_remote_plugin (安装时启用)
    │   └── uninstall_remote_plugin (卸载时禁用)
    │
    └── 依赖:
        ├── crate::auth::CodexAuth (认证)
        ├── crate::config::Config (配置)
        └── crate::default_client::build_reqwest_client (HTTP 客户端)
```

### 常量定义

```rust
const DEFAULT_REMOTE_MARKETPLACE_NAME: &str = "openai-curated";
const REMOTE_PLUGIN_FETCH_TIMEOUT: Duration = Duration::from_secs(30);
const REMOTE_FEATURED_PLUGIN_FETCH_TIMEOUT: Duration = Duration::from_secs(10);
const REMOTE_PLUGIN_MUTATION_TIMEOUT: Duration = Duration::from_secs(30);
```

### API 端点

| 功能 | HTTP 方法 | 端点 | 认证要求 |
|------|-----------|------|----------|
| 获取插件列表 | GET | `/plugins/list` | 必需 |
| 获取精选插件 | GET | `/plugins/featured` | 可选 |
| 启用插件 | POST | `/plugins/{id}/enable` | 必需 |
| 卸载插件 | POST | `/plugins/{id}/uninstall` | 必需 |

---

## 依赖与外部交互

### 外部服务依赖

| 服务 | 用途 | 失败处理 |
|------|------|----------|
| ChatGPT API | 插件状态同步 | 返回特定错误类型，由调用方处理 |
| GitHub API | 精选仓库同步（在 curated_repo.rs） | 独立模块，不影响 remote.rs |

### 认证集成

```rust
// 依赖 crate::auth::CodexAuth
pub struct CodexAuth {
    // ...
}

impl CodexAuth {
    fn is_chatgpt_auth(&self) -> bool;      // 检查是否为 ChatGPT OAuth
    fn get_token(&self) -> Result<String>;  // 获取 Bearer token
    fn get_account_id(&self) -> Option<String>;  // 获取账户 ID
}
```

### 配置依赖

```rust
// 依赖 crate::config::Config
pub struct Config {
    pub chatgpt_base_url: String,  // 后端基础 URL
    // ...
}
```

### HTTP 客户端

```rust
// 使用 crate::default_client::build_reqwest_client
// 统一配置超时、TLS、代理等
fn build_reqwest_client() -> reqwest::Client;
```

---

## 风险、边界与改进建议

### 安全风险

1. **认证令牌泄露**：
   - 风险：Bearer token 在日志中可能意外泄露
   - 现状：代码中没有明显的日志记录 token
   - 建议：添加 `#[serde(skip)]` 或自定义 Debug 实现

2. **URL 拼接安全**：
   - 现状：使用 `url::Url::path_segments_mut` 安全拼接
   - 风险：较低，已正确处理

3. **响应验证**：
   - 现状：验证响应中的 plugin_id 和 enabled 状态
   - 风险：如果后端被攻破，可能返回恶意数据
   - 建议：考虑添加响应签名验证

### 性能边界

| 指标 | 当前值 | 风险 |
|------|--------|------|
| 获取超时 | 30s | 慢网络环境下可能频繁超时 |
| 精选获取超时 | 10s | 合理 |
| 变更超时 | 30s | 合理 |
| 并发请求 | 无限制 | 大量插件同步时可能产生并发风暴 |

### 可靠性边界

1. **无重试机制**：
   - 当前：单次请求，失败即返回错误
   - 风险：瞬态网络故障导致操作失败
   - 建议：添加指数退避重试

2. **无缓存机制**（除 featured 外）：
   - 当前：每次调用都请求后端
   - 风险：频繁调用可能触发限流
   - 建议：对 `list` 添加短期缓存

3. **认证失效处理**：
   - 当前：返回 `AuthRequired` 错误
   - 风险：调用方需正确处理并引导用户重新认证

### 改进建议

1. **添加重试机制**：
   ```rust
   use tokio_retry::Retry;
   use tokio_retry::strategy::ExponentialBackoff;
   
   let retry_strategy = ExponentialBackoff::from_millis(100).take(3);
   let result = Retry::spawn(retry_strategy, || async {
       fetch_remote_plugin_status(config, auth).await
   }).await;
   ```

2. **添加指标收集**：
   ```rust
   // 记录请求延迟、成功率等指标
   metrics::histogram!("plugins.remote.request_duration", duration.as_millis() as f64);
   metrics::counter!("plugins.remote.requests_total", 1, "status" => status.as_str());
   ```

3. **改进错误分类**：
   ```rust
   // 区分可重试错误和永久错误
   impl RemotePluginFetchError {
       fn is_retryable(&self) -> bool {
           matches!(self, 
               Self::Request { .. } | 
               Self::UnexpectedStatus { status, .. } if status.is_server_error()
           )
       }
   }
   ```

4. **添加请求追踪**：
   ```rust
   // 使用 tracing 的 span 追踪请求链路
   let span = tracing::info_span!("remote_plugin_request", plugin_id, action);
   let _enter = span.enter();
   ```

### 测试建议

当前文件没有对应的 `remote_tests.rs`，建议添加：

1. **Mock 测试**：使用 `wiremock` 模拟后端响应
2. **错误场景测试**：超时、认证失败、无效响应等
3. **并发测试**：验证多线程环境下的安全性
4. **重试测试**：验证重试逻辑的正确性（如果实现）
