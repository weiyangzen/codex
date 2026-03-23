# 研究文档: codex-rs/mcp-server/tests/all.rs

## 1. 场景与职责

### 1.1 文件定位

`codex-rs/mcp-server/tests/all.rs` 是 **Codex MCP (Model Context Protocol) 服务器**的集成测试入口文件。该文件本身非常精简（仅3行），作为测试聚合器将子模块组织在 `tests/suite/` 目录下。

### 1.2 架构位置

```
┌─────────────────────────────────────────────────────────────────┐
│                        测试层次结构                              │
├─────────────────────────────────────────────────────────────────┤
│  all.rs (入口) ──→ suite/mod.rs ──→ suite/codex_tool.rs (实际测试)│
├─────────────────────────────────────────────────────────────────┤
│  common/lib.rs (测试支持库)                                       │
│  ├── mcp_process.rs    # MCP进程管理                             │
│  ├── mock_model_server.rs  # 模拟模型服务器                       │
│  └── responses.rs      # SSE响应构造器                           │
└─────────────────────────────────────────────────────────────────┘
```

### 1.3 核心职责

1. **集成测试聚合**: 作为单一测试二进制文件的入口点，聚合所有测试模块
2. **端到端验证**: 测试MCP服务器与Codex核心、模拟模型服务器之间的完整交互流程
3. **elicitation流程验证**: 验证shell命令审批和patch审批的elicitation（征求）机制
4. **工具调用测试**: 验证 `codex` 和 `codex-reply` 工具调用的正确性

### 1.4 测试场景

| 场景 | 描述 |
|------|------|
| Shell命令审批 | 测试非信任命令触发elicitation请求，用户批准后执行 |
| Patch审批 | 测试代码修改patch触发elicitation请求，用户批准后应用 |
| 基础指令传递 | 验证base_instructions和developer_instructions正确传递给模型 |

---

## 2. 功能点目的

### 2.1 测试功能详解

#### 2.1.1 `test_shell_command_approval_triggers_elicitation`

**目的**: 验证当Codex尝试执行非信任shell命令时，MCP服务器会暂停执行并向客户端发送elicitation请求，等待用户明确批准。

**测试流程**:
1. 创建临时工作目录和测试文件
2. 配置模拟模型服务器返回 `shell_command` 函数调用SSE事件
3. 发送 `codex` 工具调用请求
4. 验证收到 `elicitation/create` 请求（方法为exec-approval）
5. 模拟用户批准响应
6. 验证命令实际执行（文件被创建）
7. 验证最终工具调用响应包含正确内容

**关键断言**:
- Elicitation请求方法为 `"elicitation/create"`
- 请求参数包含正确的命令、工作目录、thread_id
- 批准后文件实际被创建
- 最终响应包含 `"File created!"` 文本

#### 2.1.2 `test_patch_approval_triggers_elicitation`

**目的**: 验证当Codex尝试应用代码patch时，MCP服务器会发送elicitation请求，等待用户批准后再应用修改。

**测试流程**:
1. 创建临时目录和测试文件（含原始内容）
2. 构造patch内容（ unified diff格式 ）
3. 配置模拟服务器返回 `apply_patch` shell命令SSE事件
4. 发送 `codex` 工具调用请求
5. 验证收到 `elicitation/create` 请求（方法为patch-approval）
6. 模拟用户批准响应
7. 验证文件内容被修改

**关键断言**:
- Elicitation请求包含正确的文件变更信息
- 批准后文件内容从 `"original content"` 变为 `"modified content"`
- 响应包含 `"Patch has been applied successfully!"`

#### 2.1.3 `test_codex_tool_passes_base_instructions`

**目的**: 验证通过MCP工具调用传递的 `base_instructions` 和 `developer_instructions` 正确包含在发送到模型服务器的请求中。

