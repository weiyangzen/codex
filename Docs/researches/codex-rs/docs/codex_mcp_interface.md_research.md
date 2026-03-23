# Codex MCP Server Interface 研究文档

## 场景与职责

本文档描述 Codex 的实验性 MCP（Model Context Protocol）服务器接口。这是一个 JSON-RPC API，通过 MCP 传输层控制本地 Codex 引擎。

### 核心定位

- **状态**: 实验性，可能随时变更
- **服务器二进制**: `codex mcp-server` 或 `codex-mcp-server`
- **传输层**: 标准 MCP over stdio（JSON-RPC 2.0，行分隔）
- **用途**: 为 IDE 扩展（如 VS Code）和其他客户端提供程序化控制接口

### 与 app-server 的关系

MCP 服务器接口与 `codex app-server` 的协议共享底层类型定义（位于 `app-server-protocol/src/protocol/{common,v1,v2}.rs`），但提供不同的传输封装：

- **app-server**: 专用 JSON-RPC 协议，支持 WebSocket 和 stdio
- **MCP server**: 标准 MCP 协议，更好的生态兼容性

## 功能点目的

### 1. 主要 RPC 方法

#### v2 API（推荐用于新集成）

| 类别 | 方法 | 用途 |
|------|------|------|
| **Thread 生命周期** | `thread/start`, `thread/resume`, `thread/fork` | 创建、恢复、分叉对话线程 |
| **Thread 管理** | `thread/read`, `thread/list` | 读取和列举线程 |
| **Turn 控制** | `turn/start`, `turn/steer`, `turn/interrupt` | 启动、引导、中断对话轮次 |
| **账户管理** | `account/read`, `account/login/start`, `account/logout` | 用户认证和账户信息 |
| **配置管理** | `config/read`, `config/value/write`, `config/batchWrite` | 配置读写 |
| **模型/应用** | `model/list`, `app/list`, `collaborationMode/list` | 列举可用资源 |

#### v1 兼容 API

- `getConversationSummary`: 获取对话摘要
- `getAuthStatus`: 获取认证状态
- `gitDiffToRemote`: 获取与远程的 git diff
- `fuzzyFileSearch`: 模糊文件搜索

### 2. 通知机制

| 通知类型 | 示例 | 用途 |
|----------|------|------|
| v2 类型化通知 | `thread/started`, `turn/completed` | 生命周期事件 |
| 事件流 | `codex/event/*` | 实时代理事件 |
| 搜索事件 | `fuzzyFileSearch/sessionUpdated` | 文件搜索进度 |

### 3. 审批流程（Server → Client）

当 Codex 需要用户批准时，服务器向客户端发送 JSON-RPC 请求：

- `applyPatchApproval`: 应用代码补丁审批
- `execCommandApproval`: 执行命令审批

客户端必须回复 `{ decision: "allow" | "deny" }`。

## 具体技术实现

### 1. 启动服务器

```bash
# 基本启动
codex mcp-server | your_mcp_client

# 使用 MCP Inspector 调试
npx @modelcontextprotocol/inspector codex mcp-server
```

### 2. 协议类型定义

核心类型位于 `app-server-protocol/src/protocol/`：

```rust
// common.rs - 共享类型和宏定义
// v1.rs - v1 API 类型
// v2.rs - v2 API 类型（主要开发目标）
```

### 3. v2 API 设计规范

根据 `AGENTS.md` 中的规范：

#### 命名约定
- 请求参数: `*Params`
- 响应: `*Response`
- 通知: `*Notification`
- RPC 方法: `<resource>/<method>`（resource 使用单数）

#### 序列化规则
- 默认使用 camelCase: `#[serde(rename_all = "camelCase")]`
- 配置相关使用 snake_case（匹配 config.toml）
- TypeScript 导出: `#[ts(export_to = "v2/")]`

#### 可选字段处理
- 不使用 `skip_serializing_if = "Option::is_none"`
- 客户端→服务器请求使用 `#[ts(optional = nullable)]`
- 集合类型使用 `Option<Vec/HashMap>` 而非 `#[serde(default)]`

### 4. 模型列表响应结构

```json
{
  "data": [
    {
      "id": "gpt-5.1-codex",
      "model": "gpt-5.1-codex",
      "displayName": "GPT-5.1 Codex",
      "description": "...",
      "supportedReasoningEfforts": [
        { "reasoningEffort": "medium", "description": "..." }
      ],
      "defaultReasoningEffort": "medium",
      "inputModalities": ["text", "image"],
      "supportsPersonality": true,
      "isDefault": true,
      "upgrade": "gpt-5.2-codex",
      "upgradeInfo": { ... }
    }
  ],
  "nextCursor": "opaque-token"
}
```

### 5. 协作模式（实验性）

`collaborationMode/list` 返回内置协作模式预设：

```json
{
  "data": [
    {
      "id": "code-review",
      "name": "Code Review",
      "settings": {
        "reasoning_effort": "high",
        "developer_instructions": null  // null 表示使用内置指令
      }
    }
  ]
}
```

### 6. 工具响应格式

