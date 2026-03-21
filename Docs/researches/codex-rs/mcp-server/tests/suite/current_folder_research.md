# DIR codex-rs/mcp-server/tests/suite 研究文档

## 概述

`codex-rs/mcp-server/tests/suite` 是 Codex MCP (Model Context Protocol) 服务器的集成测试套件目录。该目录包含针对 MCP 服务器核心功能的端到端测试，主要验证服务器与客户端之间的 JSON-RPC 通信、工具调用、执行审批和补丁审批等关键流程。

---

## 场景与职责

### 核心职责

1. **端到端集成测试**: 验证 MCP 服务器作为独立进程与模拟客户端的完整交互流程
2. **工具调用测试**: 测试 `codex` 和 `codex-reply` 两个核心工具的调用流程
3. **审批流程验证**: 验证 shell 命令执行审批和代码补丁应用审批的完整生命周期
4. **SSE 响应处理**: 测试服务器对 Server-Sent Events 响应流的处理

### 测试场景

| 场景 | 描述 |
|------|------|
| Shell 命令审批 | 非受信任命令触发征求请求，客户端批准后执行 |
| 补丁应用审批 | 代码修改触发征求请求，客户端批准后应用补丁 |
| 基础指令传递 | 验证 base_instructions 和 developer_instructions 正确传递到模型 |

---

## 功能点目的

### 1. `test_shell_command_approval_triggers_elicitation`

**目的**: 验证当模型生成非受信任的 shell 命令时，MCP 服务器能够：
- 暂停命令执行
- 向客户端发送 `elicitation/create` 请求
- 等待用户审批决策
- 根据决策执行或拒绝命令

**关键验证点**:
- 征求请求包含正确的命令、工作目录、调用 ID
- 客户端批准后文件被成功创建
- 最终响应包含 `threadId` 和助手消息

### 2. `test_patch_approval_triggers_elicitation`

**目的**: 验证当模型尝试应用代码补丁时，MCP 服务器能够：
- 解析补丁内容并识别文件变更
- 向客户端发送补丁审批征求请求
- 批准后正确应用补丁到目标文件

**关键验证点**:
- 征求请求包含变更文件映射和统一差异
- 客户端批准后文件内容被正确修改
- 验证补丁应用的幂等性

### 3. `test_codex_tool_passes_base_instructions`

**目的**: 验证工具调用参数中的指令正确传递到模型请求：
- `base_instructions` 作为系统指令前缀
- `developer_instructions` 作为开发者角色消息注入

**关键验证点**:
- 请求体中包含正确的 `instructions` 字段
- 开发者消息包含权限说明和自定义指令

---

## 具体技术实现

### 关键流程

#### 1. 测试初始化流程

```rust
// tests/suite/codex_tool.rs
async fn create_mcp_process(responses: Vec<String>) -> anyhow::Result<McpHandle> {
    let server = create_mock_responses_server(responses).await;
    let codex_home = TempDir::new()?;
    create_config_toml(codex_home.path(), &server.uri())?;
    let mut mcp_process = McpProcess::new(codex_home.path()).await?;
    timeout(DEFAULT_READ_TIMEOUT, mcp_process.initialize()).await??;
    Ok(McpHandle { ... })
}
```

流程说明：
1. 启动 Mock HTTP 服务器模拟模型 API (`/v1/responses`)
2. 创建临时 CODEX_HOME 目录并写入测试配置
3. 启动 `codex-mcp-server` 子进程
4. 执行 MCP 初始化握手 (`initialize` 请求/响应)

#### 2. Shell 命令审批流程

```
┌─────────────┐     ┌─────────────────┐     ┌──────────────┐
│   Client    │────▶│  MCP Server     │────▶│  Mock Model  │
│  (Test)     │     │ (codex-mcp-server)│    │   Server     │
└─────────────┘     └─────────────────┘     └──────────────┘
       │                      │                      │
       │  tools/call          │                      │
       │─────────────────────▶│                      │
       │                      │  POST /v1/responses  │
       │                      │─────────────────────▶│
       │                      │                      │
       │                      │◀─────────────────────│
       │                      │  SSE: function_call  │
       │                      │  (shell_command)     │
       │                      │                      │
       │◀─────────────────────│  elicitation/create  │
       │                      │                      │
       │  response (approve)  │                      │
       │─────────────────────▶│                      │
       │                      │  ExecApproval Op     │
       │                      │─────────────────────▶│
       │                      │  (to CodexThread)    │
       │                      │                      │
       │◀─────────────────────│  SSE: output         │
       │                      │◀─────────────────────│
       │                      │                      │
       │◀─────────────────────│  tools/call response │
       │                      │  (with threadId)     │
```