**测试流程**:
1. 创建模拟模型服务器
2. 配置Codex home目录和config.toml
3. 发送带自定义指令的 `codex` 工具调用
4. 捕获并验证发送到模型服务器的请求体

**关键断言**:
- 请求体 `instructions` 字段以 `"You are a helpful assistant."` 开头
- `input` 数组中包含developer角色的消息
- Developer消息包含 `developer_instructions` 内容

---

## 3. 具体技术实现

### 3.1 关键数据结构

#### 3.1.1 测试参数结构

```rust
// CodexToolCallParam: codex工具调用的参数
pub struct CodexToolCallParam {
    pub prompt: String,                    // 初始用户提示
    pub model: Option<String>,             // 模型名称覆盖
    pub profile: Option<String>,           // 配置profile
    pub cwd: Option<String>,               // 工作目录
    pub approval_policy: Option<CodexToolCallApprovalPolicy>,  // 审批策略
    pub sandbox: Option<CodexToolCallSandboxMode>,             // 沙箱模式
    pub config: Option<HashMap<String, serde_json::Value>>,    // 配置覆盖
    pub base_instructions: Option<String>,       // 基础指令
    pub developer_instructions: Option<String>,  // 开发者指令
    pub compact_prompt: Option<String>,          // 压缩提示
}

// ExecApprovalElicitRequestParams: 执行审批elicitation请求参数
pub struct ExecApprovalElicitRequestParams {
    pub message: String,                   // 显示给用户的消息
    pub requested_schema: Value,           // 请求的JSON schema
    pub thread_id: ThreadId,               // 线程ID
    pub codex_elicitation: String,         // elicitation类型 ("exec-approval")
    pub codex_mcp_tool_call_id: String,    // MCP工具调用ID
    pub codex_event_id: String,            // Codex事件ID
    pub codex_call_id: String,             // 调用ID
    pub codex_command: Vec<String>,        // 命令参数
    pub codex_cwd: PathBuf,                // 工作目录
    pub codex_parsed_cmd: Vec<ParsedCommand>,  // 解析后的命令
}

// PatchApprovalElicitRequestParams: Patch审批elicitation请求参数
pub struct PatchApprovalElicitRequestParams {
    pub message: String,
    pub requested_schema: Value,
    pub thread_id: ThreadId,
    pub codex_elicitation: String,         // "patch-approval"
    pub codex_mcp_tool_call_id: String,
    pub codex_event_id: String,
    pub codex_call_id: String,
    pub codex_reason: Option<String>,      // 修改原因
    pub codex_grant_root: Option<PathBuf>, // 根目录权限
    pub codex_changes: HashMap<PathBuf, FileChange>,  // 文件变更映射
}
```

#### 3.1.2 响应结构

```rust
// ExecApprovalResponse: 执行审批响应
pub struct ExecApprovalResponse {
    pub decision: ReviewDecision,  // Approved 或 Denied
}

// PatchApprovalResponse: Patch审批响应
pub struct PatchApprovalResponse {
    pub decision: ReviewDecision,
}
```

### 3.2 关键流程

#### 3.2.1 测试初始化流程

```
┌─────────────────┐
│   创建McpHandle  │
│  (测试辅助结构)   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     ┌──────────────────┐
│ create_mcp_process│────→│ 启动MockServer    │
│                 │     │ (模拟模型服务器)   │
└────────┬────────┘     └──────────────────┘
         │
         ▼
┌─────────────────┐     ┌──────────────────┐
│ 创建临时CODEX_HOME│────→│ 写入config.toml   │
│                 │     │ (配置mock provider)│
└────────┬────────┘     └──────────────────┘
         │
         ▼
┌─────────────────┐
│ 启动McpProcess   │
│ (codex-mcp-server│
│  子进程)         │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ 执行initialize   │
│ 握手协议         │
└─────────────────┘
```

#### 3.2.2 Shell命令审批流程

