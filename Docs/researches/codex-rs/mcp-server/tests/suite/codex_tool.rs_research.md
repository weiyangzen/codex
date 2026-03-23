# codex-rs/mcp-server/tests/suite/codex_tool.rs 研究文档

## 场景与职责

本文件是 Codex MCP (Model Context Protocol) 服务器的集成测试套件，负责验证 MCP 服务器与 Codex 核心之间的端到端交互。主要测试场景包括：

1. **Shell 命令审批流程**：验证当 Codex 需要执行非受信任命令时，MCP 服务器能够正确触发征求请求 (elicitation) 并处理用户审批
2. **Patch 应用审批流程**：验证代码变更补丁的审批流程，确保文件修改需要用户明确授权
3. **基础指令传递**：验证 `base_instructions` 和 `developer_instructions` 参数能够正确传递到模型请求中

这些测试确保 MCP 服务器作为 Codex 与外部 MCP 客户端之间的桥梁，能够正确处理工具调用、事件流和审批交互。

## 功能点目的

### 1. Shell 命令审批测试 (`test_shell_command_approval_triggers_elicitation`)

**目的**：验证非受信任 shell 命令的审批流程

**测试流程**：
- 创建一个临时工作目录，用于验证命令执行副作用
- 配置 Mock 服务器返回 shell 命令 SSE 响应（使用 `touch` 或 PowerShell 创建文件）
- 发送 `codex` 工具调用请求，触发命令执行
- 验证 MCP 服务器发送 `elicitation/create` 请求，包含命令详情和工作目录
- 模拟用户批准响应
- 验证命令实际执行（文件被创建）
- 验证最终响应包含预期的助手消息

**关键断言**：
- 验证征求请求方法为 `elicitation/create`
- 验证征求请求参数包含正确的命令、工作目录、线程 ID 等信息
- 验证文件实际被创建
- 验证响应包含 `threadId` 和 `content`

### 2. Patch 审批测试 (`test_patch_approval_triggers_elicitation`)

**目的**：验证代码补丁应用的审批流程

**测试流程**：
- 创建临时目录和测试文件，写入原始内容
- 构造补丁内容（使用 `apply_patch` 格式）
- 配置 Mock 服务器返回补丁应用 SSE 响应
- 发送 `codex` 工具调用请求
- 验证 MCP 服务器发送 `elicitation/create` 请求，包含文件变更详情
- 模拟用户批准响应
- 验证文件内容被正确修改
- 验证最终响应结构

**关键断言**：
- 验证征求请求包含正确的文件变更映射 (`FileChange::Update`)
- 验证统一差异格式 (unified diff) 正确
- 验证文件内容从 "original content" 变为 "modified content"

### 3. 基础指令传递测试 (`test_codex_tool_passes_base_instructions`)

**目的**：验证自定义指令能够正确传递到模型请求

**测试流程**：
- 创建 Mock 响应服务器
- 配置临时 CODEX_HOME 和 config.toml
- 发送包含 `base_instructions` 和 `developer_instructions` 的工具调用
- 验证模型请求中包含正确的指令
- 验证开发者消息中包含权限说明和自定义开发者指令

**关键断言**：
- 验证 `instructions` 字段以 "You are a helpful assistant." 开头
- 验证开发者消息包含 `sandbox_mode` 权限说明
- 验证开发者消息包含 "Foreshadow upcoming tool calls."

## 具体技术实现

### 测试架构

```
┌─────────────────┐     JSON-RPC      ┌──────────────────┐     SSE/HTTP      ┌─────────────┐
│   Test Case     │◄─────────────────►│  MCP Process     │◄─────────────────►│ Mock Server │
│  (codex_tool.rs)│   (stdin/stdout)  │ (codex-mcp-server)│   (OpenAI API)   │  (wiremock) │
└─────────────────┘                   └──────────────────┘                  └─────────────┘
                                              │
                                              ▼
                                       ┌─────────────┐
                                       │  Codex Core │
                                       │  (Thread)   │
                                       └─────────────┘
```

### 关键数据结构

#### 1. McpHandle
```rust
pub struct McpHandle {
    pub process: McpProcess,
    #[allow(dead_code)]
    server: MockServer,  // 保持 MockServer 存活
    #[allow(dead_code)]
    dir: TempDir,        // 保持临时目录存活
}
```

