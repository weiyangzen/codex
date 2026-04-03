# error.rs 深度研究文档

## 场景与职责

`error.rs` 是 Codex 客户端的错误类型定义模块，为 HTTP 传输层和 SSE 流处理提供统一的错误抽象。在分布式系统中，错误处理是可靠性的关键：该模块将底层库（reqwest、hyper 等）的多样化错误转换为 Codex 特定的、具有语义意义的错误类型，使上层代码能够根据错误类型做出恰当的响应（如重试、降级或报错）。

该模块的核心职责：
1. **错误分类**：区分 HTTP 错误、网络错误、超时错误、重试限制错误
2. **上下文保留**：HTTP 错误保留状态码、URL、响应头、响应体等关键信息
3. **错误传播**：使用 `thiserror` 实现标准 `Error` trait，支持错误链
4. **重试决策支持**：错误类型设计支持 `RetryOn::should_retry` 的决策逻辑

## 功能点目的

### 1. TransportError - 传输层错误
涵盖同步/异步 HTTP 请求可能遇到的所有错误场景：
- **Http**：服务器返回非成功状态码（4xx/5xx）
- **RetryLimit**：已达到最大重试次数
- **Timeout**：请求超时
- **Network**：底层网络错误（DNS、连接重置等）
- **Build**：请求构建错误（无效头、序列化失败等）

### 2. StreamError - SSE 流错误
专门处理 Server-Sent Events 流式响应的错误：
- **Stream**：流处理失败（连接中断、解析错误等）
- **Timeout**：空闲超时（长时间无数据）

## 具体技术实现

### 关键数据结构

```rust
use http::{HeaderMap, StatusCode};
use thiserror::Error;

/// 传输层错误类型
#[derive(Debug, Error)]
pub enum TransportError {
    /// HTTP 错误（非 2xx 响应）
    #[error("http {status}: {body:?}")]
    Http {
        status: StatusCode,           // HTTP 状态码
        url: Option<String>,          // 请求 URL（用于诊断）
        headers: Option<HeaderMap>,   // 响应头（可能包含错误详情）
        body: Option<String>,         // 响应体（可能包含错误消息）
    },
    
    /// 重试次数耗尽
    #[error("retry limit reached")]
    RetryLimit,
    
    /// 请求超时
    #[error("timeout")]
    Timeout,
    
    /// 网络层错误
    #[error("network error: {0}")]
    Network(String),
    
    /// 请求构建错误
    #[error("request build error: {0}")]
    Build(String),
}

/// SSE 流错误类型
#[derive(Debug, Error)]
pub enum StreamError {
    /// 流处理失败
    #[error("stream failed: {0}")]
    Stream(String),
    
    /// 流空闲超时
    #[error("timeout")]
    Timeout,
}
```

### 错误类型设计决策

#### 1. 丰富的 HTTP 错误上下文
```rust
Http {
    status: StatusCode,           // 必须：决定重试策略
    url: Option<String>,          // 可选：诊断用
    headers: Option<HeaderMap>,   // 可选：可能包含 RateLimit 信息
    body: Option<String>,         // 可选：错误详情
}
```
- 所有字段均为 `Option`，允许渐进式构建错误
- `StatusCode` 非可选，因为它是重试决策的核心依据

#### 2. 字符串 vs 结构化错误
- `Network(String)` 和 `Build(String)` 使用字符串而非结构化类型
- 原因：底层错误（io::Error、reqwest::Error）的多样性难以统一抽象
- 权衡：牺牲部分类型安全换取实现简洁

#### 3. 重试限制作为独立错误
- `RetryLimit` 独立于原始错误
- 原因：调用方需要明确知道"已尽力重试但仍失败" vs "首次尝试即失败"
- 使用场景：日志记录、指标统计、用户提示

### 与 retry 模块的交互

```rust
// retry.rs
impl RetryOn {
    pub fn should_retry(&self, err: &TransportError, attempt: u64, max_attempts: u64) -> bool {
        if attempt >= max_attempts {
            return false;  // 达到最大尝试次数
        }
        match err {
            TransportError::Http { status, .. } => {
                (self.retry_429 && status.as_u16() == 429)  // Too Many Requests
                    || (self.retry_5xx && status.is_server_error())  // 5xx 错误
            }
            TransportError::Timeout | TransportError::Network(_) => self.retry_transport,
            _ => false,  // Build 错误、RetryLimit 不重试
        }
    }
}
```

### 错误转换链

```
底层错误 → TransportError → 重试决策 → 最终结果
    │              │              │
    ▼              ▼              ▼
reqwest::Error   Http/Timeout   should_retry()
io::Error        Network        → 重试 / 返回错误
serde::Error     Build
```

## 关键代码路径与文件引用