```
测试线程                                    MCP服务器进程
    │                                              │
    │── send_codex_tool_call() ───────────────────→│
    │   (发送tools/call请求)                        │
    │                                              │
    │←─ read_stream_until_request_message() ───────│
    │   (接收elicitation/create请求)                │
    │   验证: method="elicitation/create"           │
    │        params.codex_elicitation="exec-approval"│
    │                                              │
    │── send_response() ──────────────────────────→│
    │   (发送ExecApprovalResponse { Approved })     │
    │                                              │
    │←─ read_stream_until_legacy_task_complete() ──│
    │   (接收task_complete通知)                     │
    │                                              │
    │←─ read_stream_until_response_message() ──────│
    │   (接收tools/call响应)                        │
    │   验证: 包含"File created!"文本               │
    │                                              │
    │── 验证文件实际被创建 ─────────────────────────→│
```

#### 3.2.3 Patch审批流程

```
测试线程                                    MCP服务器进程
    │                                              │
    │── send_codex_tool_call() ───────────────────→│
    │   (发送包含patch操作的请求)                    │
    │                                              │
    │←─ read_stream_until_request_message() ───────│
    │   (接收elicitation/create请求)                │
    │   验证: method="elicitation/create"           │
    │        params.codex_elicitation="patch-approval"│
    │        params.codex_changes包含正确变更        │
    │                                              │
    │── send_response() ──────────────────────────→│
    │   (发送PatchApprovalResponse { Approved })    │
    │                                              │
    │←─ read_stream_until_response_message() ──────│
    │   (接收tools/call响应)                        │
    │                                              │
    │── 验证文件内容被修改 ─────────────────────────→│
```

### 3.3 协议细节

#### 3.3.1 MCP JSON-RPC协议

测试使用标准的JSON-RPC 2.0协议与MCP服务器通信：

**Initialize请求**:
```json
{
  "jsonrpc": "2.0",
  "id": 0,
  "method": "initialize",
  "params": {
    "capabilities": {
      "elicitation": {
        "form": { "schemaValidation": null }
      }
    },
    "clientInfo": { "name": "elicitation test", "version": "0.0.0" },
    "protocolVersion": "2025-03-26"
  }
}
```

**Tools/Call请求**:
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "codex",
    "arguments": { "prompt": "run `git init`" }
  }
}
```

**Elicitation/Create请求** (服务器→客户端):
```json
{
  "jsonrpc": "2.0",
  "id": 0,
  "method": "elicitation/create",
  "params": {
    "message": "Allow Codex to run `touch file.txt` in `/tmp/...`?",
    "requestedSchema": {"type":"object","properties":{}},
    "threadId": "thread-uuid",
    "codexElicitation": "exec-approval",
    "codexMcpToolCallId": "1",
    "codexEventId": "event-uuid",
    "codexCallId": "call1234",
    "codexCommand": ["touch", "file.txt"],
    "codexCwd": "/tmp/...",
    "codexParsedCmd": [...]
  }
}
```

#### 3.3.2 SSE响应格式

模拟模型服务器使用Server-Sent Events (SSE)格式返回模型响应：

```
event: response.created
data: {"type":"response.created","response":{"id":"resp-call1234"}}

event: response.output_item.done
data: {"type":"response.output_item.done","item":{"type":"function_call","call_id":"call1234","name":"shell_command","arguments":"{\"command\":\"touch file.txt\"}"}}

event: response.completed
data: {"type":"response.completed","response":{"id":"resp-call1234",...}}
```

### 3.4 命令与配置

#### 3.4.1 测试配置 (config.toml)

```toml
model = "mock-model"
approval_policy = "untrusted"      # 关键: 启用审批流程
sandbox_policy = "workspace-write"

model_provider = "mock_provider"

[model_providers.mock_provider]
name = "Mock provider for test"
base_url = "{server_uri}/v1"       # 指向模拟服务器
wire_api = "responses"
request_max_retries = 0
stream_max_retries = 0