`codex` 和 `codex-reply` 工具返回标准 MCP `CallToolResult`：

```json
{
  "content": [{ "type": "text", "text": "Hello from Codex" }],
  "structuredContent": {
    "threadId": "019bbed6-1e9e-7f31-984c-a05b65045719",
    "content": "Hello from Codex"
  }
}
```

## 关键代码路径与文件引用

### 协议定义

| 文件路径 | 内容 |
|----------|------|
| `codex-rs/app-server-protocol/src/protocol/common.rs` | 共享类型、宏定义、ClientRequest/ServerRequest 枚举 |
| `codex-rs/app-server-protocol/src/protocol/v1.rs` | v1 API 类型定义 |
| `codex-rs/app-server-protocol/src/protocol/v2.rs` | v2 API 类型定义（主要开发目标） |
| `codex-rs/app-server-protocol/src/protocol/mod.rs` | 模块导出 |
| `codex-rs/app-server-protocol/src/protocol/mappers.rs` | 类型映射转换 |

### MCP 服务器实现

| 文件路径 | 内容 |
|----------|------|
| `codex-rs/mcp-server/src/main.rs` | 入口点，调用 `run_main` |
| `codex-rs/mcp-server/src/lib.rs` | 主库，消息循环和任务协调 |
| `codex-rs/mcp-server/src/message_processor.rs` | JSON-RPC 消息处理 |
| `codex-rs/mcp-server/src/codex_tool_config.rs` | Codex 工具配置 |
| `codex-rs/mcp-server/src/codex_tool_runner.rs` | 工具执行逻辑 |
| `codex-rs/mcp-server/src/exec_approval.rs` | 执行命令审批流程 |
| `codex-rs/mcp-server/src/patch_approval.rs` | 补丁审批流程 |
| `codex-rs/mcp-server/src/outgoing_message.rs` | 出站消息封装 |

### 相关文档

| 文件路径 | 内容 |
|----------|------|
| `codex-rs/docs/codex_mcp_interface.md` | 本文档的源文件 |
| `codex-rs/app-server/README.md` | app-server 详细文档 |

## 依赖与外部交互

### 1. 内部依赖

```rust
// 核心依赖
codex_core::config::Config          // 配置管理
codex_arg0::Arg0DispatchPaths       // 参数分发
codex_utils_cli::CliConfigOverrides // CLI 配置覆盖

// 协议依赖（通过 rmcp crate）
rmcp::model::ClientNotification
rmcp::model::ClientRequest
rmcp::model::JsonRpcMessage
```

### 2. 外部 crate 依赖

```toml
rmcp = "0.15.0"           # MCP 协议实现
tokio = "1"               # 异步运行时
tracing = "0.1"           # 日志和追踪
serde_json = "1"          # JSON 序列化
```

### 3. 传输层

- **输入**: 从 stdin 读取行分隔的 JSON-RPC 消息
- **输出**: 向 stdout 写入行分隔的 JSON-RPC 响应
- **并发**: 使用 Tokio 多任务处理：
  - 任务1: stdin 读取器 → incoming_tx
  - 任务2: 消息处理器（MessageProcessor）
  - 任务3: stdout 写入器 ← outgoing_rx

### 4. 与 Codex Core 的交互

```rust
// 配置加载
let config = Config::load_with_cli_overrides(cli_kv_overrides).await?;

// OpenTelemetry 初始化
codex_core::otel_init::build_provider(&config, ...)?;

// 工具调用通过 MessageProcessor 协调
let processor = MessageProcessor::new(
    outgoing_message_sender,
    arg0_paths,
    Arc::new(config),
);
```

## 风险、边界与改进建议

### 当前风险

1. **实验性状态**: 接口可能随时变更，不适合生产环境稳定依赖
2. **功能覆盖**: 相比 app-server，MCP 接口可能缺少某些高级功能
3. **错误处理**: 需要确保所有错误都正确转换为 MCP 错误格式

### 边界条件

1. **传输限制**: stdio 传输有缓冲区限制，大量数据需要流式处理
2. **并发限制**: `CHANNEL_CAPACITY = 128`，高并发场景可能需要调整
3. **平台差异**: 某些功能（如 Windows 沙箱）可能有平台特定限制

### 改进建议

1. **稳定化路线图**:
   - 明确稳定化时间表
   - 提供版本兼容性保证
   - 添加更多集成测试

2. **功能增强**:
   - 支持更多 app-server 的功能
   - 添加 WebSocket 传输选项（如 app-server）
   - 改进错误消息和调试信息

3. **文档完善**:
   - 提供完整的 API 参考
   - 添加更多使用示例
   - 编写客户端 SDK 指南

4. **性能优化**:
   - 评估并调整通道容量
   - 优化大文件传输
   - 添加流量控制机制

5. **生态集成**:
   - 发布到 MCP 官方服务器列表
   - 提供 TypeScript 客户端库
   - 与更多 IDE 集成

### 相关参考

- MCP 协议规范: https://modelcontextprotocol.io/
- MCP Inspector: https://github.com/modelcontextprotocol/inspector
- app-server README: `codex-rs/app-server/README.md`
