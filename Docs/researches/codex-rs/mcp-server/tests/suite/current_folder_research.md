# Research: codex-rs/mcp-server/tests/suite

## 场景与职责

`codex-rs/mcp-server/tests/suite` 是 Codex MCP (Model Context Protocol) 服务器的集成测试套件目录。该目录包含对 MCP 服务器核心功能的端到端测试，主要验证以下场景：

1. **MCP 服务器与 Codex 核心的集成测试**：验证 MCP 服务器能够正确启动 Codex 会话、处理工具调用、并与后端模型服务通信。
2. **审批流程测试**：验证当 Codex 执行 shell 命令或应用代码补丁时，MCP 服务器能够正确触发审批请求（elicitation）并处理用户响应。
3. **配置传递测试**：验证工具调用参数（如基础指令、开发者指令）能够正确传递到 Codex 核心。

该测试套件通过模拟 MCP 客户端与真实 MCP 服务器进程通信，配合 Mock 模型服务器来验证完整的数据流。

## 功能点目的

### 1. Shell 命令审批测试 (`test_shell_command_approval_triggers_elicitation`)
- **目的**：验证当 Codex 尝试执行非受信任的 shell 命令时，MCP 服务器会暂停执行并向客户端发送审批请求（elicitation/create）。
- **流程**：
  1. 启动 MCP 服务器并配置 `approval_policy = "untrusted"`
  2. 发送 `tools/call` 请求调用 `codex` 工具
  3. Mock 模型服务器返回包含 `shell_command` 函数调用的 SSE 响应
  4. 验证 MCP 服务器发送 `elicitation/create` 请求
  5. 模拟客户端批准执行
  6. 验证命令实际执行（创建测试文件）
  7. 验证最终工具调用响应包含正确内容

### 2. 代码补丁审批测试 (`test_patch_approval_triggers_elicitation`)
- **目的**：验证当 Codex 尝试应用代码补丁时，MCP 服务器会触发补丁审批流程。
- **流程**：
  1. 创建临时工作目录和测试文件
  2. 发送 `codex` 工具调用请求
  3. Mock 模型服务器返回包含 `apply_patch` 命令的 SSE 响应
  4. 验证 MCP 服务器发送包含补丁变更详情的审批请求
  5. 模拟客户端批准补丁应用
  6. 验证文件内容被正确修改

### 3. 指令传递测试 (`test_codex_tool_passes_base_instructions`)
- **目的**：验证 `base_instructions` 和 `developer_instructions` 参数能够正确传递到后端模型请求。
- **验证点**：
  - 请求体中的 `instructions` 字段包含基础指令
  - `input` 数组中包含角色为 `developer` 的消息
  - 开发者消息内容包含传入的 `developer_instructions`

## 具体技术实现

### 关键数据结构

#### 1. MCP 工具调用参数 (`CodexToolCallParam`)
```rust
pub struct CodexToolCallParam {
    pub prompt: String,
    pub model: Option<String>,
    pub profile: Option<String>,
    pub cwd: Option<String>,
    pub approval_policy: Option<CodexToolCallApprovalPolicy>,
    pub sandbox: Option<CodexToolCallSandboxMode>,
    pub config: Option<HashMap<String, serde_json::Value>>,
    pub base_instructions: Option<String>,
    pub developer_instructions: Option<String>,
    pub compact_prompt: Option<String>,
}
```

#### 2. 执行审批请求参数 (`ExecApprovalElicitRequestParams`)
```rust
pub struct ExecApprovalElicitRequestParams {
    pub message: String,
    pub requested_schema: Value,
    pub thread_id: ThreadId,
    pub codex_elicitation: String,
    pub codex_mcp_tool_call_id: String,
    pub codex_event_id: String,
    pub codex_call_id: String,
    pub codex_command: Vec<String>,
    pub codex_cwd: PathBuf,
    pub codex_parsed_cmd: Vec<ParsedCommand>,
}
```

#### 3. 补丁审批请求参数 (`PatchApprovalElicitRequestParams`)
```rust
pub struct PatchApprovalElicitRequestParams {
    pub message: String,
    pub requested_schema: Value,
    pub thread_id: ThreadId,
    pub codex_elicitation: String,
    pub codex_mcp_tool_call_id: String,
    pub codex_event_id: String,
    pub codex_call_id: String,
    pub codex_reason: Option<String>,
    pub codex_grant_root: Option<PathBuf>,
    pub codex_changes: HashMap<PathBuf, FileChange>,
}
```

### 关键流程