[features]
```

#### 3.4.2 环境变量

| 变量 | 用途 |
|------|------|
| `CODEX_HOME` | 指向临时配置目录 |
| `RUST_LOG` | 设置为`debug`用于调试输出 |
| `CODEX_SANDBOX_NETWORK_DISABLED` | 如果设置，跳过需要网络的测试 |

---

## 4. 关键代码路径与文件引用

### 4.1 测试相关文件

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/mcp-server/tests/all.rs` | 测试入口，聚合子模块 |
| `codex-rs/mcp-server/tests/suite/mod.rs` | 测试套件模块声明 |
| `codex-rs/mcp-server/tests/suite/codex_tool.rs` | 实际测试实现（516行） |
| `codex-rs/mcp-server/tests/common/lib.rs` | 测试支持库导出 |
| `codex-rs/mcp-server/tests/common/mcp_process.rs` | MCP进程管理（399行） |
| `codex-rs/mcp-server/tests/common/mock_model_server.rs` | 模拟模型服务器（47行） |
| `codex-rs/mcp-server/tests/common/responses.rs` | SSE响应构造器（47行） |
| `codex-rs/mcp-server/tests/common/Cargo.toml` | 测试支持库配置 |

### 4.2 被测试的源代码

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/mcp-server/src/lib.rs` | MCP服务器主库（227行） |
| `codex-rs/mcp-server/src/main.rs` | 二进制入口（11行） |
| `codex-rs/mcp-server/src/message_processor.rs` | 消息处理器（603行） |
| `codex-rs/mcp-server/src/codex_tool_runner.rs` | Codex工具运行器（434行） |
| `codex-rs/mcp-server/src/codex_tool_config.rs` | 工具配置定义（433行） |
| `codex-rs/mcp-server/src/exec_approval.rs` | 执行审批处理（147行） |
| `codex-rs/mcp-server/src/patch_approval.rs` | Patch审批处理（142行） |
| `codex-rs/mcp-server/src/outgoing_message.rs` | 消息发送管理（472行） |

### 4.3 核心依赖

| 文件路径 | 职责 |
|----------|------|
| `codex-rs/core/tests/common/lib.rs` | 核心测试支持库（524行） |
| `codex-rs/core/tests/common/responses.rs` | 响应模拟工具（1000+行） |

### 4.4 关键代码路径追踪

#### 路径1: Shell命令审批

```
test_shell_command_approval_triggers_elicitation()
  └── create_mcp_process()
      └── McpProcess::new()  [mcp_process.rs:46]
          └── 启动 codex-mcp-server 子进程
  └── mcp_process.send_codex_tool_call()
      └── 发送 tools/call 请求
  
  [MCP服务器端]
  message_processor.rs:328 handle_call_tool()
      └── handle_tool_call_codex()
          └── codex_tool_runner.rs:59 run_codex_tool_session()
              └── 提交 UserInput 到 CodexThread
              └── run_codex_tool_session_inner()
                  └── 处理 ExecApprovalRequest 事件
                      └── exec_approval.rs:51 handle_exec_approval_request()
                          └── 发送 elicitation/create 请求到客户端
  
  [测试端]
  mcp_process.read_stream_until_request_message()
      └── 接收并验证 elicitation 请求
  mcp_process.send_response()
      └── 发送批准响应
  
  [MCP服务器端]
  exec_approval.rs:112 on_exec_approval_response()
      └── 提交 ExecApproval Op 到 CodexThread
      └── 继续执行shell命令
```

#### 路径2: 消息发送流程

```
outgoing_message.rs:27 OutgoingMessageSender
    └── send_request()  [line 42]
        └── 生成请求ID
        └── 存储回调到 request_id_to_callback
        └── 发送 OutgoingMessage::Request
    
    └── send_event_as_notification()  [line 102]
        └── 序列化 Event
        └── 包装为 OutgoingNotificationParams
        └── 发送 codex/event 通知
    
    └── notify_client_response()  [line 64]
        └── 查找并调用对应回调
