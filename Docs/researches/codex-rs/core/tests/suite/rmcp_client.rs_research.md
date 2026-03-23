# rmcp_client.rs 研究文档

## 场景与职责

`rmcp_client.rs` 是 Codex Core 的集成测试套件，专注于测试 **Model Context Protocol (MCP)** 客户端功能。MCP 是 OpenAI 推出的协议，用于标准化 AI 模型与外部工具/资源的交互。本测试文件验证 Codex 通过 RMCP (Rust MCP) 客户端与 MCP 服务器通信的能力，包括：

- **Stdio 传输模式**：通过标准输入/输出与本地 MCP 服务器进程通信
- **Streamable HTTP 传输模式**：通过 HTTP 流与远程 MCP 服务器通信
- **OAuth 认证**：测试带认证的 MCP 服务器连接
- **图像内容处理**：验证 MCP 工具返回的图像数据能正确传递给模型

## 功能点目的

### 1. Stdio 服务器往返测试 (`stdio_server_round_trip`)
验证 Codex 能通过标准输入/输出与本地 MCP 服务器进行完整交互：
- 配置 MCP 服务器使用 `McpServerTransportConfig::Stdio`
- 环境变量传递（`MCP_TEST_VALUE`）
- 工具调用（`echo` 工具）和结果验证
- 事件验证：`McpToolCallBegin` 和 `McpToolCallEnd`

### 2. 图像响应往返测试 (`stdio_image_responses_round_trip`)
测试 MCP 工具返回图像内容时的完整流程：
- 图像数据通过 Base64 data URL 传递
- 工具返回 `ImageContent` 类型结果
- 验证响应格式符合 OpenAI 图像输入规范

### 3. 纯文本模型图像清理测试 (`stdio_image_responses_are_sanitized_for_text_only_model`)
验证当模型不支持图像输入时，图像内容会被正确替换为文本提示：
- 模拟纯文本模型（`input_modalities: [Text]`）
- 验证图像被替换为 `"<image content omitted because you do not support image input>"`

### 4. 环境变量白名单测试 (`stdio_server_propagates_whitelisted_env_vars`)
测试通过 `env_vars` 配置传递特定环境变量的能力：
- 使用 `env_vars: vec!["MCP_TEST_VALUE"]` 而非直接设置 `env`
- 验证父进程环境变量正确传递到 MCP 服务器

### 5. Streamable HTTP 工具调用测试 (`streamable_http_tool_call_round_trip`)
验证通过 HTTP 流与 MCP 服务器通信：
- 启动本地 HTTP MCP 服务器（`test_streamable_http_server`）
- 使用 `McpServerTransportConfig::StreamableHttp`
- 验证工具调用和响应

### 6. OAuth 认证测试 (`streamable_http_with_oauth_round_trip`)
测试带 OAuth 认证的 MCP 服务器连接：
- 配置 `bearer_token_env_var` 和 OAuth 凭证存储
- 验证认证头正确传递

## 具体技术实现

### 关键数据结构

```rust
// MCP 服务器配置（来自 codex_core::config::types）
McpServerConfig {
    transport: McpServerTransportConfig::Stdio {
        command: String,           // 服务器可执行文件路径
        args: Vec<String>,         // 启动参数
        env: Option<HashMap>,      // 环境变量（直接设置）
        env_vars: Vec<String>,     // 环境变量（从父进程继承）
        cwd: Option<PathBuf>,      // 工作目录
    },
    enabled: bool,
    required: bool,
    startup_timeout_sec: Option<Duration>,
    tool_timeout_sec: Option<Duration>,
    // ... 其他字段
}
```

### 测试流程

1. **启动 Mock 服务器**：`responses::start_mock_server()` 启动 WireMock 服务器模拟 OpenAI API
2. **配置 MCP 服务器**：通过 `test_codex().with_config()` 注入 MCP 配置
3. **挂载 SSE 响应**：使用 `mount_sse_once()` 模拟模型响应
4. **提交用户输入**：`Op::UserTurn` 触发工具调用
5. **等待事件**：`wait_for_event()` 验证 `McpToolCallBegin/End`
6. **验证结果**：检查工具返回的结构化内容

### 关键代码路径

```
test_codex()
  └─ TestCodexBuilder::build()
       └─ ThreadManager::start_thread()
            └─ Session 初始化
                 └─ McpConnectionManager::new()  // 建立 MCP 连接

Op::UserTurn 提交
  └─ Codex::submit()
       └─ 模型决定调用工具
            └─ McpToolCallHandler::handle()
                 └─ Session::call_tool()
                      └─ McpConnectionManager::call_tool()
                           └─ RmcpClient::call_tool()  // 实际 RPC 调用
```

## 依赖与外部交互

### 内部依赖

| 模块 | 用途 |
|------|------|
| `codex_core::config::types::McpServerConfig` | MCP 服务器配置定义 |
| `codex_core::mcp_connection_manager` | MCP 连接生命周期管理 |
| `codex_protocol::protocol::{McpToolCallBeginEvent, McpToolCallEndEvent}` | 工具调用事件 |
| `core_test_support` | 测试基础设施（Mock 服务器、事件等待） |

### 外部依赖

| 组件 | 用途 |
|------|------|
| `test_stdio_server` | 测试用的 MCP 服务器（stdio 模式） |
| `test_streamable_http_server` | 测试用的 MCP 服务器（HTTP 模式） |
| WireMock | 模拟 OpenAI API 响应 |

### 测试辅助函数

- `stdio_server_bin()`: 获取测试 stdio 服务器二进制路径
- `wait_for_streamable_http_server()`: 等待 HTTP 服务器就绪
- `write_fallback_oauth_tokens()`: 写入测试 OAuth 凭证
- `EnvVarGuard`: 环境变量临时设置（RAII 模式）

## 风险、边界与改进建议

### 当前风险

1. **网络依赖**：测试需要网络连接（`skip_if_no_network!`），在沙箱环境中会被跳过
2. **序列化执行**：使用 `#[serial(mcp_test_value)]` 防止环境变量污染，但增加测试时间
3. **平台限制**：部分测试依赖特定平台二进制（`test_streamable_http_server`）

### 边界情况

1. **超时处理**：MCP 服务器启动超时（默认 10 秒）和工具调用超时
2. **并发工具调用**：多个 MCP 服务器同时连接时的资源竞争
3. **凭证过期**：OAuth 测试使用硬编码凭证，可能因过期失败

### 改进建议

1. **Mock MCP 服务器**：使用纯 Rust 实现的 Mock MCP 服务器，消除外部二进制依赖
2. **并行执行**：使用进程隔离替代 `serial` 属性，加速测试套件
3. **凭证管理**：使用动态生成的测试凭证，避免硬编码
4. **覆盖率扩展**：
   - 添加 MCP 资源（Resource）读取测试
   - 测试 MCP 服务器启动失败恢复
   - 测试工具超时和重试逻辑

### 相关文件引用

- `codex-rs/core/src/mcp/mod.rs` - MCP 模块定义
- `codex-rs/core/src/mcp_connection_manager.rs` - MCP 连接管理
- `codex-rs/core/src/mcp_tool_call.rs` - MCP 工具调用处理
- `codex-rs/core/tests/common/responses.rs` - Mock 响应基础设施
- `codex-rs/rmcp/client/src/lib.rs` - RMCP 客户端实现
