# DIR codex-rs/mcp-server/tests 研究文档

## 场景与职责

`codex-rs/mcp-server/tests` 是 Codex MCP (Model Context Protocol) 服务器的集成测试套件。该测试目录负责验证 MCP 服务器作为独立进程与客户端之间的完整交互流程，包括：

1. **MCP 协议握手与初始化**：验证 JSON-RPC 2.0 协议的初始化流程
2. **工具调用生命周期**：测试 `codex` 和 `codex-reply` 工具的调用、执行和响应
3. **审批流程验证**：验证 shell 命令执行和代码补丁应用的审批触发机制
4. **Elicitation (征询) 机制**：测试服务器向客户端发送征询请求并处理响应的完整流程

该测试套件采用黑盒测试方法，将 MCP 服务器作为真实子进程启动，通过标准输入输出进行通信，模拟真实的 MCP 客户端行为。

## 功能点目的

### 1. 集成测试架构 (`all.rs` + `suite/mod.rs`)

- **单二进制测试聚合**：`all.rs` 作为统一的测试入口，聚合 `suite/` 下的所有测试模块
- **模块化组织**：`suite/mod.rs` 仅导出 `codex_tool` 模块，保持测试代码的结构清晰

### 2. MCP 进程管理 (`common/mcp_process.rs`)

`McpProcess` 结构体是测试的核心基础设施，提供：

- **进程生命周期管理**：启动 `codex-mcp-server` 二进制文件，管理 stdin/stdout/stderr
- **JSON-RPC 消息序列化/反序列化**：处理 MCP 协议消息的编码和解码
- **初始化握手**：发送 `initialize` 请求并验证响应
- **工具调用封装**：`send_codex_tool_call()` 方法封装了 `tools/call` 请求
- **响应轮询**：提供多种读取方法等待特定类型的响应（`read_stream_until_request_message`、`read_stream_until_response_message`、`read_stream_until_legacy_task_complete_notification`）

### 3. Mock 模型服务器 (`common/mock_model_server.rs`)

- **顺序响应器 (`SeqResponder`)**：为 `/v1/responses` 端点提供按顺序返回的 SSE 响应
- **请求计数验证**：使用 `wiremock` 验证预期的请求次数
- **隔离测试**：每个测试用例可配置独立的 mock 响应序列

### 4. SSE 响应构造器 (`common/responses.rs`)

提供便捷的 SSE (Server-Sent Events) 响应构造函数：

- `create_shell_command_sse_response`：构造包含 shell 命令调用的 SSE 流
- `create_apply_patch_sse_response`：构造包含补丁应用的 SSE 流
- `create_final_assistant_message_sse_response`：构造最终助手消息的 SSE 流

### 5. 测试用例 (`suite/codex_tool.rs`)

三个核心集成测试：

| 测试函数 | 目的 |
|---------|------|
| `test_shell_command_approval_triggers_elicitation` | 验证非信任 shell 命令触发 `exec-approval` 征询流程 |
| `test_patch_approval_triggers_elicitation` | 验证代码补丁应用触发 `patch-approval` 征询流程 |
| `test_codex_tool_passes_base_instructions` | 验证 `base_instructions` 和 `developer_instructions` 正确传递到模型请求 |

## 具体技术实现

### 关键流程

#### 1. Shell 命令审批流程测试

```
测试设置:
1. 创建临时工作目录
2. 配置 Mock 服务器返回 shell_command 函数调用 + 完成消息
3. 启动 MCP 服务器进程

执行流程:
1. 发送 tools/call (codex 工具) 请求
2. 读取服务器返回的 elicitation/create 征询请求
3. 验证征询参数包含正确的命令、工作目录、thread_id 等
4. 发送 elicitation 响应 (Approved)
5. 等待 task_complete 通知
6. 验证 tools/call 最终响应包含 threadId 和助手消息
7. 验证文件实际被创建
```

#### 2. 补丁审批流程测试

```
测试设置:
1. 创建临时目录并写入原始文件内容
2. 构造补丁内容 (*** Begin Patch ... *** End Patch)
3. 配置 Mock 服务器返回 shell_command (apply_patch) + 完成消息

执行流程:
1. 发送 tools/call 请求
2. 读取 elicitation/create 征询请求 (patch-approval 类型)
3. 验证征询参数包含预期的文件变更 (FileChange::Update)
4. 发送 Approved 响应
5. 验证 tools/call 响应
6. 验证文件内容已被修改
```

#### 3. 指令传递测试

```
测试设置:
1. 创建带 base_instructions 和 developer_instructions 的工具调用参数
2. 使用 Mock 服务器捕获实际发送的模型请求

验证点:
- 请求体中的 instructions 字段以 base_instructions 开头
- developer 角色的消息中包含 developer_instructions 内容
- 权限相关的 developer 消息也被正确注入
```

### 关键数据结构

#### `McpHandle` (测试辅助结构)

```rust
pub struct McpHandle {
    pub process: McpProcess,
    server: MockServer,  // 保持 MockServer 存活
    dir: TempDir,        // 保持临时目录存活
}
```