```

---

## 5. 依赖与外部交互

### 5.1 外部依赖

#### 5.1.1 运行时依赖

| Crate | 用途 |
|-------|------|
| `tokio` | 异步运行时，多线程测试 |
| `rmcp` | MCP协议实现，JSON-RPC消息类型 |
| `wiremock` | HTTP模拟服务器，模拟模型API |
| `serde_json` | JSON序列化/反序列化 |
| `tempfile` | 临时目录管理 |
| `pretty_assertions` | 美观的测试断言输出 |

#### 5.1.2 内部依赖

| Crate | 用途 |
|-------|------|
| `codex-core` | Codex核心功能，Config, ThreadManager |
| `codex-protocol` | 协议类型，ThreadId, Event, Op |
| `codex-mcp-server` | 被测试的服务器库 |
| `codex-shell-command` | Shell命令解析 |
| `core_test_support` | 核心测试支持库 |
| `codex-utils-cargo-bin` | 定位测试二进制文件 |

### 5.2 外部交互

#### 5.2.1 进程间交互

```
┌─────────────────┐         stdin/stdout          ┌─────────────────┐
│   测试进程       │◄─────────────────────────────→│ codex-mcp-server│
│  (Tokio测试)    │      JSON-RPC over stdio      │    子进程        │
└─────────────────┘                               └────────┬────────┘
         │                                                 │
         │                                                 │
         │                                          HTTP POST
         │                                         /v1/responses
         │                                                 │
         │                                                 ▼
         │                                        ┌─────────────────┐
         │                                        │   MockServer    │
         └───────────────────────────────────────→│ (wiremock)      │
              验证请求体包含正确指令                │  模拟OpenAI API │
                                                  └─────────────────┘