### 本模块定义
| 类型 | 行号 | 用途 |
|------|------|------|
| `TransportError` | 5-22 | 传输层错误枚举 |
| `StreamError` | 25-30 | SSE 流错误枚举 |

### 使用方
| 文件 | 使用场景 |
|------|----------|
| `src/transport.rs` | `map_error()` 将 `reqwest::Error` 转换为 `TransportError` |
| `src/retry.rs` | `should_retry()` 基于 `TransportError` 决策 |
| `src/sse.rs` | 将流错误转换为 `StreamError` |
| `../codex-api/src/error.rs` | 将 `TransportError` 包装为 `ApiError` |

## 依赖与外部交互

### 外部 crate 依赖
| Crate | 用途 |
|-------|------|
| `http` | `StatusCode`、`HeaderMap` 类型 |
| `thiserror` | 派生 `Error` trait 和 `Display` |

### 与 transport.rs 的错误映射
```rust
// transport.rs
fn map_error(err: reqwest::Error) -> TransportError {
    if err.is_timeout() {
        TransportError::Timeout
    } else {
        TransportError::Network(err.to_string())
    }
}

async fn execute(&self, req: Request) -> Result<Response, TransportError> {
    // ...
    if !status.is_success() {
        return Err(TransportError::Http {
            status,
            url: Some(url),
            headers: Some(headers),
            body,
        });
    }
    // ...
}
```

### 与 codex-api 的集成
```rust
// ../codex-api/src/error.rs
#[derive(Debug, Error)]
pub enum ApiError {
    #[error("transport error: {0}")]
    Transport(#[from] TransportError),  // 自动转换
    // ...
}
```

## 风险、边界与改进建议

### 已知风险

1. **HTTP 错误体可能过大**
   - 现象：`Http.body: Option<String>` 可能包含大段 HTML 错误页
   - 影响：内存占用、日志膨胀
   - 缓解：transport.rs 中应限制读取的响应体大小

2. **敏感信息泄露**
   - 现象：`Http.body` 或 `Network` 错误消息可能包含敏感信息
   - 影响：日志中泄露 API 密钥、内部路径等
   - 缓解：上层应在记录前过滤敏感字段

3. **错误消息国际化**
   - 现象：当前错误消息为硬编码英文
   - 影响：非英语用户体验

### 边界条件

| 场景 | 行为 |
|------|------|
| HTTP 204 No Content | 成功（2xx），不返回 Http 错误 |
| HTTP 429 Too Many Requests | Http 错误，可配置重试 |
| DNS 解析失败 | Network 错误 |
| 连接超时 | Timeout 错误 |
| 响应体非 UTF-8 | body 为 None（String::from_utf8_lossy 可能丢失） |

### 改进建议

1. **结构化网络错误**
   ```rust
   // 当前
   Network(String)
   
   // 建议
   pub enum NetworkErrorKind {
       DnsFailed,
       ConnectionRefused,
       ConnectionReset,
       TlsHandshakeFailed,
       Other(String),
   }
   Network(NetworkErrorKind)
   ```

2. **RateLimit 信息提取**
   ```rust
   // 从响应头提取限流信息
   pub struct RateLimitInfo {
       pub limit: Option<u32>,
       pub remaining: Option<u32>,
       pub reset_at: Option<SystemTime>,
       pub retry_after: Option<Duration>,
   }
   
   // 添加到 Http 变体
   Http {
       status: StatusCode,
       rate_limit: Option<RateLimitInfo>,  // 新增
       // ...
   }
   ```

3. **错误分类辅助方法**
   ```rust
   impl TransportError {
       pub fn is_retriable(&self) -> bool;
       pub fn is_client_error(&self) -> bool;  // 4xx
       pub fn is_server_error(&self) -> bool;  // 5xx
       pub fn status_code(&self) -> Option<StatusCode>;
   }
   ```

4. **错误链保留**
   ```rust
   // 当前 Network(String) 丢失原始错误
   // 建议保留源错误
   #[error("network error: {message}")]
   Network {
       message: String,
       #[source]
       source: Option<Box<dyn Error + Send + Sync>>,
   }
   ```

5. **SSE 流错误细化**
   ```rust
   // 当前 Stream(String) 过于笼统
   pub enum StreamError {
       ConnectionClosed,
       ParseError(String),
       DecodingError(String),
       // ...
   }
   ```

### 架构考虑

该模块保持最小化设计，符合 "do one thing well" 原则：
- **优点**：简单、稳定、易于理解
- **限制**：功能扩展需要修改枚举定义（破坏性变更）

对于更复杂的错误处理需求，建议：
1. 保持 `TransportError` 作为公共 API 的稳定接口
2. 内部使用更详细的错误类型，转换时聚合
3. 考虑使用 `anyhow` 或 `eyre` 在内部传递上下文