确保测试过程中所有资源保持存活状态。

#### `ExecApprovalElicitRequestParams`

```rust
pub struct ExecApprovalElicitRequestParams {
    pub message: String,
    pub requested_schema: Value,
    pub thread_id: ThreadId,
    pub codex_elicitation: String,  // "exec-approval"
    pub codex_mcp_tool_call_id: String,
    pub codex_event_id: String,
    pub codex_call_id: String,
    pub codex_command: Vec<String>,
    pub codex_cwd: PathBuf,
    pub codex_parsed_cmd: Vec<ParsedCommand>,
}
```

#### `PatchApprovalElicitRequestParams`

```rust
pub struct PatchApprovalElicitRequestParams {
    pub message: String,
    pub requested_schema: Value,
    pub thread_id: ThreadId,
    pub codex_elicitation: String,  // "patch-approval"
    pub codex_mcp_tool_call_id: String,
    pub codex_event_id: String,
    pub codex_call_id: String,
    pub codex_reason: Option<String>,
    pub codex_grant_root: Option<PathBuf>,
    pub codex_changes: HashMap<PathBuf, FileChange>,
}
```

### 协议与通信

#### MCP JSON-RPC 2.0 协议

测试使用标准的 MCP 协议消息格式：

**Initialize Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 0,
  "method": "initialize",
  "params": {
    "capabilities": {
      "elicitation": {
        "form": {"schemaValidation": null}
      }
    },
    "clientInfo": {"name": "elicitation test", "version": "0.0.0"},
    "protocolVersion": "2025-03-26"
  }
}
```

**Tools/Call Request:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "codex",
    "arguments": {"prompt": "run `git init`"}
  }
}
```

**Elicitation/Create Request (服务器 -> 客户端):**
```json
{
  "jsonrpc": "2.0",
  "id": "...",
  "method": "elicitation/create",
  "params": {
    "message": "Allow Codex to run `touch file.txt` in `/tmp/...`?",
    "requestedSchema": {"type": "object", "properties": {}},
    "threadId": "...",
    "codexElicitation": "exec-approval",
    ...
  }
}
```

### 配置与测试环境

测试使用内存中的 `config.toml` 配置：

```toml
model = "mock-model"
approval_policy = "untrusted"
sandbox_policy = "workspace-write"

model_provider = "mock_provider"

[model_providers.mock_provider]
name = "Mock provider for test"
base_url = "{server_uri}/v1"
wire_api = "responses"
request_max_retries = 0
stream_max_retries = 0
```

关键配置点：
- `approval_policy = "untrusted"`：确保所有 shell 命令都触发审批征询
- Mock 提供者指向本地 `wiremock` 服务器
- 禁用重试以加快测试速度

## 关键代码路径与文件引用

### 测试文件结构

```
codex-rs/mcp-server/tests/
├── all.rs                          # 测试入口，聚合 suite 模块
├── suite/
│   ├── mod.rs                      # 导出 codex_tool 模块
│   └── codex_tool.rs               # 核心集成测试用例 (516 行)
└── common/                         # 测试支持库 (mcp_test_support crate)
      ├── lib.rs                    # 模块导出和工具函数
      ├── mcp_process.rs            # MCP 进程管理 (399 行)
      ├── mock_model_server.rs      # Mock 模型服务器 (47 行)
      ├── responses.rs              # SSE 响应构造器 (47 行)
      ├── Cargo.toml                # 测试库配置
      └── BUILD.bazel               # Bazel 构建配置
```

### 被测试的生产代码

| 测试文件 | 覆盖的生产代码 |
|---------|--------------|
| `suite/codex_tool.rs` | `codex-rs/mcp-server/src/lib.rs` - 主入口和消息循环 |
| `suite/codex_tool.rs` | `codex-rs/mcp-server/src/message_processor.rs` - 消息处理 |
| `suite/codex_tool.rs` | `codex-rs/mcp-server/src/codex_tool_runner.rs` - 工具执行 |
| `suite/codex_tool.rs` | `codex-rs/mcp-server/src/exec_approval.rs` - 执行审批 |
| `suite/codex_tool.rs` | `codex-rs/mcp-server/src/patch_approval.rs` - 补丁审批 |
| `suite/codex_tool.rs` | `codex-rs/mcp-server/src/codex_tool_config.rs` - 工具配置 |

### 核心测试代码路径

**测试初始化流程** (`suite/codex_tool.rs:477-488`):
```rust
async fn create_mcp_process(responses: Vec<String>) -> anyhow::Result<McpHandle> {
    let server = create_mock_responses_server(responses).await;
    let codex_home = TempDir::new()?;
    create_config_toml(codex_home.path(), &server.uri())?;
    let mut mcp_process = McpProcess::new(codex_home.path()).await?;
    timeout(DEFAULT_READ_TIMEOUT, mcp_process.initialize()).await??;
    Ok(McpHandle { process: mcp_process, server, dir: codex_home })
}
```