#### 2. ExecApprovalElicitRequestParams
```rust
pub struct ExecApprovalElicitRequestParams {
    pub message: String,
    pub requested_schema: Value,
    pub thread_id: ThreadId,
    pub codex_elicitation: String,        // "exec-approval"
    pub codex_mcp_tool_call_id: String,
    pub codex_event_id: String,
    pub codex_call_id: String,
    pub codex_command: Vec<String>,
    pub codex_cwd: PathBuf,
    pub codex_parsed_cmd: Vec<ParsedCommand>,
}
```

#### 3. PatchApprovalElicitRequestParams
```rust
pub struct PatchApprovalElicitRequestParams {
    pub message: String,
    pub requested_schema: Value,
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

### 关键流程

#### 测试初始化流程 (`create_mcp_process`)
1. 创建 Mock 响应服务器 (`create_mock_responses_server`)
2. 创建临时 CODEX_HOME 目录
3. 写入测试配置 (`create_config_toml`)：
   - 使用 mock 模型提供者
   - 设置 `approval_policy = "untrusted"` 以触发审批流程
   - 设置 `sandbox_policy = "workspace-write"`
4. 启动 MCP 进程 (`McpProcess::new`)
5. 执行初始化握手 (`initialize`)

#### Shell 命令测试流程
```rust
async fn shell_command_approval_triggers_elicitation() -> anyhow::Result<()> {
    // 1. 创建临时工作目录
    let workdir = TempDir::new()?;
    let created_file = workdir.path().join("created_by_shell_tool.txt");
    
    // 2. 构建跨平台命令
    let shell_command = if cfg!(windows) {
        vec!["New-Item", "-ItemType", "File", "-Path", filename, "-Force"]
    } else {
        vec!["touch", filename]
    };
    
    // 3. 创建 MCP 进程，配置 Mock SSE 响应
    let handle = create_mcp_process(vec![
        create_shell_command_sse_response(...)?,
        create_final_assistant_message_sse_response(...)?,
    ]).await?;
    
    // 4. 发送 codex 工具调用
    let codex_request_id = mcp_process.send_codex_tool_call(...).await?;
    
    // 5. 读取征求请求
    let elicitation_request = timeout(
        DEFAULT_READ_TIMEOUT,
        mcp_process.read_stream_until_request_message(),
    ).await??;
    
    // 6. 验证征求请求内容
    assert_eq!(elicitation_request.request.method, "elicitation/create");
    let params = serde_json::from_value::<ExecApprovalElicitRequestParams>(...)?;
    
    // 7. 发送批准响应
    mcp_process.send_response(elicitation_request_id, 
        serde_json::to_value(ExecApprovalResponse { decision: ReviewDecision::Approved })?
    ).await?;
    
    // 8. 等待任务完成通知
    let _task_complete = mcp_process.read_stream_until_legacy_task_complete_notification().await?;
    
    // 9. 验证最终响应
    let codex_response = mcp_process.read_stream_until_response_message(...).await??;
    assert!(created_file.is_file());
    
    Ok(())
}
```

## 关键代码路径与文件引用

### 测试文件
- `codex-rs/mcp-server/tests/suite/codex_tool.rs` - 主测试文件（516 行）
- `codex-rs/mcp-server/tests/suite/mod.rs` - 测试模块声明
- `codex-rs/mcp-server/tests/all.rs` - 测试入口

### 测试支持库
- `codex-rs/mcp-server/tests/common/lib.rs` - 公共测试工具
- `codex-rs/mcp-server/tests/common/mcp_process.rs` - MCP 进程管理（399 行）
- `codex-rs/mcp-server/tests/common/mock_model_server.rs` - Mock 服务器（47 行）
- `codex-rs/mcp-server/tests/common/responses.rs` - SSE 响应构造器（47 行）
- `codex-rs/core/tests/common/lib.rs` - 核心测试支持（524 行）
- `codex-rs/core/tests/common/responses.rs` - 响应辅助函数（1000+ 行）

### 被测试的 MCP 服务器源码
- `codex-rs/mcp-server/src/lib.rs` - 主入口（227 行）
- `codex-rs/mcp-server/src/message_processor.rs` - 消息处理器（603 行）
- `codex-rs/mcp-server/src/codex_tool_runner.rs` - 工具运行器（434 行）
- `codex-rs/mcp-server/src/exec_approval.rs` - 执行审批处理（147 行）
- `codex-rs/mcp-server/src/patch_approval.rs` - 补丁审批处理（142 行）
- `codex-rs/mcp-server/src/codex_tool_config.rs` - 工具配置（433 行）

### 关键依赖类型
- `codex_protocol::protocol::FileChange` - 文件变更类型
- `codex_protocol::protocol::ReviewDecision` - 审批决策枚举
- `codex_protocol::parse_command::ParsedCommand` - 解析后的命令
- `rmcp::model::*` - MCP 协议模型类型

## 依赖与外部交互

### 外部依赖

#### 1. Mock 服务器 (wiremock)
- 用于模拟 OpenAI Responses API
- 按顺序返回预配置的 SSE 事件流
- 验证请求数量和路径

#### 2. 临时文件系统 (tempfile)
- `TempDir` 用于创建隔离的测试环境
- 验证命令执行的副作用（文件创建/修改）

#### 3. 异步运行时 (tokio)
- 使用 `#[tokio::test(flavor = "multi_thread")]`
- 多线程工作器避免阻塞
- `timeout` 防止测试挂起