#### 测试流程架构
```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Test Case     │────▶│  McpProcess      │────▶│  MCP Server     │
│  (codex_tool.rs)│     │  (mcp_process.rs)│     │  (binary)       │
└─────────────────┘     └──────────────────┘     └─────────────────┘
                                                        │
                                                        ▼
                                               ┌─────────────────┐
                                               │  Mock Server    │
                                               │ (mock_model_    │
                                               │  server.rs)     │
                                               └─────────────────┘
```

#### 消息处理流程
1. **初始化**：`McpProcess::initialize()` 执行 MCP 握手协议
   - 发送 `initialize` 请求
   - 接收服务器能力声明
   - 发送 `notifications/initialized` 确认

2. **工具调用**：`McpProcess::send_codex_tool_call()`
   - 构造 `tools/call` JSON-RPC 请求
   - 发送请求并返回请求 ID

3. **事件监听**：`McpProcess::read_stream_until_request_message()`
   - 从 stdout 读取 JSON-RPC 消息
   - 过滤通知消息，返回请求消息（如 elicitation/create）

4. **响应发送**：`McpProcess::send_response()`
   - 构造 JSON-RPC 响应
   - 写入 stdin

### 协议与通信

#### MCP JSON-RPC 消息格式
```json
// 工具调用请求
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "codex",
    "arguments": {
      "prompt": "run `git init`"
    }
  }
}

// 审批请求（服务器→客户端）
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "elicitation/create",
  "params": {
    "message": "Allow Codex to run `touch test.txt` in `/tmp/...`?",
    "requestedSchema": {"type": "object", "properties": {}},
    "threadId": "...",
    "codexElicitation": "exec-approval",
    ...
  }
}

// 审批响应（客户端→服务器）
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "decision": "approved"
  }
}
```

#### SSE Mock 响应格式
```
event: response.created
data: {"id": "resp-call1234"}

event: response.function_call_arguments.delta
data: {"call_id": "call1234", "name": "shell_command", "arguments": "{\"command\": \"touch test.txt\"}"}

event: response.completed
data: {"id": "resp-call1234"}
```

## 关键代码路径与文件引用

### 测试文件
| 文件 | 职责 |
|------|------|
| `tests/suite/mod.rs` | 测试模块入口，声明 `codex_tool` 子模块 |
| `tests/suite/codex_tool.rs` | 核心测试用例实现（516 行） |
| `tests/all.rs` | 集成测试二进制入口，聚合所有测试模块 |

### 测试辅助库
| 文件 | 职责 |
|------|------|
| `tests/common/lib.rs` | 公共导出（22 行） |
| `tests/common/mcp_process.rs` | MCP 进程管理（399 行） |
| `tests/common/mock_model_server.rs` | Mock 模型服务器（47 行） |
| `tests/common/responses.rs` | SSE 响应构造工具（47 行） |

### 被测源码
| 文件 | 职责 |
|------|------|
| `src/lib.rs` | MCP 服务器主入口（227 行） |
| `src/main.rs` | 二进制入口（11 行） |
| `src/message_processor.rs` | JSON-RPC 消息处理（603 行） |
| `src/codex_tool_runner.rs` | Codex 工具执行（434 行） |
| `src/exec_approval.rs` | 执行审批逻辑（147 行） |
| `src/patch_approval.rs` | 补丁审批逻辑（142 行） |
| `src/codex_tool_config.rs` | 工具配置定义（433 行） |
| `src/outgoing_message.rs` | 消息发送管理（472 行） |
| `src/tool_handlers/mod.rs` | 工具处理器模块声明（2 行） |

### 关键函数调用链
```
test_shell_command_approval_triggers_elicitation
  └── shell_command_approval_triggers_elicitation
      └── create_mcp_process
          ├── create_mock_responses_server  [mock_model_server.rs:13]
          ├── create_config_toml            [codex_tool.rs:493]
          ├── McpProcess::new               [mcp_process.rs:46]
          └── McpProcess::initialize        [mcp_process.rs:113]
              └── send_jsonrpc_message      [mcp_process.rs:250]
      ├── McpProcess::send_codex_tool_call  [mcp_process.rs:201]
      ├── McpProcess::read_stream_until_request_message [mcp_process.rs:274]
      └── McpProcess::send_response         [mcp_process.rs:237]
```

## 依赖与外部交互