**MCP 进程创建** (`common/mcp_process.rs:46-110`):
```rust
pub async fn new(codex_home: &Path) -> anyhow::Result<Self> {
    let program = codex_utils_cargo_bin::cargo_bin("codex-mcp-server")?;
    let mut cmd = Command::new(program);
    cmd.stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped());
    cmd.env("CODEX_HOME", codex_home).env("RUST_LOG", "debug");
    // ... 进程启动和 stderr 转发
}
```

**初始化握手** (`common/mcp_process.rs:113-197`):
```rust
pub async fn initialize(&mut self) -> anyhow::Result<()> {
    // 发送 initialize 请求
    // 验证响应包含正确的 capabilities 和 serverInfo
    // 发送 notifications/initialized 确认
}
```

## 依赖与外部交互

### 内部依赖

| 依赖 | 用途 |
|-----|------|
| `codex-core` | 配置加载、线程管理、CodexThread |
| `codex-mcp-server` | 被测试的服务器二进制和类型定义 |
| `codex-protocol` | ThreadId、Event、Op、ReviewDecision 等协议类型 |
| `codex-shell-command` | 命令解析 (parse_command) |
| `codex-utils-cargo-bin` | 在测试中定位编译后的二进制文件 |
| `core_test_support` | 核心测试支持库 (来自 `codex-rs/core/tests/common`) |

### 外部依赖

| 依赖 | 用途 |
|-----|------|
| `rmcp` | MCP 协议模型类型 (JsonRpcMessage, RequestId, CallToolRequestParams 等) |
| `wiremock` | Mock HTTP 服务器，模拟模型提供者 API |
| `tokio` | 异步运行时、进程管理、超时控制 |
| `tempfile` | 临时目录创建 |
| `serde_json` | JSON 序列化/反序列化 |
| `pretty_assertions` | 测试断言的可读 diff |
| `shlex` | Shell 命令的引号处理 |

### 环境变量

| 变量 | 说明 |
|-----|------|
| `CODEX_HOME` | 指向临时目录，包含测试用的 config.toml |
| `RUST_LOG` | 设置为 `debug` 以获取详细日志 |
| `CODEX_SANDBOX_NETWORK_DISABLED` | 如果设置，网络相关测试会被跳过 |

## 风险、边界与改进建议

### 当前风险

1. **平台差异**:
   - `test_patch_approval_triggers_elicitation` 在 Windows 上完全跳过 (`cfg!(windows)`)
   - Shell 命令使用 `touch` (Unix) 或 `New-Item` (PowerShell)，但测试逻辑有平台分支

2. **超时敏感性**:
   - `DEFAULT_READ_TIMEOUT = 20s` 可能不足以应对慢速 CI 环境
   - 使用 `tokio::time::timeout` 包装所有异步等待

3. **进程清理**:
   - `McpProcess::drop` 实现了同步清理，但 Tokio 的 `kill_on_drop` 是 best-effort
   - 注释提到可能出现 `LEAK` 报告的 flaky 测试

4. **测试隔离**:
   - 测试使用全局可执行文件路径 (`cargo_bin`)
   - 并行运行测试时可能产生端口冲突 (MockServer 使用随机端口)

### 边界条件

1. **网络禁用环境**:
   ```rust
   if env::var(CODEX_SANDBOX_NETWORK_DISABLED_ENV_VAR).is_ok() {
       println!("Skipping test because it cannot execute when network is disabled...");
       return;
   }
   ```
   测试在沙盒环境中会被跳过。

2. **线程数配置**:
   - `test_shell_command_approval_triggers_elicitation`: `worker_threads = 4`
   - 其他测试: `worker_threads = 2`

3. **Mock 响应顺序**:
   - `SeqResponder` 使用原子计数器确保响应按顺序返回
   - 如果请求次数超过预设响应数会 panic

### 改进建议

1. **增加测试覆盖率**:
   - 添加 `codex-reply` 工具的集成测试
   - 测试审批拒绝 (Denied) 场景
   - 测试取消通知 (`notifications/cancelled`) 的处理
   - 测试错误处理路径（如无效的配置、模型 API 错误）

2. **提高测试稳定性**:
   - 使用更长的超时时间或基于事件的等待替代固定超时
   - 添加重试机制处理 flaky 的进程清理

3. **代码组织**:
   - `suite/mod.rs` 目前只有一个模块，随着测试增长需要更好的组织
   - 考虑将 `create_expected_*_params` 辅助函数移到 common 模块

4. **文档**:
   - 添加更多内联注释解释复杂的测试设置
   - 为 `McpProcess` 的公共方法添加文档

5. **性能优化**:
   - 考虑在多个测试间复用编译后的 MCP 服务器二进制
   - 使用 `once_cell` 或 `lazy_static` 缓存测试资源

6. **类型安全**:
   - `ExecApprovalResponse` 和 `PatchApprovalResponse` 的 TODO 注释提到它们不完全符合 MCP ElicitResult 规范
   - 应该对齐规范并添加相应的序列化测试

---

*研究日期: 2026-03-21*
*研究范围: codex-rs/mcp-server/tests 目录及其直接依赖*