#### 4. JSON-RPC 协议 (rmcp)
- `JsonRpcMessage`, `JsonRpcRequest`, `JsonRpcResponse`
- `RequestId`, `JsonRpcVersion2_0`
- 自定义请求/通知类型

### 内部依赖

#### 1. codex-core
- `Config::load_with_cli_overrides` - 配置加载
- `ThreadManager` - 线程管理
- `CodexThread` - 线程操作
- `spawn::CODEX_SANDBOX_NETWORK_DISABLED_ENV_VAR` - 沙箱检测

#### 2. codex-protocol
- `ThreadId` - 线程标识
- `protocol::FileChange` - 文件变更
- `protocol::ReviewDecision` - 审批决策
- `parse_command` - 命令解析

#### 3. 测试支持库
- `core_test_support::skip_if_no_network` - 网络检查宏
- `mcp_test_support::*` - MCP 测试工具

### 环境变量
- `CODEX_SANDBOX_NETWORK_DISABLED` - 禁用网络时跳过测试
- `CODEX_HOME` - 测试配置目录
- `RUST_LOG` - 日志级别

## 风险、边界与改进建议

### 已知风险

#### 1. 平台差异
- **Windows 支持有限**：Patch 审批测试在 Windows 上被跳过（`if cfg!(windows) { return Ok(()) }`）
- **Shell 命令差异**：使用条件编译处理 `touch` vs `New-Item`
- **路径处理**：使用 `PathBuf` 和 `to_string_lossy()` 处理跨平台路径

#### 2. 测试稳定性
- **超时风险**：`DEFAULT_READ_TIMEOUT = 20 秒` 可能不足以应对慢速 CI 环境
- **并发问题**：多线程测试可能引入竞态条件
- **资源泄漏**：注释中提到 Tokio 的 `kill_on_drop` 是尽力而为，可能导致子进程泄漏检测误报

#### 3. 沙箱限制
- 测试检测 `CODEX_SANDBOX_NETWORK_DISABLED` 环境变量，在网络禁用时跳过
- 某些测试需要实际网络连接来启动 Mock 服务器

### 边界情况

#### 1. 审批响应处理
- 如果征求响应无法反序列化，默认拒绝（保守策略）
- 如果征求请求超时，测试会失败

#### 2. 并发请求
- `running_requests_id_to_codex_uuid` 使用 `Arc<Mutex<HashMap>>` 跟踪进行中的请求
- 需要正确处理请求取消通知

#### 3. 配置覆盖
- 测试使用 `approval_policy = "untrusted"` 强制触发审批流程
- 配置通过临时 `config.toml` 文件传递

### 改进建议

#### 1. 测试覆盖率
- 添加拒绝审批的测试用例
- 添加并发多个工具调用的测试
- 添加配置验证错误处理测试
- 添加 Windows 平台的完整支持

#### 2. 稳定性改进
- 使用更长的超时或自适应超时
- 添加重试机制处理 flaky 测试
- 改进子进程清理逻辑

#### 3. 可维护性
- 提取公共的测试辅助函数
- 使用 builder 模式构造复杂的测试数据
- 添加更多内联文档说明测试意图

#### 4. 性能优化
- 共享 Mock 服务器实例减少启动开销
- 使用连接池减少 TCP 连接建立时间
- 并行执行独立的测试用例

### 技术债务

1. **TODO 注释**：`exec_approval.rs` 中提到 `ExecApprovalResponse` 不完全符合 MCP ElicitResult 规范
2. **Legacy 通知**：`read_stream_until_legacy_task_complete_notification` 使用旧版事件格式
3. **硬编码值**：测试中使用硬编码的 call_id ("call1234") 和 response_id

### 安全考虑

1. **命令注入**：测试使用 `shlex::try_join` 正确转义命令参数
2. **临时目录**：使用 `tempfile::TempDir` 确保测试隔离
3. **路径遍历**：测试验证工作目录限制在临时目录内
