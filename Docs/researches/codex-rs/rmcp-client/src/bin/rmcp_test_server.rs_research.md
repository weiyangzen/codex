# rmcp_test_server.rs 研究文档

## 场景与职责

`rmcp_test_server.rs` 是 Codex 项目中用于 MCP (Model Context Protocol) 集成测试的基础测试服务器。它是一个基于 STDIO 传输的 MCP 服务器二进制文件，主要用于：

1. **核心集成测试**：作为 `codex-rs/core/tests/suite/rmcp_client.rs` 中 `stdio_server_round_trip` 测试的依赖目标
2. **环境变量传播验证**：测试 MCP 服务器配置中的环境变量是否正确传递给子进程
3. **基础工具调用测试**：提供简单的 `echo` 工具用于验证 MCP 工具调用链路

该文件是三个测试服务器中最简单的一个，仅实现最基本的工具功能，用于验证核心 MCP 客户端-服务器通信流程。

## 功能点目的

### 1. 基础 Echo 工具
- **目的**：提供最简单的工具调用验证能力
- **功能**：接收消息参数，返回带有环境变量快照的结构化响应
- **特点**：
  - 工具名称为 `"echo"`
  - 支持 `message`（必需）和 `env_var`（可选）参数
  - 返回 JSON 格式的结构化内容，包含回显消息和环境变量值

### 2. 环境变量捕获
- **目的**：验证 MCP 服务器配置中的环境变量是否正确传递
- **实现**：通过 `std::env::vars()` 捕获 `MCP_TEST_VALUE` 环境变量
- **测试场景**：用于验证 `env` 和 `env_vars` 配置字段的传播

### 3. STDIO 传输支持
- **目的**：支持基于标准输入输出的 MCP 通信
- **实现**：使用 `rmcp` 库的 `serve(stdio())` API
- **生命周期**：客户端连接 -> 服务处理 -> 客户端断开 -> 进程退出

## 具体技术实现

### 关键数据结构

```rust
#[derive(Clone)]
struct TestToolServer {
    tools: Arc<Vec<Tool>>,
}

#[derive(Deserialize)]
struct EchoArgs {
    message: String,
    env_var: Option<String>,
}
```

### ServerHandler 实现

文件实现了 `rmcp::handler::server::ServerHandler` trait，提供以下方法：

1. **`get_info`**：返回服务器能力声明
   - 启用工具支持 (`enable_tools`)
   - 启用工具列表变更通知 (`enable_tool_list_changed`)

2. **`list_tools`**：返回可用工具列表（仅包含 echo 工具）

3. **`call_tool`**：处理工具调用
   - 解析请求参数
   - 捕获环境变量
   - 返回结构化 JSON 响应

### 工具 Schema 定义

```rust
{
    "type": "object",
    "properties": {
        "message": { "type": "string" },
        "env_var": { "type": "string" }
    },
    "required": ["message"],
    "additionalProperties": false
}
```

### 主函数流程

```rust
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // 1. 创建服务实例
    let service = TestToolServer::new();
    
    // 2. 启动 STDIO 服务
    let running = service.serve(stdio()).await?;
    
    // 3. 等待客户端交互完成
    running.waiting().await?;
    
    // 4. 清理后台任务
    task::yield_now().await;
    Ok(())
}
```

## 关键代码路径与文件引用

### 当前文件
- **路径**：`codex-rs/rmcp-client/src/bin/rmcp_test_server.rs`
- **行数**：143 行

### 调用方（测试代码）

1. **核心集成测试**
   - 文件：`codex-rs/core/tests/suite/rmcp_client.rs`
   - 函数：`stdio_server_round_trip` (行 56-194)
   - 使用方式：通过 `stdio_server_bin()` 获取二进制路径
   - 环境变量注入：`MCP_TEST_VALUE` 用于验证传播

2. **测试辅助函数**
   - 文件：`codex-rs/core/tests/common/lib.rs`
   - 函数：`stdio_server_bin` (行 287-289)
   - 实现：调用 `codex_utils_cargo_bin::cargo_bin("test_stdio_server")`

### 依赖库

1. **rmcp 库**
   - 提供 MCP 协议实现
   - 关键 trait：`ServerHandler`, `ServiceExt`
   - 关键类型：`Tool`, `CallToolResult`, `ServerInfo`

2. **serde / serde_json**
   - 用于参数反序列化和响应序列化

3. **tokio**
   - 异步运行时
   - 提供 `stdin()` / `stdout()` 用于 STDIO 传输

## 依赖与外部交互

### 编译依赖

```toml
# Cargo.toml (codex-rs/rmcp-client/Cargo.toml)
[dependencies]
rmcp = { workspace = true, features = [
    "auth",
    "base64",
    "client",
    "macros",
    "schemars",
    "server",
    "transport-child-process",
    "transport-streamable-http-client-reqwest",
    "transport-streamable-http-server",
] }
serde = { workspace = true, features = ["derive"] }
serde_json = { workspace = true }
tokio = { workspace = true, features = ["io-std", "time", ...] }
```

### 运行时环境变量

| 变量名 | 用途 | 示例值 |
|--------|------|--------|
| `MCP_TEST_VALUE` | 被捕获并回显的环境变量 | `"propagated-env"` |

### 输入输出

- **输入**：STDIN 接收 MCP JSON-RPC 消息
- **输出**：STDOUT 发送 MCP JSON-RPC 响应
- **日志**：STDERR 输出启动信息 `"starting rmcp test server"`

## 风险、边界与改进建议

### 当前风险

1. **功能单一**：仅实现 echo 工具，无法测试更复杂的 MCP 场景（如资源、图片等）
2. **命名混淆**：与 `test_stdio_server.rs` 功能重叠但更简单，容易造成选择困惑
3. **硬编码工具定义**：工具 schema 在代码中硬编码，修改需要重新编译

### 边界情况

1. **参数验证**：
   - 缺少 `message` 参数会返回 `invalid_params` 错误
   - 未知工具名返回错误
   - 使用 `#[expect(clippy::expect_used)]` 允许在 schema 解析时使用 `expect`

2. **环境变量**：
   - `env_var` 参数被标记为 `#[allow(dead_code)]`，实际上未被使用
   - 仅捕获 `MCP_TEST_VALUE`，其他环境变量被忽略

3. **并发安全**：
   - 使用 `Arc<Vec<Tool>>` 共享工具定义
   - 无状态设计，线程安全

### 改进建议

1. **合并考虑**：
   - 考虑与 `test_stdio_server.rs` 合并，通过 feature flag 或配置控制功能集
   - 或者明确文档说明各自的使用场景

2. **功能扩展**：
   - 添加健康检查工具
   - 支持动态工具注册（用于测试工具列表变更通知）

3. **错误处理**：
   - 当前使用 `expect` 处理 schema 解析，建议改为返回错误
   - 添加更详细的错误日志

4. **文档**：
   - 添加模块级文档说明使用场景
   - 明确与 `test_stdio_server.rs` 的区别

### 相关测试覆盖

- `codex-rs/core/tests/suite/rmcp_client.rs::stdio_server_round_trip` - 基础工具调用
- `codex-rs/core/tests/suite/rmcp_client.rs::stdio_server_propagates_whitelisted_env_vars` - 环境变量传播

### 维护建议

该文件作为基础测试服务器，应保持简单稳定。新增功能建议优先考虑 `test_stdio_server.rs`，避免功能重叠。