#### 3. 消息处理循环

```rust
// tests/common/mcp_process.rs
pub async fn read_stream_until_request_message(&mut self) -> anyhow::Result<JsonRpcRequest<CustomRequest>> {
    loop {
        let message = self.read_jsonrpc_message().await?;
        match message {
            JsonRpcMessage::Notification(_) => { /* 忽略通知 */ }
            JsonRpcMessage::Request(jsonrpc_request) => return Ok(jsonrpc_request),
            _ => bail!("unexpected message type"),
        }
    }
}
```

### 数据结构

#### 1. McpHandle (测试资源管理)

```rust
// tests/suite/codex_tool.rs
pub struct McpHandle {
    pub process: McpProcess,
    #[allow(dead_code)]
    server: MockServer,      // 保持 MockServer 存活
    #[allow(dead_code)]
    dir: TempDir,            // 保持临时目录存活
}
```

#### 2. 执行审批征求参数

```rust
// src/exec_approval.rs
pub struct ExecApprovalElicitRequestParams {
    pub message: String,
    #[serde(rename = "requestedSchema")]
    pub requested_schema: Value,
    #[serde(rename = "threadId")]
    pub thread_id: ThreadId,
    pub codex_elicitation: String,        // "exec-approval"
    pub codex_mcp_tool_call_id: String,
    pub codex_event_id: String,
    pub codex_call_id: String,
    pub codex_command: Vec<String>,       // 解析后的命令
    pub codex_cwd: PathBuf,
    pub codex_parsed_cmd: Vec<ParsedCommand>,
}
```

#### 3. 补丁审批征求参数

```rust
// src/patch_approval.rs
pub struct PatchApprovalElicitRequestParams {
    pub message: String,
    #[serde(rename = "requestedSchema")]
    pub requested_schema: Value,
    #[serde(rename = "threadId")]
    pub thread_id: ThreadId,
    pub codex_elicitation: String,        // "patch-approval"
    pub codex_mcp_tool_call_id: String,
    pub codex_event_id: String,
    pub codex_call_id: String,
    pub codex_reason: Option<String>,
    pub codex_grant_root: Option<PathBuf>,
    pub codex_changes: HashMap<PathBuf, FileChange>,
}
```

### 协议与通信

#### 1. MCP JSON-RPC 协议

测试使用 `rmcp` crate 提供的 MCP 协议实现：

- **请求**: `JsonRpcRequest<CustomRequest>`
- **响应**: `JsonRpcResponse<Value>`
- **通知**: `JsonRpcNotification<CustomNotification>`

#### 2. 初始化握手

```rust
// tests/common/mcp_process.rs
pub async fn initialize(&mut self) -> anyhow::Result<()> {
    let params = InitializeRequestParams {
        capabilities: ClientCapabilities {
            elicitation: Some(ElicitationCapability {
                form: Some(FormElicitationCapability { schema_validation: None }),
                url: None,
            }),
            ...
        },
        protocol_version: ProtocolVersion::V_2025_03_26,
        ...
    };
    // 发送 initialize 请求，验证响应
}
```

#### 3. SSE 响应构造

```rust
// tests/common/responses.rs
pub fn create_shell_command_sse_response(
    command: Vec<String>,
    workdir: Option<&Path>,
    timeout_ms: Option<u64>,
    call_id: &str,
) -> anyhow::Result<String> {
    let arguments = serde_json::to_string(&json!({
        "command": command_str,
        "workdir": workdir.map(|w| w.to_string_lossy()),
        "timeout_ms": timeout_ms,
    }))?;
    Ok(responses::sse(vec![
        responses::ev_response_created(&response_id),
        responses::ev_function_call(call_id, "shell_command", &arguments),
        responses::ev_completed(&response_id),
    ]))
}
```

---

## 关键代码路径与文件引用

### 测试文件

| 文件 | 职责 |
|------|------|
| `tests/suite/mod.rs` | 测试模块入口，导出 `codex_tool` 模块 |
| `tests/suite/codex_tool.rs` | 核心集成测试用例 |
| `tests/all.rs` | 测试二进制入口，聚合所有测试模块 |

### 测试支持库

