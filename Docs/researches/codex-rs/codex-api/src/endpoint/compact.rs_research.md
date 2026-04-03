# compact.rs 研究文档

## 场景与职责

`compact.rs` 是 Codex API 客户端中负责**对话历史压缩**功能的端点客户端实现。在长时间对话场景中，随着消息数量的增长，上下文窗口可能会被耗尽，此时需要将历史消息压缩成更紧凑的表示形式，以便继续对话而不丢失关键信息。

该模块提供了一个 `CompactClient` 结构体，用于与后端的 `responses/compact` 端点通信，执行历史消息的压缩操作。

## 功能点目的

1. **历史消息压缩**：将冗长的对话历史压缩为更紧凑的格式，释放上下文窗口空间
2. **支持结构化输入**：通过 `CompactionInput` 类型提供类型安全的输入参数
3. **保持对话连续性**：压缩后的输出可用于后续对话，确保语义连贯

## 具体技术实现

### 核心数据结构

```rust
pub struct CompactClient<T: HttpTransport, A: AuthProvider> {
    session: EndpointSession<T, A>,
}
```

- 使用泛型参数 `T: HttpTransport` 支持不同的 HTTP 传输实现
- 使用 `A: AuthProvider` 支持不同的认证方式
- 内部封装 `EndpointSession` 处理实际的 HTTP 请求

### 关键流程

#### 1. 客户端创建
```rust
pub fn new(transport: T, provider: Provider, auth: A) -> Self
pub fn with_telemetry(self, request: Option<Arc<dyn RequestTelemetry>>) -> Self
```

- 通过 `new` 方法创建客户端实例
- 可选的 `with_telemetry` 方法添加请求遥测功能

#### 2. 压缩请求执行
```rust
pub async fn compact(
    &self,
    body: serde_json::Value,
    extra_headers: HeaderMap,
) -> Result<Vec<ResponseItem>, ApiError>
```

- 发送 POST 请求到 `responses/compact` 端点
- 返回压缩后的 `ResponseItem` 列表

#### 3. 类型安全输入
```rust
pub async fn compact_input(
    &self,
    input: &CompactionInput<'_>,
    extra_headers: HeaderMap,
) -> Result<Vec<ResponseItem>, ApiError>
```

- 接受结构化的 `CompactionInput` 参数
- 自动序列化为 JSON 格式

### 响应解析

```rust
#[derive(Debug, Deserialize)]
struct CompactHistoryResponse {
    output: Vec<ResponseItem>,
}
```

响应体包含压缩后的输出项列表。

## 关键代码路径与文件引用

### 内部依赖

| 文件 | 用途 |
|------|------|
| `crate::auth::AuthProvider` | 认证提供者 trait |
| `crate::common::CompactionInput` | 压缩输入结构体 |
| `crate::endpoint::session::EndpointSession` | HTTP 会话管理 |
| `crate::error::ApiError` | 错误类型定义 |
| `crate::provider::Provider` | 端点配置 |

### 外部依赖

| Crate | 用途 |
|-------|------|
| `codex_client::HttpTransport` | HTTP 传输抽象 |
| `codex_client::RequestTelemetry` | 请求遥测 |
| `codex_protocol::models::ResponseItem` | 响应项模型 |
| `http` | HTTP 类型（HeaderMap, Method） |
| `serde_json` | JSON 序列化/反序列化 |

### API 端点

- **路径**: `responses/compact`
- **方法**: `POST`
- **请求体**: `CompactionInput` 的 JSON 表示
- **响应体**: `CompactHistoryResponse` 包含压缩后的 `ResponseItem` 列表

## 依赖与外部交互

### 调用关系

```
CompactClient::compact_input
  └─> CompactClient::compact
      └─> EndpointSession::execute (POST responses/compact)
          └─> HttpTransport::execute
```

### 输入数据结构 (`CompactionInput`)

定义在 `crate::common` 中：

```rust
pub struct CompactionInput<'a> {
    pub model: &'a str,
    pub input: &'a [ResponseItem],
    pub instructions: &'a str,
    pub tools: Vec<Value>,
    pub parallel_tool_calls: bool,
    pub reasoning: Option<Reasoning>,
    pub text: Option<TextControls>,
}
```

## 风险、边界与改进建议

### 风险点

1. **序列化失败**: `serde_json::to_value` 可能失败，已处理并转换为 `ApiError::Stream`
2. **响应解析失败**: 如果后端返回非预期格式，会导致解析错误
3. **网络超时**: 压缩操作可能耗时较长，依赖底层传输的超时配置

### 边界条件

1. **空输入**: 输入空的消息列表时，后端行为未明确
2. **超大历史**: 极端长的对话历史可能导致请求体过大
3. **认证过期**: 长时间运行的会话可能遇到 token 过期问题

### 测试覆盖

模块包含基础单元测试：
- `path_is_responses_compact`: 验证端点路径正确性
- 使用 `DummyTransport` 和 `DummyAuth` 进行测试替身

### 改进建议

1. **增加重试机制**: 压缩操作可能因临时网络问题失败，可考虑添加重试逻辑
2. **流式压缩**: 对于超大历史，考虑支持流式处理
3. **压缩进度反馈**: 长时间压缩操作可提供进度事件
4. **缓存机制**: 相同的压缩输入可考虑缓存结果
5. **输入验证**: 在发送请求前验证输入参数的有效性

### 代码质量

- 代码简洁，职责单一
- 错误处理使用 `?` 操作符，简洁明了
- 测试覆盖基础路径，但缺少集成测试
