# dynamic_tools.rs 研究文档

## 场景与职责

`dynamic_tools.rs` 是 Codex App Server v2 API 的集成测试文件，专注于**动态工具（Dynamic Tools）**功能的端到端测试。动态工具是一种允许客户端在运行时向 AI 模型注册自定义工具的机制，这些工具由客户端实现，AI 模型可以调用它们并通过 App Server 将调用请求转发给客户端。

该测试文件的核心职责包括：
1. 验证动态工具规范（Dynamic Tool Spec）能否正确注入到模型请求中
2. 测试隐藏动态工具（defer_loading=true）不会被发送到模型
3. 验证完整的动态工具调用链路（服务器请求 → 客户端响应 → 模型输出）
4. 测试动态工具响应支持多种内容类型（文本、图片等）

## 功能点目的

### 1. 动态工具注入测试 (`thread_start_injects_dynamic_tools_into_model_requests`)
- **目的**：确保通过 `thread/start` 传入的动态工具规范会被序列化到模型请求负载中
- **业务价值**：允许客户端在创建线程时注册自定义工具，扩展 AI 的能力边界
- **关键验证点**：
  - 工具名称、描述、输入模式（JSON Schema）正确传递
  - 工具出现在发送到 `/responses` 端点的请求体中

### 2. 隐藏动态工具测试 (`thread_start_keeps_hidden_dynamic_tools_out_of_model_requests`)
- **目的**：验证 `defer_loading=true` 的动态工具不会被发送到模型
- **业务价值**：支持"懒加载"模式，工具仅在需要时才暴露给模型，减少上下文窗口占用
- **关键验证点**：
  - `defer_loading=true` 的工具不会出现在模型请求中
  - 工具仍保留在线程的工具注册表中，可在后续激活

### 3. 动态工具调用完整链路测试 (`dynamic_tool_call_round_trip_sends_text_content_items_to_model`)
- **目的**：测试从模型发起工具调用到客户端响应的完整流程
- **业务价值**：确保动态工具调用的可靠性，支持客户端实现自定义业务逻辑
- **关键验证点**：
  - 模型触发工具调用后，App Server 向客户端发送 `DynamicToolCall` 请求
  - 客户端响应后，结果被正确转换为 `function_call_output` 发送给模型
  - 通知消息（item/started, item/completed）正确发送

### 4. 结构化内容响应测试 (`dynamic_tool_call_round_trip_sends_content_items_to_model`)
- **目的**：验证动态工具响应支持多种内容类型（文本、图片）
- **业务价值**：支持富媒体交互，如图像分析、多模态响应
- **关键验证点**：
  - 支持 `InputText` 和 `InputImage` 内容项
  - 内容项正确序列化为 JSON 数组格式

## 具体技术实现

### 关键数据结构

#### DynamicToolSpec（协议定义）
```rust
pub struct DynamicToolSpec {
    pub name: String,
    pub description: String,
    pub input_schema: JsonValue,  // JSON Schema 定义输入参数
    pub defer_loading: bool,      // 是否延迟加载（隐藏工具）
}
```

#### DynamicToolCallParams（服务器请求）
```rust
pub struct DynamicToolCallParams {
    pub thread_id: String,
    pub turn_id: String,
    pub call_id: String,
    pub tool: String,           // 工具名称
    pub arguments: JsonValue,   // 调用参数
}
```

#### DynamicToolCallResponse（客户端响应）
```rust
pub struct DynamicToolCallResponse {
    pub content_items: Vec<DynamicToolCallOutputContentItem>,
    pub success: bool,
}
```

### 关键流程

#### 1. 动态工具注册流程
```
Client                     App Server                  Model
  |                           |                          |
  |-- thread/start ---------->|                          |
  |   (dynamic_tools: [...])  |                          |
  |                           |-- inject tools --------->|
  |                           |   into request payload   |
  |                           |                          |
```

#### 2. 动态工具调用流程
```
Client                     App Server                  Model
  |                           |                          |
  |                           |<-- function_call ---------|
  |                           |   (tool name + args)       |
  |                           |                          |
  |<-- DynamicToolCall -------|                          |
  |   ServerRequest           |                          |
  |                           |                          |
  |-- DynamicToolCallResp --->|                          |
  |                           |-- function_call_output -->|
  |                           |   (result)                 |
```

### 测试辅助函数