### 内部依赖
| Crate | 用途 |
|-------|------|
| `codex-core` | Codex 核心功能（ThreadManager, Config, AuthManager） |
| `codex-protocol` | 协议类型（ThreadId, Event, EventMsg, Op, ReviewDecision） |
| `codex-shell-command` | Shell 命令解析（parse_command） |
| `codex-arg0` | 可执行文件路径管理（Arg0DispatchPaths） |
| `codex-utils-cli` | CLI 配置覆盖（CliConfigOverrides） |
| `codex-utils-json-to-toml` | JSON 到 TOML 转换 |
| `core_test_support` | 测试支持库（skip_if_no_network, format_with_current_shell） |
| `mcp_test_support` | MCP 测试支持（McpProcess, SSE 响应构造） |

### 外部依赖
| Crate | 用途 |
|-------|------|
| `rmcp` | MCP 协议实现（JSON-RPC 消息类型、工具定义） |
| `tokio` | 异步运行时 |
| `serde`/`serde_json` | 序列化/反序列化 |
| `wiremock` | HTTP Mock 服务器（模拟模型服务端点） |
| `tempfile` | 临时目录/文件管理 |
| `pretty_assertions` | 测试断言美化 |

### 环境变量
| 变量 | 用途 |
|------|------|
| `CODEX_HOME` | 指定 Codex 配置目录（测试中使用临时目录） |
| `CODEX_SANDBOX_NETWORK_DISABLED` | 网络禁用标志（测试跳过条件） |
| `RUST_LOG` | 日志级别（测试中设为 "debug"） |

## 风险、边界与改进建议

### 当前风险

1. **平台差异**
   - Shell 命令测试在 Windows 上使用 PowerShell (`New-Item`)，在 Unix 上使用 `touch`
   - 补丁审批测试在 Windows 上被完全跳过（`if cfg!(windows) { return Ok(()) }`）
   - 建议：增加更多平台的测试覆盖，或明确文档化平台限制

2. **网络依赖**
   - 部分测试需要网络连接（使用 `skip_if_no_network!()` 宏跳过）
   - 测试在沙箱环境中可能无法运行（检查 `CODEX_SANDBOX_NETWORK_DISABLED`）
   - 建议：将网络依赖测试与纯本地测试分离

3. **超时风险**
   - 默认读取超时为 20 秒（`DEFAULT_READ_TIMEOUT`）
   - CI 环境或慢速机器上可能出现 flaky 测试
   - 建议：根据 CI 环境动态调整超时时间

4. **进程清理**
   - `McpProcess::drop` 实现了同步清理逻辑，但依赖 `tokio::process` 的 `kill_on_drop`
   - 文档中提到可能存在进程泄漏检测误报（LEAK）
   - 建议：增加更健壮的进程生命周期管理

### 边界情况

1. **并发处理**
   - 测试使用 `multi_thread` 运行时（2-4 个 worker 线程）
   - `running_requests_id_to_codex_uuid` 使用 `Arc<Mutex<HashMap>>` 管理并发访问
   - 边界：高并发场景下的请求 ID 冲突风险

2. **消息顺序**
   - `read_stream_until_request_message` 会跳过所有通知消息直到找到请求
   - 边界：如果服务器发送大量通知，可能导致读取延迟

3. **配置覆盖**
   - 测试通过 `create_config_toml` 创建临时配置
   - 边界：某些配置项可能无法通过 TOML 完全覆盖

### 改进建议

1. **测试覆盖率**
   - 当前只有 3 个主要测试用例
   - 建议增加：
     - 错误处理测试（无效参数、网络超时）
     - 并发会话测试（多个 thread 同时运行）
     - 取消操作测试（`CancelledNotification`）
     - 工具回复测试（`codex-reply` 工具）

2. **测试可维护性**
   - 测试代码中存在大量重复的 JSON 构造逻辑
   - 建议：提取公共的响应构造辅助函数

3. **Mock 服务器增强**
   - 当前 `SeqResponder` 仅支持顺序响应
   - 建议：支持基于请求内容的动态响应

4. **文档化**
   - 测试辅助函数缺乏文档注释
   - 建议：为 `McpProcess` 的公共方法添加 rustdoc

5. **性能优化**
   - 每个测试用例都启动新的 MCP 服务器进程（约 1-2 秒）
   - 建议：考虑测试间的服务器复用机制（需解决状态隔离问题）

### 相关 TODO（来自源码）

- `exec_approval.rs:41-43`：`ExecApprovalResponse` 不符合 MCP ElicitResult 规范，需要添加 `action` 和 `content` 字段
- `codex_tool_runner.rs:269-271`：`ElicitationRequest` 事件转发给客户端的实现待完成
- `codex_tool_runner.rs:319-324`：`AgentMessageDelta` 和 `AgentReasoningDelta` 在 MCP 中的支持待设计
