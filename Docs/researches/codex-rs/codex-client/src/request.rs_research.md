# request.rs 研究文档

## 场景与职责

`request.rs` 是 Codex HTTP 客户端的基础模块，定义了 HTTP 请求和响应的核心数据结构。它为整个 `codex-client` crate 提供统一的请求/响应抽象，被 `transport.rs`、`retry.rs` 等模块使用。

该模块位于 HTTP 客户端层的最底层，职责包括：
- 定义请求结构体，封装 HTTP 方法、URL、头部、请求体等元数据
- 支持请求压缩（Zstd）配置
- 提供 Builder 风格的请求构造 API
- 定义统一的响应结构体

## 功能点目的

### 1. RequestCompression 枚举
```rust
pub enum RequestCompression {
    #[default]
    None,
    Zstd,
}
```
- **目的**：控制请求体是否启用压缩
- **默认值**：`None`（不压缩）
- **当前支持**：仅 Zstd 压缩算法

### 2. Request 结构体
```rust
pub struct Request {
    pub method: Method,           // HTTP 方法 (GET/POST等)
    pub url: String,              // 请求 URL
    pub headers: HeaderMap,       // HTTP 头部
    pub body: Option<Value>,      // JSON 请求体
    pub compression: RequestCompression,  // 压缩配置
    pub timeout: Option<Duration>, // 超时配置
}
```
- **目的**：封装完整的 HTTP 请求信息
- **设计特点**：所有字段公开，便于直接访问和修改

### 3. Request Builder API
- `Request::new(method, url)`：创建基础请求
- `with_json<T>(body)`：设置 JSON 请求体（自动序列化）
- `with_compression(compression)`：设置压缩方式

### 4. Response 结构体
```rust
pub struct Response {
    pub status: http::StatusCode,  // HTTP 状态码
    pub headers: HeaderMap,        // 响应头部
    pub body: Bytes,               // 响应体（字节数组）
}
```
- **目的**：统一封装 HTTP 响应数据
- **特点**：body 使用 `bytes::Bytes` 类型，支持零拷贝操作

## 具体技术实现

### 关键数据结构

| 类型 | 用途 | 关键字段 |
|------|------|----------|
| `RequestCompression` | 压缩配置枚举 | `None`, `Zstd` |
| `Request` | HTTP 请求封装 | method, url, headers, body, compression, timeout |
| `Response` | HTTP 响应封装 | status, headers, body |

### 关键流程

1. **请求构造流程**
   ```
   Request::new(method, url)
       → with_json(&body)      // 可选：设置 JSON 体
       → with_compression(Zstd) // 可选：启用压缩
   ```

2. **JSON 序列化**
   - 使用 `serde_json::to_value` 将任意可序列化类型转换为 `serde_json::Value`
   - 使用 `.ok()` 忽略序列化错误（静默失败设计）

## 关键代码路径与文件引用

### 当前文件关键代码
- **行 8-13**：`RequestCompression` 枚举定义
- **行 15-23**：`Request` 结构体定义
- **行 25-45**：`Request` 实现（Builder 方法）
- **行 48-53**：`Response` 结构体定义

### 被调用方（使用者）
| 文件 | 使用方式 |
|------|----------|
| `transport.rs` | 核心消费者，将 `Request` 转换为 `reqwest` 请求 |
| `retry.rs` | 接收 `Request` 进行重试逻辑处理 |
| `codex-api/src/telemetry.rs` | 使用 `Request` 进行遥测数据收集 |
| `codex-api/src/endpoint/*.rs` | 各端点客户端构造请求 |

### 依赖的外部 crate
| crate | 用途 |
|-------|------|
| `bytes` | `Bytes` 类型用于响应体 |
| `http` | `Method`, `HeaderMap`, `StatusCode` |
| `reqwest` | 底层 HTTP 客户端（通过 header 类型） |
| `serde` | `Serialize` trait |
| `serde_json` | `Value` 类型 |

## 依赖与外部交互

### 模块依赖图
```
request.rs
    ↑
    ├── transport.rs (构建并执行请求)
    ├── retry.rs (重试逻辑)
    └── codex-api (高层 API 使用)
```

### 与 transport.rs 的交互
- `transport.rs` 中的 `ReqwestTransport` 接收 `Request` 对象
- 将 `Request` 转换为 `reqwest::RequestBuilder`
- 处理 `RequestCompression` 配置，执行实际的压缩操作

### 与 retry.rs 的交互
- `retry.rs` 中的 `run_with_retry` 接收 `Request` 构造闭包
- 在每次重试时重新构造请求

## 风险、边界与改进建议

### 潜在风险

1. **序列化错误静默处理**
   ```rust
   self.body = serde_json::to_value(body).ok();  // 行 38
   ```
   - 问题：序列化失败时返回 `None`，调用方无法感知错误
   - 影响：可能导致请求体为空而调用方不知情

2. **URL 类型为 String**
   - 问题：没有 URL 验证，可能传入非法 URL
   - 建议：考虑使用 `url::Url` 类型进行验证

3. **timeout 配置未在 Builder API 中暴露**
   - 问题：`timeout` 字段只能通过直接赋值设置
   - 建议：添加 `with_timeout()` 方法

### 边界情况

1. **空请求体**：`body: None` 是合法状态
2. **大请求体**：未限制 body 大小，依赖下层 transport 处理
3. **压缩与 Content-Encoding 冲突**：`transport.rs` 会检查并拒绝重复设置

### 改进建议

1. **添加 `with_timeout()` 方法**
   ```rust
   pub fn with_timeout(mut self, timeout: Duration) -> Self {
       self.timeout = Some(timeout);
       self
   }
   ```

2. **序列化错误处理改进**
   - 考虑返回 `Result<Self, serde_json::Error>` 而非静默失败
   - 或在 `with_json` 方法中添加日志记录

3. **URL 类型安全**
   - 考虑使用 `url::Url` 替代 `String`
   - 或在 `new()` 中进行 URL 格式验证

4. **添加请求 ID 追踪**
   - 考虑添加 `request_id` 字段用于分布式追踪

### 测试建议
- 当前模块无单元测试
- 建议添加：
  - Builder 方法链式调用测试
  - 大请求体处理测试
  - 非法 URL 处理测试