```

#### 5.2.2 网络依赖

测试需要网络访问（除非在sandbox中运行）：
- 模拟服务器绑定到本地端口
- MCP服务器通过HTTP与模拟模型服务器通信

**网络跳过机制**:
```rust
if env::var(CODEX_SANDBOX_NETWORK_DISABLED_ENV_VAR).is_ok() {
    println!("Skipping test because it cannot execute when network is disabled...");
    return;
}
```

---

## 6. 风险、边界与改进建议

### 6.1 已知风险

#### 6.1.1 测试稳定性风险

| 风险 | 描述 | 缓解措施 |
|------|------|----------|
| 超时 flaky | 测试使用20秒超时，CI负载高时可能失败 | 使用 `DEFAULT_READ_TIMEOUT = 20s` |
| 进程清理 | 子进程可能残留导致资源泄漏 | `Drop` 实现中调用 `start_kill()` 并轮询 `try_wait()` |
| 端口冲突 | MockServer绑定随机端口，理论上可能冲突 | 使用 `MockServer::start()` 自动分配 |

#### 6.1.2 平台差异

| 平台 | 限制 |
|------|------|
| Windows | Patch审批测试被跳过（`powershell apply_patch`解析不支持） |
| Linux | 需要 `codex-linux-sandbox` 二进制文件 |
| 所有平台 | 网络禁用sandbox中跳过测试 |

#### 6.1.3 代码注释中的已知问题

```rust
// exec_approval.rs:41-43
// TODO(mbolin): ExecApprovalResponse does not conform to ElicitResult.
// 应该包含 "action" 和 "content" 字段，但目前只返回 decision。
```

### 6.2 边界情况

#### 6.2.1 测试覆盖边界

| 边界 | 当前状态 |
|------|----------|
| 拒绝审批 | 未测试拒绝执行/patch的场景 |
| 超时处理 | 未测试elicitation超时场景 |
| 并发请求 | 未测试多线程并发工具调用 |
| 错误恢复 | 未测试模型服务器返回错误的情况 |
| 会话回复 | `codex-reply` 工具测试覆盖有限 |

#### 6.2.2 资源边界

```rust
// McpProcess::Drop 实现中的边界处理
impl Drop for McpProcess {
    fn drop(&mut self) {
        let _ = self.process.start_kill();
        let start = std::time::Instant::now();
        let timeout = std::time::Duration::from_secs(5);  // 5秒清理超时
        while start.elapsed() < timeout {
            match self.process.try_wait() {
                Ok(Some(_)) => return,  // 成功退出
                Ok(None) => std::thread::sleep(std::time::Duration::from_millis(10)),
                Err(_) => return,       // 错误也返回
            }
        }
    }
}
```

### 6.3 改进建议

#### 6.3.1 测试覆盖增强

1. **添加拒绝场景测试**:
   ```rust
   #[tokio::test]
   async fn test_shell_command_rejection_denies_execution() {
       // 验证拒绝后命令不执行
   }
   ```

2. **添加错误场景测试**:
   - 模型服务器返回5xx错误
   - 无效的JSON-RPC消息
   - 配置加载失败

3. **添加并发测试**:
   - 多个并发的 `codex` 工具调用
   - 混合 `codex` 和 `codex-reply` 调用

#### 6.3.2 代码质量改进

1. **减少重复代码**:
   ```rust
   // 当前: 三个测试都有类似的网络检查
   if env::var(CODEX_SANDBOX_NETWORK_DISABLED_ENV_VAR).is_ok() { ... }
   
   // 建议: 提取为宏或属性
   #[tokio::test]
   #[skip_if_network_disabled]
   async fn test_xxx() { ... }
   ```

2. **增强错误信息**:
   ```rust
   // 当前: 简单的 panic
   if let Err(err) = shell_command_approval_triggers_elicitation().await {
       panic!("failure: {err}");
   }
   
   // 建议: 使用 anyhow::Context 提供更详细的错误上下文
   ```

3. **参数化测试**:
   - 使用 `rstest` 或类似库参数化不同shell命令的测试

#### 6.3.3 性能优化

1. **共享MockServer**: 当前每个测试创建新的MockServer，考虑使用共享实例
2. **并行测试优化**: 确保测试间无状态冲突，充分利用 `worker_threads`

#### 6.3.4 文档改进

1. 添加测试架构图到README
2. 记录每个测试的具体前置条件和预期状态
3. 添加故障排查指南

### 6.4 技术债务追踪

| 问题 | 位置 | 优先级 |
|------|------|--------|
| ExecApprovalResponse不符合ElicitResult规范 | exec_approval.rs:41 | 中 |
| Windows patch审批未实现 | codex_tool.rs:226 | 低 |
| TODO: AgentMessageDelta支持 | codex_tool_runner.rs:319 | 低 |
| TODO: ElicitationRequest转发 | codex_tool_runner.rs:269 | 低 |

---

## 7. 总结

`codex-rs/mcp-server/tests/all.rs` 及其测试套件是Codex MCP服务器质量保证的关键组成部分。测试采用端到端集成测试策略，通过启动真实的MCP服务器子进程、模拟模型服务器，验证完整的elicitation审批流程。

### 核心优势

1. **真实场景验证**: 测试覆盖从JSON-RPC协议到实际命令执行的完整链路
2. **平台兼容性**: 考虑Windows/Linux差异，提供适当的跳过机制
3. **资源管理**: 完善的临时目录和进程清理机制
4. **可维护性**: 清晰的模块划分，测试支持代码复用

### 主要局限

1. 部分边界场景（拒绝审批、错误恢复）测试覆盖不足
2. Windows平台patch审批功能未完整支持
3. 测试执行时间较长（需要启动多个进程）

### 建议优先级

1. **高**: 添加拒绝场景测试，确保权限控制正确性
2. **中**: 完善Windows平台支持
3. **低**: 优化测试执行速度，考虑共享基础设施
