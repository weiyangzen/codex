# provider.rs 研究文档

## 场景与职责

`provider.rs` 是 `codex-api` crate 的服务提供者配置模块，负责管理 HTTP 端点的连接配置。该模块是 API 层与具体服务部署（OpenAI、Azure 等）之间的桥梁：

1. **端点配置**: 封装 base URL、默认头、查询参数
2. **重试策略**: 定义指数退避、最大尝试次数、可重试状态码
3. **Azure 检测**: 识别 Azure OpenAI 服务端点，应用特殊处理
4. **WebSocket URL 构建**: 将 HTTP URL 转换为 WebSocket URL

在架构中，该模块为所有 API 客户端（`ResponsesClient`, `CompactClient` 等）提供统一的连接配置。

## 功能点目的

### 1. Provider 结构体
核心配置聚合：
- `name`: 提供者标识（如 "openai", "azure"）
- `base_url`: API 基础 URL
- `query_params`: 默认查询参数（如 Azure 的 `api-version`）
- `headers`: 默认请求头
- `retry`: 重试配置
- `stream_idle_timeout`: 流空闲超时

### 2. RetryConfig 结构体
可配置的重试策略：
- `max_attempts`: 最大尝试次数
- `base_delay`: 基础退避延迟
- `retry_429`: 是否在 429 状态码时重试
- `retry_5xx`: 是否在 5xx 状态码时重试
- `retry_transport`: 是否在传输错误时重试

### 3. Azure 检测逻辑
- `is_azure_responses_endpoint()`: 基于配置名称和 URL 检测
- `is_azure_responses_wire_base_url()`: 全局检测函数
- 支持多种 Azure 域名模式：
  - `*.openai.azure.*`
  - `*.cognitiveservices.azure.*`
  - `*.aoai.azure.*`
  - `*.azure-api.*`
  - `*.azurefd.*`
  - `*.windows.net/openai`

### 4. URL 构建方法
- `url_for_path(path)`: 构建完整 URL，支持查询参数附加
- `build_request(method, path)`: 构建基础 `Request` 对象
- `websocket_url_for_path(path)`: 将 HTTP URL 转换为 WebSocket URL
  - `http` -> `ws`
  - `https` -> `wss`

## 具体技术实现

### 关键数据结构

```rust
#[derive(Debug, Clone)]
pub struct Provider {
    pub name: String,
    pub base_url: String,
    pub query_params: Option<HashMap<String, String>>,
    pub headers: HeaderMap,
    pub retry: RetryConfig,
    pub stream_idle_timeout: Duration,
}

#[derive(Debug, Clone)]
pub struct RetryConfig {
    pub max_attempts: u64,
    pub base_delay: Duration,
    pub retry_429: bool,
    pub retry_5xx: bool,
    pub retry_transport: bool,
}
```

### URL 构建算法

```rust
pub fn url_for_path(&self, path: &str) -> String {
    let base = self.base_url.trim_end_matches('/');
    let path = path.trim_start_matches('/');
    let mut url = if path.is_empty() {
        base.to_string()
    } else {
        format!("{base}/{path}")
    };

    // 附加查询参数
    if let Some(params) = &self.query_params && !params.is_empty() {
        let qs = params.iter()
            .map(|(k, v)| format!("{k}={v}"))
            .collect::<Vec<_>>()
            .join("&");
        url.push('?');
        url.push_str(&qs);
    }
    url
}
```

### WebSocket URL 转换

```rust
pub fn websocket_url_for_path(&self, path: &str) -> Result<Url, url::ParseError> {
    let mut url = Url::parse(&self.url_for_path(path))?;
    let scheme = match url.scheme() {
        "http" => "ws",
        "https" => "wss",
        "ws" | "wss" => return Ok(url),  // 已经是 ws
        _ => return Ok(url),              // 未知协议，保持原样
    };
    let _ = url.set_scheme(scheme);
    Ok(url)
}
```

### Azure 检测算法

```rust
pub fn is_azure_responses_wire_base_url(name: &str, base_url: Option<&str>) -> bool {
    // 1. 检查名称是否为 "azure"（不区分大小写）
    if name.eq_ignore_ascii_case("azure") {
        return true;
    }
    
    // 2. 检查 URL 是否包含 Azure 特征
    let Some(base_url) = base_url else { return false };
    let base = base_url.to_ascii_lowercase();
    base.contains("openai.azure.") || matches_azure_responses_base_url(&base)
}

fn matches_azure_responses_base_url(base_url: &str) -> bool {
    const AZURE_MARKERS: [&str; 5] = [
        "cognitiveservices.azure.",
        "aoai.azure.",
        "azure-api.",
        "azurefd.",
        "windows.net/openai",
    ];
    AZURE_MARKERS.iter().any(|marker| base_url.contains(marker))
}
```

### 重试策略转换