#### `responses_bodies`
- **功能**：从 MockServer 提取所有 `/responses` 端点的请求体
- **用途**：验证模型请求中是否包含预期的动态工具

#### `find_tool`
- **功能**：在 JSON 请求体中查找指定名称的工具
- **实现**：遍历 `tools` 数组，匹配 `name` 字段

#### `wait_for_dynamic_tool_started/completed`
- **功能**：等待特定的动态工具调用通知
- **实现**：循环读取通知消息，匹配 `call_id` 和 `ThreadItem::DynamicToolCall`

## 关键代码路径与文件引用

### 协议定义
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | `DynamicToolSpec`, `DynamicToolCallParams`, `DynamicToolCallResponse` 定义 |
| `codex-rs/app-server-protocol/src/protocol/common.rs` | `ServerRequest::DynamicToolCall` 枚举定义 |
| `codex-rs/protocol/src/dynamic_tools.rs` | 核心协议动态工具类型定义 |

### 实现代码
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/src/dynamic_tools.rs` | 动态工具响应处理逻辑 |
| `codex-rs/app-server/src/codex_message_processor.rs` | 动态工具调用转发逻辑 |
| `codex-rs/core/src/tools/handlers/dynamic.rs` | 核心层动态工具处理器 |
| `codex-rs/core/src/tools/router.rs` | 工具路由逻辑 |

### 测试支持
| 文件 | 说明 |
|------|------|
| `codex-rs/app-server/tests/common/mcp_process.rs` | MCP 进程封装，提供测试辅助方法 |
| `codex-rs/core_test_support/src/responses.rs` | Mock SSE 响应生成 |

## 依赖与外部交互

### 内部依赖
1. **app_test_support**：提供 `McpProcess` 测试客户端、`create_mock_responses_server_sequence_unchecked`
2. **codex_app_server_protocol**：协议类型定义
3. **codex_protocol**：核心协议类型（`FunctionCallOutputPayload` 等）
4. **core_test_support**：Mock 响应服务器支持

### 外部依赖
1. **wiremock**：HTTP Mock 服务器，模拟 OpenAI Responses API
2. **tempfile**：临时目录管理
3. **tokio**：异步运行时和超时控制
4. **serde_json**：JSON 序列化/反序列化

### 环境要求
- `codex_home` 目录包含 `config.toml` 配置文件
- Mock 模型提供商配置（`mock_provider`）

## 风险、边界与改进建议

### 风险点

1. **超时敏感性**
   - 测试使用 `DEFAULT_READ_TIMEOUT = 10s` 超时
   - 在慢速 CI 环境可能导致 flaky 测试
   - **建议**：考虑使用更宽松的 CI 环境超时，或实现重试机制

2. **Mock 服务器依赖**
   - 测试依赖 wiremock 的精确请求匹配
   - 如果协议变更，Mock 设置可能过时
   - **建议**：定期审查 Mock 响应格式与实际 API 的一致性

3. **并发安全性**
   - 测试使用 `tokio::time::timeout` 进行并发控制
   - 多个测试同时运行时可能产生端口冲突
   - **建议**：使用动态端口分配或串行化测试

### 边界情况

1. **defer_loading 语义**
   - 当前测试仅验证工具不出现在模型请求中
   - 未测试延迟加载工具后续激活的场景
   - **建议**：补充动态工具从隐藏到激活的测试用例

2. **错误处理**
   - 测试主要关注成功路径
   - 缺少客户端不响应或返回错误格式的测试
   - **建议**：添加 `dynamic_tool_call_client_error` 测试用例

3. **内容项类型限制**
   - 当前仅测试 `InputText` 和 `InputImage`
   - 未覆盖其他可能的内容类型
   - **建议**：根据协议扩展添加更多内容类型测试

### 改进建议

1. **测试覆盖率**
   - 添加动态工具名称冲突的测试
   - 测试 JSON Schema 验证失败场景
   - 测试大量动态工具（性能边界）

2. **代码组织**
   - 提取公共的 Mock 服务器设置逻辑
   - 复用 `create_config_toml` 函数（当前内联定义）

3. **可观测性**
   - 添加更详细的断言失败信息
   - 记录关键步骤的日志输出

4. **协议演进**
   - 跟踪 `expose_to_context` 字段的弃用进度
   - 准备移除对旧字段的兼容性测试