| 文件 | 职责 |
|------|------|
| `tests/common/lib.rs` | 公共导出，暴露测试辅助函数 |
| `tests/common/mcp_process.rs` | `McpProcess` 结构体，封装 MCP 子进程管理 |
| `tests/common/mock_model_server.rs` | Mock HTTP 服务器，模拟模型 API |
| `tests/common/responses.rs` | SSE 响应构造辅助函数 |

### 被测源码

| 文件 | 职责 |
|------|------|
| `src/lib.rs` | MCP 服务器主入口，消息循环 |
| `src/message_processor.rs` | JSON-RPC 消息处理器 |
| `src/codex_tool_runner.rs` | Codex 工具会话执行器 |
| `src/exec_approval.rs` | 执行审批处理逻辑 |
| `src/patch_approval.rs` | 补丁审批处理逻辑 |
| `src/outgoing_message.rs` | 出站消息发送器 |
| `src/codex_tool_config.rs` | 工具配置参数定义 |

---

## 依赖与外部交互

### 内部依赖

```
codex-mcp-server/tests/suite
├── codex-mcp-server (被测库)
│   ├── codex-core (核心逻辑)
│   ├── codex-protocol (协议定义)
│   ├── codex-shell-command (命令解析)
│   └── rmcp (MCP 协议实现)
├── core_test_support (测试支持)
│   └── responses (SSE 构造)
└── mcp_test_support (本 crate 测试支持)
    ├── McpProcess
    └── mock_model_server
```

### 外部依赖

| Crate | 用途 |
|-------|------|
| `wiremock` | HTTP Mock 服务器 |
| `tempfile` | 临时目录管理 |
| `tokio` | 异步运行时 |
| `serde_json` | JSON 序列化 |
| `pretty_assertions` | 测试断言美化 |

### 环境变量

| 变量 | 说明 |
|------|------|
| `CODEX_HOME` | 指向临时配置目录 |
| `CODEX_SANDBOX_NETWORK_DISABLED` | 网络禁用检测（测试跳过条件） |
| `RUST_LOG` | 日志级别控制 |

---

## 风险、边界与改进建议

### 已知风险

1. **网络依赖**: 
   - 测试需要网络访问（除非 `CODEX_SANDBOX_NETWORK_DISABLED` 设置）
   - 使用 `skip_if_no_network!()` 宏处理网络不可用场景

2. **平台差异**:
   - `test_patch_approval_triggers_elicitation` 在 Windows 上跳过（PowerShell 解析差异）
   - Shell 命令在 Windows 使用 `New-Item`，Unix 使用 `touch`

3. **进程清理**:
   - `McpProcess::drop` 实现了同步清理逻辑，防止子进程泄漏
   - 使用 `kill_on_drop(true)` 和 `try_wait()` 轮询确保进程退出

4. **超时风险**:
   - `DEFAULT_READ_TIMEOUT = 20s` 用于 CI 环境
   - 慢速环境可能导致测试不稳定

### 边界情况

1. **并发安全**:
   - `running_requests_id_to_codex_uuid` 使用 `Arc<Mutex<...>>` 保护
   - 多线程测试 (`worker_threads = 4`) 验证并发正确性

2. **错误处理**:
   - 测试使用 `anyhow::Result` 和 `?` 运算符简化错误传播
   - 失败时通过 `panic!("failure: {err}")` 提供详细错误信息

3. **资源生命周期**:
   - `McpHandle` 确保 `MockServer` 和 `TempDir` 在进程生命周期内保持存活

### 改进建议

1. **测试覆盖率**:
   - 增加 `codex-reply` 工具的完整流程测试
   - 添加错误场景测试（如无效 thread_id、配置错误）
   - 增加并发工具调用测试

2. **性能优化**:
   - 考虑使用共享的 MockServer 减少测试启动时间
   - 评估是否可以将部分集成测试转为单元测试

3. **可维护性**:
   - 将 `create_expected_*_params` 辅助函数提取到公共模块
   - 增加更多文档注释说明测试意图

4. **平台支持**:
   - 完善 Windows 平台的补丁审批测试支持
   - 考虑使用跨平台的文件操作命令

5. **调试能力**:
   - 增加测试失败时的日志输出
   - 考虑添加 MCP 消息流的结构化日志记录

---

## 附录：测试执行

```bash
# 运行所有 MCP 服务器测试
cargo test -p codex-mcp-server

# 运行特定测试
cargo test -p codex-mcp-server test_shell_command_approval_triggers_elicitation

# 带日志输出运行
cargo test -p codex-mcp-server -- --nocapture
```

---

*文档生成时间: 2026-03-21*
*研究范围: codex-rs/mcp-server/tests/suite/*