```rust
impl RetryConfig {
    pub fn to_policy(&self) -> RetryPolicy {
        RetryPolicy {
            max_attempts: self.max_attempts,
            base_delay: self.base_delay,
            retry_on: RetryOn {
                retry_429: self.retry_429,
                retry_5xx: self.retry_5xx,
                retry_transport: self.retry_transport,
            },
        }
    }
}
```

## 关键代码路径与文件引用

### 内部调用关系
```
provider.rs
├── Provider
│   ├── url_for_path (被 build_request, websocket_url_for_path 使用)
│   ├── build_request (被 endpoint/session.rs: EndpointSession::make_request 使用)
│   ├── websocket_url_for_path (被 responses_websocket.rs 使用)
│   └── is_azure_responses_endpoint (被 responses.rs 使用)
├── RetryConfig::to_policy (被 endpoint/session.rs 使用)
└── is_azure_responses_wire_base_url (被 lib.rs 导出，被 core crate 使用)
```

### 被调用方
- `codex-rs/codex-api/src/endpoint/session.rs`: 构建请求、配置重试
- `codex-rs/codex-api/src/endpoint/responses.rs`: 检测 Azure 端点以应用特殊处理
- `codex-rs/codex-api/src/endpoint/responses_websocket.rs`: 构建 WebSocket URL
- `codex-rs/core/src/model_provider_info.rs`: 检测 Azure 端点
- `codex-rs/core/src/client_common.rs`: 配置提供者

### 调用方
- `codex-rs/core/src/client.rs`: 从配置构建 Provider
- `codex-rs/core/src/connectors.rs`: 连接器配置

## 依赖与外部交互

### 外部依赖
| Crate | 用途 |
|-------|------|
| `codex_client` | `Request`, `RequestCompression`, `RetryPolicy`, `RetryOn` |
| `http` | `Method`, `HeaderMap` |
| `url` | `Url` 解析和修改 |
| `std::collections::HashMap` | 查询参数存储 |
| `std::time::Duration` | 超时和延迟 |

### 协议规范
- **URL 格式**: 遵循 RFC 3986
- **WebSocket**: RFC 6455，自动协议升级
- **Azure OpenAI**: 支持多种部署域名模式

## 风险、边界与改进建议

### 已知风险

1. **URL 拼接安全性**
   - 使用字符串拼接构建 URL，未对路径和参数进行 URL 编码
   - 风险：特殊字符可能导致 URL 解析错误
   - 示例：`query_params` 中的值包含 `&` 或 `=` 时可能破坏查询字符串
   - 建议：使用 `url::form_urlencoded` 或 `serde_urlencoded`

2. **Azure 检测误报**
   - 基于子字符串匹配，可能误伤
   - 示例：`https://myproxy.azurewebsites.net/openai` 包含 `azure` 但不是 Azure OpenAI
   - 缓解：测试用例中包含此类负例

3. **WebSocket 协议转换**
   - 未知协议（非 http/https/ws/wss）保持原样，可能导致连接失败
   - 建议：对未知协议返回错误而非保持原样

### 边界条件

1. **空路径**: `url_for_path("")` 返回 base_url
2. **斜杠处理**: 正确处理 base_url 尾部斜杠和 path 头部斜杠
3. **空查询参数**: 空的 `query_params` HashMap 不产生 `?`
4. **超时为零**: `stream_idle_timeout` 为零时可能导致立即超时

### 改进建议

1. **URL 编码安全**
   ```rust
   use url::form_urlencoded;
   
   let qs = form_urlencoded::Serializer::new(String::new())
       .extend_pairs(params)
       .finish();
   ```

2. **类型安全封装**
   ```rust
   pub struct BaseUrl(Url);
   pub struct ProviderName(String);
   ```

3. **配置验证**
   ```rust
   impl Provider {
       pub fn validate(&self) -> Result<(), ProviderError> {
           Url::parse(&self.base_url)?;
           // 验证其他字段...
       }
   }
   ```

4. **测试增强**
   - 当前测试仅覆盖 Azure 检测
   - 建议添加：URL 构建测试、WebSocket 转换测试、查询参数编码测试

5. **文档完善**
   ```rust
   /// Builds a WebSocket URL from an HTTP/HTTPS URL.
   /// 
   /// # Examples
   /// 
   /// ```
   /// let provider = Provider {
   ///     base_url: "https://api.openai.com".to_string(),
   ///     // ...
   /// };
   /// let ws_url = provider.websocket_url_for_path("/v1/realtime")?;
   /// assert_eq!(ws_url.as_str(), "wss://api.openai.com/v1/realtime");
   /// ```
   ```

6. **常量提取**
   ```rust
   pub const DEFAULT_STREAM_IDLE_TIMEOUT: Duration = Duration::from_secs(60);
   pub const AZURE_PROVIDER_NAME: &str = "azure";
   ```
